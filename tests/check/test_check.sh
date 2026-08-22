#!/usr/bin/env bash
# tests/check/test_check.sh — scenarios for scripts/caped-check.py.
#
# Each scenario builds a throwaway repo in mktemp (the checker resolves the
# repo root via git rev-parse) with fixture ideas/changes files, then runs the
# real `caped.sh check` from the project under test.
#
# Scenario names carry the [#<slug>] marker of the requirement they cover
# (root README, "Структурная валидация (caped check)").
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
  mkdir -p "$dir/ideas"
  cd "$dir"
  git init -q
  git config user.email test@caped.dev
  git config user.name "caped test"
  printf 'root\tREADME.md\tenforced\tREADME.md\n' > caped.registry
  printf '# fixture\n' > README.md
  git add -A
  git commit -qm seed
}

valid_file() { # <dir/name> [spawned_from] — a fully valid entity file
  local path="$1" spawned="${2:-null}"
  cat > "$path" <<EOF
---
name: $(basename "$path" .md)
summary: fixture entity
spawned_from: $spawned
---

## Зачем

z

## Контекст

k

## Требования

t

## Решения

## Рассмотрено и отклонено

—

## Променанс

p

## Открытые вопросы

o
EOF
}

run_check() { # sets OUT and RC
  set +e
  OUT="$(bash "$CAPED" check 2>&1)"; RC=$?
  set -e
}

expect_error() { # <name> <word>
  local name="$1" word="$2"
  if [ "$RC" -ne 1 ]; then bad "$name — expected exit 1, got $RC: $OUT"
  elif printf '%s' "$OUT" | grep -q "$word"; then ok "$name"
  else bad "$name — failed, but the report lacks '$word': $OUT"; fi
}

# A fully valid file passes clean. [#check-structure]
new_repo
valid_file ideas/alpha.md
git add -A && git commit -qm alpha
run_check
if [ "$RC" -eq 0 ]; then ok 'valid file passes [#check-structure]'
else bad "valid file failed: $OUT"; fi

# No frontmatter at all. [#check-structure]
new_repo
printf 'no frontmatter here\n' > ideas/broken.md
git add -A && git commit -qm broken
run_check
expect_error 'missing frontmatter is an error [#check-structure]' 'frontmatter'

# Frontmatter name disagrees with the file name. [#check-structure]
new_repo
valid_file ideas/gamma.md
sed -i '' 's/^name: gamma$/name: delta/' ideas/gamma.md
git add -A && git commit -qm gamma
run_check
expect_error 'name/file mismatch is an error [#check-structure]' '!= file name'

# A missing required section. [#check-structure]
new_repo
valid_file ideas/epsilon.md
awk '!/^## Променанс$/' ideas/epsilon.md > ideas/epsilon.tmp && mv ideas/epsilon.tmp ideas/epsilon.md
git add -A && git commit -qm epsilon
run_check
expect_error 'missing section is an error [#check-structure]' 'Променанс'

# spawned_from pointing nowhere. [#check-spawned-from]
new_repo
valid_file ideas/zeta.md ghost
git add -A && git commit -qm zeta
run_check
expect_error 'dangling spawned_from is an error [#check-spawned-from]' 'spawned_from'

# spawned_from to an archived entity resolves via git history. [#check-spawned-from]
new_repo
git commit -q --allow-empty -m 'архив: old-parent

Archives: old-parent'
valid_file ideas/eta.md old-parent
git add -A && git commit -qm eta
run_check
if [ "$RC" -eq 0 ]; then ok 'spawned_from to archived entity passes [#check-spawned-from]'
else bad "archived spawned_from failed: $OUT"; fi

# Bold-lead bullets without a marker warn but do not fail. [#check-marker-fullness]
new_repo
valid_file ideas/theta.md
printf -- '- **Rejected alternative** — prose, not a requirement\n' >> README.md
git add -A && git commit -qm theta
run_check
if [ "$RC" -ne 0 ]; then bad "marker fullness must not fail the run: $OUT"
elif printf '%s' "$OUT" | grep -q 'warning.*bold-lead'; then ok 'unmarked bold-lead bullet warns, exit 0 [#check-marker-fullness]'
else bad "expected a bold-lead warning: $OUT"; fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
