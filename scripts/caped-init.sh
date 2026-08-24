#!/usr/bin/env bash
# caped init — one-time wiring of a repository for the caped model.
# Idempotent: re-running only repairs what is missing and refreshes the report.
#
# What it does:
#   1. Installs the .git/hooks/commit-msg shim delegating to the caped
#      dispatcher. Linked mode: the shim points at the installed tool
#      (absolute path) and the repo vendors no scripts; if the dispatcher
#      runs from inside the repo itself, the shim stays repo-relative.
#   2. Seeds caped.registry if missing: root cap + auto-discovery of
#      src/features/*/ as legacy caps (for adopting repositories).
#   3. Adds .caped/ to .gitignore (derived views are never committed).
#   4. Creates ideas/ and changes/ with .gitkeep.
#   5. Seeds a minimal AGENTS.md pointer if the repo has none.
#   6. Prints (and writes to .caped/coverage.txt) the coverage report:
#      how many tracked files fall under enforced caps, legacy, or none.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# The tool's own scripts directory — the repo does not have to vendor them.
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_WRAPPER="$(dirname "$TOOL_DIR")/caped"
[ -x "$TOOL_WRAPPER" ] || TOOL_WRAPPER="$TOOL_DIR/caped.sh"

die() { echo "caped-init: $*" >&2; exit 1; }

[ -d .git ] || die "not a git repository: $ROOT"

# --- 1. commit-msg shim ---------------------------------------------------
SHIM=.git/hooks/commit-msg
if [ "${TOOL_DIR#"$ROOT"/}" != "$TOOL_DIR" ]; then
  # Dispatcher lives inside this repo (vendored layout) — keep the shim
  # repo-relative so it survives the repo moving around.
  REL="${TOOL_DIR#"$ROOT"/}"
  printf '#!/bin/sh\n# caped commit-msg shim — logic is versioned in %s\nexec "$(git rev-parse --show-toplevel)/%s/caped.sh" hook commit-msg "$@"\n' \
    "$REL" "$REL" > "$SHIM"
  echo "ok: $SHIM -> $REL/caped.sh hook commit-msg (vendored)"
else
  # Linked mode: point at the installed tool, vendor nothing.
  printf '#!/bin/sh\n# caped commit-msg shim — delegates to the installed caped tool\nexec "%s/caped.sh" hook commit-msg "$@"\n' \
    "$TOOL_DIR" > "$SHIM"
  echo "ok: $SHIM -> $TOOL_DIR/caped.sh hook commit-msg (linked)"
fi
chmod +x "$SHIM"

# --- 1b. post-commit shim (event feed) -----------------------------------
PCSHIM=.git/hooks/post-commit
if [ "${TOOL_DIR#"$ROOT"/}" != "$TOOL_DIR" ]; then
  REL="${TOOL_DIR#"$ROOT"/}"
  printf '#!/bin/sh\n# caped post-commit shim — lifecycle events to .caped/events/\nexec "$(git rev-parse --show-toplevel)/%s/caped.sh" hook post-commit "$@"\n' \
    "$REL" > "$PCSHIM"
  echo "ok: $PCSHIM -> $REL/caped.sh hook post-commit (vendored)"
else
  printf '#!/bin/sh\n# caped post-commit shim — lifecycle events to .caped/events/\nexec "%s/caped.sh" hook post-commit "$@"\n' \
    "$TOOL_DIR" > "$PCSHIM"
  echo "ok: $PCSHIM -> $TOOL_DIR/caped.sh hook post-commit (linked)"
fi
chmod +x "$PCSHIM"

# --- 2. caped.registry ----------------------------------------------------
if [ ! -f caped.registry ]; then
  {
    printf '# caped registry — name<TAB>path-prefix<TAB>state<TAB>spec-file\n'
    printf '# state: enforced | declared | legacy\n'
    printf 'root\tREADME.md\tenforced\tREADME.md\n'
    printf 'hooks\t.caped/hooks/\tenforced\tREADME.md\n'
    # auto-discovery: typical feature-sliced layout — existing features as legacy
    if [ -d src/features ]; then
      for d in src/features/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        printf '%s\t%s\tlegacy\t%sREADME.md\n' "$name" "$d" "$d"
      done
    fi
  } > caped.registry
  echo "ok: caped.registry seeded (src/features/* entered as legacy — flip to enforced one by one)"
else
  echo "ok: caped.registry already exists, untouched"
fi

# --- 3. .gitignore --------------------------------------------------------
touch .gitignore
if grep -qxF '.caped/*' .gitignore; then
  echo "ok: .caped/* already in .gitignore (hooks versioned)"
else
  printf '\n# caped derived views/machine state — never committed; .caped/hooks/ is repo policy and IS versioned\n.caped/*\n!.caped/hooks/\n!.caped/hooks/*\n' >> .gitignore
  echo "ok: .caped/* ignored, .caped/hooks/ kept versioned"
fi

# --- 4. ideas/ + changes/ -------------------------------------------------
mkdir -p ideas changes .caped .caped/hooks .caped/events
for d in ideas changes; do
  [ -e "$d/.gitkeep" ] || { : > "$d/.gitkeep"; echo "ok: $d/.gitkeep"; }
done
# The archive gate deposits deferred questions into ideas/_backlog.md — seed
# the skeleton so the first `caped archive` does not die on a missing target.
if [ ! -f ideas/_backlog.md ]; then
  cat > ideas/_backlog.md <<'EOF'
---
name: _backlog
summary: Reserved pseudo-idea — the backlog of deferred "future" thoughts; entries live as bullets in Requirements (render reqs indexes them); caped archive deposits land here; never taken into work
depends_on: []
spawned_from: null
---

## Why

Middle ground between "an open question in a change" (dies with the archive) and "a whole idea" (too much ceremony for one future thought). Reserved service name: it sorts first and is NEVER taken into work — picking an entry up means spawning a real idea from it.

## Context

Entry format (one line): thought | from <change/idea> | date | (status). The showcase is forward-only: an entry that got applied or transferred is REMOVED — the trace lives in git history, a (status) tag marks a line for cleanup, not a ledger.

## Requirements

-

## Decisions

-

## Rejected alternatives

-

## Provenance

Seeded by caped init.

## Open questions

-
EOF
  echo "ok: ideas/_backlog.md seeded (archive deposit target)"
else
  echo "ok: ideas/_backlog.md already exists, untouched"
fi

# --- 5. AGENTS.md pointer ---------------------------------------------------
if [ ! -f AGENTS.md ]; then
  cat > AGENTS.md <<EOF
# AGENTS.md

This repository uses caped (capability-based change discipline).
First action in any session: run \`$TOOL_WRAPPER\` with no arguments
and follow the printed rules. \`$TOOL_WRAPPER plan\` shows the
work map (queue, territories, blockers).
EOF
  echo "ok: AGENTS.md seeded (points at $TOOL_WRAPPER)"
else
  echo "ok: AGENTS.md already exists, untouched"
fi

# --- 6. coverage report (generated by render — one views generator) ----------
bash "$TOOL_DIR/caped.sh" render coverage --write

echo "caped init: done"
