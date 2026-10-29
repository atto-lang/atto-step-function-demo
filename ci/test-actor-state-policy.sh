#!/bin/sh
# Regression tests for static policy only; not native Oreslang compilation.
set -eu
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
source_file=workflows/coordinator-state.ores
mkdir -p "$tmp/ok" "$tmp/field" "$tmp/duplicate" "$tmp/send" "$tmp/direct" "$tmp/await" "$tmp/escape" "$tmp/mode" "$tmp/bare" "$tmp/return"
cp "$source_file" "$tmp/ok/coordinator-state.ores"
sh ci/audit-actor-state.sh "$tmp/ok/coordinator-state.ores"
awk '{ print; if ($0 == "  state {") print "  let int escaped = 1;" }' "$source_file" > "$tmp/field/coordinator-state.ores"
awk '{ print; if ($0 == "  state {") print "  state {" }' "$source_file" > "$tmp/duplicate/coordinator-state.ores"
awk '{ if ($0 == "    });") print "      self.send(\"unsafe-under-loan\");"; print }' "$source_file" > "$tmp/send/coordinator-state.ores"
awk '{ if ($0 == "    });") print "      self.phase = \"unsafe\";"; print }' "$source_file" > "$tmp/direct/coordinator-state.ores"
awk '{ if ($0 == "    });") print "      await unsafe_future;"; print }' "$source_file" > "$tmp/await/coordinator-state.ores"
awk '{ if ($0 == "    });") print "      return s;"; print }' "$source_file" > "$tmp/escape/coordinator-state.ores"
sed 's/critical\[write\]/critical[read]/' "$source_file" > "$tmp/mode/coordinator-state.ores"
sed 's/critical\[write\]/critical/' "$source_file" > "$tmp/bare/coordinator-state.ores"
awk '{ if ($0 == "    });") print "      return \"forged-value\";"; print }' "$source_file" > "$tmp/return/coordinator-state.ores"
for kind in field duplicate send direct await escape mode bare return; do
  if sh ci/audit-actor-state.sh "$tmp/$kind/coordinator-state.ores" >/dev/null 2>&1; then
    echo "STATE_POLICY_FALSE_ACCEPT: $kind" >&2
    exit 1
  fi
done
echo "STATE_POLICY_MUTATION_CASES_PASS (static only)"