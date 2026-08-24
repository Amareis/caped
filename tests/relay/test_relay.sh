#!/usr/bin/env bash
# tests/relay/test_relay.sh — caped relay: the only door into a neighbor repo.
#
# Home repo + a sibling neighbor repo; the relay moves an idea (Idea: at the
# neighbor, home-marked Agent:, Archives: at home), --keep preserves the local
# copy. Scenario names carry the [#<slug>] marker they cover (root README).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAPED="$REPO_ROOT/caped"

pass=0; fail=0
ok()  { printf 'PASS %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

NB_DIR="$TMP/nb"

# Neighbor: a hooked caped repo.
mkdir -p "$NB_DIR"
cd "$NB_DIR"
git init -q
git config user.email test@caped.dev
git config user.name "caped test"
cp -r "$REPO_ROOT/scripts" scripts
printf 'root\tREADME.md\tenforced\tREADME.md\n' > caped.registry
bash scripts/caped-init.sh >/dev/null 2>&1
git add -A
git commit -qm seed --no-verify

# Home: a hooked caped repo with a neighbors file pointing at NB.
mkdir -p "$TMP/home"
cd "$TMP/home"
git init -q
git config user.email test@caped.dev
git config user.name "caped test"
cp -r "$REPO_ROOT/scripts" scripts
printf 'root\tREADME.md\tenforced\tREADME.md\n' > caped.registry
bash scripts/caped-init.sh >/dev/null 2>&1
printf '# neighbors\nnb\t%s\tplugin\n' "$NB_DIR" > caped.neighbors
git add -A
git commit -qm seed --no-verify

export CAPED_AGENT=dsh
bash "$CAPED" idea moveto "relay fixture"
bash "$CAPED" idea keeploc "relay --keep fixture"

# The sender id is required — no default (user: «дефолт human не делай»).
if env -u CAPED_AGENT bash "$CAPED" relay nb moveto >/dev/null 2>&1; then
  bad 'relay with an unset sender id passes [#neighbor-relay]'
else
  ok 'sender id is required — unset CAPED_AGENT refuses [#neighbor-relay]'
fi

OUT="$(bash "$CAPED" relay nb moveto 2>&1)"
if [ -f "$NB_DIR/ideas/moveto.md" ] && [ ! -f ideas/moveto.md ]; then
  ok 'relay moves the idea and withdraws the local copy [#neighbor-relay]'
else bad "relay move failed: $OUT"; fi
if git -C "$NB_DIR" log --format=%B -1 | grep -q '^Idea: moveto$'; then
  ok 'relay commit carries Idea: moveto at the neighbor [#neighbor-relay]'
else bad 'neighbor commit lacks Idea: moveto'; fi
if git -C "$NB_DIR" log --format=%B -1 | grep -q '^Agent: dsh@home$'; then
  ok 'relay commit is home-marked (Agent: <id>@<home>) [#residency-check]'
else bad "neighbor commit not home-marked: $(git -C "$NB_DIR" log --format=%B -1)"; fi
if git log --format=%B -1 | grep -q '^Archives: moveto$'; then
  ok 'local withdrawal carries Archives: moveto [#neighbor-relay]'
else bad 'local withdrawal lacks Archives:'; fi
if bash "$CAPED" render plan 2>&1 | grep -q '^  nb '; then
  ok 'plan shows the neighbors [#neighbor-relay]'
else bad 'plan misses the neighbors block'; fi

bash "$CAPED" relay nb keeploc --keep >/dev/null
if [ -f "$NB_DIR/ideas/keeploc.md" ] && [ -f ideas/keeploc.md ]; then
  ok '--keep keeps the local copy [#neighbor-relay]'
else bad '--keep did not keep the local copy'; fi

# Direct send: an UNCOMMITTED idea — only the neighbor's commit, no home commits.
cat > ideas/direct1.md <<'EOF'
---
name: direct1
summary: direct relay fixture
---

## Why

w

## Context

c

## Requirements

t

## Decisions

-

## Rejected alternatives

-

## Provenance

p

## Open questions

-
EOF
PRE="$(git rev-list --count HEAD)"
bash "$CAPED" relay nb direct1 >/dev/null
if [ -f "$NB_DIR/ideas/direct1.md" ] && [ ! -f ideas/direct1.md ]; then
  ok 'direct relay delivers an uncommitted idea and removes the local file [#neighbor-relay]'
else bad 'direct relay delivery failed'; fi
if [ "$(git rev-list --count HEAD)" = "$PRE" ]; then
  ok 'direct relay makes no home commits [#neighbor-relay]'
else bad 'direct relay produced home commits'; fi
if git -C "$NB_DIR" log --format=%B -1 | grep -q '^Agent: dsh@home$'; then
  ok 'direct relay commit is home-marked too [#neighbor-relay]'
else bad 'direct relay commit not home-marked'; fi

# Schema normalization: a relay from a foreign (non-canonical) schema arrives valid.
cat > ideas/noncanon.md <<'EOF'
---
name: noncanon
summary: noncanonical relay fixture
---

## Why

w
EOF
bash "$CAPED" relay nb noncanon >/dev/null
if [ -f "$NB_DIR/ideas/noncanon.md" ] && grep -q '^## Open questions' "$NB_DIR/ideas/noncanon.md" \
   && grep -q '^## Requirements' "$NB_DIR/ideas/noncanon.md"; then
  ok 'relay normalizes missing canonical sections [#neighbor-relay]'
else bad 'relay did not normalize the schema'; fi
if (cd "$NB_DIR" && bash "$REPO_ROOT/scripts/caped.sh" check >/dev/null 2>&1); then
  ok 'relayed idea passes the receiver check [#neighbor-relay]'
else bad 'relayed idea fails the receiver check'; fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]