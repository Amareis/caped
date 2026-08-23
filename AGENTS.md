# AGENTS.md

Before doing anything in this repository, run `caped` with no arguments (the wrapper
in this repo's root; on the maintainer's machine also on PATH via ~/.local/bin/caped) —
it prints the full working rules (idea/change lifecycle, commit trailers, capability
registry). Follow that output; everything it states is enforced by the `commit-msg` hook.

Layout: hooks and scripts live in `scripts/`, the project spec is the root `README.md`
(Russian), the registry is `caped.registry`. No code conventions yet — they will arrive
together with the tool's own code.

Checks: run `just test` (or `bash scripts/run-tests.sh` when `just` is not installed) —
caped trace plus every `tests/*/test_*.sh` suite. Run it before archiving a change; a red
suite blocks the archive. These are the tool's own tests: there is deliberately no
`caped test` command, an adopting project keeps its own runner.

Developing the tool itself (not relevant to adopting repos): the tool's interface texts —
the rules dump, this stub, hook messages, command output — are written in English; specs
(root README, ideas/changes) are in the project's language (Russian here).
The rules dump is project-neutral by design ([#dump-neutrality] in the root README): only
portable working rules and the tool's identity belong there — this repo's history,
rationale and roadmap stay in the README. When reviewing the dump for gaps, project
narrative missing from it is the neutrality boundary, not a hole.
