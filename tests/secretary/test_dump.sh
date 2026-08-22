#!/usr/bin/env bash
# tests/secretary/test_dump.sh — scenarios for the dump attribute of
# requirement markers (scripts/caped-trace.sh, "undumped" failure class).
#
# Fixtures follow the test_trace.sh pattern: a throwaway repo with a registry,
# a spec file and a fake rules dump at scripts/caped.sh, then the real
# caped-trace.sh runs against it. Fixture markers are built via $MK so this
# file's own source does not read as marker references.
#
# Scenario names carry the [#<slug>] marker of the requirement they cover
# (root README, "Трассировка требований и тестов").
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

new_repo() { # <spec-content> <dump-content> <test-content>
  n=$((n + 1))
  local dir="$TMP/repo$n"
  mkdir -p "$dir/scripts" "$dir/t"
  cd "$dir"
  git init -q
  git config user.email test@caped.dev
  git config user.name "caped test"
  printf 'root\tREADME.md\tenforced\tREADME.md\n' > caped.registry
  printf '%b' "$1" > README.md
  printf '%b' "$2" > scripts/caped.sh
  printf '%b' "$3" > t/test_x.sh
  git add -A
  git commit -qm seed
}

expect_fail_matching() { # <name> <word>
  local name="$1" word="$2" out rc
  set +e
  out="$(bash "$TRACE" 2>&1)"; rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then bad "$name — expected failure, trace passed"
  elif printf '%s' "$out" | grep -q "$word"; then ok "$name"
  else bad "$name — failed, but the report lacks '$word': $out"; fi
}
expect_pass() { # <name>
  local name="$1" out rc
  set +e
  out="$(bash "$TRACE" 2>&1)"; rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then ok "$name"
  else bad "$name — expected pass, trace failed: $out"; fi
}

# dump-attr def referenced in the dump: balanced. [#trace-dump-attr]
new_repo "Rule one ${MK}alpha dump].\n" "rules: see ${MK}alpha]\n" "case alpha ${MK}alpha]\n"
expect_pass 'dump-attr def referenced in the dump passes [#trace-dump-attr]'

# dump-attr def missing from the dump: undumped. [#trace-undumped]
new_repo "Rule one ${MK}alpha dump].\n" 'rules: nothing here\n' "case alpha ${MK}alpha]\n"
expect_fail_matching 'dump-attr def outside the dump is undumped [#trace-undumped]' 'undumped'

# A test-file ref does not satisfy the dump requirement. [#trace-undumped]
new_repo "Rule one ${MK}alpha dump]. Rule two ${MK}beta dump].\n" "rules: see ${MK}alpha]\n" "case ${MK}alpha] ${MK}beta]\n"
expect_fail_matching 'test ref does not cover the dump [#trace-undumped]' 'undumped	beta'

# Combined attributes parse: no-test + dump, referenced in the dump only. [#trace-dump-attr]
new_repo "Convention ${MK}gamma no-test dump].\n" "rules: see ${MK}gamma]\n" 'echo nothing here\n'
expect_pass 'no-test + dump combination passes [#trace-dump-attr]'

# A plain def never claims the dump: a test ref is enough. [#trace-dump-attr]
new_repo "Rule one ${MK}alpha].\n" 'rules: nothing here\n' "case alpha ${MK}alpha]\n"
expect_pass 'non-dump def does not need the dump [#trace-dump-attr]'

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
