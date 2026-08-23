#!/usr/bin/env bash
# caped-lifecycle — `caped idea|work|archive <name>`: lifecycle commits with
# the right trailers. archive runs the gates itself (deferred-OQ deposit into
# ideas/_backlog.md, then the full test runner) and refuses on red. [#lifecycle-cmds]
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

sub="${1:-}"
[ -n "$sub" ] || { echo "caped: usage: caped idea|work|archive <name> [summary]" >&2; exit 2; }
shift 2>/dev/null || true

die() { echo "caped ${sub}: $*" >&2; exit 2; }

case "$sub" in
  idea)
    name="$1"
    [ -n "$name" ] || die "usage: caped idea <name> [summary]"
    printf '%s' "$name" | grep -qE '^[a-z0-9][a-z0-9-]*$' || die "name must be [a-z0-9][a-z0-9-]*"
    [ -e "ideas/$name.md" ] && die "ideas/$name.md already exists"
    summary="${2:-}"
    mkdir -p ideas
    cat > "ideas/$name.md" <<EOF
---
name: $name
summary: $summary
depends_on: []
spawned_from: null
---

## Why

TODO

## Context

TODO

## Requirements

-

## Decisions

-

## Rejected alternatives

-

## Provenance

-

## Open questions

-
EOF
    git add "ideas/$name.md"
    git commit -q -F - <<EOF
идея $name: $summary

Idea: $name
EOF
    echo "ok: ideas/$name.md born (Idea: $name)"
    ;;
  work)
    name="$1"
    [ -e "ideas/$name.md" ] || die "no ideas/$name.md — nothing to take into work"
    mkdir -p changes
    git mv "ideas/$name.md" "changes/$name.md"
    git commit -q -F - <<EOF
в работу: $name

Change: $name
EOF
    echo "ok: $name taken into work (Change: $name)"
    ;;
  archive)
    name="$1"
    [ -e "changes/$name.md" ] || die "no changes/$name.md — nothing to archive"
    mkdir -p ideas
    [ -f ideas/_backlog.md ] || die "ideas/_backlog.md missing — the deposit target"
    old="$(cat "changes/$name.md" 2>/dev/null || true)"
    future="$(printf '%s\n' "$old" | sed -n '/^## Open questions/,/^## /p' | grep -E 'v0\.1|позже|отлож|будущ|следующ' || true)"
    promoted="$(printf '%s\n' "$old" | grep 'промоут →' || true)"
    if [ -n "$future" ] && [ -z "$promoted" ]; then
      printf '%s\n' "$future" | while IFS= read -r q; do
        printf -- '- %s | from %s | %s\n' "$q" "$name" "$(date +%F)" >> ideas/_backlog.md
      done
      git add ideas/_backlog.md
      echo "ok: deferred open questions deposited into ideas/_backlog.md"
    fi
    if [ -f scripts/run-tests.sh ]; then
      if bash scripts/run-tests.sh >/dev/null 2>&1; then :; else
        echo "caped archive: gate red — test suites failed, archive refused" >&2; exit 1
      fi
    else
      if bash "scripts/caped.sh" trace >/dev/null 2>&1; then :; else
        echo "caped archive: trace red — archive refused" >&2; exit 1
      fi
    fi
    git rm -q "changes/$name.md"
    git commit -q -F - <<EOF
архив: $name

Change: $name
Archives: $name
EOF
    echo "ok: $name archived (Change + Archives)"
    ;;
  *)
    die "unknown subcommand: $sub (have: idea|work|archive)"
    ;;
esac
