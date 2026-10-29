#!/bin/sh
# Source-free NEGATIVE tests of acceptance guard. Never a guest test/pass.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf '%s\n' "NEGATIVE_GUARD_TEST_FAILED: $*" >&2; exit 1; }
tmp="$(mktemp -d)" || die "cannot create temporary directory"
dirty="ci/.negative-guard-test-$$"
trap 'rm -f "$dirty"; rm -rf "$tmp"' EXIT HUP INT TERM
chmod 700 "$tmp"
[ ! -e "$dirty" ] || die "sentinel path already exists"
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
reject 'guest execution disabled' env EXPECTED_SOURCE_SHA="$head" ORESLANG_BIN="$tmp/disabled-guest" ORESLANG_COMPILER_SHA256="$hash" sh ci/verify-native.sh
printf 'NEGATIVE_GUARD_TEST_PASS (not an Oreslang guest execution)\n'
