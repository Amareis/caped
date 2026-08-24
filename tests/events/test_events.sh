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
export CAPED_BUNDLE_PATH="$TMP/bundle.md"
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

# --- tool-updated: the bundle head vs the session cursor ---------------------
printf 'caped changelog: 1 contract change(s) · head a1b2c3d4 · 2026-08-23\n' > "$TMP/bundle.md"
bash "$CAPED" events >/dev/null 2>&1
N1="$(wc -l < .caped/events/feed.jsonl)"
printf 'caped changelog: 2 contract change(s) · head e5f6a7b8 · 2026-08-23\n' > "$TMP/bundle.md"
bash "$CAPED" events >/dev/null 2>&1
N2="$(wc -l < .caped/events/feed.jsonl)"
if [ "$N2" -gt "$N1" ] && tail -1 .caped/events/feed.jsonl | grep -q 'tool-updated'; then
  ok 'tool-updated event when the bundle head moves [#tool-version]'
else
  bad "tool-updated missing: $(tail -1 .caped/events/feed.jsonl 2>/dev/null)"
fi

# --- commit-rejected: hook rejection is a feed fact ---------------------------
if grep -q '"t":"commit-rejected"' .caped/events/feed.jsonl 2>/dev/null; then
  bad 'commit-rejected leaked on a valid chain [#commit-rejected-event]'
else ok 'valid commits do not emit commit-rejected [#commit-rejected-event]'; fi
N0="$(wc -l < .caped/events/feed.jsonl)"
mkdir -p changes
printf '# z\n' > changes/z.md; git add changes/z.md
set +e; git commit -qF - <<'MSG' >/dev/null 2>&1; RC=$?; set -e
if [ "$RC" -ne 0 ]; then ok 'hook rejects the direct change add (setup) [#commit-rejected-event]'
else bad 'hook accepted the direct add'; git reset -q --soft HEAD~1; fi
N1="$(wc -l < .caped/events/feed.jsonl)"
if [ "$N1" -gt "$N0" ] && tail -1 .caped/events/feed.jsonl | grep -q '"t":"commit-rejected"'; then
  ok 'rejected commit lands as commit-rejected in the feed [#commit-rejected-event]'
else bad "commit-rejected missing: $(tail -1 .caped/events/feed.jsonl 2>/dev/null)"; fi
git reset -q -- changes/z.md 2>/dev/null || true; rm -f changes/z.md

# --- caped version: the consumer contract point -----------------------------
OUT="$(bash "$CAPED" version)"
case "$OUT" in
  *'caped changelog: 2 contract change(s)'*) ok 'caped version prints the bundle head [#tool-version]' ;;
  *) bad "version wrong: $OUT" ;;
esac
P="$(bash "$CAPED" version --path)"
if [ "$P" = "$TMP/bundle.md" ]; then ok 'version --path prints the bundle path [#tool-version]'
else bad "path wrong: $P"; fi
OUT="$(CAPED_BUNDLE_PATH="$TMP/none.md" bash "$CAPED" version 2>&1)"
if [ "$?" -eq 0 ] && printf '%s' "$OUT" | grep -q 'no bundled changelog'; then
  ok 'version without a bundle answers cleanly [#tool-version]'
else
  bad "no-bundle answer wrong: $OUT"
fi

# --- caped version --changelog: the bundle contents -------------------------
OUT="$(bash "$CAPED" version --changelog)"
EXP="$(cat "$TMP/bundle.md")"
if [ "$OUT" = "$EXP" ]; then ok 'version --changelog prints the bundle contents [#tool-version]'
else bad "changelog wrong: $(printf '%s' "$OUT" | head -1)"; fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
