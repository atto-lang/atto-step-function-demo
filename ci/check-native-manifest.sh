#!/bin/sh
# Structural source/oracle bijection; not native guest execution.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
fail() { printf 'ATTO_MANIFEST_FAIL: %s\n' "$*" >&2; exit 1; }
command -v git >/dev/null 2>&1 || fail "git unavailable"
[ -f ci/native-cases.txt ] && [ ! -L ci/native-cases.txt ] ||
  fail "manifest missing or symlinked"
git ls-files --error-unmatch -- ci/native-cases.txt >/dev/null 2>&1 ||
  fail "manifest is not tracked"
if git ls-files -- '*.ores' | grep -q .; then
  fail "legacy .ores source tracked (new sources must be .atto)"
fi
if ! awk -F '|' '
  /^[[:space:]]*(#|$)/ { next }
  NF != 2 || $1 !~ /^workflows\/[a-z0-9-]+[.]atto$/ || $2 !~ /^[a-z0-9:-]+$/ { bad=1; next }
  seen[$1]++ { bad=1 }
  output[$2]++ { bad=1 }
  { count++ }
  END { if (bad || count != 9) exit 1 }
' ci/native-cases.txt; then
  fail "expected nine unique safe .atto paths and distinct stdout oracles"
fi
tracked="$(git ls-files -- 'workflows/*.atto' | wc -l | tr -d ' ')"
[ "$tracked" -eq 9 ] || fail "expected nine tracked .atto workflows, found $tracked"
for source in $(git ls-files -- 'workflows/*.atto'); do
  [ -f "$source" ] && [ ! -L "$source" ] && [ -s "$source" ] ||
    fail "missing, empty or symlinked source: $source"
  mode="$(git ls-files -s -- "$source" | awk '{print $1}')"
  [ "$mode" = 100644 ] || fail "unexpected tracked source mode: $source $mode"
  awk -F '|' -v source="$source" '$1 == source { n++ }
    END { if (n != 1) exit 1 }' ci/native-cases.txt ||
      fail "source does not map to exactly one stdout oracle: $source"
done
for example in $(git ls-files -- 'examples/attolang/*.atto'); do
  [ -f "$example" ] && [ ! -L "$example" ] && [ -s "$example" ] ||
    fail "missing, empty or symlinked example: $example"
  [ "$(git ls-files -s -- "$example" | awk '{print $1}')" = 100644 ] ||
    fail "unexpected tracked example mode: $example"
done
printf 'NATIVE_ATTO_MANIFEST_PASS cases=9 (STRUCTURAL_ONLY; NOT_EXECUTED)\n'
