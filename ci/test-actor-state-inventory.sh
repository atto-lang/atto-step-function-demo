#!/bin/sh
# Isolated source-only actor inventory mutation probes, NOT guest execution.
set -eu
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/ci" "$tmp/workflows" "$tmp/examples/oreslang"
cp ci/check-actor-state-inventory.sh "$tmp/ci/"
cat > "$tmp/workflows/coordinator-state.ores" <<'GUEST'
define isolated actor Coordinator as
  state {
    phase: String = "created";
  }
end
GUEST
cat > "$tmp/workflows/order-workflow.ores" <<'GUEST'
define actor StepA as
end
define actor StepB as
end
GUEST
cat > "$tmp/ci/legacy-stateless-actors.txt" <<'MANIFEST'
workflows/order-workflow.ores|StepA
workflows/order-workflow.ores|StepB
MANIFEST
git -C "$tmp" init -q
git -C "$tmp" add ci workflows
(cd "$tmp" && sh ci/check-actor-state-inventory.sh) >/dev/null
cat > "$tmp/workflows/extra.ores" <<'GUEST'
define pub actor NewStateful as
  state {
  }
end
GUEST
git -C "$tmp" add workflows/extra.ores
(cd "$tmp" && sh ci/check-actor-state-inventory.sh) >/dev/null
cat > "$tmp/workflows/extra.ores" <<'GUEST'
define actor UnsafeNewStateless as
end
GUEST
if (cd "$tmp" && sh ci/check-actor-state-inventory.sh) >/dev/null 2>&1; then
  echo 'INVENTORY_FALSE_ACCEPT: unreviewed stateless actor' >&2; exit 1
fi
git -C "$tmp" rm -q -f workflows/extra.ores
echo 'workflows/order-workflow.ores|StepB' >> "$tmp/ci/legacy-stateless-actors.txt"
if (cd "$tmp" && sh ci/check-actor-state-inventory.sh) >/dev/null 2>&1; then
  echo 'INVENTORY_FALSE_ACCEPT: duplicate exemption' >&2; exit 1
fi
sed -i '$d' "$tmp/ci/legacy-stateless-actors.txt"
printf 'define isolated actor Coordinator as\nend\n' > "$tmp/workflows/coordinator-state.ores"
if (cd "$tmp" && sh ci/check-actor-state-inventory.sh) >/dev/null 2>&1; then
  echo 'INVENTORY_FALSE_ACCEPT: lost coordinator state' >&2; exit 1
fi
echo 'ACTOR_STATE_INVENTORY_SYNTHETIC_SELFTEST_PASS'
