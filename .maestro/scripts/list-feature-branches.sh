#!/usr/bin/env bash
# list-feature-branches.sh — Print <repo>:<branch> lines for a feature.
#
# Usage: list-feature-branches.sh [--feature <feature-id>]
#
# Reads state from .maestro/state/<feature-id>.json via read_state_worktrees
# (defined in bd-helpers.sh). Output format is one line per repo:
#
#   <repo-name>:<branch-name>
#
# Multi-repo features produce N lines; single-repo features produce exactly
# one line. Suitable for piping into a linear-pr runner or similar tooling.
#
# If --feature is omitted, defaults to the most-recently-modified state file
# under .maestro/state/ (matching the convention in worktree-create.sh and
# other maestro scripts).
#
# Exit codes:
#   0 — success, one or more lines written to stdout
#   1 — usage error, missing state file, unknown feature, or empty worktrees map

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Source helpers (worktree-detect.sh for MAESTRO_BASE/MAESTRO_MAIN_REPO,
# bd-helpers.sh for read_state_worktrees).
# ---------------------------------------------------------------------------
# shellcheck source=worktree-detect.sh
source "$SCRIPT_DIR/worktree-detect.sh" 2>/dev/null || true

# shellcheck source=bd-helpers.sh
source "$SCRIPT_DIR/bd-helpers.sh" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Argument parsing.
# ---------------------------------------------------------------------------
FEATURE_FLAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --feature)
      [[ $# -ge 2 ]] || { echo "list-feature-branches: --feature requires a value" >&2; exit 1; }
      FEATURE_FLAG="$2"
      shift 2
      ;;
    --feature=*)
      FEATURE_FLAG="${1#--feature=}"
      shift
      ;;
    --help|-h)
      echo "Usage: list-feature-branches.sh [--feature <feature-id>]"
      echo ""
      echo "Print <repo>:<branch> lines for the given feature. Defaults to"
      echo "the most-recently-modified state file if --feature is omitted."
      exit 0
      ;;
    *)
      echo "list-feature-branches: unknown argument: $1 (try --help)" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Locate the state directory.
# ---------------------------------------------------------------------------
MAIN_REPO="${MAESTRO_MAIN_REPO:-}"
if [[ -z "$MAIN_REPO" ]]; then
  # Fall back to the directory two levels above SCRIPT_DIR (i.e. repo root
  # when .maestro/scripts/ is the conventional location).
  MAIN_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

STATE_DIR="$MAIN_REPO/.maestro/state"

if [[ ! -d "$STATE_DIR" ]]; then
  echo "list-feature-branches: state directory not found: $STATE_DIR" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Resolve the state file.
# ---------------------------------------------------------------------------
if [[ -n "$FEATURE_FLAG" ]]; then
  STATE_FILE="$STATE_DIR/${FEATURE_FLAG}.json"
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "list-feature-branches: state file not found for feature '${FEATURE_FLAG}': $STATE_FILE" >&2
    exit 1
  fi
else
  # Default: most-recently-modified .json file in STATE_DIR.
  # `ls -t` sorts by modification time (newest first); head picks the first.
  STATE_FILE="$(ls -t "$STATE_DIR"/*.json 2>/dev/null | head -1 || true)"
  if [[ -z "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
    echo "list-feature-branches: no state files found in $STATE_DIR" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Read the worktrees map via the canonical reader.
# ---------------------------------------------------------------------------
declare -f read_state_worktrees >/dev/null 2>&1 || { echo "list-feature-branches: bd-helpers.sh not loaded (read_state_worktrees missing)" >&2; exit 1; }
WORKTREES_JSON="$(read_state_worktrees "$STATE_FILE" 2>/dev/null)"

if [[ "$WORKTREES_JSON" == "{}" || -z "$WORKTREES_JSON" ]]; then
  echo "list-feature-branches: no worktrees found in state file: $STATE_FILE" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Validate that jq is available (read_state_worktrees would have exited 2
# already, but be explicit for the output step below).
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "list-feature-branches: jq not found in PATH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Emit one "<repo>:<branch>" line per worktrees entry.
# ---------------------------------------------------------------------------
printf '%s' "$WORKTREES_JSON" | jq -r 'to_entries[] | select(.value.branch != null and .value.branch != "") | "\(.key):\(.value.branch)"'
