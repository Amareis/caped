#!/usr/bin/env bash
# caped trace — static requirement<->test balance check (no test execution).
#
#   defs — requirement markers in the spec files of enforced caps
#          (caped.registry column 4); a marker with a " no-test" suffix inside
#          the brackets is an explicit exemption
#   refs — the same markers in any tracked file that is not a spec file and
#          not an idea/change file (ideas/, changes/ are prose, not coverage)
#
# Failures: uncovered (def with no ref, not exempt), dangling (ref with no
# def — a test outlived its requirement), duplicate (one slug defined twice).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

REG=caped.registry
[ -f "$REG" ] || { echo "caped trace: no $REG — run scripts/caped.sh init first" >&2; exit 2; }

SPECS=()
while IFS= read -r line; do SPECS+=("$line"); done < <(
  awk -F'\t' '$1 !~ /^#/ && NF >= 4 && $3 == "enforced" { print $4 }' "$REG" | sort -u
)
if [ "${#SPECS[@]}" -eq 0 ]; then
  echo "caped trace: no enforced caps in $REG — nothing to check"
  exit 0
fi

defs="$(mktemp)"; refs="$(mktemp)"
trap 'rm -f "$defs" "$refs"' EXIT

is_spec() {
  local f="$1" s
  for s in "${SPECS[@]}"; do [ "$f" = "$s" ] && return 0; done
  return 1
}

for f in "${SPECS[@]}"; do
  [ -f "$f" ] || { echo "caped trace: spec file '$f' from $REG does not exist" >&2; exit 2; }
  grep -oE '\[#[a-z0-9][a-z0-9-]*( no-test)?\]' "$f" \
    | sed -E 's/^\[#([a-z0-9-]+)( no-test)?\]$/\1\t\2/' >> "$defs" || true
done

while IFS= read -r f; do
  case "$f" in ideas/* | changes/*) continue ;; esac
  is_spec "$f" && continue
  [ -f "$f" ] || continue
  grep -IoE '\[#[a-z0-9][a-z0-9-]*\]' "$f" | sed -E 's/^\[#([a-z0-9-]+)\]$/\1/' >> "$refs" || true
done < <(git ls-files)

report="$(awk -F'\t' '
  FILENAME == ARGV[1] { ref[$1]=1; next }
  { count[$1]++; if ($2 != "") notest[$1]=1 }
  END {
    for (s in count) {
      if (count[s] > 1)
        printf "duplicate\t%s\tdefined %d times in spec files — keep one definition, rename the rest\n", s, count[s]
      if (!(s in notest) && !(s in ref))
        printf "uncovered\t%s\tdefined in a spec but referenced by no test — add a marker to a scenario or exempt it with no-test\n", s
    }
    for (s in ref)
      if (!(s in count))
        printf "dangling\t%s\treferenced by a test but defined in no spec — the requirement is gone; remove the marker or restore the requirement\n", s
  }' "$refs" "$defs" | sort)"

ndefs="$(cut -f1 "$defs" | sort -u | grep -c . || true)"
nrefs="$(sort -u "$refs" | grep -c . || true)"

if [ -n "$report" ]; then
  echo "caped trace: requirement/test imbalance:"
  echo "$report" | sed 's/^/  /'
  exit 1
fi

echo "caped trace: OK — $ndefs requirement markers defined, $nrefs referenced"
