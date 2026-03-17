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

# Extract stacks list from compile_gate block
get_stacks_list() {
  awk '
    BEGIN { in_compile_gate=0; in_stacks=0 }
    /^compile_gate:[[:space:]]*$/ { in_compile_gate=1; next }
    in_compile_gate && /^[^[:space:]]/ { in_compile_gate=0; in_stacks=0 }
    in_compile_gate && /^[[:space:]]+stacks:[[:space:]]*$/ { in_stacks=1; next }
    in_stacks && /^[[:space:]]+-[[:space:]]+/ {
      line=$0
      sub(/^[[:space:]]+-[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      print line
      next
    }
    in_stacks && /^[[:space:]]+[^-]/ { in_stacks=0 }
  ' "$CONFIG"
}

# Try stacks list first
STACKS_LIST=$(get_stacks_list)

if [[ -n "$STACKS_LIST" ]]; then
  # Multi-stack mode
  overall_pass=true
  while IFS= read -r stack_name; do
    [[ -z "$stack_name" ]] && continue
    CMD=$(get_compile_gate_value "$stack_name")
    if [[ -z "$CMD" ]]; then
      echo "WARN: No command for stack: $stack_name" >&2
      continue
    fi
    echo "=== Running stack: $stack_name ===" >&2
    if eval "$CMD" 2>&1; then
      echo "=== Stack: $stack_name PASSED ===" >&2
    else
      echo "=== Stack: $stack_name FAILED ===" >&2
      overall_pass=false
    fi
  done <<< "$STACKS_LIST"

  if [[ "$overall_pass" == "true" ]]; then
    echo "=== All stacks PASSED ===" >&2
    exit 0
  else
    echo "=== One or more stacks FAILED ===" >&2
    exit 1
  fi
else
  # Single-stack fallback (existing behavior)
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
fi
