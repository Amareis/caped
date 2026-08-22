# AGENTS.md

Before doing anything in this repository, run `scripts/caped.sh` with no arguments —
it prints the full working rules (idea/change lifecycle, commit trailers, capability
registry). Follow that output; everything it states is enforced by the `commit-msg` hook.

Layout: hooks and scripts live in `scripts/`, the project spec is the root `README.md`
(Russian), the registry is `caped.registry`. No code conventions yet — they will arrive
together with the tool's own code.
