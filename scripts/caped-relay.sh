#!/usr/bin/env bash
# caped relay <neighbor> <idea> [--keep] [--agent <id>] — the ONLY door into a
# neighbor repo.
#
# Two modes, split by whether the local idea is committed:
#   - tracked ideas/...md  — normal relay: copy+adapt, Idea: commit at the
#     neighbor, then a local withdrawal (Archives:) unless --keep (2 home commits);
#   - untracked ideas/...md — DIRECT send: only the neighbor's commit; the local
#     file is removed (or kept with --keep) with NO home commits at all.
# The sender id is REQUIRED (CAPED_AGENT or --agent; manual runs set
# CAPED_AGENT=human explicitly — there is no default). The neighbor commit is
# home-marked Agent: <id>@<home> + Behavior: internal (target hooks may cap paths).
# [#neighbor-relay]
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

die() { echo "caped relay: $*" >&2; exit 2; }

keep=0
agent=""
args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --keep) keep=1 ;;
    --agent) [ "$#" -ge 2 ] || die "--agent needs a value"; agent="$2"; shift ;;
    *) args+=("$1") ;;
  esac
  shift
done
[ "${#args[@]}" -eq 2 ] || die "usage: caped relay <neighbor> <idea> [--keep] [--agent <id>]"
nb="${args[0]}"
name="${args[1]}"

[ -f "ideas/$name.md" ] || die "no ideas/$name.md here — nothing to relay"
[ -f caped.neighbors ] || die "no caped.neighbors — add neighbors first"

agent="${agent:-${CAPED_AGENT:-}}"
[ -n "$agent" ] || die "sender id required — no default: set CAPED_AGENT (manual: CAPED_AGENT=human) or --agent <id>"

path=""
# awk parse (not while-read): while-read silently drops a final line that lacks
# a trailing newline; awk is newline- and TAB-robust.
while IFS= read -r line; do
  [ -n "$line" ] || continue
  n="$(printf '%s' "$line" | awk -F'\t' '$1 !~ /^#/ && $1 != "" {print $1; exit}')"
  p="$(printf '%s' "$line" | awk -F'\t' '{print $2}')"
  [ -n "$n" ] || continue
  if [ "$n" = "$nb" ] && [ -n "$p" ]; then path="$p"; break; fi
done < caped.neighbors
[ -n "$path" ] || die "neighbor '$nb' not found in caped.neighbors"
[ -d "$path/.git" ] || die "$path is not a git repo"
[ -f "$path/caped.registry" ] || die "$path is not a caped repo (no caped.registry)"
[ -e "$path/ideas/$name.md" ] && die "$path/ideas/$name.md already exists at the neighbor"

home="$(basename "$ROOT")"
ours="$(git rev-parse --short HEAD 2>/dev/null || echo -)"
tracked=0
git ls-files --error-unmatch "ideas/$name.md" >/dev/null 2>&1 && tracked=1

mkdir -p "$path/ideas"
{
  sed 's/^spawned_from: .*/spawned_from: null/' "ideas/$name.md"
  printf '\n## Handoff\n\nРелей из %s@%s (`caped relay %s %s`, %s); происхождение — %s.\n' \
    "$home" "$ours" "$nb" "$name" "$(date +%F)" "$ROOT"
} > "$path/ideas/$name.md"

# Canonical schema: the receiver's caped check expects the full section set.
# Relays from foreign schemas must arrive valid (both live inbound relays from
# kudach needed manual repair). Missing sections are appended empty; then the
# receiver's caped check runs BEFORE the commit — a red check kills the relay.
for sec in "Why" "Context" "Requirements" "Decisions" "Rejected alternatives" "Provenance" "Open questions"; do
  grep -q "^## $sec\$" "$path/ideas/$name.md" || printf '\n## %s\n\n-\n' "$sec" >> "$path/ideas/$name.md"
done
RELAY_CAPED="$(cd "$(dirname "$0")" && pwd)/caped.sh"
if ! (cd "$path" && bash "$RELAY_CAPED" check >/dev/null 2>&1); then
  die "relaid idea failed $path's caped check — canonical schema not achieved; fix ideas/$name.md first"
fi

git -C "$path" add "ideas/$name.md"
git -C "$path" commit -q -F - <<EOF
идея $name: релей из $home ($ours)

Idea: $name
Behavior: internal
Agent: $agent@$home
EOF
relayed="$(git -C "$path" rev-parse --short HEAD)"
echo "ok: relayed → $path/ideas/$name.md ($relayed)"

if [ "$keep" -eq 0 ]; then
  if [ "$tracked" -eq 1 ]; then
    git rm -q "ideas/$name.md"
    git commit -q -F - <<EOF
снята идея $name: передана релей-идеей в $nb ($relayed)

Причина: владение переехало к соседу (caped relay); ссылки резолвятся как архивные.

Archives: $name
Agent: $agent
EOF
  else
    rm -f "ideas/$name.md"
  fi
  echo "ok: local copy removed (direct mode: no home commits)"
else
  echo "ok: kept the local copy (--keep)"
fi