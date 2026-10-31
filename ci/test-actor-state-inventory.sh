#!/bin/sh
# Isolated source-only actor inventory mutation probes, NOT guest execution.
set -eu
export LC_ALL=C
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
git -C "$tmp" config user.name "Actor State Inventory Test"
git -C "$tmp" config user.email "actor-inventory@example.invalid"
git -C "$tmp" add ci workflows
git -C "$tmp" commit -qm 'synthetic actor inventory baseline'
base="$(git -C "$tmp" rev-parse HEAD)"
accept() {
  (cd "$tmp" && sh ci/check-actor-state-inventory.sh) >/dev/null ||
    { echo "INVENTORY_FALSE_REJECT: $1" >&2; exit 1; }
}
reject() {
  if (cd "$tmp" && sh ci/check-actor-state-inventory.sh) >/dev/null 2>&1; then
    echo "INVENTORY_FALSE_ACCEPT: $1" >&2; exit 1
  fi
}
commit_case() {
  git -C "$tmp" add -A
  git -C "$tmp" commit -qm "$1"
}
accept baseline
cat > "$tmp/workflows/extra.ores" <<'GUEST'
define pub actor NewStateful as
  state {
  }
end
GUEST
commit_case 'admitted explicit stateful actor'
accept new-stateful-actor
cat > "$tmp/workflows/extra.ores" <<'GUEST'
define actor UnsafeNewStateless as
end
GUEST
commit_case 'unlisted stateless actor'
reject unreviewed-stateless-actor
git -C "$tmp" rm -q -f workflows/extra.ores
git -C "$tmp" commit -qm 'remove unsafe extra actor'
echo 'workflows/order-workflow.ores|StepB' >> "$tmp/ci/legacy-stateless-actors.txt"
commit_case 'duplicate exemption'
reject duplicate-exemption
sed -i '$d' "$tmp/ci/legacy-stateless-actors.txt"
commit_case 'restore exception inventory'
printf 'define isolated actor Coordinator as\nend\n' > "$tmp/workflows/coordinator-state.ores"
commit_case 'remove coordinator state'
reject lost-coordinator-state

# Restore a valid exact commit before testing hidden working-tree mutations.
git -C "$tmp" reset --hard -q "$base"
accept restored-baseline
git -C "$tmp" update-index --skip-worktree -- ci/legacy-stateless-actors.txt
echo 'workflows/order-workflow.ores|Unapproved' >> "$tmp/ci/legacy-stateless-actors.txt"
reject skip-worktree-hidden-manifest
git -C "$tmp" update-index --no-skip-worktree -- ci/legacy-stateless-actors.txt
git -C "$tmp" reset --hard -q "$base"

git -C "$tmp" update-index --assume-unchanged -- workflows/order-workflow.ores
printf '// hidden source mutation\n' >> "$tmp/workflows/order-workflow.ores"
reject assume-unchanged-hidden-source
git -C "$tmp" update-index --no-assume-unchanged -- workflows/order-workflow.ores
git -C "$tmp" reset --hard -q "$base"
accept final-baseline
echo 'ACTOR_STATE_INVENTORY_SYNTHETIC_SELFTEST_PASS (committed-state and hidden-dirty negatives)'
