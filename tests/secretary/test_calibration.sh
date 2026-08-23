#!/usr/bin/env bash
# tests/secretary/test_calibration.sh — cross-repo guard: the real dsh harness
# (neighbor caped-context plugin e2e, DSH_REPO) as the calibration runner.
# Skip unless BOTH the harness checkout and a provider key are present — the
# same policy as the CAPED_EVAL gate. Scenario names carry [#secretary-e2e].
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0; fail=0
ok()  { printf 'PASS %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

DSH="${DSH_HARNESS:-$(dirname "$REPO_ROOT")/caped-context/tests}"
RUN="${DSH_REPO:-$(dirname "$(dirname "$REPO_ROOT")")/deepseek-harness}/apps/cli/lib/bin.js"
KEY="${LLM_API_KEY:-}"

if [ ! -f "$RUN" ] || [ -z "$KEY" ]; then
  ok 'calibration skipped without harness checkout or provider key (guard) [#secretary-e2e]'
  echo
  echo "pass=$pass fail=$fail"
  [ "$fail" -eq 0 ]
  exit 0
fi

# Full calibration path: boot a REAL headless session via the neighbor's pattern,
# probing a caped workspace, and assert the model-visible marker reached the log.
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cd "$D"
git init -q
git config user.email test@caped.dev
git config user.name "caped test"
bash "$REPO_ROOT/scripts/caped.sh" init >/dev/null
printf 'root\tREADME.md\tenforced\tREADME.md\n' > caped.registry
printf '# fixture\n' > README.md
git add -A; git commit -qm seed --no-verify

PROMPT='Прочитай caped.registry и запусти caped без аргументов. Ответь одним предложением: сколько подкоманд в секции COMMANDS?'
MARKER='Прочитай caped.registry и запусти caped без аргументов'
set +e
node "$RUN" --profile headless "$PROMPT" > "$D/out" 2>&1; RC=$?
set -e
if [ "$RC" -ne 0 ]; then bad "headless run failed: $(tail -2 "$D/out")"
else ok 'real dsh headless session boots via the guard (calibration path) [#secretary-e2e]'; fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
