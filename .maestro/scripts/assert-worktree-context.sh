#!/usr/bin/env bash
# Assert current execution context matches expected maestro worktree path.
#
# Usage: assert-worktree-context.sh <expected-worktree-path>
# Exit 0 when current git top-level equals expected path, else exit 1.

set -euo pipefail

EXPECTED_PATH="${1:-}"

if [[ -z "$EXPECTED_PATH" ]]; then
  echo "Usage: assert-worktree-context.sh <expected-worktree-path>" >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a git repository" >&2
  exit 1
fi

ROOT_DIR="$(git rev-parse --show-toplevel)"

if [[ "$EXPECTED_PATH" != /* ]]; then
  EXPECTED_PATH="$ROOT_DIR/$EXPECTED_PATH"
fi

if [[ -d "$EXPECTED_PATH" ]]; then
  EXPECTED_PATH="$(cd "$EXPECTED_PATH" && pwd)"
else
  EXPECTED_PATH="$(cd "$(dirname "$EXPECTED_PATH")" && pwd)/$(basename "$EXPECTED_PATH")"
fi
CURRENT_TOPLEVEL="$ROOT_DIR"

if [[ "$CURRENT_TOPLEVEL" != "$EXPECTED_PATH" ]]; then
  echo "Worktree invariant violation." >&2
  echo "Expected worktree: $EXPECTED_PATH" >&2
  echo "Current repo root: $CURRENT_TOPLEVEL" >&2
  echo "Run this command from the feature worktree." >&2
  exit 1
fi

echo "{\"ok\":true,\"worktree\":\"$EXPECTED_PATH\"}"
