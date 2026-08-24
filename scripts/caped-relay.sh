#!/usr/bin/env bash
# caped relay <neighbor> <idea> [--keep] — the ONLY door into a neighbor repo.
#
# Copies ideas/<name>.md to the neighbor's ideas/ with adapted frontmatter
# (spawned_from: null + a Handoff note), commits there with Idea: <name> (+ a
# home-marked Agent:), then withdraws the local copy (Archives: <name>) unless
# --keep. The neighbor's hooks (Idea:, Agent:, residency) do the enforcement.
# [#neighbor-relay]
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

die() { echo "caped relay: $*" >&2; exit 2; }

keep=0
args=()
for a in "$@"; do
  case "$a" in
    --keep) keep=1 ;;
    *) args+=("$a") ;;
  esac
done
[ "${#args[@]}" -eq 2 ] || die "usage: caped relay <neighbor> <idea> [--keep]"
nb="${args[0]}"
name="${args[1]}"

[ -f "ideas/$name.md" ] || die "no ideas/$name.md here — nothing to relay"
[ -f caped.neighbors ] || die "no caped.neighbors — add neighbors first"

path=""
while IFS=$'\t' read -r n p role; do
  case "$n" in '' | \#*) continue ;; esac
  if [ "$n" = "$nb" ]; then path="$p"; break; fi
done < caped.neighbors
[ -n "$path" ] || die "neighbor '$nb' not found in caped.neighbors"
[ -d "$path/.git" ] || die "$path is not a git repo"
[ -f "$path/caped.registry" ] || die "$path is not a caped repo (no caped.registry)"
[ -e "$path/ideas/$name.md" ] && die "$path/ideas/$name.md already exists at the neighbor"

home="$(basename "$ROOT")"
ours="$(git rev-parse --short HEAD)"
agent="${CAPED_AGENT:-human}"
[ "$agent" = "human" ] || agent="$agent@$home"   # honest foreigner mark; @home is residency-exempt

mkdir -p "$path/ideas"
{
  sed 's/^spawned_from: .*/spawned_from: null/' "ideas/$name.md"
  printf '\n## Handoff\n\nРелей из %s@%s (`caped relay %s %s`, %s); происхождение — %s.\n' \
    "$home" "$ours" "$nb" "$name" "$(date +%F)" "$ROOT"
} > "$path/ideas/$name.md"

git -C "$path" add "ideas/$name.md"
git -C "$path" commit -q -F - <<EOF
идея $name: релей из $home ($ours)

Idea: $name
Behavior: internal
Agent: $agent
EOF
relayed="$(git -C "$path" rev-parse --short HEAD)"
echo "ok: relayed → $path/ideas/$name.md ($relayed)"

if [ "$keep" -eq 0 ]; then
  git rm -q "ideas/$name.md"
  git commit -q -F - <<EOF
снята идея $name: передана релей-идеей в $nb ($relayed)

Причина: владение переехало к соседу (caped relay); ссылки резолвятся как архивные.

Archives: $name
Agent: ${CAPED_AGENT:-human}
EOF
  echo "ok: local copy withdrawn (Archives: $name)"
else
  echo "ok: kept the local copy (--keep)"
fi