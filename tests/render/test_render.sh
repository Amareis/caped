#!/usr/bin/env bash
# tests/render/test_render.sh — scenarios for scripts/caped-render.py.
#
# Each scenario builds a throwaway repo in mktemp with fixture commits that
# carry the lifecycle trailers (Idea:/Change:/Archives:), then runs the real
# `caped.sh render` from the project under test (the script resolves the repo
# root via git rev-parse, so the fixture itself needs no caped scripts).
#
# Scenario names carry the [#<slug>] marker of the requirement they cover
# (root README, "Производные view").
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAPED="$REPO_ROOT/scripts/caped.sh"

pass=0; fail=0
ok()  { printf 'PASS %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
n=0

new_repo() { # fresh repo inside $TMP, cd into it
  n=$((n + 1))
  local dir="$TMP/repo$n"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git config user.email test@caped.dev
  git config user.name "caped test"
  printf 'root\tREADME.md\tenforced\tREADME.md\n' > caped.registry
  printf '# fixture\n' > README.md
  git add -A
  git commit -qm seed
}

add_idea() { # <name> <summary> — ideas/<name>.md with frontmatter, no commit
  mkdir -p ideas
  cat > "ideas/$1.md" <<EOF
---
name: $1
summary: $2
priority: high
---
EOF
}

commit_msg() { # <message...> — commit all staged with trailers as given
  git commit -qF -
}

expect_out() { # <name> <args...> — run render, succeed, output in $OUT
  local name="$1"; shift
  set +e
  OUT="$(bash "$CAPED" render "$@" 2>&1)"; RC=$?
  set -e
  if [ "$RC" -eq 0 ]; then ok "$name"
  else bad "$name — exit $RC: $OUT"; fi
}

# --- fixture with a full lifecycle: born -> in work -> archived -------------
new_repo
add_idea alpha "the alpha change"
git add -A
commit_msg <<'EOF'
идея alpha

Idea: alpha
EOF
git mv ideas/alpha.md changes/alpha.md 2>/dev/null || { mkdir -p changes; git mv ideas/alpha.md changes/alpha.md; }
commit_msg <<'EOF'
в работу: alpha

Change: alpha
EOF
git rm -q changes/alpha.md
commit_msg <<'EOF'
архив: alpha

Change: alpha
Archives: alpha
EOF
add_idea beta "a live idea"
git add -A
commit_msg <<'EOF'
идея beta

Idea: beta
EOF

# Default run prints all three views and writes nothing. [#render-stdout]
expect_out 'default prints plan, history and coverage [#render-stdout]'
case "$OUT" in
  *"== plan =="*"== history"*"== coverage"*) ok 'default output has all three views [#render-stdout]' ;;
  *) bad "default output misses a view: $OUT" ;;
esac
if [ -e .caped ]; then bad 'default run created .caped/ [#render-stdout]'
else ok 'default run writes nothing [#render-stdout]'; fi

# A single view prints only that view. [#render-stdout]
expect_out 'single view run succeeds [#render-stdout]' plan
case "$OUT" in
  *"== plan =="*) ok 'plan view printed [#render-stdout]' ;;
  *) bad "plan view missing: $OUT" ;;
esac
case "$OUT" in
  *"== history"*) bad "plan-only run leaked history: $OUT" ;;
  *) ok 'plan-only run has no history section [#render-stdout]' ;;
esac

# History reconstructs the archive from trailers. [#render-history]
expect_out 'history view succeeds [#render-history]' history
case "$OUT" in
  *alpha*"(was:"*) bad "unexpected rename alias: $OUT" ;;
  *alpha*) ok 'archived change listed [#render-history]' ;;
  *) bad "archived change missing: $OUT" ;;
esac
case "$OUT" in
  *"the alpha change"*) ok 'archived summary recovered [#render-history]' ;;
  *) bad "archived summary missing: $OUT" ;;
esac
case "$OUT" in
  *beta*"- idea"*) ok 'live idea status read from the filesystem [#render-history]' ;;
  *) bad "live idea row wrong: $OUT" ;;
esac


# --- change show: rebuild an entity in one call ----------------------------
expect_out 'change show of an archived change [#change-show]' change show alpha
case "$OUT" in
  *"== change: alpha =="*"archived"*"архив: alpha"*) ok 'archived: final doc + timeline [#change-show]' ;;
  *) bad "archived show wrong: $OUT" ;;
esac
expect_out 'change show of a live idea [#change-show]' change show beta
case "$OUT" in
  *"== change: beta =="*"idea"*"идея beta"*) ok 'live idea: doc from FS [#change-show]' ;;
  *) bad "live idea show wrong: $OUT" ;;
esac
mkdir -p changes ideas
printf -- '---\nname: gamma\nsummary: an in-work change\n---\n' > changes/gamma.md
git add -A
commit_msg <<'EOF'
в работу gamma

Change: gamma
EOF
expect_out 'change show of an in-work change [#change-show]' change show gamma
case "$OUT" in
  *"in work"*"в работу gamma"*) ok 'in-work: doc from FS + timeline [#change-show]' ;;
  *) bad "in-work show wrong: $OUT" ;;
esac
set +e
OUT="$(bash "$CAPED" change show ghost 2>&1)"; RC=$?
set -e
if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -qE 'alpha|beta|gamma'; then
  ok 'unknown name fails exit 2 with candidates [#change-show]'
else
  bad "unknown show wrong: $OUT rc=$RC"
fi

# --write materialises views with the generated header. [#render-write]
expect_out '--write succeeds [#render-write]' --write
missing=""
for f in plan.md history.md coverage.txt plan.json history.json coverage.json; do
  [ -f ".caped/$f" ] || missing="$missing $f"
done
if [ -z "$missing" ]; then ok '--write creates the text AND json forms [#render-write]'
else bad "--write missed:$missing"; fi
if head -1 .caped/plan.md | grep -q 'generated by'; then ok 'generated header present [#render-write]'
else bad 'generated header missing [#render-write]'; fi

# --clean removes the materialised views. [#render-clean]
expect_out '--clean succeeds [#render-clean]' --clean
if [ -e .caped ]; then bad '.caped/ survived --clean [#render-clean]'
else ok '--clean removes .caped/ [#render-clean]'; fi

# --- idea archival: withdrawn shown in history ------------------------------
add_idea delta "withdrawn idea"
git add -A
commit_msg <<'EOF'
идея delta

Idea: delta
EOF
git rm -q ideas/delta.md
commit_msg <<'EOF'
снята идея delta

причина: устарела.

Archives: delta
EOF
expect_out 'history shows withdrawn idea [#idea-archival]' history
case "$OUT" in
  *delta*"withdrawn"*) ok 'idea archived directly shows as withdrawn [#idea-archival]' ;;
  *) bad "withdrawn missing: $OUT" ;;
esac

# --- rename stitching: old name shown as (was: ...) -------------------------
new_repo
add_idea oldname "renamed idea"
git add -A
commit_msg <<'EOF'
идея oldname

Idea: oldname
EOF
git mv ideas/oldname.md ideas/newname.md
commit_msg <<'EOF'
ренейм oldname → newname

Change: init
EOF
expect_out 'history after rename succeeds [#render-history]' history
case "$OUT" in
  *newname*"(was: oldname)"*) ok 'rename stitched as (was: oldname) [#render-history]' ;;
  *) bad "rename not stitched: $OUT" ;;
esac

# --- empty repo: no ideas, no changes — still exit 0 ------------------------
new_repo
expect_out 'empty repo renders fine [#render-stdout]'
case "$OUT" in
  *"(none)"*) ok 'empty plan shows (none) [#render-stdout]' ;;
  *) bad "empty plan wrong: $OUT" ;;
esac

# --- unknown view is a usage error ------------------------------------------
set +e
OUT="$(bash "$CAPED" render bogus 2>&1)"; RC=$?
set -e
if [ "$RC" -eq 2 ]; then ok 'unknown view exits 2 [#render-stdout]'
else bad "unknown view exit $RC, want 2: $OUT"; fi

# --- adhoc decisions: fileless contract commits listed in history -----------
new_repo
echo a >> README.md; git add -A
commit_msg <<'EOF'
адхок: решение без файла

Behavior: contract
Spec: README.md
EOF
echo b >> README.md; git add -A
commit_msg <<'EOF'
внутренняя правка

Behavior: internal
EOF
echo c >> README.md; git add -A
commit_msg <<'EOF'
контракт внутри чейнджа

Behavior: contract
Change: alpha
EOF
expect_out 'history with adhoc commits succeeds [#render-history-adhoc]' history
case "$OUT" in
  *"-- adhoc decisions"*"адхок: решение без файла"*) ok 'fileless contract listed [#render-history-adhoc]' ;;
  *) bad "fileless contract missing: $OUT" ;;
esac
case "$OUT" in
  *"внутренняя правка"*) bad "internal leaked into history: $OUT" ;;
  *) ok 'internal commit not listed [#render-history-adhoc]' ;;
esac
case "$OUT" in
  *"контракт внутри чейнджа"*) bad "change-bound contract leaked into adhoc: $OUT" ;;
  *) ok 'change-bound contract not in adhoc section [#render-history-adhoc]' ;;
esac

# --- plan: last commit carries its subject; BLOCKED on unarchived deps ------
new_repo
mkdir -p ideas
cat > ideas/gamma.md <<'EOF'
---
name: gamma
summary: depends on a live idea
phase: v0
priority: high
depends_on: [delta]
---
EOF
cat > ideas/delta.md <<'EOF'
---
name: delta
summary: a live blocking idea
---
EOF
git add -A
commit_msg <<'EOF'
идеи gamma и delta

Idea: gamma
Idea: delta
EOF
expect_out 'plan with deps succeeds [#render-blocked]' plan
case "$OUT" in
  *"gamma"*"BLOCKED (dep unarchived: delta)"*) ok 'unarchived dep marks BLOCKED [#render-blocked]' ;;
  *) bad "BLOCKED marker missing: $OUT" ;;
esac
case "$OUT" in
  *"«идеи gamma и delta»"*) ok 'last: carries the commit subject [#render-stdout]' ;;
  *) bad "subject missing in last: $OUT" ;;
esac
git rm -q ideas/delta.md
commit_msg <<'EOF'
архив: delta

Change: delta
Archives: delta
EOF
expect_out 'plan after dep archival succeeds [#render-blocked]' plan
case "$OUT" in
  *"gamma"*"BLOCKED"*) bad "still blocked after the dep archived: $OUT" ;;
  *) ok 'archived dep clears BLOCKED [#render-blocked]' ;;
esac

# --- JSON mode: machine-readable form of the same view ----------------------
expect_out 'render plan --json succeeds [#render-json]' plan --json
if printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["view"]=="plan"; r=d["ideas"][0]; assert "last_commit" in r and "blocked" in r and "deps" in r' 2>/dev/null
then ok 'plan --json parses, stable keys present [#render-json]'
else bad "plan --json invalid: $OUT"; fi

# --- coverage: per-cap rows and top free paths ------------------------------
expect_out 'coverage succeeds [#render-stdout]' coverage
case "$OUT" in
  *"-- per cap --"*"root"*"enforced"*) ok 'per-cap rows present [#render-stdout]' ;;
  *) bad "per-cap rows missing: $OUT" ;;
esac
mkdir -p free/dir && echo x > free/dir/a.txt && echo y > free/dir/b.txt && git add -A && git commit -qm free
expect_out 'coverage with free files succeeds [#render-stdout]' coverage
case "$OUT" in
  *"-- top free paths --"*"free/"*) ok 'top free paths listed [#render-stdout]' ;;
  *) bad "top free paths missing: $OUT" ;;
esac


# --- reqs: requirement index from specs and ideas ---------------------------
# Fixture markers are built via $MK so the test source itself is not read
# by trace as a requirement reference.
MK='[#'
new_repo
cat > README.md <<FIX
# fixture

## Requirements

- ${MK}alpha-rule] Alpha rule gist — the first line is self-contained.
  A wrapped continuation line that never enters the index.
- ${MK}beta-rule no-test] Beta rule gist on one line.

## Other

- ${MK}gamma-rule] not a def, just prose outside the section
FIX
mkdir -p ideas
cat > ideas/zeta.md <<FIX
---
name: zeta
summary: an idea with requirements
---

## Requirements

- Zeta wants a thing done quickly.
- ${MK}zeta-opt] Optional slug leads the bullet when present.
FIX
git add -A
commit_msg <<'FIX'
фикстура reqs

Idea: zeta
FIX
expect_out 'render reqs succeeds [#render-reqs]' reqs
case "$OUT" in
  *"${MK}alpha-rule] Alpha rule gist — the first line is self-contained. …"*) ok 'spec def: slug + first-line gist, wrap marked [#render-reqs]' ;;
  *) bad "spec req row wrong: $OUT" ;;
esac
case "$OUT" in
  *"-- README.md (spec) --"*"${MK}beta-rule] Beta rule gist on one line."*) ok 'single-line gist without wrap marker, grouped by source [#render-reqs]' ;;
  *) bad "single-line gist wrong: $OUT" ;;
esac
case "$OUT" in
  *"-- ideas/zeta.md (idea) --"*"Zeta wants a thing done quickly."*) ok 'idea bullet gist listed under its source header [#render-reqs]' ;;
  *) bad "idea req row missing: $OUT" ;;
esac
case "$OUT" in
  *"${MK}zeta-opt] Optional slug leads the bullet"*) ok 'optional idea slug shown [#render-reqs]' ;;
  *) bad "idea slug row wrong: $OUT" ;;
esac
case "$OUT" in
  *gamma-rule*) bad "marker outside the section leaked into reqs: $OUT" ;;
  *) ok 'prose marker outside the section not indexed [#render-reqs]' ;;
esac
expect_out 'render reqs --json succeeds [#render-reqs]' reqs --json
if printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["view"]=="reqs"; assert any(r["slug"]=="alpha-rule" for r in d["specs"]); assert any(r["source"]=="ideas/zeta.md" for r in d["entities"])' 2>/dev/null
then ok 'reqs --json parses, specs/entities present [#render-reqs]'
else bad "reqs --json invalid: $OUT"; fi

# --- adhoc excerpt: body rationale visible under the subject -----------------
new_repo
echo a >> README.md; git add -A
commit_msg <<'FIX'
адхок: решение с ратионале

Ратионале первая строка — видна в листинге истории.
Вторая строка уже не попадает.

Behavior: contract
Spec: README.md
FIX
expect_out 'history with adhoc excerpt succeeds [#render-history-adhoc]' history
case "$OUT" in
  *"адхок: решение с ратионале"*"Ратионале первая строка — видна в листинге истории."*) ok 'adhoc body excerpt under the subject [#render-history-adhoc]' ;;
  *) bad "adhoc excerpt missing: $OUT" ;;
esac
case "$OUT" in
  *"Вторая строка"*) bad "second body line leaked into the excerpt: $OUT" ;;
  *) ok 'excerpt is the first substantive line only [#render-history-adhoc]' ;;
esac

# --- adhoc grouping: Adhoc: <name> clusters the commits; renames excluded -----
new_repo
echo a >> README.md; git add -A
commit_msg <<'FIX'
адхок первый

тело: ратионале первого решения.

Adhoc: fix-src
Behavior: contract
Spec: README.md
FIX
echo b >> README.md; git add -A
commit_msg <<'FIX'
адхок второй

тело: ратионале второго решения.

Adhoc: fix-src
Behavior: contract
Spec: README.md
FIX
mkdir -p ideas
printf -- '---\nname: r\nsummary: rename fixture\n---\n' > ideas/r.md
git add ideas/r.md
commit_msg <<'FIX'
идея r (setup для ренейма)

Idea: r
FIX
git mv ideas/r.md ideas/renamed.md
commit_msg <<'FIX'
ренейм события, не адхок

тело: рефереры правлены.

Behavior: contract
Spec: README.md
FIX
expect_out 'history grouping succeeds [#adhoc-id]' history
case "$OUT" in
  *"Adhoc: fix-src (2 commits)"*) ok 'same Adhoc name is one cluster [#adhoc-id]' ;;
  *) bad "cluster header missing: $OUT" ;;
esac
case "$OUT" in
  *"ренейм события, не адхок"*) bad "rename event leaked into adhoc: $OUT" ;;
  *) ok 'idea-rename event excluded from adhoc decisions [#adhoc-id]' ;;
esac
case "$OUT" in
  *"1 id(s)"*"0 cluster(s) over 2"*) ok 'cluster metric in the header [#adhoc-id]' ;;
  *) bad "metric missing: $OUT" ;;
esac
expect_out 'plan shows recent fileless decisions [#adhoc-id]' plan
case "$OUT" in
  *"-- recent fileless decisions --"*"адхок второй"*"Spec: README.md"*) ok 'plan survey lists recent adhocs with their Spec [#adhoc-id]' ;;
  *) bad "recent adhoc section missing: $OUT" ;;
esac

# --- --write materialises the reqs view too ----------------------------------
expect_out '--write with reqs succeeds [#render-write]' --write
missing=""
for f in plan.md history.md coverage.txt reqs.md plan.json history.json coverage.json reqs.json; do
  [ -f ".caped/$f" ] || missing="$missing $f"
done
if [ -z "$missing" ]; then ok '--write creates reqs.md + reqs.json too [#render-write]'
else bad "--write missed:$missing"; fi


# --- changelog: contract commits as the free changelog ---------------------
new_repo
printf '# fixture\n\n## Requirements\n\n- %salpha-rule] Rule.\n' "$MK" > README.md
git add -A; git commit -qm seed
printf '# fixture\n\n## Requirements\n\n- %salpha-rule] Rule.\n\n- %sbeta-rule no-test] Beta rule.\n' "$MK" "$MK" > README.md
git add README.md
git commit -qF - <<'FIX'
contract: beta rule added

Adhoc: hotfix-x
Behavior: contract
Spec: README.md
FIX
expect_out 'changelog view succeeds [#tool-version]' changelog
case "$OUT" in
  *"contract change"*"beta rule added"*"Spec: README.md"*) ok 'contract commit listed with Spec [#tool-version]' ;;
  *) bad "changelog wrong: $OUT" ;;
esac
case "$OUT" in
  *"head "*" · "*"20"*) ok 'version constant on the first line [#tool-version]' ;;
  *) bad "version line wrong: $OUT" ;;
esac

# --- text layout: two-line rows, no ANSI when piped -------------------------
new_repo
mkdir -p ideas
cat > ideas/eta.md <<'FIX'
---
name: eta
summary: layout fixture with a blocking dep
phase: v0
priority: high
depends_on: [theta]
---
FIX
git add -A
commit_msg <<'FIX'
идея eta

Idea: eta
FIX
expect_out 'plan renders for the layout checks [#render-text-layout]' plan
case "$OUT" in
  *$'\x1b'*) bad "ANSI escapes in piped output: $OUT" ;;
  *) ok 'piped output is plain (no ANSI) [#render-text-layout]' ;;
esac
case "$OUT" in
  *$'  eta  v0 high  BLOCKED (dep unarchived: theta)\n'*) ok 'name and marks on their own line [#render-text-layout]' ;;
  *) bad "name line wrong: $OUT" ;;
esac
case "$OUT" in
  *$'\n    last: 20'*" · deps: theta · from: —"*) ok 'metadata on a separate dimmed line [#render-text-layout]' ;;
  *) bad "metadata line wrong: $OUT" ;;
esac

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
