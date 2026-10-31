#!/bin/sh
# Compiler-backed NEGATIVE challenges. A rejection is not proof of the
# underlying borrow rule without a trusted compiler and diagnostic provenance.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
die() { printf '%s\n' "NATIVE_SEMANTIC_NEGATIVE_FAILED: $*" >&2; exit 1; }
[ "$#" -eq 2 ] || die 'usage: verifier COMPILER PRIVATE_TEMP_DIR'
compiler="$1"
tmp="$2"
[ -f "$compiler" ] && [ -x "$compiler" ] && [ ! -L "$compiler" ] || die 'invalid compiler executable'
[ -d "$tmp" ] && [ ! -L "$tmp" ] || die 'invalid private temp directory'
[ -f workflows/coordinator-state.ores ] && [ ! -L workflows/coordinator-state.ores ] || die 'missing coordinator guest'
if command -v timeout >/dev/null 2>&1; then
  limiter="$(command -v timeout)"
elif command -v gtimeout >/dev/null 2>&1; then
  limiter="$(command -v gtimeout)"
else
  die 'no bounded execution tool'
fi
# Mutate the coordinator after its positive compile/run in the parent verifier.
# Intentionally invalid guests stay out of the fourteen-case output manifest.
sed 's/critical\[write\]/critical[read]/g' workflows/coordinator-state.ores > "$tmp/illegal-read-loan.ores"
sed 's/s[.]phase/self.phase/g' workflows/coordinator-state.ores > "$tmp/illegal-direct-field.ores"
grep -Fq 'self.handle_state(critical[read]' "$tmp/illegal-read-loan.ores" || die 'missing read-loan mutation'
grep -Fq 'self.phase' "$tmp/illegal-direct-field.ores" || die 'missing direct-field mutation'
for kind in read-loan direct-field; do
  file="$tmp/illegal-$kind.ores"
  cmp -s workflows/coordinator-state.ores "$file" && die "mutation did not change source: $kind"
  if "$limiter" --kill-after=5s 15s "$compiler" --check "$file" > "$tmp/negative-$kind.out" 2> "$tmp/negative-$kind.err"; then
    die "compiler accepted unsafe mutation: $kind"
  else
    status="$?"
  fi
  [ "$status" -gt 0 ] && [ "$status" -lt 124 ] || die "compiler timeout, crash or launch failure: $kind (exit $status)"
  [ -s "$tmp/negative-$kind.err" ] || [ -s "$tmp/negative-$kind.out" ] || die "missing rejection diagnostic: $kind"
  [ "$(wc -c < "$tmp/negative-$kind.out" | tr -d ' ')" -le 4096 ] || die "oversized rejection stdout: $kind"
  [ "$(wc -c < "$tmp/negative-$kind.err" | tr -d ' ')" -le 4096 ] || die "oversized rejection stderr: $kind"
  printf 'NATIVE_SEMANTIC_NEGATIVE_REJECTED case=%s\n' "$kind"
done
