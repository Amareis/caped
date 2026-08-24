#!/usr/bin/env bash
# caped events — lifecycle event feed + .caped/hooks dispatch.
#
# The feed is append-only jsonl at .caped/events/feed.jsonl. Each event is one
# line written with a single write(2) ('printf %s\n >>' is O_APPEND; atomic for
# lines < PIPE_BUF). The consumer cursor is the count of already-consumed
# lines; a partial trailing line is never produced by << but is skipped on read.
#
# Event types (v0): idea-born, relayed, idea-edited, taken-into-work, archived,
# idea-withdrawn, adhoc, contract, backlog-edited. (tool-updated arrives with the
# version-stamp check later.)
#
# Dispatch: for each event, if .caped/hooks/<event> exists and is executable it
# runs with CAPED_EVENT, CAPED_ENTITY, CAPED_COMMIT, CAPED_ROOT in the env.
# .caped/hooks/ is VERSIONED — hooks are the repo's own policy (like git hooks).
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
FEED_DIR="$ROOT/.caped/events"
FEED="$FEED_DIR/feed.jsonl"

emit() { # <event> [entity] — append one jsonl line, then dispatch
  local ev="$1" ent=""
  [ "$#" -ge 2 ] && ent="$2"
  mkdir -p "$FEED_DIR" 2>/dev/null || true
  printf '{"t":"%s","e":"%s","c":"%s","at":"%s"}\n' \
    "$ev" "$ent" "$(git rev-parse --short HEAD 2>/dev/null || echo -)" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$FEED" 2>/dev/null || true
  dispatch "$ev" "$ent"
}

dispatch() { # <event> <entity>
  local ev="$1" ent="$2" hook
  hook="$ROOT/.caped/hooks/$ev"
  [ -x "$hook" ] || return 0
  CAPED_EVENT="$ev" CAPED_ENTITY="$ent" CAPED_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || true)" \
    CAPED_ROOT="$ROOT" "$hook" || true
}

post_commit() { # called by the post-commit shim; reads HEAD, emits the dominant event
  local h body ent
  h="$(git rev-parse HEAD)"
  body="$(git log -1 --format='%B' "$h")"
  ent="$(printf '%s\n' "$body" | sed -n 's/^Archives: \([^ ]*\)/\1/p' | head -1)"
  if [ -n "$ent" ] && git show --name-status --format= "$h" | grep -q "^D\tchanges/$ent.md$"; then
    emit archived "$ent"; return 0; fi
  if [ -n "$ent" ] && git show --name-status --format= "$h" | grep -q "^D\tideas/$ent.md$"; then
    emit idea-withdrawn "$ent"; return 0; fi
  ent="$(printf '%s\n' "$body" | sed -n 's/^Idea: \([^ ]*\)/\1/p' | head -1)"
  ag="$(printf '%s\n' "$body" | sed -n 's/^Agent: \([^ ]*\)/\1/p' | head -1)"
  if [ -n "$ent" ] && git show --name-status --format= "$h" | grep -q "^A\tideas/$ent.md$"; then
    # A relayed idea arrives stamped Agent: <id>@<home> — a birth with the
    # @home suffix is `relayed`, not a local born.
    if printf '%s' "$ag" | grep -q '@'; then
      emit relayed "$ent"; return 0; fi
    emit idea-born "$ent"; return 0; fi
  if [ -n "$ent" ] && git show --name-status --format= "$h" | grep -q "^M\tideas/$ent.md$"; then
    emit idea-edited "$ent"; return 0; fi
  ent="$(printf '%s\n' "$body" | sed -n 's/^Change: \([^ ]*\)/\1/p' | head -1)"
  if [ -n "$ent" ] && git show --name-status --format= -M "$h" | grep -q "^R[0-9]*\tideas/$ent.md\tchanges/$ent.md$"; then
    emit taken-into-work "$ent"; return 0; fi
  if printf '%s\n' "$body" | grep -q '^Behavior: contract' && ! printf '%s\n' "$body" | grep -q '^Change: '; then
    emit adhoc; return 0; fi
  if printf '%s\n' "$body" | grep -q '^Behavior: contract'; then
    emit contract; return 0; fi
  # backlog-edited: _backlog is Idea:-exempt, but its edits are still facts for
  # parallel agents (deposits, line maintenance). Archive deposits are already
  # covered by the dominant `archived` event above — only standalone edits land here.
  if git show --name-status --format= "$h" | grep -q "^M\tideas/_backlog.md$"; then
    emit backlog-edited "_backlog"; return 0; fi
}

events_cmd() { # caped events [--since <n>] — lines after the cursor, no partial tail
  local since=0 total
  if [ "$#" -ge 1 ] && [ "$1" != "--since" ]; then
    echo "caped events: usage: caped events [--since <lines-consumed>]" >&2; exit 2
  fi
  [ "$#" -ge 2 ] && since="$2"
  [ -f "$FEED" ] || { echo "caped events: no feed yet — nothing has happened since init"; exit 0; }
  total="$(wc -l < "$FEED")"
  if [ "$since" -lt "$total" ]; then
    sed -n "$((since + 1)),\$p" "$FEED" | head -n "$((total - since))"
  fi
}

version_check() { # bundled changelog head vs the session cursor (tool-updated)
  local bundle="$(env | sed -n 's/^CAPED_BUNDLE_PATH=//p' | head -1)" line stamp
  [ -n "$bundle" ] || bundle="$(cd "$(dirname "$0")" && pwd)/CHANGELOG.caped.generated.md"
  [ -f "$bundle" ] || return 0
  line="$(head -1 "$bundle")"
  [ -n "$line" ] || return 0
  stamp="$ROOT/.caped/state/tool-version"
  if [ -f "$stamp" ]; then
    [ "$(cat "$stamp")" = "$line" ] && return 0
    mkdir -p "$(dirname "$stamp")" 2>/dev/null || true
    printf '%s\n' "$line" > "$stamp"
    emit tool-updated
  else
    mkdir -p "$(dirname "$stamp")" 2>/dev/null || true
    printf '%s\n' "$line" > "$stamp"
  fi
}

case "$#" in
  0) version_check; events_cmd ;;
  *)
    case "$1" in
      post-commit) version_check; post_commit ;;
      version-check) version_check ;;
      emit) shift; emit "$1" "$2" ;;
      *) version_check; events_cmd "$@" ;;
    esac
    ;;
esac
