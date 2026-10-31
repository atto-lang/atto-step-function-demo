#!/bin/sh
# Compiler-backed NEGATIVE challenges; source-free stubs are never guest evidence.
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
# Parent verifier first checks and executes the pristine coordinator guest.
sed 's/critical\[write\]/critical[read]/g' workflows/coordinator-state.ores > "$tmp/illegal-read-loan.ores"
sed 's/s[.]phase/self.phase/g' workflows/coordinator-state.ores > "$tmp/illegal-direct-field.ores"
grep -Fq 'self.handle_state(critical[read]' "$tmp/illegal-read-loan.ores" || die 'missing read-loan mutation'
grep -Fq 'self.phase' "$tmp/illegal-direct-field.ores" || die 'missing direct-field mutation'
for kind in read-loan direct-field; do
  file="$tmp/illegal-$kind.ores"
  cmp -s workflows/coordinator-state.ores "$file" && die "mutation did not change source: $kind"
  status=0
  "$limiter" --kill-after=5s 15s "$compiler" --check "$file" > "$tmp/negative-$kind.out" 2> "$tmp/negative-$kind.err" || status=$?
  [ "$status" -eq 1 ] || die "expected compiler error exit 1, got $status: $kind"
  [ ! -s "$tmp/negative-$kind.out" ] || die "unexpected compiler stdout: $kind"
  [ -s "$tmp/negative-$kind.err" ] || die "missing rejection diagnostic: $kind"
  [ "$(wc -c < "$tmp/negative-$kind.err" | tr -d ' ')" -le 4096 ] || die "oversized diagnostic: $kind"
  grep -Fq "illegal-$kind.ores" "$tmp/negative-$kind.err" || die "diagnostic not tied to challenged source: $kind"
  case "$kind" in
    read-loan)
      grep -Eiq 'read.only|readonly|immutable.*state|cannot.*(write|mutat|assign)|write.*read.*loan|state.*loan.*write' "$tmp/negative-$kind.err" ||
        die "missing read-only loan semantic diagnostic: $kind"
      ;;
    direct-field)
      grep -Eiq 'sealed|direct.*(field|state)|state.*(private|inaccessible|forbidden|access)|self[.]phase.*(private|inaccessible|forbidden)|cannot.*(field|state).*access' "$tmp/negative-$kind.err" ||
        die "missing sealed-state semantic diagnostic: $kind"
      ;;
  esac
  printf 'NATIVE_SEMANTIC_NEGATIVE_REJECTED case=%s\n' "$kind"
done
