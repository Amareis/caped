#!/usr/bin/env bash
# caped — v0 dispatcher. Bare invocation prints the full working rules
# (this IS the self-documentation: AGENTS.md and the hook both point here).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cmd="${1:-}"

rules() {
  cat <<'EOF'
caped — tracker and specs in git. The working rules of this repository.

ABOUT [#dump-abstract]

  caped keeps the project's tracker (idea -> change -> archive) and its
  capability specs inside git itself. Specs live as capability READMEs next
  to the code; every decision carries provenance (human quotes vs agent
  deductions); the lifecycle is reconstructed from commit trailers, so no
  status file can drift. A commit-msg hook enforces the discipline. The
  division of labor: the human decides WHAT, the agent does the secretary
  work — spawns ideas, records rationale, keeps the trailers.

  The name: caped = "capability-ed". The tool assumes capability-organized
  code (feature-sliced, FSD-like): every capability owns its files and its
  README; the registry maps everything else by path prefixes.

LIFECYCLE (each event is a separate atomic commit)

  1. Idea:      new file ideas/<name>.md, commit with trailer  Idea: <name>
                [#idea-birth]
  2. In work:   clean git mv ideas/<name>.md changes/<name>.md [#take-into-work] (no content
                edits — rename detection must stitch the file's history;
                the mv keeps the filename), trailer Change: <name>. A
                change is born ONLY this way — adding changes/<name>.md
                directly is rejected (sole exception: the 'Change: init'
                seed commit).
  3. Work:      every commit of the change carries Change: <name> [#work-trailer]; editing
                changes/<name>.md without it is rejected by the hook
  4. Archive:   the final commit applies the deltas to capability READMEs [#archival]
                (those deltas ARE its content) and deletes changes/<name>.md,
                trailers Change: <name> + Archives: <name>. Finishing may be a
                single commit (deltas + deletion together) — splitting the
                last work commit and the deletion is valid but not required.

COMMIT TRAILERS (git trailers, enforced by the commit-msg hook)

  Behavior: contract|internal|wip  — change class [#behavior-trailer], required for ANY commit
                                     touching enforced capabilities, the
                                     archive commit included (a subject
                                     starting with "wip" counts as wip;
                                     merge commits are exempt). A contract
                                     hotfix = change file + code + spec
                                     delta in ONE commit.
  Spec: <path>                     — on contract [#spec-trailer]: the path of the spec whose
                                     contract changes. Either the trailer or
                                     the spec file changed in the same commit
                                     satisfies the hook — no need for both.
  Idea: <name>                     — birth of ideas/<name>.md
  Change: <name>                   — the commit belongs to changes/<name>.md.
                                     REQUIRED on contract commits (a contract
                                     without a change doc is an undiscussed
                                     rule), optional on internal/wip. Must
                                     point at an existing changes/<name>.md —
                                     except 'Change: init' (the seed) and the
                                     archival commit itself.
  Archives: <name>                 — archival: the change file is deleted in
                                     this very commit

CAPABILITY REGISTRY (caped.registry, TAB-separated: name, prefix, state, spec file)

  prefix    — a path prefix; a commit "touches" the cap when a staged file
              starts with it. READ caped.registry to know which paths are
              enforced — or just commit and let the hook tell you.
              Then survey the territory BEFORE any tracker action
              (spawning, working, reviewing): run caped.sh render plan —
              the registry says which paths are enforced, the plan says
              what is already in work, stalled, or depended on; the hook
              guards format, not territory [#render-first]. The history
              and coverage views are on demand.
  legacy    — coverage declared, hook does not check (migration path)
  declared  — spec file exists, enforcement not yet enabled
  enforced  — hook requires Behavior/Spec
  The root README.md is the root capability — the project as one big
  feature; cross-cutting contract changes carry Spec: README.md.
  Rollout: enforcement starts advisory; flipping to blocking is a
  separate deliberate act after calibration.
  Paths outside the registry are ignored by design [#free-paths].
  Overlapping prefixes: longest prefix wins [#longest-prefix].
  A cap is a decision territory, not necessarily code — business caps
  (marketing, acquisition) point their prefixes at docs [#caps-territory].
  Birth/split/merge of a cap is a contract commit touching caped.registry
  [#registry-mutation]. A cap's spec README lives at
  src/features/<cap>/README.md or caps/<cap>/README.md; the agent writes it
  at change time from the human's words, the human approves it by diff —
  keep it small enough to eyeball [#cap-readme-authorship].

ADHOC (fileless) DECISIONS

  A small, already-discussed, 1–2-commit decision may live entirely in its
  commits — no ideas/changes file: Behavior: contract|internal (+ Spec: on
  contract) with the rationale in the commit BODY [#adhoc-body] (enforced: a fileless
  contract requires a non-empty body — subject and trailers don't count).
  A file is required when the work is > 2 commits, opens a new decision
  territory, is disputed or undiscussed, spans several caps, or carries open
  questions. Drift review watches the share of fileless contract commits.

SPAWNING IDEAS [#idea-autonomy] (the agent decides WHERE a decision lives — don't wait to be told)

  The human decides WHAT; placing the decision correctly is your job:
  - Same contract territory as the current change → extend the change itself:
    same Change: trailer, the decision appended to its "Decisions"/"Provenance".
  - New decision territory, open questions, a disputed call, >2 commits or
    several caps → a new idea file. Born inside a change → spawned_from plus
    a commit with Change: <parent> + Idea: <child>.
  - Scope cut from the current change "for later" → an idea with
    spawned_from in the SAME commit that cuts it — silently deferred = lost.
  - Small, already-discussed, 1–2-commit decision → no file at all (ADHOC).
  - Naming: ideas are verbs (work to do), caps are nouns (a decision
    territory); an idea becomes a cap when a standing territory appears.
  - Every idea carries a "Rejected alternatives" list — rejected
    alternatives with grounds, so the same circle is never walked twice.
  - Open questions promote: a small open question is answered right in the
    change and dies with it; a question that became work is promoted to an
    idea (spawned_from records the origin) [#question-promotion].

DISCIPLINE

  - One semantic event = one commit. Never mix mv/archival with UNRELATED
    edits; the archive commit's own content is the spec deltas it applies.
  - Squashing a change is legitimate — but then the file's Provenance is the
    only remaining step history [#squash-legit]. Scratch materials of a big
    change sit beside the files and die with its deletion; parallel changes
    on one branch are told apart by the Change: trailer [#change-scratch].
  - Chat is ephemeral, provenance is not: everything that influenced a decision
    lands in the file's "Provenance" section in the same commit (human quote /
    agent deduction with its reasoning).
  - Frontmatter: name, summary, phase, priority, depends_on, spawned_from
    (phase/priority are advisory free-form fields in v0). depends_on is a
    gate: an idea cannot go into work while its dependency is unarchived.
  - Idea and change share ONE section set: "Why" / "Context" /
    "Requirements" / "Decisions" / "Rejected alternatives" / "Provenance" /
    "Open questions" (a fresh idea may leave "Decisions" and "Rejected
    alternatives" empty). Section
    names are fixed format strings — use them verbatim, never translated.
    A change may append extra sections at the bottom — typically "Tasks",
    a stage checklist for big tasks.
  - Findings born inside a change: same contract/artifact → extend the SAME
    change (same Change: trailer, decisions appended to its file); a new
    decision territory → a new idea with spawned_from (commit with
    Change: <parent> + Idea: <child>). Deferred scope is a finding too: a
    piece cut mid-change ("later") becomes an idea with spawned_from in the
    SAME commit that cuts it — silently deferred means lost.
  - A finding addresses a standing contract in ANOTHER territory (another
    cap / change / idea) → hand it off immediately: edit the target's
    "Requirements" section on its file and record "handed off → <target>"
    in the source's provenance; discussed but not applied = silently
    deferred = lost; if the target must land first, add depends_on
    [#territory-handoff].
  - Renaming an idea is one commit [#idea-rename]: git mv + the name: frontmatter fix + all
    referrers (depends_on, spawned_from, prose) — referrers ARE the rename's
    content, not unrelated edits; only the name: line changes, so rename
    detection stays intact. No new trailer: the event is derived from the diff.
    Validation (name matches filename, no dangling refs) is caped check's
    territory, not the hook's.
  - A change that alters behavior leaves its scenarios as tests at archive
    time (for this tool: a hook rule without a scenario in tests/hooks/ is a
    process violation); docs/process-only changes are exempt.
  - Specs (capability READMEs, ideas/changes) are written in the project's
    own language — match the language of the existing files
    [#interface-language].
  - Requirements in enforced spec files live ONLY as bullets inside the
    '## Requirements' section (fixed literal, never translated), marker
    FIRST: '- [#slug[ attrs]] Statement...' [#req-form]. A bullet without a
    marker inside the section — or a marker bullet outside it — is a caped
    check error. The bullet stays self-sufficient (statement + rationale,
    not a bare slug); ### subgroups and intro prose inside the section are
    allowed. The bullet's FIRST LINE is a self-contained gist: the reqs
    index renders exactly it. In ideas/changes the same section holds
    bullets only (numbered lists are a caped check error), the slug is
    optional (idea requirements are ephemeral) but leads the bullet when
    present; norm references from prose use {#slug}, backticked mentions
    are not markers. A test covering a
    requirement repeats the marker in its name or a comment [#trace-refs];
    references between requirements INSIDE a spec use {#slug} (braces) —
    neither a definition nor a covering quote [#trace-defs]. Marker
    attributes: 'no-test' exempts from coverage [#trace-no-test], 'dump'
    marks the rule agent-facing — such rules MUST appear in this dump
    [#trace-dump-attr], trace fails on 'undumped' otherwise
    [#trace-undumped]. Run caped.sh trace before archiving a change — a red
    trace blocks the archive [#trace-checker].
  - The hook checks facts, not substance: the rename fact (not its 100%
    similarity), that Change: resolves to an existing change, that an adhoc
    contract body is non-empty (not what it says). Content validation is
    caped check's territory; the rest is conscience and drift review.

COMMANDS

  caped.sh              — this reference [#rules-in-cli]
  caped.sh init         — wire up a repo (hook shims, registry, ideas/ +
                          changes/). Idempotent [#init-idempotent]: safe to re-run,
                          it only repairs missing pieces and refreshes the report.
  caped.sh check        — structural validation of ideas/ and changes/ [#check-structure]
                          (frontmatter,
                          required sections, spawned_from resolves to a live or
                          archived entity) [#check-spawned-from]; plus the
                          requirement-form check on enforced specs: a '## Requirements'
                          section must exist, every bullet in it starts with a
                          [#<slug>] marker, marker bullets outside it are rejected
                          [#req-form]. Errors fail with a fix instruction.
  caped.sh trace        — requirement<->test marker balance: defs are
                          slug-first bullets ('- [#<slug>] ...') in enforced
                          spec files (a marker quoted in prose is NOT a def),
                          refs are the same markers in all tracked files
                          except spec files; fails on uncovered, dangling
                          or duplicated slugs ('[#<slug> no-test]' exempts)
  caped.sh render [view]— derived views (plan, history, coverage, reqs)
                          printed to
                          stdout — read-only by default [#render-stdout]; --json
                          prints the machine-readable form of a view (same
                          generator as the text) [#render-json]. --write
                          materialises BOTH forms into .caped/ (gitignored)
                          [#render-write], --clean removes it [#render-clean].
                          The plan marks entities with unarchived depends_on as
                          BLOCKED [#render-blocked]; history is rebuilt from git
                          trailers [#render-history], reads the live status of
                          unarchived entities from the filesystem ('?' on drift)
                          and also lists fileless adhoc contract commits
                          (Behavior: contract without Change:) with a ~140-char
                          body excerpt under each subject
                          [#render-history-adhoc]; reqs is the requirement
                          index — slug + first-line gist from enforced specs,
                          bullet gists from ideas/changes, grouped by source
                          file [#render-reqs]. Text views are laid out for the
                          eye (name line, summary, dimmed metadata); ANSI only
                          on a TTY (NO_COLOR respected) — piped output is
                          plain, agents read the same text [#render-text-layout]

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
  check)
    shift
    exec python3 "$DIR/caped-check.py" "$@"
    ;;
  render)
    shift
    exec python3 "$DIR/caped-render.py" "$@"
    ;;
  trace) exec "$DIR/caped-trace.sh" ;;
  *)
    echo "caped: unknown command '$cmd' — run scripts/caped.sh with no arguments for the rules" >&2
    exit 2
    ;;
esac
