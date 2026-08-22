#!/usr/bin/env bash
# caped — v0 dispatcher. Bare invocation prints the full working rules
# (this IS the self-documentation: AGENTS.md and the hook both point here).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cmd="${1:-}"

rules() {
  cat <<'EOF'
caped — tracker and specs in git. The working rules of this repository.

LIFECYCLE (each event is a separate atomic commit)

  1. Idea:      new file ideas/<name>.md, commit with trailer  Idea: <name>
  2. In work:   clean git mv ideas/<name>.md changes/<name>.md (no content
                edits — rename detection must stitch the file's history),
                trailer Change: <name>
  3. Work:      every commit of the change carries Change: <name>; editing
                changes/<name>.md without it is rejected by the hook
  4. Archive:   the final commit applies the deltas to capability READMEs
                (those deltas ARE its content) and deletes changes/<name>.md,
                trailers Change: <name> + Archives: <name>. Finishing may be a
                single commit (deltas + deletion together) — splitting the
                last work commit and the deletion is valid but not required.

COMMIT TRAILERS (git trailers, enforced by the commit-msg hook)

  Behavior: contract|internal|wip  — change class, required for ANY commit
                                     touching enforced capabilities, the
                                     archive commit included (subject
                                     "wip*" counts as wip)
  Spec: <path>                     — on contract: the path of the spec whose
                                     contract changes. Either the trailer or
                                     the spec file changed in the same commit
                                     satisfies the hook — no need for both.
  Idea: <name>                     — birth of ideas/<name>.md
  Change: <name>                   — the commit belongs to changes/<name>.md
  Archives: <name>                 — archival: the change file is deleted in
                                     this very commit

CAPABILITY REGISTRY (caped.registry, TAB-separated: name, prefix, state, spec file)

  prefix    — a path prefix; a commit "touches" the cap when a staged file
              starts with it. READ caped.registry to know which paths are
              enforced — or just commit and let the hook tell you.
  legacy    — coverage declared, hook does not check (migration path)
  declared  — spec file exists, enforcement not yet enabled
  enforced  — hook requires Behavior/Spec
  Paths outside the registry are ignored by design. Overlapping prefixes:
  longest prefix wins.

ADHOC (fileless) DECISIONS

  A small, already-discussed, 1–2-commit decision may live entirely in its
  commits — no ideas/changes file: Behavior: contract|internal (+ Spec: on
  contract) with the rationale in the commit BODY (enforced: a fileless
  contract requires a non-empty body — subject and trailers don't count).
  A file is required when the work is > 2 commits, opens a new decision
  territory, is disputed or undiscussed, spans several caps, or carries open
  questions. Drift review watches the share of fileless contract commits.

DISCIPLINE

  - One semantic event = one commit. Never mix mv/archival with UNRELATED
    edits; the archive commit's own content is the spec deltas it applies.
  - Chat is ephemeral, provenance is not: everything that influenced a decision
    lands in the file's "Променанс" section in the same commit (human quote /
    agent deduction with its reasoning).
  - Frontmatter: name, summary, phase, priority, depends_on, spawned_from
    (phase/priority are advisory free-form fields in v0).
  - Idea and change share ONE section set: Зачем / Контекст / Требования /
    Решения / Променанс / Открытые вопросы (a fresh idea may leave Решения
    empty). A change may append extra sections at the bottom — typically
    Задачи, a stage checklist for big tasks.
  - Findings born inside a change: same contract/artifact → extend the SAME
    change (same Change: trailer, decisions appended to its file); a new
    decision territory → a new idea with spawned_from (commit with
    Change: <parent> + Idea: <child>). Deferred scope is a finding too: a
    piece cut mid-change ("later") becomes an idea with spawned_from in the
    SAME commit that cuts it — silently deferred means lost.
  - Renaming an idea is one commit: git mv + the name: frontmatter fix + all
    referrers (depends_on, spawned_from, prose) — referrers ARE the rename's
    content, not unrelated edits; the one-line file diff keeps rename
    detection intact. No new trailer: the event is derived from the diff.
    Validation (name matches filename, no dangling refs) is caped check's
    territory, not the hook's.
  - A change that alters behavior leaves its scenarios as tests at archive
    time (for this tool: a hook rule without a scenario in tests/hooks/ is a
    process violation); docs/process-only changes are exempt.
  - Specs (capability READMEs, ideas/changes) are written in the project's
    language; the tool's interface texts (this dump, AGENTS.md stub, hook
    messages) are in English.
  - Requirements in enforced spec files carry stable [#<slug>] markers; a test
    covering a requirement repeats the marker in its name or a comment.
    Run caped.sh trace to check the balance before archiving a change.

COMMANDS

  caped.sh              — this reference
  caped.sh init         — wire up a repo (hook shims, registry, ideas/ +
                          changes/). Idempotent: safe to re-run, it only
                          repairs missing pieces and refreshes the report.
  caped.sh check        — frontmatter/section validation (not implemented yet)
  caped.sh trace        — requirement<->test marker balance: defs are [#<slug>]
                          markers in enforced spec files, refs are the same
                          markers in tests/code; fails on uncovered, dangling
                          or duplicated slugs ('[#<slug> no-test]' exempts)
  caped.sh materialise  — derived views into .caped/ (not implemented yet)

A hook error is an instruction: read it and fix the commit accordingly.
EOF
}

case "$cmd" in
  "") rules ;;
  init) exec "$DIR/caped-init.sh" ;;
  hook)
    shift
    [ $# -ge 1 ] || { echo "caped: hook <name> [args...]" >&2; exit 2; }
    hook="$DIR/hooks/$1"; shift
    [ -x "$hook" ] || { echo "caped: no such hook: $hook" >&2; exit 2; }
    exec "$hook" "$@"
    ;;
  check | materialise)
    echo "caped: '$cmd' is not implemented yet (see README, the tool's own-bootstrap section)" >&2
    exit 1
    ;;
  trace) exec "$DIR/caped-trace.sh" ;;
  *)
    echo "caped: unknown command '$cmd' — run scripts/caped.sh with no arguments for the rules" >&2
    exit 2
    ;;
esac
