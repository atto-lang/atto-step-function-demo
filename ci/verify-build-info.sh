#!/bin/sh
# Strict source-only validation of compiler-reported JSON. NOT build attestation.
set -eu
export LC_ALL=C
[ "$#" -eq 1 ] || { echo 'BUILD_INFO_INVALID: expected exactly one file' >&2; exit 1; }
file="$1"
[ -f "$file" ] && [ ! -L "$file" ] || { echo 'BUILD_INFO_INVALID: absent or symlinked file' >&2; exit 1; }
[ "$(wc -c < "$file" | tr -d ' ')" -le 2048 ] || { echo 'BUILD_INFO_INVALID: oversized JSON' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo 'BUILD_INFO_UNVERIFIED: jq unavailable' >&2; exit 1; }
# Reject duplicate/nested keys rather than accepting jq's last-wins JSON map.
for key in guest_execution build_mode; do
  n="$(grep -oE '"'$key'"[[:space:]]*:' "$file" | wc -l | tr -d ' ')"
  [ "$n" -eq 1 ] || { echo "BUILD_INFO_INVALID: missing or repeated $key" >&2; exit 1; }
done
jq -e -s '
  length == 1 and
  (.[0] | type == "object" and
   .guest_execution == true and
   (.build_mode | type == "string" and length > 0 and length <= 128))
' "$file" >/dev/null 2>&1 || {
  echo 'BUILD_INFO_INVALID: malformed JSON or unsupported guest execution' >&2
  exit 1
}
printf '%s\n' 'BUILD_INFO_JSON_PASS (reported capability only; not attestation)'
