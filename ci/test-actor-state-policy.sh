#!/bin/sh
# Regression tests for static policy only; not native Oreslang compilation.
set -eu
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
source_file=workflows/coordinator-state.ores
mkdir -p "$tmp/ok" "$tmp/field" "$tmp/duplicate" "$tmp/send" "$tmp/direct" "$tmp/await" "$tmp/escape"
cp "$source_file" "$tmp/ok/coordinator-state.ores"
sh ci/audit-actor-state.sh "$tmp/ok/coordinator-state.ores"
awk '{ print; if ($0 == "  state {") print "  let int escaped = 1;" }' "$source_file" > "$tmp/field/coordinator-state.ores"
awk '{ print; if ($0 == "  state {") print "  state {" }' "$source_file" > "$tmp/duplicate/coordinator-state.ores"
awk '{ if ($0 == "    });") print "      self.send(\"unsafe-under-loan\");"; print }' "$source_file" > "$tmp/send/coordinator-state.ores"
awk '{ if ($0 == "    });") print "      self.phase = \"unsafe\";"; print }' "$source_file" > "$tmp/direct/coordinator-state.ores"
awk '{ if ($0 == "    });") print "      await unsafe_future;"; print }' "$source_file" > "$tmp/await/coordinator-state.ores"
awk '{ if ($0 == "    });") print "      return s;"; print }' "$source_file" > "$tmp/escape/coordinator-state.ores"
for kind in field duplicate send direct await escape; do
  if sh ci/audit-actor-state.sh "$tmp/$kind/coordinator-state.ores" >/dev/null 2>&1; then
    echo "STATE_POLICY_FALSE_ACCEPT: $kind" >&2
    exit 1
  fi
done
# Reconcile the AI-agent effect-ledger contract: no mutable bypass or
# messaging while the synthetic in-memory outcome is unknown.
effect_source=workflows/effect-receipt-ledger.ores
cp "$effect_source" "$tmp/ok/effect-receipt-ledger.ores"
sh ci/audit-actor-state.sh "$tmp/ok/effect-receipt-ledger.ores"
mkdir -p "$tmp/effect-field" "$tmp/effect-send" "$tmp/effect-direct-write" "$tmp/effect-direct-read" "$tmp/unknown-direct" "$tmp/effect-url-bypass"
awk '{ print; if ($0 == "  state {") print "  let String extra = \"unsafe\";" }' "$effect_source" > "$tmp/effect-field/effect-receipt-ledger.ores"
awk '{ if ($0 == "    });") print "      self.send(\"unsafe-under-loan\");"; print }' "$effect_source" > "$tmp/effect-send/effect-receipt-ledger.ores"
# Names other than phase must be rejected as well; direct self-field
# bypass cannot depend on one hardcoded field name.
awk '{ if ($0 == "    });") print "      self.surprise = 7;"; print }' "$source_file" > "$tmp/unknown-direct/coordinator-state.ores"
if sh ci/audit-actor-state.sh "$tmp/unknown-direct/coordinator-state.ores" >/dev/null 2>&1; then
  echo "STATE_POLICY_FALSE_ACCEPT: unknown-direct" >&2
  exit 1
fi
awk '{ if ($0 == "    });") print "      self.transition_epoch = 99;"; print }' "$effect_source" > "$tmp/effect-direct-write/effect-receipt-ledger.ores"
awk '{ if ($0 == "    });") print "      val leaked = self.transition_epoch;"; print }' "$effect_source" > "$tmp/effect-direct-read/effect-receipt-ledger.ores"
# A real string literal containing "//" must not disable the rest of the
# line's self-field checks (comment-only lines are the only exemption).
awk '{ if ($0 == "    });") print "      stdio.stdout.write(\"http://example\"); self.transition_epoch = 2;"; print }' "$effect_source" > "$tmp/effect-url-bypass/effect-receipt-ledger.ores"
for kind in effect-field effect-send effect-direct-write effect-direct-read effect-url-bypass; do
  if sh ci/audit-actor-state.sh "$tmp/$kind/effect-receipt-ledger.ores" >/dev/null 2>&1; then
    echo "STATE_POLICY_FALSE_ACCEPT: $kind" >&2
    exit 1
  fi
done
# Canonical bracket spelling and ASCII-adjacent hyphen shorthand are
# the same source policy. Unknown selectors and whitespace are not.
for kind in coordinator-state effect-receipt-ledger; do
  original="workflows/$kind.ores"
  mkdir -p "$tmp/mode-$kind"
  sed 's/critical\[write\]/critical-write/' "$original" > "$tmp/mode-$kind/$kind.ores"
  if sh ci/audit-actor-state.sh "$tmp/mode-$kind/$kind.ores" >/dev/null 2>&1; then
    echo "STATE_POLICY_FALSE_ACCEPT: hyphen alias $kind" >&2
    exit 1
  fi
  sed 's/critical\[write\]/critical[upgrade]/' "$original" > "$tmp/mode-$kind/invalid-$kind.ores"
  # Preserve the canonical basename for its fixture-specific policy.
  mv "$tmp/mode-$kind/invalid-$kind.ores" "$tmp/mode-$kind/$kind.ores"
  if sh ci/audit-actor-state.sh "$tmp/mode-$kind/$kind.ores" >/dev/null 2>&1; then
    echo "STATE_POLICY_FALSE_ACCEPT: unknown critical mode $kind" >&2
    exit 1
  fi
  sed 's/critical\[write\]/critical -write/' "$original" > "$tmp/mode-$kind/$kind.ores"
  if sh ci/audit-actor-state.sh "$tmp/mode-$kind/$kind.ores" >/dev/null 2>&1; then
    echo "STATE_POLICY_FALSE_ACCEPT: spaced critical hyphen $kind" >&2
    exit 1
  fi
done
# Reject value-returning callback regressions and expression-shaped loans.
mkdir -p "$tmp/coordinator-return" "$tmp/effect-return" "$tmp/coordinator-expression" "$tmp/effect-expression"
awk '{ if ($0 == "    });") print "      return \\"forged-value\\";"; print }' "$source_file" > "$tmp/coordinator-return/coordinator-state.ores"
awk '{ if ($0 == "    });") print "      return \\"forged-value\\";"; print }' "$effect_source" > "$tmp/effect-return/effect-receipt-ledger.ores"
sed 's/^    self.handle_state(/    val outcome = self.handle_state(/' "$source_file" > "$tmp/coordinator-expression/coordinator-state.ores"
sed 's/^    self.handle_state(/    val reply = self.handle_state(/' "$effect_source" > "$tmp/effect-expression/effect-receipt-ledger.ores"
for item in coordinator-return/coordinator-state effect-return/effect-receipt-ledger coordinator-expression/coordinator-state effect-expression/effect-receipt-ledger; do
  if sh ci/audit-actor-state.sh "$tmp/$item.ores" >/dev/null 2>&1; then
    echo "STATE_POLICY_FALSE_ACCEPT: $item" >&2
    exit 1
  fi
done
echo "STATE_POLICY_MUTATION_CASES_PASS (static only)"