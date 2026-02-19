#!/usr/bin/env bash
# Run compile gate based on stack from config.yaml
# Usage: compile-gate.sh [worktree-path]
# Exit 0 = pass, exit 1 = fail

set -euo pipefail

WORKTREE="${1:-.}"
CONFIG=".maestro/config.yaml"

echo "=== Compile Gate: $WORKTREE ===" >&2

cd "$WORKTREE" || { echo "FAIL: Cannot cd to $WORKTREE" >&2; exit 1; }

# Parse stack from config
if [[ ! -f "$CONFIG" ]]; then
  echo "FAIL: Config not found at $CONFIG" >&2
  exit 1
fi

# Extract stack value (simple grep, avoid yq dependency)
STACK=$(grep -E "^\s+stack:" "$CONFIG" | head -1 | sed 's/.*stack:\s*//' | tr -d '"' | tr -d "'")

if [[ -z "$STACK" ]]; then
  echo "FAIL: No stack defined in config.yaml" >&2
  exit 1
fi

# Get command for this stack
CMD=$(grep -A1 "^compile_gate:" "$CONFIG" | grep -E "^\s+$STACK:" | sed "s/.*$STACK:\s*//" | tr -d '"')

if [[ -z "$CMD" ]]; then
  echo "FAIL: No compile_gate command for stack: $STACK" >&2
  exit 1
fi

echo "Running: $CMD" >&2
if eval "$CMD" 2>&1; then
  echo "=== Compile gate PASSED ===" >&2
  exit 0
else
  echo "=== Compile gate FAILED ===" >&2
  echo "Fix the errors above and re-run." >&2
  exit 1
fi
