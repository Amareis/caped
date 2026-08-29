#!/usr/bin/env bash
# tests/init/test_init.sh — linked-mode install: the adopting repo vendors
# no scripts, the shim points at the installed tool [#linked-install].
#
# Builds a throwaway repo in mktemp, runs the REAL tool's dispatcher from
# its installed location (never copied into the fixture), and asserts:
#   - the commit-msg shim references the tool's absolute path;
#   - the hook chain really enforces (a trailer-less commit is rejected);
#   - check / trace / render work from the fixture via the tool wrapper;
#   - trace stays green with no dangling refs — the tool's own markers
#     cannot leak through a repo that never vendors the scripts;
#   - AGENTS.md is seeded and points at the wrapper;
#   - init stays idempotent;
#   - bootstrap mode (init <name>) creates the directory, git repo and README
#     skeleton, and lands a repo where check is green right away.
#
# Fixture markers are built as ${MK}slug] so the REAL repo's trace does not
# read them as refs; scenario names carry [#linked-install] as coverage.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MK='[#'

pass=0; fail=0
ok()  { printf 'PASS %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

cd "$TMP"
git init -q
git config user.email test@caped.dev
git config user.name "caped test"

# --- init from the installed tool, no vendoring -----------------------------

if bash "$REPO_ROOT/scripts/caped.sh" init >/dev/null; then
  ok 'caped init succeeds without vendored scripts [#linked-install]'
else
  bad 'caped init succeeds without vendored scripts [#linked-install] — non-zero exit'
fi

if [ ! -e scripts/caped.sh ]; then
  ok 'fixture vendors no dispatcher [#linked-install]'
else
  bad 'fixture vendors no dispatcher [#linked-install] — scripts/caped.sh appeared'
fi

if grep -qF "$REPO_ROOT/scripts/caped.sh" .git/hooks/commit-msg; then
  ok 'shim points at the installed tool (absolute path) [#linked-install]'
else
  bad 'shim points at the installed tool (absolute path) [#linked-install]'
fi

if grep -qF "$REPO_ROOT/caped" AGENTS.md; then
  ok 'AGENTS.md seeded pointing at the wrapper [#linked-install]'
else
  bad 'AGENTS.md seeded pointing at the wrapper [#linked-install]'
fi

if [ -x .git/hooks/post-commit ]; then
  ok 'post-commit shim installed for the event feed [#linked-install]'
else
  bad 'post-commit shim missing for the event feed [#linked-install]'
fi

# --- init seeds the archive deposit target -------------------------------------

if [ -f ideas/_backlog.md ]; then
  ok 'init seeds ideas/_backlog.md [#init-idempotent]'
else
  bad 'init seeds ideas/_backlog.md [#init-idempotent] — file missing'
fi

missing_sec=0
for sec in "Why" "Context" "Requirements" "Decisions" "Rejected alternatives" "Provenance" "Open questions"; do
  grep -q "^## $sec\$" ideas/_backlog.md || missing_sec=1
done
if [ "$missing_sec" -eq 0 ]; then
  ok 'seeded _backlog carries the canonical section set [#init-idempotent]'
else
  bad 'seeded _backlog carries the canonical section set [#init-idempotent] — sections missing'
fi

# --- the linked hook chain really enforces -----------------------------------

echo '# fixture spec' > README.md
printf '\n## Requirements\n' >> README.md
git add -A
git commit -qm 'seed' --no-verify

echo 'v2' >> README.md
git add README.md
if git commit -qm 'no trailers' >/dev/null 2>&1; then
  bad 'linked hook rejects a trailer-less commit on an enforced cap [#linked-install]'
  git reset -q --soft HEAD~1
else
  ok 'linked hook rejects a trailer-less commit on an enforced cap [#linked-install]'
fi

printf 'internal spec tweak\n\nBehavior: internal\nAgent: human\n' > .git/CAPED_MSG
if git commit -qF .git/CAPED_MSG >/dev/null 2>&1; then
  ok 'linked hook accepts Behavior: internal [#linked-install]'
else
  bad 'linked hook accepts Behavior: internal [#linked-install] — rejected'
  git reset -q
fi

# --- the tool's subcommands work from the fixture -----------------------------

for cmd in check trace render; do
  if "$REPO_ROOT/caped" "$cmd" >/dev/null 2>&1; then
    ok "caped $cmd works from a linked fixture [#linked-install]"
  else
    bad "caped $cmd works from a linked fixture [#linked-install] — non-zero exit"
  fi
done

if "$REPO_ROOT/caped" trace 2>&1 | grep -qE '^caped trace: RED'; then
  bad 'linked fixture trace has no dangling refs from the tool namespace [#linked-install]'
else
  ok 'linked fixture trace has no dangling refs from the tool namespace [#linked-install]'
fi

# --- the wrapper works through a symlink (PATH install) ----------------------

mkdir -p "$TMP/bin"
ln -s "$REPO_ROOT/caped" "$TMP/bin/caped"
if "$TMP/bin/caped" check >/dev/null 2>&1; then
  ok 'wrapper resolves through a symlink [#linked-install]'
else
  bad 'wrapper resolves through a symlink [#linked-install] — non-zero exit'
fi

# --- idempotence --------------------------------------------------------------

printf -- '- sentinel backlog line\n' >> ideas/_backlog.md
if bash "$REPO_ROOT/scripts/caped.sh" init >/dev/null 2>&1; then
  ok 're-running linked init repairs and exits 0 [#linked-install]'
else
  bad 're-running linked init repairs and exits 0 [#linked-install] — non-zero exit'
fi

if grep -q 'sentinel backlog line' ideas/_backlog.md; then
  ok 're-run keeps an existing _backlog.md untouched [#init-idempotent]'
else
  bad 're-run keeps an existing _backlog.md untouched [#init-idempotent] — clobbered'
fi

# --- bootstrap mode: caped init <name> -----------------------------------------

mkdir -p "$TMP/boot"
cd "$TMP/boot"
if GIT_AUTHOR_NAME='caped test' GIT_AUTHOR_EMAIL=test@caped.dev \
   GIT_COMMITTER_NAME='caped test' GIT_COMMITTER_EMAIL=test@caped.dev \
   bash "$REPO_ROOT/scripts/caped.sh" init myproj >/dev/null 2>&1; then
  ok 'bootstrap init <name> succeeds [#init-idempotent]'
else
  bad 'bootstrap init <name> succeeds [#init-idempotent] — non-zero exit'
fi

if [ -d myproj/.git ] \
  && grep -q '^## Requirements$' myproj/README.md \
  && [ -f myproj/ideas/_backlog.md ] \
  && [ -f myproj/AGENTS.md ]; then
  ok 'bootstrapped repo has git, README skeleton, _backlog, AGENTS.md [#init-idempotent]'
else
  bad 'bootstrapped repo has git, README skeleton, _backlog, AGENTS.md [#init-idempotent] — piece missing'
fi

if [ "$(git -C myproj rev-list --count HEAD 2>/dev/null)" = 1 ] \
  && git -C myproj log --format=%B -1 | grep -q '^Change: init$'; then
  ok 'bootstrap lands the seed commit with Change: init [#init-idempotent]'
else
  bad 'bootstrap lands the seed commit with Change: init [#init-idempotent] — no/bad seed commit'
fi

if (cd myproj && "$REPO_ROOT/caped" check >/dev/null 2>&1); then
  ok 'caped check is green right after bootstrap [#init-idempotent]'
else
  bad 'caped check is green right after bootstrap [#init-idempotent] — red'
fi

if bash "$REPO_ROOT/scripts/caped.sh" init myproj >/dev/null 2>&1; then
  bad 'bootstrap refuses an existing non-empty directory [#init-idempotent]'
else
  ok 'bootstrap refuses an existing non-empty directory [#init-idempotent]'
fi

cd "$TMP"

# --- Report ------------------------------------------------------------------

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
