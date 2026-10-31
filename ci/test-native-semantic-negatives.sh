#!/bin/sh
# Synthetic host-only probes. No Oreslang compiler or guest is executed.
set -eu
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cat > "$tmp/mock" <<'MOCK'
#!/bin/sh
file="$2"
case "${MOCK_FAULT:-good}" in
  silent) : ;;
  generic) printf '%s:1:1: error: expected token\n' "$file" >&2 ;;
  wrong-path) printf '/tmp/not-the-guest.ores:1:1: error: read-only state loan invalid\n' >&2 ;;
  *) case "$file" in
      */illegal-read-loan.ores) printf '%s:10:2: error: read-only state loan cannot write phase\n' "$file" >&2 ;;
      */illegal-direct-field.ores) printf '%s:10:2: error: sealed actor state direct field access forbidden\n' "$file" >&2 ;;
     esac ;;
esac
exit "${MOCK_EXIT:-1}"
MOCK
chmod 700 "$tmp/mock"
mkdir -p workflows
# The actual repo coordinator is present. The mock does not run .ores code.
MOCK_EXIT=1 sh ci/verify-native-semantic-negatives.sh "$tmp/mock" "$tmp" > "$tmp/passed"
grep -Fq 'NATIVE_SEMANTIC_NEGATIVE_REJECTED case=direct-field' "$tmp/passed"
reject() {
  if "$@" > "$tmp/out" 2> "$tmp/err"; then
    echo "NEGATIVE_HARNESS_FALSE_ACCEPT: $*" >&2; exit 1
  fi
}
for status in 0 2 124 125 126 127 137 143; do
  reject env MOCK_EXIT="$status" sh ci/verify-native-semantic-negatives.sh "$tmp/mock" "$tmp"
done
for fault in silent generic wrong-path; do
  reject env MOCK_EXIT=1 MOCK_FAULT="$fault" sh ci/verify-native-semantic-negatives.sh "$tmp/mock" "$tmp"
done
printf 'NATIVE_SEMANTIC_HARNESS_SELFTEST_PASS cases=11 negative_plus_1_positive (synthetic only)\n'
