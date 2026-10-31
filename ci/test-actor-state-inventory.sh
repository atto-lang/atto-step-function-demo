#!/bin/sh
# Local source-only mutation probes, not Oreslang guest compilation.
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
commit_fixture() {
  git -C "$tmp" add ci workflows examples
  git -C "$tmp" -c user.name='State Inventory Test' -c user.email='inventory@example.invalid' commit -qm "$1"
}
reject() {
  if (cd "$tmp" && sh ci/check-actor-state-inventory.sh) > "$tmp/check.stdout" 2> "$tmp/check.stderr"; then
    echo "INVENTORY_FALSE_ACCEPT: $1" >&2; exit 1
  fi
  printf 'ACTOR_STATE_INVENTORY_NEGATIVE_PASS %s\n' "$1"
}
commit_fixture 'initial synthetic actor inventory'
(cd "$tmp" && sh ci/check-actor-state-inventory.sh) >/dev/null
cat > "$tmp/workflows/extra.ores" <<'GUEST'
define pub actor NewStateful as
  state {
  }
end
GUEST
commit_fixture 'new actor has explicit state'
(cd "$tmp" && sh ci/check-actor-state-inventory.sh) >/dev/null
cat > "$tmp/workflows/extra.ores" <<'GUEST'
define actor UnsafeNewStateless as
end
GUEST
commit_fixture 'unsafe extra actor for negative test'
reject 'unreviewed stateless actor'
git -C "$tmp" rm -q -f workflows/extra.ores
commit_fixture 'restore baseline'
echo 'workflows/order-workflow.ores|StepB' >> "$tmp/ci/legacy-stateless-actors.txt"
commit_fixture 'invalid duplicate exemption'
reject 'duplicate exemption'
sed -i '$d' "$tmp/ci/legacy-stateless-actors.txt"
commit_fixture 'remove duplicate'
printf 'define isolated actor Coordinator as\nend\n' > "$tmp/workflows/coordinator-state.ores"
commit_fixture 'remove coordinator state'
reject 'lost coordinator state'
# Restore valid fixture and prove an index flag cannot conceal changed bytes.
cat > "$tmp/workflows/coordinator-state.ores" <<'GUEST'
define isolated actor Coordinator as
  state {
    phase: String = "created";
  }
end
GUEST
commit_fixture 'restore state before tamper'
git -C "$tmp" update-index --assume-unchanged workflows/order-workflow.ores
printf '\n// tampered after commit\n' >> "$tmp/workflows/order-workflow.ores"
reject 'assume-unchanged source bypass'
git -C "$tmp" update-index --no-assume-unchanged workflows/order-workflow.ores
git -C "$tmp" checkout -q -- workflows/order-workflow.ores
git -C "$tmp" update-index --skip-worktree ci/legacy-stateless-actors.txt
printf '# tampered after commit\n' >> "$tmp/ci/legacy-stateless-actors.txt"
reject 'skip-worktree manifest bypass'
git -C "$tmp" update-index --no-skip-worktree ci/legacy-stateless-actors.txt
printf 'ACTOR_STATE_INVENTORY_SYNTHETIC_SELFTEST_PASS\n'
