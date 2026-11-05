#!/bin/sh
# Strict source-only validation of compiler-reported JSON. NOT build attestation.
set -eu
export LC_ALL=C
[ "$#" -eq 1 ] || { echo 'BUILD_INFO_INVALID: expected exactly one file' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || {
  echo 'BUILD_INFO_UNVERIFIED: Python 3 unavailable' >&2; exit 1;
}
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
exec python3 "$script_dir/validate_build_info_json.py" "$1"
