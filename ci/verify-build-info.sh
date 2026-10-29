#!/bin/sh
# Strict source-only validation of compiler-reported JSON. NOT build attestation.
set -eu
export LC_ALL=C
[ "$#" -eq 1 ] || { echo 'BUILD_INFO_INVALID: expected exactly one file' >&2; exit 1; }
file="$1"
[ -f "$file" ] && [ ! -L "$file" ] || { echo 'BUILD_INFO_INVALID: absent or symlinked file' >&2; exit 1; }
[ "$(wc -c < "$file" | tr -d ' ')" -le 2048 ] || { echo 'BUILD_INFO_INVALID: oversized JSON' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo 'BUILD_INFO_UNVERIFIED: jq unavailable' >&2; exit 1; }
# jq's ordinary object parser uses the last value of a duplicate key.
# Stream events retain duplicate keys after JSON Unicode-escape decoding.
# Require exactly one occurrence of each protected key at the top level,
# and no shadow occurrence at a nested path. A raw-text grep is insufficient:
# `"guest_execution":false,"guest_\u0065xecution":true` is the same key.
jq -e --stream -s '
  ([.[] | select(length == 2 and .[0][-1] == "guest_execution")] | length) == 1 and
  ([.[] | select(length == 2 and .[0][-1] == "build_mode")] | length) == 1 and
  ([.[] | select(length == 2 and .[0] == ["guest_execution"])] | length) == 1 and
  ([.[] | select(length == 2 and .[0] == ["build_mode"])] | length) == 1
' "$file" >/dev/null 2>&1 || {
  echo 'BUILD_INFO_INVALID: missing, duplicate or nested protected key' >&2
  exit 1
}
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
