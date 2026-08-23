#!/usr/bin/env bash
# scripts/run-tests.sh — the single entry for all repo checks: caped trace
# plus every tests/*/test_*.sh suite. A new suite joins by dropping a script
# into a tests/<area>/ directory — no registration here.
#
# Suites are independent throwaway repos in mktemp: after the serial trace,
# they run in PARALLEL (each writes its log; results are printed in the same
# order as before).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0

echo "== caped trace =="
bash scripts/caped-trace.sh || fail=1

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

n=0
declare -a suites
for t in tests/*/test_*.sh; do
  [ -f "$t" ] || continue
  n=$((n + 1))
  suites[$n]="$t"
  ( bash "$t" > "$TMPD/out$n" 2>&1; echo "$?" > "$TMPD/rc$n" ) &
done
wait

for k in $(seq 1 "$n"); do
  echo
  echo "== ${suites[$k]} =="
  cat "$TMPD/out$k"
  rc="$(cat "$TMPD/rc$k")"
  [ "$rc" -eq 0 ] || fail=1
done

echo
if [ "$fail" -eq 0 ]; then
  echo "ALL OK"
else
  echo "FAILURES — see the suite output above" >&2
  exit 1
fi
