#!/bin/sh
# Test harness only; workflow logic lives exclusively in .ores source.
set -eu
cd "$(dirname "$0")/.."

# Do not silently accept a Node simulator, a missing binary, or no executed guest programs.
if [ -n "${ORESLANG_BIN:-}" ]; then
  compiler="$ORESLANG_BIN"
else
  compiler="$(command -v oreslang-compiler || command -v oreslang || true)"
fi
if [ -z "$compiler" ] || [ ! -x "$compiler" ]; then
  echo "NOT_EXECUTED: native Oreslang compiler binary unavailable; set ORESLANG_BIN" >&2
  exit 1
fi
while IFS='|' read -r file expected; do
  [ -n "$file" ] || continue
  echo "checking .ores guest: $file"
  "$compiler" --check "$file"
  echo "executing .ores guest: $file"
  actual="$("$compiler" "$file")"
  if [ "$actual" != "$expected" ]; then
    printf 'FAILED: %s expected <%s> got <%s>\n' "$file" "$expected" "$actual" >&2
    exit 1
  fi
done <<'CASES'
workflows/order-workflow.ores|order:complete
workflows/order-rejected.ores|order:rejected
workflows/agent-memory-workflow.ores|memory:fixture-indexed
workflows/agent-memory-quarantine.ores|memory:quarantined
workflows/release-review-workflow.ores|release:preview-only
workflows/release-waiting.ores|release:waiting
CASES
echo "6 native Oreslang guest scenarios executed successfully."
