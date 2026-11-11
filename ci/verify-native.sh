#!/bin/sh
# Runs real .atto guests only: never replaces native execution with an interpreter shim.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."

die() { printf '%s\n' "$*" >&2; exit 1; }
command -v git >/dev/null 2>&1 || die "NO_GIT"
[ -f ci/native-cases.txt ] || die "NO_CASES: missing native guest manifest"
[ ! -L ci/native-cases.txt ] || die "UNTRUSTED_CASES: native guest manifest must not be a symlink"
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
if [ -n "$(git status --porcelain --untracked-files=normal -- workflows/ examples/ ci/ .github/workflows/ 2>/dev/null)" ]; then
  die "DIRTY_GUEST_SOURCES: native acceptance requires exact committed source files"
fi

sh ci/check-native-manifest.sh || die "ATTO_MANIFEST_REJECTED"

if [ -n "${ATTOLANG_BIN:-}" ] && [ -n "${ORESLANG_BIN:-}" ] && [ "$ATTOLANG_BIN" != "$ORESLANG_BIN" ]; then
  die "COMPILER_PATH_VARIABLE_CONFLICT"
fi
if [ -n "${ATTOLANG_COMPILER_SHA256:-}" ] && [ -n "${ORESLANG_COMPILER_SHA256:-}" ] && [ "$ATTOLANG_COMPILER_SHA256" != "$ORESLANG_COMPILER_SHA256" ]; then
  die "COMPILER_DIGEST_VARIABLE_CONFLICT"
fi
compiler_bin="${ATTOLANG_BIN:-${ORESLANG_BIN:-}}"
compiler_pin="${ATTOLANG_COMPILER_SHA256:-${ORESLANG_COMPILER_SHA256:-}}"

# Require operator-provided, immutable executable identity. SHA-256 of a wrapper
# does not authenticate its internals: use a trusted, versioned compiler binary.
case "$compiler_bin" in
  /*) ;;
  *) die "NOT_EXECUTED: specify absolute ATTOLANG_BIN (or legacy ORESLANG_BIN) for a genuine AttoLang compiler" ;;
esac
[ ! -L "$compiler_bin" ] ||
  die "NOT_EXECUTED: compiler executable must not be a symlink"
[ -f "$compiler_bin" ] && [ -x "$compiler_bin" ] ||
  die "NOT_EXECUTED: compiler binary does not exist or is not executable"
case "$compiler_pin" in
  *[!0123456789abcdef]* | "") die "NOT_EXECUTED: require lowercase ATTOLANG_COMPILER_SHA256 (or legacy ORESLANG_COMPILER_SHA256) pin" ;;
esac
[ "${#compiler_pin}" -eq 64 ] ||
  die "NOT_EXECUTED: invalid compiler SHA-256 pin"
if command -v sha256sum >/dev/null 2>&1; then
  digest="$(sha256sum "$compiler_bin" | cut -d ' ' -f 1)"
elif command -v shasum >/dev/null 2>&1; then
  digest="$(shasum -a 256 "$compiler_bin" | cut -d ' ' -f 1)"
else
  die "NOT_EXECUTED: SHA-256 utility unavailable"
fi
[ "$digest" = "$compiler_pin" ] ||
  die "NOT_EXECUTED: compiler executable digest mismatch"
if command -v timeout >/dev/null 2>&1; then
  limiter="$(command -v timeout)"
elif command -v gtimeout >/dev/null 2>&1; then
  limiter="$(command -v gtimeout)"
else
  die "NOT_EXECUTED: install coreutils timeout/gtimeout to bound native guest execution"
fi
tmp="$(mktemp -d)" || die "CANNOT_MAKE_PRIVATE_TEMP_DIR"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
chmod 700 "$tmp"
"$limiter" --kill-after=5s 15s "$compiler_bin" --build-info >"$tmp/info" 2>"$tmp/err" ||
  die "BAD_COMPILER: --build-info did not execute successfully"
[ "$(wc -c <"$tmp/info" | tr -d ' ')" -le 2048 ] ||
  die "BAD_COMPILER: excessive build-info output"
# Strict JSON capability validation rejects false/strings, duplicate or
# escaped protected fields, nested spoofing and trailing JSON documents.
# This is NOT a signed compiler provenance or build attestation.
sh ci/verify-build-info.sh "$tmp/info" ||
  die "BAD_COMPILER: untrusted reported guest_execution/build_mode"

# Reject compilers that accept arbitrary invalid .atto source in --check mode.
# This is a parser sanity challenge, not proof of a genuine compiler binary.
printf 'define actor BadSyntax as\n  this-is-not-valid-attolang-@@@\nend\n' > "$tmp/invalid.atto"
if "$limiter" --kill-after=5s 15s "$compiler_bin" --check "$tmp/invalid.atto" > "$tmp/invalid.out" 2> "$tmp/invalid.err"; then
  die "BAD_COMPILER: accepted deliberately invalid AttoLang syntax"
else
  invalid_status="$?"
fi
[ "$invalid_status" -eq 1 ] ||
  die "BAD_COMPILER: invalid syntax challenge returned nonparser exit status $invalid_status"
[ ! -s "$tmp/invalid.out" ] && [ -s "$tmp/invalid.err" ] ||
  die "BAD_COMPILER: invalid syntax must produce stderr diagnostic only"
[ "$(wc -c < "$tmp/invalid.err" | tr -d ' ')" -le 4096 ] ||
  die "BAD_COMPILER: invalid syntax diagnostic too large"
grep -Fq "$tmp/invalid.atto" "$tmp/invalid.err" ||
  die "BAD_COMPILER: invalid syntax diagnostic missing source path"
printf 'NATIVE_NEGATIVE_PARSE_REJECTED compiler_sha256=%s\n' "$digest"

printf 'NATIVE_ACCEPTANCE_START source_sha=%s compiler_sha256=%s\n' "$commit" "$digest"
count=0
while IFS='|' read -r file expected || [ -n "$file" ]; do
  case "$file" in
    '' | \#*) continue ;;
    workflows/*.atto) ;;
    *) die "INVALID_CASE_PATH: $file" ;;
  esac
  case "$file" in
    *[!a-z0-9./-]*) die "INVALID_CASE_PATH_CHARS: $file" ;;
  esac
  case "$expected" in
    '' | *[!a-z0-9:-]*) die "INVALID_CASE_EXPECTED_OUTPUT: $file" ;;
  esac
  [ ! -L "$file" ] || die "UNTRUSTED_GUEST_SYMLINK: $file"
  [ -f "$file" ] || die "MISSING_GUEST: $file"
  git ls-files --error-unmatch -- "$file" >/dev/null 2>&1 ||
    die "UNTRACKED_GUEST: $file"
  [ "$(git ls-files -s -- "$file" | awk '{print $1}')" = 100644 ] ||
    die "INVALID_GUEST_MODE: $file"
  committed_blob="$(git rev-parse --verify "HEAD:$file")" ||
    die "MISSING_GUEST_COMMIT_BLOB: $file"
  [ "$(git hash-object -- "$file")" = "$committed_blob" ] ||
    die "GUEST_BLOB_MISMATCH: $file"
  if grep -Fxq "$file" "$tmp/seen" 2>/dev/null; then
    die "DUPLICATE_CASE: $file"
  fi
  printf '%s\n' "$file" >> "$tmp/seen"
  count=$((count + 1))
  [ "$count" -le 64 ] || die "CASE_BUDGET_EXCEEDED"
  printf 'NATIVE_CASE_BEGIN %s\n' "$file"

  # A failing parse, nonzero exit, timeout, unexpected bytes or oversized output
  # is a failure. Source guest code must not gain host API access via a JS fallback.
  if ! "$limiter" --kill-after=5s 25s "$compiler_bin" --check "$file" >"$tmp/check.out" 2>"$tmp/check.err"; then
    cat "$tmp/check.err" >&2
    die "NATIVE_CHECK_FAILED: $file"
  fi
  if ! "$limiter" --kill-after=5s 25s "$compiler_bin" "$file" >"$tmp/actual" 2>"$tmp/run.err"; then
    cat "$tmp/run.err" >&2
    die "NATIVE_EXEC_FAILED: $file"
  fi
  if [ "$(wc -c <"$tmp/actual" | tr -d ' ')" -gt 4096 ]; then
    die "NATIVE_OUTPUT_LIMIT: $file"
  fi
  printf '%s' "$expected" > "$tmp/expected"
  if ! cmp -s "$tmp/actual" "$tmp/expected"; then
    die "NATIVE_OUTPUT_MISMATCH: $file"
  fi
  [ "$(git hash-object -- "$file")" = "$committed_blob" ] ||
    die "GUEST_CHANGED_DURING_EXECUTION: $file"
  printf 'NATIVE_CASE_PASS %s source_blob=%s\n' "$file" "$(git rev-parse "HEAD:$file")"
done < ci/native-cases.txt

total="$(git ls-files 'workflows/*.atto' | wc -l | tr -d ' ')"
[ "$count" -eq "$total" ] && [ "$count" -eq 9 ] ||
  die "NATIVE_CASE_COVERAGE_MISMATCH: checked $count, tracked $total, expected 9"
printf 'NATIVE_ACCEPTANCE_PASS count=%s source_sha=%s compiler_sha256=%s\n' "$count" "$commit" "$digest"
