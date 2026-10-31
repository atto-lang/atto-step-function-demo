#!/bin/sh
# Only synthetic compiler stub checks. NOT a native Oreslang guest verdict.
set -eu
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/mock" <<'MOCK'
#!/bin/sh
[ "${MOCK_SILENT:-0}" = 1 ] || echo 'synthetic compiler diagnostic' >&2
exit "${MOCK_EXIT:-1}"
MOCK
chmod 700 "$tmp/mock"
MOCK_EXIT=1 sh ci/verify-native-semantic-negatives.sh "$tmp/mock" "$tmp" >/dev/null
for status in 0 124 125 126 127 137; do
  if MOCK_EXIT="$status" sh ci/verify-native-semantic-negatives.sh "$tmp/mock" "$tmp" >/dev/null 2>&1; then
    echo "NEGATIVE_HARNESS_FALSE_ACCEPT: status=$status" >&2
    exit 1
  fi
done
if MOCK_EXIT=1 MOCK_SILENT=1 sh ci/verify-native-semantic-negatives.sh "$tmp/mock" "$tmp" >/dev/null 2>&1; then
  echo 'NEGATIVE_HARNESS_FALSE_ACCEPT: silent rejection' >&2
  exit 1
fi
echo 'NATIVE_SEMANTIC_HARNESS_SELFTEST_PASS (synthetic stubs, NO Oreslang guest execution)'
