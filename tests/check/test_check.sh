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
MK='[#'

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
  printf '# fixture\n\n## Requirements\n\n- %sfx no-test] Fixture requirement.\n' "$MK" > README.md
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

## Why

z

## Context

k

## Requirements

t

## Decisions

## Rejected alternatives

—

## Provenance

p

## Open questions

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
awk '!/^## Provenance$/' ideas/epsilon.md > ideas/epsilon.tmp && mv ideas/epsilon.tmp ideas/epsilon.md
git add -A && git commit -qm epsilon
run_check
expect_error 'missing section is an error [#check-structure]' 'Provenance'

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

# Requirement form: a markerless bullet inside '## Requirements' of an
# enforced spec is an error. [#req-form]
new_repo
valid_file ideas/iota.md
cat >> README.md <<EOF
- ${MK}fx2] Marked requirement.
- Unmarked requirement bullet.
EOF
git add -A && git commit -qm iota
run_check
expect_error 'markerless requirement bullet is an error [#req-form]' 'without a leading'

# Slug-first bullets pass; prose and ### groups inside the section are fine. [#req-form]
new_repo
valid_file ideas/kappa.md
cat >> README.md <<EOF

### Subgroup

Intro prose, no marker needed.

- ${MK}fx2 no-test] Marked requirement.
EOF
git add -A && git commit -qm kappa
run_check
if [ "$RC" -eq 0 ]; then ok 'slug-first bullets pass, prose and ### untouched [#req-form]'
else bad "req-form pass failed: $OUT"; fi

# Idea/change files are not specs: their Requirements sections stay unchecked. [#req-form]
new_repo
valid_file ideas/lambda.md
awk '{print} /^t$/{print ""; print "- A plain work item, no marker."}' ideas/lambda.md > ideas/lambda.tmp \
  && mv ideas/lambda.tmp ideas/lambda.md
git add -A && git commit -qm lambda
run_check
if [ "$RC" -eq 0 ]; then ok 'idea file Requirements are not spec-checked [#req-form]'
else bad "idea file failed: $OUT"; fi

# A marker bullet outside '## Requirements' is a misplaced definition. [#req-form]
new_repo
valid_file ideas/mu.md
cat >> README.md <<EOF

## Notes

- ${MK}stray] Stray definition.
EOF
git add -A && git commit -qm mu
run_check
expect_error 'marker bullet outside the section is an error [#req-form]' 'outside'

# An enforced spec without a '## Requirements' section is an error. [#req-form]
new_repo
valid_file ideas/nu.md
printf '# fixture\n' > README.md
git add -A && git commit -qm nu
run_check
expect_error 'spec without the section is an error [#req-form]' "no '## Requirements'"


# Idea/change requirements: numbered lists are an error, bullets only. [#req-form]
new_repo
valid_file ideas/xi.md
awk '{print} /^t$/{print ""; print "1. Numbered work item."}' ideas/xi.md > ideas/xi.tmp \
  && mv ideas/xi.tmp ideas/xi.md
git add -A && git commit -qm xi
run_check
expect_error 'numbered requirement in an idea is an error [#req-form]' 'numbered requirement'

# A slug in an idea bullet is optional but must lead the bullet. [#req-form]
new_repo
valid_file ideas/omikron.md
awk -v mk="$MK" '{print} /^t$/{print ""; print "- Work item mentioning " mk "some-norm] mid-text."}' ideas/omikron.md > ideas/omikron.tmp \
  && mv ideas/omikron.tmp ideas/omikron.md
git add -A && git commit -qm omikron
run_check
expect_error 'mid-text marker in an idea bullet is an error [#req-form]' 'must lead'

# Slug-first bullets and backticked mentions pass in ideas. [#req-form]
new_repo
valid_file ideas/pi.md
awk -v mk="$MK" '{print} /^t$/{print ""; print "- " mk "opt-slug] Optional slug leads the bullet."; print "- Norms in backticks: `" mk "req-form]` is prose, not a marker."}' ideas/pi.md > ideas/pi.tmp \
  && mv ideas/pi.tmp ideas/pi.md
git add -A && git commit -qm pi
run_check
if [ "$RC" -eq 0 ]; then ok 'slug-first bullet and backticked mention pass [#req-form]'
else bad "idea slug-first bullet failed: $OUT"; fi

# --- caped check push: pre-push range audit over origin..HEAD ---------------
push_repo() { # fresh repo with a local bare origin; seed pushed
  n=$((n + 1))
  local dir="$TMP/push$n"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git config user.email test@caped.dev
  git config user.name "caped test"
  printf 'root\tREADME.md\tenforced\tREADME.md\n' > caped.registry
  printf '# fixture\n\n## Requirements\n\n- %sfx no-test] Fixture requirement.\n' "$MK" > README.md
  git add -A
  git commit -qm seed
  git clone -q --bare . "$dir-origin.git" >/dev/null 2>&1
  git remote add origin "$dir-origin.git"
  git push -q origin HEAD
  git remote set-head origin -a >/dev/null 2>&1 || true
}

run_push() {
  set +e
  POUT="$(bash "$CAPED" check push 2>&1)"; PRC=$?
  set -e
}

expect_push_error() { # <name> <word>
  local name="$1" word="$2"
  if [ "$PRC" -ne 1 ]; then bad "$name — expected exit 1, got $PRC: $POUT"
  elif printf '%s' "$POUT" | grep -q "$word"; then ok "$name"
  else bad "$name — failed, but the report lacks '$word': $POUT"; fi
}

# A new requirement definition inside a fileless contract. [#adhoc-id]
push_repo
echo x >> notes.txt; git add notes.txt
git commit -qm 'адхок с новым требованием

тело: решили добавить правило.

Adhoc: hotfix-norm
Behavior: contract
Spec: README.md'
cat >> README.md <<EOF
- "$MK"new-rule] Brand new requirement.
EOF
git add README.md
git commit -qm 'адхок вводит требование в спек

тело: новое правило прямо в адхоке.

Adhoc: hotfix-norm
Behavior: contract
Spec: README.md'
run_push
expect_push_error 'push: new requirement in a fileless contract fails [#adhoc-id]' 'introduces requirement'

# Adhoc: <name> appearing 3+ times in the range. [#adhoc-id]
push_repo
for i in 1 2 3; do
  echo "n$i" >> notes.txt; git add notes.txt
  git commit -qF - <<FIX
адхок $i

тело: кластерное решение $i.

Adhoc: fix-run
Behavior: contract
Spec: README.md
FIX
done
run_push
expect_push_error 'push: Adhoc cluster of 3 is flagged [#adhoc-id]' 'materialise changes/fix-run.md'

# A single well-formed fileless contract passes clean. [#adhoc-id]
push_repo
echo x >> notes.txt; git add notes.txt
git commit -qF - <<'FIX'
один адхок

тело: одно решение, всё в порядке.

Adhoc: one-off
Behavior: contract
Spec: README.md
FIX
run_push
if [ "$PRC" -eq 0 ]; then ok 'push: single named adhoc passes [#adhoc-id]'
else bad "push clean failed: $POUT"; fi


echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
