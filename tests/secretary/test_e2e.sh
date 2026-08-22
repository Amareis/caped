#!/usr/bin/env bash
# tests/secretary/test_e2e.sh — wrapper for the LLM e2e eval of the agent
# instructions. Skips (exit 0) unless CAPED_EVAL=1 and LLM_API_KEY are set —
# the default suite stays free and deterministic.
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 tests/secretary/e2e_instructions.py
