#!/bin/sh
# Static exception inventory only. NOT native Oreslang compiler/runtime evidence.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf 'ACTOR_STATE_INVENTORY_REJECT: %s\n' "$*" >&2; exit 1; }
manifest=ci/legacy-stateless-actors.txt
[ -f "$manifest" ] && [ ! -L "$manifest" ] || die 'missing or symlinked exception inventory'
[ "$(git ls-files -s -- "$manifest" | cut -d ' ' -f1)" = 100644 ] || die 'untracked/nonregular inventory'
# Structural evidence must describe the exact committed manifest, even when
# skip-worktree or assume-unchanged masks an edited working copy from git status.
manifest_head_blob="$(git rev-parse --verify "HEAD:$manifest" 2>/dev/null)" ||
  die 'inventory absent from HEAD'
manifest_disk_blob="$(git hash-object -- "$manifest")" ||
  die 'cannot hash inventory'
[ "$manifest_disk_blob" = "$manifest_head_blob" ] ||
  die 'inventory differs from HEAD Git blob'
tmp="$(mktemp -d)" || die 'cannot allocate scratch'
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
: > "$tmp/observed"
git ls-files -- 'workflows/*.ores' 'examples/oreslang/*.ores' > "$tmp/sources"
[ -s "$tmp/sources" ] || die 'empty source inventory'
while IFS= read -r path; do
  [ -f "$path" ] && [ ! -L "$path" ] || die "missing/symlinked source: $path"
  [ "$(git ls-files -s -- "$path" | cut -d ' ' -f1)" = 100644 ] || die "nonregular source: $path"
  # Every source parsed below must match HEAD bytes, not just the Git index.
  source_head_blob="$(git rev-parse --verify "HEAD:$path" 2>/dev/null)" ||
    die "source absent from HEAD: $path"
  source_disk_blob="$(git hash-object -- "$path")" ||
    die "cannot hash source: $path"
  [ "$source_disk_blob" = "$source_head_blob" ] ||
    die "actor source differs from HEAD Git blob: $path"
  awk -v file="$path" '
    $1 == "define" {
      a = 0
      for (i=2; i<=NF; i++) if ($i=="actor") a=i
      if (a>0) {
        if (actor!="" || NF!=a+2 || $(a+2)!="as" ||
            $(a+1)!~/^[A-Za-z_][A-Za-z0-9_]*$/) bad=1
        else { actor=$(a+1); states=0 }
      }
    }
    actor!="" && /^  state[[:space:]]*[{]/ { states++ }
    actor!="" && /^end$/ {
      if (states==0) print file "|" actor
      if (states>1) bad=1
      actor=""
    }
    END { if (actor!="" || bad) exit 1 }
  ' "$path" >> "$tmp/observed" || die "malformed actor state shape: $path"
done < "$tmp/sources"
awk -F '|' '
  NF!=2 || $1!~/^(workflows|examples\/oreslang)\/[a-z0-9-]+[.]ores$/ ||
    $2!~/^[A-Za-z_][A-Za-z0-9_]*$/ { bad=1 }
  seen[$0]++ { bad=1 }
  END { if (bad) exit 1 }
' "$manifest" || die 'invalid/duplicate exception'
sort -u "$manifest" > "$tmp/sorted"
cmp -s "$manifest" "$tmp/sorted" || die 'inventory not canonical sorted/unique'
sort "$tmp/observed" > "$tmp/actual"
cmp -s "$tmp/actual" "$manifest" || die 'new or missing state-less actor exception'
count="$(wc -l < "$manifest" | tr -d ' ')"
[ "$count" -le 39 ] || die 'legacy exception budget exceeded'
printf 'ACTOR_STATE_INVENTORY_STRUCTURAL_PASS legacy_stateless=%s\n' "$count"
echo 'NOT_EXECUTED: no native Oreslang compiler or actor runtime verified'
