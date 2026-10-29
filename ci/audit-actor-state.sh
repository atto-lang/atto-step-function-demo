#!/bin/sh
# Source-shape guard only; actual compiler effects/borrow checks remain required.
set -eu
[ "$#" -gt 0 ] || { echo 'STATE_POLICY_NO_SOURCE' >&2; exit 1; }
for source do
  [ -f "$source" ] || { echo "STATE_POLICY_MISSING: $source" >&2; exit 1; }
  awk '
    /^define (isolated )?actor [A-Za-z_][A-Za-z0-9_]* as$/ {
      if (inside) invalid = 1
      inside = 1
      count = 0
      next
    }
    inside && /^  state[[:space:]]*[{]/ {
      count++
      if (count > 1) invalid = 1
    }
    inside && /^  (let|val|var|mut)[[:space:]]/ { invalid = 1 }
    # Only the explicit actor control APIs are currently used in this demo.
    # A direct self.<field> read, write or unknown method is not a valid
    # substitute for a compiler-sealed actor state loan. No string matching
    # here constitutes a complete compiler reference-escape checker.
    inside && /self[.][A-Za-z_][A-Za-z0-9_]*/ {
      line = $0
      sub(/\/\/.*$/, "", line)
      gsub(/self[.](send|end|handle_state)[[:space:]]*[(]/, "ALLOWED_CALL(", line)
      if (line ~ /self[.][A-Za-z_][A-Za-z0-9_]*/) invalid = 1
    }
    inside && /^end$/ { inside = 0 }
    END {
      if (inside || invalid) exit 1
    }
  ' "$source" || { echo "STATE_POLICY_ACTOR_FIELD: $source" >&2; exit 1; }

  case "$source" in
    */coordinator-state.ores | coordinator-state.ores)
      awk '
        /^define actor WorkflowCoordinator as$/ { actor=1; actors++; next }
        actor && /^  state [{]$/ { states++ }
        actor && /^  receive[(]ActorMail<String> mail[)]: void with state[.]read, state[.]write [{]$/ { effects++ }
        actor && /^    val outcome = self[.]handle_state[(]critical-write [|]s[|] -> [{]$/ {
          writes++; in_loan=1; next
        }
        in_loan && /self[.]send[(]|self[.]end[(]|await[[:space:]]|spawn[[:space:]]|stdio[.]|return[[:space:]]+s[;]/ {
          invalid=1
        }
        in_loan && /^    [}][)];$/ { in_loan=0 }
        actor && /^end$/ { actor=0 }
        END {
          if (actors != 1 || states != 1 || effects != 1 ||
              writes != 1 || actor || in_loan || invalid) exit 1
        }
      ' "$source" || { echo "STATE_POLICY_CRITICAL_SECTION: $source" >&2; exit 1; }
    ;;
    */effect-receipt-ledger.ores | effect-receipt-ledger.ores)
      awk '
        /^define isolated actor WorkflowEffectLedger as$/ { actor=1; actors++; next }
        actor && /^  state [{]$/ { states++ }
        actor && /^  receive[(]ActorMail<String> mail[)]: void with state[.]read, state[.]write [{]$/ { effects++ }
        actor && /^    val reply = self[.]handle_state[(]critical-write [|]s[|] -> [{]$/ {
          writes++; in_loan=1; next
        }
        in_loan && /self[.]send[(]|self[.]end[(]|await[[:space:]]|spawn[[:space:]]|stdio[.]|return[[:space:]]+s[;]/ {
          invalid=1
        }
        in_loan && /^    [}][)];$/ { in_loan=0 }
        actor && /^end$/ { actor=0 }
        END {
          if (actors != 1 || states != 1 || effects != 1 ||
              writes != 1 || actor || in_loan || invalid) exit 1
        }
      ' "$source" || { echo "STATE_POLICY_EFFECT_LEDGER: $source" >&2; exit 1; }
    ;;
  esac
done