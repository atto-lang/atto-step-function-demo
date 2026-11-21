#!/bin/sh
# Runs real .ores guests only: never replaces native execution with an interpreter shim.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."

die() { printf '%s\n' "$*" >&2; exit 1; }
[ -f ci/native-cases.txt ] && [ ! -L ci/native-cases.txt ] ||
  die "NO_CASES: missing native guest manifest or symlink"
[ "$(git ls-files -s -- ci/native-cases.txt | cut -d ' ' -f 1)" = "100644" ] ||
  die "INVALID_CASE_MANIFEST_MODE"
command -v git >/dev/null 2>&1 || die "NO_GIT"
git ls-files --error-unmatch -- ci/native-cases.txt >/dev/null 2>&1 ||
  die "UNTRACKED_CASES: native guest manifest must be committed"
commit="$(git rev-parse --verify HEAD 2>/dev/null)" || die "NO_CHECKED_OUT_HEAD"
case "$commit" in
  *[!0123456789abcdef]* | "") die "BAD_SOURCE_SHA" ;;
esac
[ "${#commit}" -eq 40 ] || die "BAD_SOURCE_SHA_LENGTH"
if [ -n "${EXPECTED_SOURCE_SHA:-}" ] && [ "$EXPECTED_SOURCE_SHA" != "$commit" ]; then
  die "SOURCE_SHA_MISMATCH: expected $EXPECTED_SOURCE_SHA but checked out $commit"
fi
if [ -n "$(git status --porcelain --untracked-files=normal -- workflows/ examples/oreslang/ ci/ .github/workflows/demo.yml 2>/dev/null)" ]; then
  die "DIRTY_GUEST_SOURCES: native acceptance requires exact committed source files"
fi
# git status is insufficient: assume-unchanged/skip-worktree can hide
# changes to executed CI shell scripts. Bind each tracked harness script to
# the Git object in the exact checked-out HEAD, before running any script.
# This is a provenance guard, not trust attestation of the Git repository.
git ls-files -- 'ci/*.sh' | while IFS= read -r harness; do
  [ -f "$harness" ] && [ ! -L "$harness" ] ||
    die "HARNESS_MISSING_OR_SYMLINK: $harness"
  [ "$(git ls-files -s -- "$harness" | cut -d ' ' -f 1)" = "100644" ] ||
    die "HARNESS_NONREGULAR: $harness"
  committed_harness="$(git rev-parse --verify "HEAD:$harness" 2>/dev/null)" ||
    die "HARNESS_NOT_IN_HEAD: $harness"
  actual_harness="$(git hash-object -- "$harness")" ||
    die "HARNESS_HASH_FAILED: $harness"
  [ "$actual_harness" = "$committed_harness" ] ||
    die "HARNESS_BLOB_MISMATCH: $harness"
done
# Running the native acceptance script directly must enforce the complete
# canonical path, 14-case, unique oracle and committed-file provenance gate.
# An unrelated workflow's structural CI verdict is not a substitute.
sh ci/check-native-manifest.sh || die "INVALID_MANIFEST_PROVENANCE"

# Require operator-provided, immutable executable identity. SHA-256 of a wrapper
# does not authenticate its internals: use a trusted, versioned compiler binary.
case "${ORESLANG_BIN:-}" in
  /*) ;;
  *) die "NOT_EXECUTED: specify absolute ORESLANG_BIN for a genuine Oreslang compiler" ;;
esac
[ ! -L "$ORESLANG_BIN" ] ||
  die "NOT_EXECUTED: compiler executable must not be a symlink"
[ -f "$ORESLANG_BIN" ] && [ -x "$ORESLANG_BIN" ] ||
  die "NOT_EXECUTED: compiler binary does not exist or is not executable"
case "${ORESLANG_COMPILER_SHA256:-}" in
  *[!0123456789abcdef]* | "") die "NOT_EXECUTED: require lowercase ORESLANG_COMPILER_SHA256 pin" ;;
esac
[ "${#ORESLANG_COMPILER_SHA256}" -eq 64 ] ||
  die "NOT_EXECUTED: invalid compiler SHA-256 pin"
if command -v sha256sum >/dev/null 2>&1; then
  digest="$(sha256sum "$ORESLANG_BIN" | cut -d ' ' -f 1)"
elif command -v shasum >/dev/null 2>&1; then
  digest="$(shasum -a 256 "$ORESLANG_BIN" | cut -d ' ' -f 1)"
else
  die "NOT_EXECUTED: SHA-256 utility unavailable"
fi
[ "$digest" = "$ORESLANG_COMPILER_SHA256" ] ||
  die "NOT_EXECUTED: compiler executable digest mismatch"
if command -v timeout >/dev/null 2>&1; then
  limiter="$(command -v timeout)"
elif command -v gtimeout >/dev/null 2>&1; then
  limiter="$(command -v gtimeout)"
else
  die "NOT_EXECUTED: install coreutils timeout/gtimeout to bound native guest execution"
fi
# POSIX process file-size limit: a compiler cannot write one unlimited log,
# core image, temp object or guest artifact before our post-exit byte checks.
# GitHub runner/workspace quotas are still needed to bound AGGREGATE disk use.
file_limit="$(ulimit -f)" || die "NOT_EXECUTED: cannot read process file limit"
case "$file_limit" in
  unlimited) ulimit -f 262144 || die "NOT_EXECUTED: cannot cap compiler file sizes" ;;
  *[!0-9]* | '') die "NOT_EXECUTED: unknown process file limit" ;;
  *) if [ "$file_limit" -gt 262144 ]; then
       ulimit -f 262144 || die "NOT_EXECUTED: cannot cap compiler file sizes"
     fi ;;
esac
ulimit -c 0 || die "NOT_EXECUTED: cannot disable compiler core dumps"
tmp="$(mktemp -d)" || die "CANNOT_MAKE_PRIVATE_TEMP_DIR"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
chmod 700 "$tmp"
"$limiter" --kill-after=5s 15s "$ORESLANG_BIN" --build-info >"$tmp/info" 2>"$tmp/err" ||
  die "BAD_COMPILER: --build-info did not execute successfully"
[ "$(wc -c <"$tmp/info" | tr -d ' ')" -le 2048 ] ||
  die "BAD_COMPILER: excessive build-info output"
[ "$(wc -c <"$tmp/err" | tr -d ' ')" -le 4096 ] ||
  die "BAD_COMPILER: excessive build-info stderr"
# Strict JSON capability check; a string or number must never be accepted
# as a true guest-execution boolean. This still requires trusted build provenance.
sh ci/verify-build-info.sh "$tmp/info" ||
  die "BAD_COMPILER: invalid reported guest execution build info"
# Syntax-negative challenge prevents an always-true --check shim from being
# treated as verified compilation. A fake binary can still spoof this; digest
# and trusted build provenance must be established out of band.
printf 'define actor BadSyntax as\n  this-is-not-valid-oreslang-@@@\nend\n' > "$tmp/invalid.ores"
# Timeout (124+), failed shell invocation, or a terminated compiler cannot
# count as an expected parser/typecheck rejection of deliberately bad guest.
if "$limiter" --kill-after=5s 15s "$ORESLANG_BIN" --check "$tmp/invalid.ores" >"$tmp/invalid.out" 2>"$tmp/invalid.err"; then
  die "BAD_COMPILER: accepted deliberately invalid Oreslang source"
else
  invalid_status="$?"
fi
[ "$invalid_status" -lt 124 ] ||
  die "BAD_COMPILER: negative syntax challenge timed out, crashed or could not execute"
[ "$invalid_status" -eq 1 ] ||
  die "BAD_COMPILER: negative syntax challenge returned noncompiler exit status"
[ ! -s "$tmp/invalid.out" ] && [ -s "$tmp/invalid.err" ] ||
  die "BAD_COMPILER: negative syntax challenge must emit stderr diagnostic only"
grep -Fq "$tmp/invalid.ores" "$tmp/invalid.err" ||
  die "BAD_COMPILER: negative syntax challenge missing source path"
grep -Eq ':[0-9]+:[0-9]+: (error|Error): ' "$tmp/invalid.err" ||
  die "BAD_COMPILER: negative syntax challenge missing positioned parser error"
invalid_bytes="$(wc -c <"$tmp/invalid.err" | tr -d ' ')"
[ "$invalid_bytes" -le 4096 ] ||
  die "BAD_COMPILER: oversized negative syntax diagnostic"
printf 'NATIVE_NEGATIVE_PARSE_REJECTED compiler_sha256=%s\n' "$digest"

printf 'NATIVE_ACCEPTANCE_START source_sha=%s compiler_sha256=%s\n' "$commit" "$digest"
count=0
while IFS='|' read -r file expected || [ -n "$file" ]; do
  case "$file" in
    '' | \#*) continue ;;
    workflows/*.ores) ;;
    *) die "INVALID_CASE_PATH: $file" ;;
  esac
  case "$file" in
    *[!a-z0-9./-]*) die "INVALID_CASE_PATH_CHARS: $file" ;;
    *..* | workflows/*/*) die "INVALID_CASE_PATH_TRAVERSAL: $file" ;;
  esac
  case "$expected" in
    '' | *[!a-z0-9:-]*) die "INVALID_CASE_EXPECTED_OUTPUT: $file" ;;
  esac
  case "$file" in
    *..*|*//*|*/./*|*/.) die "PATH_TRAVERSAL: $file" ;;
  esac
  [ -f "$file" ] && [ ! -L "$file" ] || die "MISSING_OR_SYMLINK_GUEST: $file"
  [ "$(git ls-files -s -- "$file" | cut -d ' ' -f 1)" = "100644" ] ||
    die "INVALID_GUEST_MODE: $file"
  on_disk_blob="$(git hash-object -- "$file")" || die "GUEST_HASH_FAILED: $file"
  committed_blob="$(git rev-parse "HEAD:$file")" || die "GUEST_COMMIT_BLOB_MISSING: $file"
  [ "$on_disk_blob" = "$committed_blob" ] ||
    die "GUEST_BLOB_MISMATCH: $file"
  git ls-files --error-unmatch -- "$file" >/dev/null 2>&1 ||
    die "UNTRACKED_GUEST: $file"
  if grep -Fxq "$file" "$tmp/seen" 2>/dev/null; then
    die "DUPLICATE_CASE: $file"
  fi
  printf '%s\n' "$file" >> "$tmp/seen"
  count=$((count + 1))
  [ "$count" -le 64 ] || die "CASE_BUDGET_EXCEEDED"
  printf 'NATIVE_CASE_BEGIN %s\n' "$file"

  # A failing parse, nonzero exit, timeout, unexpected bytes or oversized output
  # is a failure. Source guest code must not gain host API access via a JS fallback.
  if ! "$limiter" --kill-after=5s 25s "$ORESLANG_BIN" --check "$file" >"$tmp/check.out" 2>"$tmp/check.err"; then
    head -c 4096 "$tmp/check.err" >&2
    die "NATIVE_CHECK_FAILED: $file"
  fi
  if ! "$limiter" --kill-after=5s 25s "$ORESLANG_BIN" "$file" >"$tmp/actual" 2>"$tmp/run.err"; then
    head -c 4096 "$tmp/run.err" >&2
    die "NATIVE_EXEC_FAILED: $file"
  fi
  [ "$(wc -c <"$tmp/check.out" | tr -d ' ')" -le 4096 ] ||
    die "NATIVE_CHECK_OUTPUT_LIMIT: $file"
  [ "$(wc -c <"$tmp/check.err" | tr -d ' ')" -le 4096 ] ||
    die "NATIVE_CHECK_DIAGNOSTIC_LIMIT: $file"
  [ "$(wc -c <"$tmp/run.err" | tr -d ' ')" -le 4096 ] ||
    die "NATIVE_RUN_DIAGNOSTIC_LIMIT: $file"
  if [ "$(wc -c <"$tmp/actual" | tr -d ' ')" -gt 4096 ]; then
    die "NATIVE_OUTPUT_LIMIT: $file"
  fi
  printf '%s' "$expected" > "$tmp/expected"
  if ! cmp -s "$tmp/actual" "$tmp/expected"; then
    die "NATIVE_OUTPUT_MISMATCH: $file"
  fi
  printf 'NATIVE_CASE_PASS %s source_blob=%s\n' "$file" "$committed_blob"
done < ci/native-cases.txt

total="$(git ls-files 'workflows/*.ores' | wc -l | tr -d ' ')"
[ "$count" -eq "$total" ] && [ "$count" -eq 14 ] ||
  die "NATIVE_CASE_COVERAGE_MISMATCH: checked $count, tracked $total, expected 14"
# A separately scoped experimental Oreslang state-fencing guest must compile
# and emit the exact synthetic protocol oracle. This is not crash recovery.
experimental="examples/oreslang/workflow-generation-fence.ores"
[ -f "$experimental" ] && [ ! -L "$experimental" ] ||
  die "MISSING_EXPERIMENTAL_FENCING_GUEST"
[ "$(git ls-files -s -- "$experimental" | cut -d ' ' -f1)" = 100644 ] ||
  die "INVALID_EXPERIMENTAL_GUEST_MODE"
experimental_blob="$(git rev-parse --verify "HEAD:$experimental")" ||
  die "EXPERIMENTAL_GUEST_NOT_COMMITTED"
[ "$(git hash-object -- "$experimental")" = "$experimental_blob" ] ||
  die "EXPERIMENTAL_GUEST_BLOB_MISMATCH"
if ! "$limiter" --kill-after=5s 25s "$ORESLANG_BIN" --check "$experimental" >"$tmp/fence-check.out" 2>"$tmp/fence-check.err"; then
  head -c 4096 "$tmp/fence-check.err" >&2
  die "EXPERIMENTAL_FENCING_CHECK_FAILED"
fi
if ! "$limiter" --kill-after=5s 25s "$ORESLANG_BIN" "$experimental" >"$tmp/fence-output" 2>"$tmp/fence-run.err"; then
  head -c 4096 "$tmp/fence-run.err" >&2
  die "EXPERIMENTAL_FENCING_EXEC_FAILED"
fi
[ "$(wc -c <"$tmp/fence-check.out" | tr -d ' ')" -le 4096 ] ||
  die "EXPERIMENTAL_FENCING_CHECK_OUTPUT_LIMIT"
[ "$(wc -c <"$tmp/fence-check.err" | tr -d ' ')" -le 4096 ] ||
  die "EXPERIMENTAL_FENCING_CHECK_DIAGNOSTIC_LIMIT"
[ "$(wc -c <"$tmp/fence-run.err" | tr -d ' ')" -le 4096 ] ||
  die "EXPERIMENTAL_FENCING_RUN_DIAGNOSTIC_LIMIT"
[ "$(wc -c <"$tmp/fence-output" | tr -d ' ')" -le 4096 ] ||
  die "EXPERIMENTAL_FENCING_OUTPUT_LIMIT"
printf '%s' 'fence:synthetic-stale-rejected' > "$tmp/fence-expected"
cmp -s "$tmp/fence-output" "$tmp/fence-expected" ||
  die "EXPERIMENTAL_FENCING_OUTPUT_MISMATCH"
printf 'NATIVE_EXPERIMENTAL_FENCING_PASS source_blob=%s (non-durable fixture)\n' "$experimental_blob"
# Typed M1 candidate SOURCE-SHAPE fixture only: no committed transaction,
# no actor restart and no storage authority. This is a separate experimental
# compiler/guest check; it must never count as the 14 canonical workflows.
candidate="examples/oreslang/checkpoint-candidate-m1.ores"
[ -f "$candidate" ] && [ ! -L "$candidate" ] ||
  die "MISSING_TYPED_CANDIDATE_GUEST"
[ "$(git ls-files -s -- "$candidate" | cut -d ' ' -f 1)" = 100644 ] ||
  die "INVALID_TYPED_CANDIDATE_MODE"
candidate_blob="$(git rev-parse --verify "HEAD:$candidate")" ||
  die "TYPED_CANDIDATE_GUEST_NOT_COMMITTED"
[ "$(git hash-object -- "$candidate")" = "$candidate_blob" ] ||
  die "TYPED_CANDIDATE_GUEST_BLOB_MISMATCH"
if ! "$limiter" --kill-after=5s 25s "$ORESLANG_BIN" --check "$candidate" >"$tmp/candidate-check.out" 2>"$tmp/candidate-check.err"; then
  head -c 4096 "$tmp/candidate-check.err" >&2
  die "TYPED_CANDIDATE_CHECK_FAILED"
fi
if ! "$limiter" --kill-after=5s 25s "$ORESLANG_BIN" "$candidate" >"$tmp/candidate-output" 2>"$tmp/candidate-run.err"; then
  head -c 4096 "$tmp/candidate-run.err" >&2
  die "TYPED_CANDIDATE_EXEC_FAILED"
fi
for output in candidate-check.out candidate-check.err candidate-output candidate-run.err; do
  [ "$(wc -c <"$tmp/$output" | tr -d ' ')" -le 4096 ] ||
    die "TYPED_CANDIDATE_OUTPUT_LIMIT: $output"
done
printf '%s' 'checkpoint:typed-shape-only' > "$tmp/candidate-expected"
cmp -s "$tmp/candidate-output" "$tmp/candidate-expected" ||
  die "TYPED_CANDIDATE_OUTPUT_MISMATCH"
printf 'NATIVE_TYPED_CANDIDATE_PASS source_blob=%s (shape only; NOT durable)\n' "$candidate_blob"

# Compiler-backed negative checks of the sealed actor state contract.
# Rejections are not build attestation or positive execution proof.
sh ci/verify-native-semantic-negatives.sh "$ORESLANG_BIN" "$tmp"
printf 'NATIVE_ACCEPTANCE_PASS count=%s source_sha=%s compiler_sha256=%s\n' "$count" "$commit" "$digest"
