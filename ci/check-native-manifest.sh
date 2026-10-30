#!/bin/sh
# Source-only provenance check. Passing never implies .ores guest execution.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf '%s\n' "NATIVE_MANIFEST_REJECT: $*" >&2; exit 1; }

[ -f ci/native-cases.txt ] && [ ! -L ci/native-cases.txt ] ||
  die "manifest absent or symlinked"
[ "$(git ls-files -s -- ci/native-cases.txt | cut -d ' ' -f 1)" = 100644 ] ||
  die "manifest must be a regular committed blob"
[ -z "$(git status --porcelain --untracked-files=normal -- workflows/ ci/native-cases.txt)" ] ||
  die "native sources or manifest differ from committed revision"

umask 077
temp="$(mktemp -d)" || die "cannot allocate private scratch"
trap 'rm -rf "$temp"' EXIT HUP INT TERM
: > "$temp/seen"
: > "$temp/seen-stdout"
count=0
while IFS= read -r row || [ -n "$row" ]; do
  case "$row" in '' | \#*) continue ;; esac
  case "$row" in *'|'*) ;; *) die "missing separator" ;; esac
  path="${row%%|*}"
  expected="${row#*|}"
  case "$expected" in '' | *'|'* | *[!a-z0-9:-]*)
    die "invalid output contract for $path" ;;
  esac
  case "$path" in workflows/*.ores) ;; *) die "wrong workflow prefix" ;; esac
  leaf="${path#workflows/}"
  stem="${leaf%.ores}"
  case "$stem" in '' | -* | *[!a-z0-9-]*)
    die "noncanonical workflow name: $path" ;;
  esac
  case "$leaf" in */*) die "nested or traversal path: $path" ;; esac
  [ "$path" = "workflows/$stem.ores" ] || die "noncanonical suffix"
  [ -f "$path" ] && [ ! -L "$path" ] || die "missing/symlinked guest: $path"
  git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 ||
    die "untracked guest: $path"
  [ "$(git ls-files -s -- "$path" | cut -d ' ' -f 1)" = 100644 ] ||
    die "nonregular tracked guest: $path"
  if grep -Fxq "$path" "$temp/seen"; then die "duplicate: $path"; fi
  printf '%s\n' "$path" >> "$temp/seen"
  # Independent workflows must have distinct stdout oracles; otherwise
  # a copied/wrong guest can masquerade as a second tested behavior.
  if grep -Fxq "$expected" "$temp/seen-stdout"; then
    die "duplicate stdout oracle: $expected"
  fi
  printf '%s\n' "$expected" >> "$temp/seen-stdout"
  count=$((count + 1))
  [ "$count" -le 14 ] || die "more than 14 cases"
done < ci/native-cases.txt
[ "$count" -eq 14 ] || die "expected 14 cases, got $count"
git ls-files 'workflows/*.ores' | sort > "$temp/tracked"
sort "$temp/seen" > "$temp/manifest"
cmp -s "$temp/tracked" "$temp/manifest" || die "manifest/guest inventory mismatch"
printf 'NATIVE_MANIFEST_SOURCE_ONLY_PASS cases=%s\n' "$count"
