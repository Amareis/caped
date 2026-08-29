#!/usr/bin/env bash
# caped trace — static requirement<->test balance check (no test execution).
#
#   defs — requirement markers opening a bullet ('- [#<slug> ...') in the
#          spec files of enforced caps (caped.registry column 4; by the
#          req-form norm they live in the '## Requirements' section);
#          a marker quoted in prose is NOT a definition. Declared/legacy
#          caps are "a spec without trace": their markers are NOT defs and
#          their spec files are excluded from the ref scan — a ref naming
#          such a slug dangles with a hint to flip the cap to enforced.
#          Attributes inside the brackets:
#          " no-test" — explicit exemption from coverage,
#          " dump"    — the requirement is agent-facing and MUST be
#                      referenced in the rules dump (scripts/caped.sh)
#   refs — the same markers in any tracked file that is not a spec file
#          (of ANY cap state) and not an idea/change file (ideas/,
#          changes/ are prose, not coverage)
#
# Failures: uncovered (def with no ref, not exempt), dangling (ref with no
# def — a test outlived its requirement), duplicate (one slug defined twice),
# undumped (dump-attr def never referenced in scripts/caped.sh).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

REG=caped.registry
[ -f "$REG" ] || { echo "caped trace: no $REG — run caped init first" >&2; exit 2; }

SPECS=()       # enforced caps — defs are loaded from these
ALLSPECS=()    # every registry spec file — excluded from the ref scan
NONENFORCED=() # state<TAB>spec rows of declared/legacy caps — dangling hints
while IFS=$'\t' read -r name path state spec; do
  case "$name" in '' | \#*) continue ;; esac
  [ -n "${spec:-}" ] || continue
  ALLSPECS+=("$spec")
  if [ "$state" = enforced ]; then
    SPECS+=("$spec")
  else
    NONENFORCED+=("$state	$spec")
  fi
done < "$REG"
if [ "${#SPECS[@]}" -eq 0 ]; then
  echo "caped trace: no enforced caps in $REG — nothing to check"
  exit 0
fi

defs="$(mktemp)"; refs="$(mktemp)"; dumprefs="$(mktemp)"; nondefs="$(mktemp)"
trap 'rm -f "$defs" "$refs" "$dumprefs" "$nondefs"' EXIT

is_spec() {
  local f="$1" s
  for s in "${ALLSPECS[@]:-}"; do [ -n "$s" ] && [ "$f" = "$s" ] && return 0; done
  return 1
}

for f in "${SPECS[@]}"; do
  [ -f "$f" ] || { echo "caped trace: spec file '$f' from $REG does not exist" >&2; exit 2; }
done
# Dedupe: several caps may share one spec file (e.g. root + scripts + tests
# all point at README.md) — a repeated spec must not multiply defs.
while IFS= read -r f; do
  grep -oE '^- \[#[a-z0-9][a-z0-9-]*(( (no-test|dump))*)\]' "$f" \
    | sed -E 's/^- \[#([a-z0-9-]+)(( (no-test|dump))*)\]$/\1\t\2/' >> "$defs" || true
done < <(printf '%s\n' "${SPECS[@]}" | sort -u)

# Slugs defined in non-enforced specs — not defs, only a dangling diagnostic:
# "the spec exists, the cap is just not enforced".
for row in "${NONENFORCED[@]:-}"; do
  [ -n "$row" ] || continue
  state="${row%%	*}"; f="${row#*	}"
  [ -f "$f" ] || continue
  grep -oE '^- \[#[a-z0-9][a-z0-9-]*(( (no-test|dump))*)\]' "$f" \
    | sed -E "s/^- \[#([a-z0-9-]+)(( (no-test|dump))*)\]\$/\1\t$state/" >> "$nondefs" || true
done

while IFS= read -r f; do
  case "$f" in ideas/* | changes/*) continue ;; esac
  is_spec "$f" && continue
  [ -f "$f" ] || continue
  grep -IoE '\[#[a-z0-9][a-z0-9-]*\]' "$f" | sed -E 's/^\[#([a-z0-9-]+)\]$/\1/' >> "$refs" || true
done < <(git ls-files)

# Refs inside the rules dump specifically — for the undumped class.
# Prefer the repo's own dump (self-host layout, also what the fixtures
# build); when the repo vendors nothing (linked mode), fall back to the
# dump installed next to this script.
DUMP=scripts/caped.sh
[ -f "$DUMP" ] || DUMP="$(cd "$(dirname "$0")" && pwd)/caped.sh"
[ -f "$DUMP" ] && grep -IoE '\[#[a-z0-9][a-z0-9-]*\]' "$DUMP" \
  | sed -E 's/^\[#([a-z0-9-]+)\]$/\1/' >> "$dumprefs" || true

report="$(awk -F'\t' '
  FILENAME == ARGV[1] { ref[$1]=1; next }
  FILENAME == ARGV[2] { dref[$1]=1; next }
  FILENAME == ARGV[3] { nd[$1]=$2; next }
  { count[$1]++; if ($2 ~ /no-test/) notest[$1]=1; if ($2 ~ /dump/) isdump[$1]=1 }
  END {
    for (s in count) {
      if (count[s] > 1)
        printf "duplicate\t%s\tdefined %d times in spec files — keep one definition, rename the rest\n", s, count[s]
      if (!(s in notest) && !(s in ref))
        printf "uncovered\t%s\tdefined in a spec but referenced by no test — add a marker to a scenario or exempt it with no-test\n", s
      if ((s in isdump) && !(s in dref))
        printf "undumped\t%s\tdeclared agent-facing (dump attribute) but never referenced in the rules dump (scripts/caped.sh) — add the rule to the dump or drop the attribute\n", s
    }
    for (s in ref)
      if (!(s in count)) {
        if (s in nd)
          printf "dangling\t%s\treferenced by a test but defined in the spec of a %s cap — non-enforced caps have no trace coverage: flip the cap to enforced or remove the marker\n", s, nd[s]
        else
          printf "dangling\t%s\treferenced by a test but defined in no spec — the requirement is gone; remove the marker or restore the requirement\n", s
      }
  }' "$refs" "$dumprefs" "$nondefs" "$defs" | sort)"

ndefs="$(cut -f1 "$defs" | sort -u | grep -c . || true)"
nrefs="$(sort -u "$refs" | grep -c . || true)"
nnotest="$(awk -F'\t' '$2 ~ /no-test/ { print $1 }' "$defs" | sort -u | grep -c . || true)"

if [ -n "$report" ]; then
  nu="$(printf '%s\n' "$report" | grep -c '^uncovered' || true)"
  nd="$(printf '%s\n' "$report" | grep -c '^dangling' || true)"
  np="$(printf '%s\n' "$report" | grep -c '^duplicate' || true)"
  nuu="$(printf '%s\n' "$report" | grep -c '^undumped' || true)"
  echo "caped trace: RED — defs $ndefs, refs $nrefs: $nu uncovered, $nd dangling, $np duplicate, $nuu undumped"
  echo "$report" | sed 's/^/  /'
  exit 1
fi

echo "caped trace: OK — defs $ndefs ($nnotest no-test), refs $nrefs: 0 uncovered, 0 dangling, 0 duplicate, 0 undumped"
