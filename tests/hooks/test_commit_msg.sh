#!/usr/bin/env bash
# tests/hooks/test_commit_msg.sh — regression scenarios for the commit-msg hook.
#
# Builds a throwaway repo in mktemp, wires it with the real scripts/caped-init.sh
# (so commits go through the shim -> dispatcher -> hook chain exactly as users see
# it), and drives real git commits. Fixture/setup commits use --no-verify; only
# the commit under test passes through the hook.
#
# The scenario list mirrors the hook's contract: every rule in
# scripts/hooks/commit-msg has its case here. Adding a hook rule without a
# scenario here is a process violation (see root README, lifecycle events).
#
# Scenario names carry the [#<slug>] marker of the requirement they cover
# (root README, "Трассировка требований и тестов"); scripts/caped-trace.sh
# checks the balance.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { printf 'PASS %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

cd "$TMP"
git init -q
git config user.email test@caped.dev
git config user.name "caped test"
cp -r "$REPO_ROOT/scripts" scripts
printf 'root\tREADME.md\tenforced\tREADME.md\nsrc\tsrc/\tenforced\tsrc/README.md\n' > caped.registry
bash scripts/caped-init.sh >/dev/null
mkdir -p src
echo 'fn a() {}' > src/a.rs
echo '# src spec' > src/README.md
git add -A
git commit -qm "seed" --no-verify

msg() { printf '%b' "$1" > .caped-test-msg; }
expect_accept() { # <name> — commit staged changes with .caped-test-msg, want hook accept
  if git commit -q -F .caped-test-msg >/dev/null 2>&1; then ok "$1"
  else bad "$1 — expected accept, hook rejected"; git reset -q; fi
}
expect_reject() { # <name> — want hook reject
  if git commit -q -F .caped-test-msg >/dev/null 2>&1; then
    bad "$1 — expected reject, hook accepted"; git reset -q --soft HEAD~1
  else ok "$1"; fi
}
expect_reject_matching() { # <name> <pattern> — want hook reject whose output matches
  if git commit -q -F .caped-test-msg >/dev/null 2>.caped-test-err; then
    bad "$1 — expected reject, hook accepted"; git reset -q --soft HEAD~1
  elif grep -q "$2" .caped-test-err; then ok "$1"
  else bad "$1 — rejected, but the message lacks '$2'"; fi
}

# --- Behavior: capability rules --------------------------------------------

echo 'fn a2() {}' >> src/a.rs; git add src/a.rs
msg 'change src\n'
expect_reject 'enforced cap without Behavior [#behavior-trailer]'

msg 'wip: change src\n'
expect_accept 'wip subject counts as Behavior: wip [#behavior-trailer]'

echo 'fn a3() {}' >> src/a.rs; git add src/a.rs
msg 'change src\n\nBehavior: internal\n'
expect_accept 'Behavior: internal passes [#behavior-trailer]'

echo 'fn a4() {}' >> src/a.rs; git add src/a.rs
msg 'change src contract\n\nrationale: needed for X\n\nBehavior: contract\n'
expect_reject 'Behavior: contract without Spec and without spec file [#spec-trailer]'

msg 'change src contract\n\nrationale: needed for X\n\nAdhoc: hotfix\nBehavior: contract\nSpec: src/README.md\n'
expect_accept 'contract with Spec trailer [#spec-trailer]'

echo '# src spec v2' > src/README.md; git add src/a.rs src/README.md 2>/dev/null || git add src/README.md
echo 'fn a5() {}' >> src/a.rs; git add src/a.rs src/README.md
msg 'change src contract\n\nrationale: spec changed inline\n\nAdhoc: hotfix\nBehavior: contract\n'
expect_accept 'contract with the spec file in the commit (no trailer) [#spec-trailer]'

echo 'fn a6() {}' >> src/a.rs; git add src/a.rs
msg 'adhoc src\n\nBehavior: contract\nSpec: README.md\n'
expect_reject 'fileless contract without Adhoc trailer [#adhoc-id]'

msg 'adhoc src\n\nAdhoc: fix-src\n\nBehavior: contract\nSpec: README.md\n'
expect_reject 'fileless contract with Adhoc but no body [#adhoc-body]'

msg 'adhoc src\n\nFix X because Y; grounds: Z.\n\nAdhoc: fix-src\nBehavior: contract\nSpec: README.md\n'
expect_accept 'fileless contract with Adhoc + rationale body [#adhoc-id]'

echo 'note' >> notes.txt; git add notes.txt
msg 'free zone note\n'
expect_accept 'path outside the registry needs no trailers [#free-paths]'

# --- Registry: longest prefix wins ------------------------------------------

# A longer prefix shadows the shorter one for paths under it.
printf 'feature\tsrc/f/\tenforced\tsrc/f/README.md\n' >> caped.registry
mkdir -p src/f
echo '# feature spec' > src/f/README.md
echo 'fn f1() {}' > src/f/x.rs
git add src/f/x.rs
msg 'change feature\n'
expect_reject_matching 'overlapping prefixes: the longer one decides [#longest-prefix]' "capability 'feature'"

msg 'change feature\n\nBehavior: internal\n'
expect_accept 'Behavior accepted under the longer prefix [#longest-prefix]'

# A registry prefix may name a single file, not only a directory.
printf 'dump\tscripts/caped.sh\tenforced\tREADME.md\n' >> caped.registry
printf '# touched\n' >> scripts/caped.sh
git add scripts/caped.sh
msg 'touch dump\n'
expect_reject_matching 'a file-prefix cap is enforced on its exact file [#longest-prefix]' "capability 'dump'"
msg 'touch dump\n\nBehavior: internal\n'
expect_accept 'Behavior accepted under a file-prefix cap [#longest-prefix]'

# --- Events: ideas/ ----------------------------------------------------------

echo '- idea x' > ideas/x.md; git add ideas/x.md
msg 'add idea x\n'
expect_reject 'A ideas/x.md without Idea trailer [#idea-birth]'

msg 'add idea x\n\nIdea: other\n'
expect_reject 'A ideas/x.md with a wrong Idea trailer [#idea-birth]'

msg 'add idea x\n\nIdea: x\n'
expect_accept 'idea born with Idea: x [#idea-birth]'

# --- Events: idea edits -------------------------------------------------------

echo '- edit' >> ideas/x.md; git add ideas/x.md
msg 'edit idea x\n'
expect_reject 'M ideas/x.md without Idea trailer [#idea-edit]'

msg 'edit idea x\n\nIdea: x\n'
expect_accept 'idea edit with Idea: x [#idea-edit]'

echo '- backlog note' >> ideas/_backlog.md; git add ideas/_backlog.md
msg 'twik in _backlog\n'
expect_accept 'M ideas/_backlog.md needs no Idea trailer [#idea-edit]'

echo '- idea r1' > ideas/r1.md; git add ideas/r1.md
msg 'add idea r1\n\nIdea: r1\n'
expect_accept 'idea r1 born (setup for rename exemption) [#idea-edit]'
echo '- idea r2' > ideas/r2.md; git add ideas/r2.md
msg 'add idea r2\n\nIdea: r2\n'
expect_accept 'idea r2 born (setup for rename exemption) [#idea-edit]'
git mv ideas/r1.md ideas/r1b.md
echo '- refers r1b' >> ideas/r2.md
git add ideas/r2.md
msg 'rename r1 -> r1b with a referrer fix\n'
expect_accept 'rename commit with referrer fix needs no Idea: [#idea-edit]'

# --- Events: changes/ --------------------------------------------------------

echo '- change y' > changes/y.md; git add changes/y.md
msg 'add change y\n\nChange: y\n'
expect_reject 'change added directly (not via mv) [#take-into-work]'

msg 'seed change y\n\nChange: init\n'
expect_accept 'direct add allowed for Change: init (adopting-repo seed) [#seed-commit]'

echo '- more' >> changes/y.md; git add changes/y.md
msg 'work on y\n'
expect_reject 'M changes/y.md without Change trailer [#work-trailer]'

msg 'work on y\n\nChange: y\n'
expect_accept 'work commit with Change: y [#work-trailer]'

echo 'n2' >> notes.txt; git add notes.txt
msg 'free note\n\nChange: ghost\n'
expect_reject 'Change: referencing a nonexistent change [#work-trailer]'

# --- Events: mv into work ----------------------------------------------------

echo '- idea z' > ideas/z.md; git add ideas/z.md
msg 'add idea z\n\nIdea: z\n'
expect_accept 'idea z born (setup for mv) [#idea-birth]'

git mv ideas/z.md changes/z.md
msg 'take z into work\n'
expect_reject 'mv ideas->changes without Change trailer [#take-into-work]'

msg 'take z into work\n\nChange: z\n'
expect_accept 'mv into work with Change: z [#take-into-work]'

echo '- idea a' > ideas/a.md; git add ideas/a.md
msg 'add idea a\n\nIdea: a\n'
expect_accept 'idea a born (setup for bad rename) [#idea-birth]'

git mv ideas/a.md changes/b.md
msg 'take a into work\n\nChange: b\n'
expect_reject 'mv renaming the file is rejected [#take-into-work]'
git mv changes/b.md ideas/a.md 2>/dev/null || true; git reset -q; git checkout -q -- ideas 2>/dev/null || true
rm -f changes/b.md ideas/a.md 2>/dev/null || true

# --- Events: archival --------------------------------------------------------

git rm -q changes/y.md
msg 'archive y\n\nChange: y\n'
expect_reject 'D changes/y.md without Archives trailer [#archival]'

msg 'archive y\n\nChange: y\nArchives: y\n'
expect_accept 'archival with Change + Archives [#archival]'

echo 'n3' >> notes.txt; git add notes.txt
msg 'free note\n\nArchives: z\n'
expect_reject 'Archives: without the file deletion [#archival]'

# --- idea archival: D ideas/*.md needs Archives: ------------------------------
echo '- идея ia' > ideas/ia.md; git add ideas/ia.md
msg 'идея ia

Idea: ia
'
expect_accept 'idea ia born (setup) [#idea-archival]'
git rm -q ideas/ia.md
msg 'снята идея ia
'
expect_reject_matching 'D ideas without Archives is rejected [#idea-archival]' 'deletion of idea'
msg 'снята идея ia

Причина: устарела.

Archives: ia
'
expect_accept 'D ideas with Archives + причина passes [#idea-archival]'

# --- question-lifecycle gate: deferred open questions at archive -------------
printf -- '---
name: _backlog
summary: x
---

## Requirements

- placeholder
' > ideas/_backlog.md
git add ideas/_backlog.md
msg 'идея _backlog (setup)

Idea: _backlog
'
expect_accept 'idea _backlog born (setup) [#question-gate]'
echo '- идея qg' > ideas/qg.md; git add ideas/qg.md
msg 'идея qg

Idea: qg
'
expect_accept 'idea qg born (setup) [#question-gate]'
git mv ideas/qg.md changes/qg.md
msg 'в работу qg

Change: qg
'
expect_accept 'qg into work (setup) [#question-gate]'
printf '
## Open questions

- Куда деть флаг: v0.1.
' >> changes/qg.md; git add changes/qg.md
msg 'работа qg: открытый вопрос

Change: qg
'
expect_accept 'qg work commit with deferred OQ (setup) [#question-gate]'
git rm -q changes/qg.md
msg 'архив qg

Change: qg
Archives: qg
'
expect_reject_matching 'archive with deferred OQ and no deposit [#question-gate]' 'deferred open questions'
printf '
- qg note | from qg | 2026-08-23
' >> ideas/_backlog.md
git add ideas/_backlog.md
msg 'архив qg

Change: qg
Archives: qg
'
expect_accept 'archive with deposit line in _backlog passes [#question-gate]'

# --- init --------------------------------------------------------------------

if bash scripts/caped-init.sh >/dev/null 2>&1; then
  ok 're-running caped init repairs and exits 0 [#init-idempotent]'
else
  bad 're-running caped init repairs and exits 0 [#init-idempotent] — non-zero exit'
fi

# --- Report ------------------------------------------------------------------

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
