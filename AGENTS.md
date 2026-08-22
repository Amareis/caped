# AGENTS.md

Before doing anything in this repository, run `scripts/caped.sh` with no arguments —
it prints the full working rules (idea/change lifecycle, commit trailers, capability
registry). Follow that output; everything it states is enforced by the `commit-msg` hook.

Layout: hooks and scripts live in `scripts/`, the project spec is the root `README.md`
(Russian), the registry is `caped.registry`. No code conventions yet — they will arrive
together with the tool's own code.

Checks: run `just test` (or `bash scripts/run-tests.sh` when `just` is not installed) —
caped trace plus every `tests/*/test_*.sh` suite. Run it before archiving a change; a red
suite blocks the archive. These are the tool's own tests: there is deliberately no
`caped test` command, an adopting project keeps its own runner.
