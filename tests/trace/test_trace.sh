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
new_repo "Rule one ${MK}alpha].\n" 'echo nothing here\n'
expect_fail_matching 'def without ref is uncovered [#trace-checker]' 'uncovered'

# A marker referencing a requirement that no longer exists: dangling. [#trace-refs]
new_repo "Rule one ${MK}alpha].\n" "case beta ${MK}beta]\n"
expect_fail_matching 'ref without def is dangling [#trace-refs]' 'dangling'

# no-test: explicit exemption passes without any ref. [#trace-no-test]
new_repo "Convention ${MK}gamma no-test].\n" 'echo nothing here\n'
expect_pass 'no-test def without ref passes [#trace-no-test]'

# The same slug defined twice is a duplicate, refs or not. [#trace-defs]
new_repo "Rule ${MK}alpha]. Restated ${MK}alpha].\n" "case alpha ${MK}alpha]\n"
expect_fail_matching 'duplicate slug definition fails [#trace-defs]' 'duplicate'

# Full balance: every def referenced, every ref defined. [#trace-checker]
new_repo "Rule one ${MK}alpha]. Convention ${MK}gamma no-test].\n" "case alpha ${MK}alpha]\n"
expect_pass 'balanced defs and refs pass [#trace-checker]'

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
