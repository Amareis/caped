#!/usr/bin/env bash
# tests/events/test_events.sh — lifecycle event feed + .caped/hooks dispatch.
#
# Fixture: fresh repo wired with the real init (commit-msg + post-commit shims,
# registry incl. the hooks cap), then lifecycle commits drive the real post-commit
# emitter; `caped events` reads the feed by cursor; a .caped/hooks/<event> script
# asserts dispatch. Scenario names carry [#event-feed].
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAPED="$REPO_ROOT/caped"

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
printf '# fixture\n\n## Requirements\n\n- [#fx no-test] Fixture requirement.\n' > README.md
mkdir -p .caped/hooks
cat > .caped/hooks/taken-into-work <<'HOOK'
#!/bin/sh
echo "dispatch $CAPED_EVENT $CAPED_ENTITY $CAPED_COMMIT" >> .caped/dispatch.log
HOOK
chmod +x .caped/hooks/taken-into-work
git add -A
git commit -qm seed --no-verify

mkdir -p ideas
printf -- '---\nname: ex1\nsummary: events fixture\n---\n' > ideas/ex1.md
git add ideas/ex1.md
git commit -qF - <<'FIX'
идея ex1

Idea: ex1
FIX

git mv ideas/ex1.md changes/ex1.md
git commit -qF - <<'FIX'
в работу ex1

Change: ex1
FIX

echo note >> changes/ex1.md; git add changes/ex1.md
git commit -qF - <<'FIX'
работа ex1

Change: ex1
FIX

git rm -q changes/ex1.md
git commit -qF - <<'FIX'
архив ex1

Change: ex1
Archives: ex1
FIX

printf '\nExtra prose outside the section.\n' >> README.md
git add README.md
git commit -qF - <<'FIX'
адхок: подчистить формулировку

тело: переформулировка без изменения требования.

Adhoc: fix-wording
Behavior: contract
Spec: README.md
FIX

OUT="$(bash "$CAPED" events)"
case "$OUT" in
  *'idea-born'*'ex1'*) ok 'idea-born event in the feed [#event-feed]' ;;
  *) bad "idea-born missing: $OUT" ;;
esac
case "$OUT" in
  *'taken-into-work'*'ex1'*) ok 'taken-into-work event in the feed [#event-feed]' ;;
  *) bad "taken-into-work missing: $OUT" ;;
esac
case "$OUT" in
  *'archived'*'ex1'*) ok 'archived event in the feed [#event-feed]' ;;
  *) bad "archived missing: $OUT" ;;
esac
case "$OUT" in
  *'"t":"adhoc"'*) ok 'adhoc event in the feed [#event-feed]' ;;
  *) bad "adhoc missing: $OUT" ;;
esac

N="$(wc -l < .caped/events/feed.jsonl)"
OUT="$(bash "$CAPED" events --since "$N")"
if [ -z "$OUT" ]; then ok 'cursor at the end yields nothing [#event-feed]'
else bad "expected empty after cursor: $OUT"; fi

if [ -f .caped/dispatch.log ] && grep -q 'dispatch taken-into-work ex1' .caped/dispatch.log; then
  ok 'dispatch ran .caped/hooks/taken-into-work with env context [#event-feed]'
else
  bad "dispatch log missing: $(cat .caped/dispatch.log 2>/dev/null || echo none)"
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
