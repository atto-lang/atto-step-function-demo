#!/bin/sh
# Source-free NEGATIVE tests of acceptance guard. Never a guest test/pass.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf '%s\n' "NEGATIVE_GUARD_TEST_FAILED: $*" >&2; exit 1; }
tmp="$(mktemp -d)" || die "cannot create temporary directory"
dirty="ci/.negative-guard-test-$$"
experimental_dirty="examples/oreslang/.negative-guard-test-$$"
# Both sentinels are per-process; the prior literal trailing "$" allowed
# different invocations to collide and left cleanup pointing at a shared path.
trap 'rm -f "$dirty" "$experimental_dirty"; rm -rf "$tmp"' EXIT HUP INT TERM
chmod 700 "$tmp"
[ ! -e "$dirty" ] && [ ! -L "$dirty" ] || die "sentinel path already exists or is a symlink"
head="$(git rev-parse --verify HEAD)" || die "no checked-out Git commit"
bad_sha=0000000000000000000000000000000000000000
[ "$head" != "$bad_sha" ] || die "unexpected zero SHA"
reject() {
  marker="$1"; shift
  if "$@" >"$tmp/out" 2>"$tmp/err"; then
    die "guard accepted invalid case $marker"
  fi
  grep -Fq "$marker" "$tmp/err" || {
    cat "$tmp/err" >&2
    die "wrong failure for $marker"
  }
  printf 'NEGATIVE_GUARD_PASS %s\n' "$marker"
}
# Invalid exact source cannot reach compiler execution.
reject SOURCE_SHA_MISMATCH env EXPECTED_SOURCE_SHA="$bad_sha" ORESLANG_BIN=/missing ORESLANG_COMPILER_SHA256= sh ci/verify-native.sh
# Missing a genuine absolute compiler always fails closed.
reject NOT_EXECUTED env EXPECTED_SOURCE_SHA="$head" ORESLANG_BIN= ORESLANG_COMPILER_SHA256= sh ci/verify-native.sh
# The *harness* must itself be from the checked-out tree.
printf 'dirty harness marker\n' > "$dirty"
reject DIRTY_GUEST_SOURCES env EXPECTED_SOURCE_SHA="$head" ORESLANG_BIN= ORESLANG_COMPILER_SHA256= sh ci/verify-native.sh
rm -f "$dirty"
# Experimental guest sources are also immutable acceptance inputs.
[ ! -e "$experimental_dirty" ] && [ ! -L "$experimental_dirty" ] || die "experimental sentinel already exists or is a symlink"
printf 'dirty experimental fixture marker\n' > "$experimental_dirty"
reject DIRTY_GUEST_SOURCES env EXPECTED_SOURCE_SHA="$head" ORESLANG_BIN= ORESLANG_COMPILER_SHA256= sh ci/verify-native.sh
rm -f "$experimental_dirty"
# Mock compiler is intentionally disabled. It MUST NOT produce a passing
# native acceptance verdict, even if its build-info call exits zero.
cat >"$tmp/disabled-guest" <<'MOCK'
#!/bin/sh
if [ "$1" = "--build-info" ]; then
  printf '%s\n' '{"build_mode":"disabled-test-only","guest_execution":false}'
  exit 0
fi
exit 0
MOCK
chmod 700 "$tmp/disabled-guest"
if command -v sha256sum >/dev/null 2>&1; then
  hash="$(sha256sum "$tmp/disabled-guest" | cut -d ' ' -f 1)"
elif command -v shasum >/dev/null 2>&1; then
  hash="$(shasum -a 256 "$tmp/disabled-guest" | cut -d ' ' -f 1)"
else
  die "no digest utility"
fi
reject 'invalid reported guest execution build info' env EXPECTED_SOURCE_SHA="$head" ORESLANG_BIN="$tmp/disabled-guest" ORESLANG_COMPILER_SHA256="$hash" sh ci/verify-native.sh
# A timed-out or crashed parser is not a negative compile verdict, even when
# the mock reports guest_execution=true. No actual compiler is used here.
cat >"$tmp/timeout-parser" <<'MOCK'
#!/bin/sh
if [ "$1" = "--build-info" ]; then
  printf '%s\n' '{"build_mode":"fixture","guest_execution":true}'
  exit 0
fi
if [ "$1" = "--check" ]; then
  echo 'synthetic failure' >&2
  exit "${MOCK_PARSE_STATUS:-124}"
fi
exit 0
MOCK
chmod 700 "$tmp/timeout-parser"
if command -v sha256sum >/dev/null 2>&1; then
  timeout_hash="$(sha256sum "$tmp/timeout-parser" | cut -d ' ' -f 1)"
else
  timeout_hash="$(shasum -a 256 "$tmp/timeout-parser" | cut -d ' ' -f 1)"
fi
reject 'negative syntax challenge timed out' env EXPECTED_SOURCE_SHA="$head" ORESLANG_BIN="$tmp/timeout-parser" ORESLANG_COMPILER_SHA256="$timeout_hash" sh ci/verify-native.sh
# Exit 2 is a CLI/invocation failure, not a parser rejection.
reject 'negative syntax challenge returned noncompiler exit status' env MOCK_PARSE_STATUS=2 EXPECTED_SOURCE_SHA="$head" ORESLANG_BIN="$tmp/timeout-parser" ORESLANG_COMPILER_SHA256="$timeout_hash" sh ci/verify-native.sh
# Exit 1 without a positioned source-specific error is also insufficient.
reject 'negative syntax challenge missing source path' env MOCK_PARSE_STATUS=1 EXPECTED_SOURCE_SHA="$head" ORESLANG_BIN="$tmp/timeout-parser" ORESLANG_COMPILER_SHA256="$timeout_hash" sh ci/verify-native.sh
# Host-only provenance regression: Git index assume-unchanged masks a
# modified harness from porcelain/status, but not from HEAD blob hashing.
# The separate temporary repo deliberately has no runnable native guests.
mkdir -p "$tmp/harness-repo/ci"
cp ci/verify-native.sh ci/check-native-manifest.sh "$tmp/harness-repo/ci/"
printf 'workflows/example.ores|synthetic-only\n' > "$tmp/harness-repo/ci/native-cases.txt"
git -C "$tmp/harness-repo" init -q
git -C "$tmp/harness-repo" add ci
git -C "$tmp/harness-repo" -c user.name='CI Source-Only Probe' -c user.email='ci@example.invalid' commit -qm 'synthetic verifier harness baseline'
git -C "$tmp/harness-repo" update-index --assume-unchanged ci/check-native-manifest.sh
printf '# tampered under assume-unchanged\n' >> "$tmp/harness-repo/ci/check-native-manifest.sh"
[ -z "$(git -C "$tmp/harness-repo" status --porcelain -- ci/check-native-manifest.sh)" ] ||
  die 'synthetic dirty-index check was not suppressed'
reject HARNESS_BLOB_MISMATCH env ORESLANG_BIN=/missing ORESLANG_COMPILER_SHA256= sh "$tmp/harness-repo/ci/verify-native.sh"
# A tracked regular file replaced by a symlink must also fail closed even if
# Git index flags conceal the replacement from the status-based guard.
rm -f "$tmp/harness-repo/ci/check-native-manifest.sh"
ln -s /dev/null "$tmp/harness-repo/ci/check-native-manifest.sh"
reject HARNESS_MISSING_OR_SYMLINK env ORESLANG_BIN=/missing ORESLANG_COMPILER_SHA256= sh "$tmp/harness-repo/ci/verify-native.sh"
printf 'NEGATIVE_GUARD_TEST_PASS (not an Oreslang guest execution)\n'
