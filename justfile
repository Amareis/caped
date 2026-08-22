# caped's own checks — these are the tool's tests, not an adopting project's.
# caped itself stays unaware of them (no `caped test` on purpose).

# Run all repo checks: caped trace + every tests/*/test_*.sh suite.
# Run before archiving a change; a red suite blocks the archive.
test:
    bash scripts/run-tests.sh
