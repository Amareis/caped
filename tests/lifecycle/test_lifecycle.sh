#!/usr/bin/env bash
# tests/lifecycle/test_lifecycle.sh — lifecycle wrapper commands (idea|work|archive)
# against a real init-wired fixture; scenario names carry [#lifecycle-cmds].
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAPED="$REPO_ROOT/scripts/caped.sh"

pass=0; fail=0
ok()  { printf 'PASS %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
git init -q
git config user.email test@caped.dev
git config user.name "caped test"
bash "$REPO_ROOT/scripts/caped.sh" init >/dev/null
printf '# fixture\n\n## Requirements\n\n- plain bullet\n' > README.md
git add -A; git commit -qm seed --no-verify

export CAPED_AGENT=human

mkdir -p ideas
printf -- '---\nname: _backlog\nsummary: x\n---\n\n## Requirements\n\n- placeholder\n' > ideas/_backlog.md
git add ideas/_backlog.md
git commit -qF - <<'EOF'
идея _backlog

Idea: _backlog
Agent: human
EOF

bash "$CAPED" idea gamma "a lifecycle fixture"
if [ -f ideas/gamma.md ] && grep -q 'name: gamma' ideas/gamma.md; then ok 'idea: skeleton born [#lifecycle-cmds]'
else bad 'idea: no skeleton'; fi
if git log --format=%B -1 | grep -q '^Idea: gamma$'; then ok 'idea: Idea trailer landed [#lifecycle-cmds]'
else bad 'idea: trailer missing'; fi

bash "$CAPED" work gamma
if [ -f changes/gamma.md ] && [ ! -e ideas/gamma.md ]; then ok 'work: clean mv into changes [#lifecycle-cmds]'
else bad 'work: mv failed'; fi
if git log --format=%B -1 | grep -q '^Change: gamma$'; then ok 'work: Change trailer landed [#lifecycle-cmds]'
else bad 'work: trailer missing'; fi

printf -- '---\nname: gamma\nsummary: x\n---\n\n## Why\n\nw\n\n## Context\n\nk\n\n## Requirements\n\nt\n\n## Decisions\n\n-\n\n## Rejected alternatives\n\n-\n\n## Provenance\n\np\n\n## Open questions\n\n- Куда деть флаг: v0.1.\n' > changes/gamma.md
git add changes/gamma.md
git commit -qF - <<'EOF'
работа gamma: вопрос

Change: gamma
Agent: human
EOF

bash "$CAPED" archive gamma
if [ ! -e changes/gamma.md ]; then ok 'archive: file removed [#lifecycle-cmds]'
else bad 'archive: file still there'; fi
if git log --format=%B -1 | grep -q '^Archives: gamma$'; then ok 'archive: Archives trailer landed [#lifecycle-cmds]'
else bad 'archive: trailer missing'; fi
if grep -q 'gamma' ideas/_backlog.md; then ok 'archive: deferred OQ deposited into _backlog [#lifecycle-cmds]'
else bad 'archive: no deposit'; fi

set +e
bash "$CAPED" work nonexistent >/dev/null 2>&1; RC=$?
set -e
if [ "$RC" -eq 2 ]; then ok 'work of a missing idea exits 2 [#lifecycle-cmds]'
else bad "work missing rc=$RC"; fi
set +e
bash "$CAPED" archive nonexistent >/dev/null 2>&1; RC=$?
set -e
if [ "$RC" -eq 2 ]; then ok 'archive of a missing change exits 2 [#lifecycle-cmds]'
else bad "archive missing rc=$RC"; fi
set +e
bash "$CAPED" idea '' >/dev/null 2>&1; RC=$?
set -e
if [ "$RC" -eq 2 ]; then ok 'idea without a name exits 2 [#lifecycle-cmds]'
else bad "idea noname rc=$RC"; fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
