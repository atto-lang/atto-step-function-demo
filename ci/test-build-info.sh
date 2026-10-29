#!/bin/sh
# Source-free adversarial JSON checks; never runs Oreslang.
set -eu
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
valid() {
  printf '%s\n' "$1" > "$tmp/info"
  sh ci/verify-build-info.sh "$tmp/info" >/dev/null || {
    echo "BUILD_INFO_SELFTEST_FALSE_REJECT: $2" >&2
    exit 1
  }
}
invalid() {
  printf '%s\n' "$1" > "$tmp/info"
  if sh ci/verify-build-info.sh "$tmp/info" >/dev/null 2>&1; then
    echo "BUILD_INFO_SELFTEST_FALSE_ACCEPT: $2" >&2
    exit 1
  fi
}
valid '{"guest_execution":true,"build_mode":"graal-aot"}' compact
valid '{"build_mode": "graal-jvm", "guest_execution": true}' spaced
invalid '{"guest_execution":false,"build_mode":"graal-jvm"}' false
invalid '{"guest_execution":null,"build_mode":"graal-jvm"}' null
invalid '{"guest_execution":0,"build_mode":"graal-jvm"}' integer
invalid '{"guest_execution":"true","build_mode":"graal-jvm"}' string
invalid '{"guest_execution":[],"build_mode":"graal-jvm"}' array
invalid '{"build_mode":"graal-jvm"}' missing-key
invalid '{"guest_execution":true,"build_mode":""}' empty-mode
invalid '{"guest_execution":true,"build_mode":null}' null-mode
invalid '{"guest_execution":true,"guest_execution":true,"build_mode":"graal-jvm"}' duplicate-key
invalid '{"guest_execution":true,"build_mode":"graal-jvm"}{"guest_execution":true,"build_mode":"graal-jvm"}' duplicate-document
invalid '[{"guest_execution":true,"build_mode":"graal-jvm"}]' array-document
invalid '{"guest_execution":true,"build_mode":"graal-jvm"' malformed-document
invalid '{"guest_execution":true,"build_mode":"graal-jvm","nested":{"guest_execution":false}}' nested-key
invalid '{"guest_execution":false,"guest_\u0065xecution":true,"build_mode":"graal-jvm"}' unicode-duplicate-guest
invalid '{"guest_\u0065xecution":true,"guest_execution":false,"build_mode":"graal-jvm"}' unicode-duplicate-guest-reversed
invalid '{"guest_execution":true,"build_mode":"graal-jvm","build_\u006dode":"graal-jvm"}' unicode-duplicate-mode
invalid '{"guest_execution":true,"build_mode":"graal-jvm","nested":{"guest_\u0065xecution":true}}' unicode-nested-guest
printf '%s\n' 'BUILD_INFO_NEGATIVE_CASES_PASS (17 invalid cases; source-only)'
