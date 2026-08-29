#!/usr/bin/env bash
# tests/trace/test_trace.sh — scenarios for scripts/caped-trace.sh.
#
# Each scenario builds its own throwaway repo in mktemp (the checker resolves
# the repo root via git rev-parse, so it must run inside a git repo) with a
# fixture registry, spec file and test file, then runs the real
# scripts/caped-trace.sh from the project under test.
#
# Scenario names carry the [#<slug>] marker of the requirement they cover
# (root README, "Трассировка требований и тестов").
#
# Fixture markers are built via $MK so that this file's own source does not
# read as a marker reference when caped's own trace scans the real repo.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TRACE="$REPO_ROOT/scripts/caped-trace.sh"
MK='[#'

pass=0; fail=0
ok()  { printf 'PASS %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
n=0

new_repo() { # <spec-content> <test-content> — fresh repo inside $TMP, cd into it
  n=$((n + 1))
  local dir="$TMP/repo$n"
  mkdir -p "$dir/t"
  cd "$dir"
  git init -q
  git config user.email test@caped.dev
  git config user.name "caped test"
  printf 'root\tREADME.md\tenforced\tREADME.md\n' > caped.registry
  printf '%b' "$1" > README.md
  printf '%b' "$2" > t/test_x.sh
  git add -A
  git commit -qm seed --no-verify
}

expect_fail_matching() { # <name> <word> — trace must exit 1 and mention the word
  local name="$1" word="$2" out rc
  set +e
  out="$(bash "$TRACE" 2>&1)"; rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then bad "$name — expected failure, trace passed"
  elif printf '%s' "$out" | grep -q "$word"; then ok "$name"
  else bad "$name — failed, but the report lacks '$word'"; fi
}
expect_pass() { # <name>
  local name="$1" out rc
  set +e
  out="$(bash "$TRACE" 2>&1)"; rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then ok "$name"
  else bad "$name — expected pass, trace failed: $out"; fi
}

# A definition every test forgot: uncovered. [#trace-defs]
new_repo "- ${MK}alpha] Rule one.\n" 'echo nothing here\n'
expect_fail_matching 'def without ref is uncovered [#trace-checker]' 'uncovered'

# A marker referencing a requirement that no longer exists: dangling. [#trace-refs]
new_repo "- ${MK}alpha] Rule one.\n" "case beta ${MK}beta]\n"
expect_fail_matching 'ref without def is dangling [#trace-refs]' 'dangling'

# no-test: explicit exemption passes without any ref. [#trace-no-test]
new_repo "- ${MK}gamma no-test] Convention.\n" 'echo nothing here\n'
expect_pass 'no-test def without ref passes [#trace-no-test]'

# The same slug defined twice is a duplicate, refs or not. [#trace-defs]
new_repo "- ${MK}alpha] Rule.\n- ${MK}alpha] Restated.\n" "case alpha ${MK}alpha]\n"
expect_fail_matching 'duplicate slug definition fails [#trace-defs]' 'duplicate'

# Full balance: every def referenced, every ref defined. [#trace-checker]
new_repo "- ${MK}alpha] Rule one.\n- ${MK}gamma no-test] Convention.\n" "case alpha ${MK}alpha]\n"
expect_pass 'balanced defs and refs pass [#trace-checker]'

# A marker quoted in spec prose is NOT a definition: the ref dangles. [#trace-defs]
new_repo "Rule one ${MK}alpha], said inline.\n" "case alpha ${MK}alpha]\n"
expect_fail_matching 'prose marker is not a def — ref dangles [#trace-defs]' 'dangling'

# A declared cap is "a spec without trace": its markers are neither defs nor
# refs — the balance stays green while the enforced cap is balanced. [#trace-defs]
new_repo "- ${MK}alpha] Rule one.\n" "case alpha ${MK}alpha]\n"
printf 'tech\tsrc/tech/\tdeclared\tsrc/tech/README.md\n' >> caped.registry
mkdir -p src/tech
printf -- "- ${MK}delta] Advisory rule.\n" > src/tech/README.md
git add -A; git commit -qm declared --no-verify
expect_pass 'markers of a declared-cap spec are neither defs nor refs [#trace-defs]'

# A test ref naming a slug whose spec belongs to a declared cap dangles —
# with a hint that points at the cap state, not "defined in no spec". [#trace-refs]
new_repo "- ${MK}alpha] Rule one.\n" "case alpha ${MK}alpha]\ncase delta ${MK}delta]\n"
printf 'tech\tsrc/tech/\tdeclared\tsrc/tech/README.md\n' >> caped.registry
mkdir -p src/tech
printf -- "- ${MK}delta] Advisory rule.\n" > src/tech/README.md
git add -A; git commit -qm declared --no-verify
expect_fail_matching 'ref to a declared-cap slug dangles with a declared hint [#trace-refs]' 'declared'

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
