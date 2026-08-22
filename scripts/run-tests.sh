#!/usr/bin/env bash
# scripts/run-tests.sh — the single entry for all repo checks: caped trace
# plus every tests/*/test_*.sh suite. A new suite joins by dropping a script
# into a tests/<area>/ directory — no registration here.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0

echo "== caped trace =="
bash scripts/caped-trace.sh || fail=1

for t in tests/*/test_*.sh; do
  [ -f "$t" ] || continue
  echo
  echo "== $t =="
  bash "$t" || fail=1
done

echo
if [ "$fail" -eq 0 ]; then
  echo "ALL OK"
else
  echo "FAILURES — see the suite output above" >&2
  exit 1
fi
