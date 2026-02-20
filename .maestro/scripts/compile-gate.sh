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

# Extract value from compile_gate block (avoid yq dependency)
get_compile_gate_value() {
  local key="$1"
  awk -v key="$key" '
    BEGIN { in_compile_gate=0 }
    /^compile_gate:[[:space:]]*$/ { in_compile_gate=1; next }
    in_compile_gate && /^[^[:space:]]/ { in_compile_gate=0 }
    in_compile_gate && $0 ~ "^[[:space:]]+" key ":[[:space:]]*" {
      line=$0
      sub("^[[:space:]]+" key ":[[:space:]]*", "", line)
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line ~ /^".*"$/) {
        sub(/^"/, "", line)
        sub(/"$/, "", line)
      }
      print line
      exit
    }
  ' "$CONFIG"
}

STACK=$(get_compile_gate_value "stack" | tr -d "'")

if [[ -z "$STACK" ]]; then
  echo "FAIL: No stack defined in config.yaml" >&2
  exit 1
fi

# Get command for this stack
CMD=$(get_compile_gate_value "$STACK")

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
