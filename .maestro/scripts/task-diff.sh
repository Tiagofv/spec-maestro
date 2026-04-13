#!/usr/bin/env bash
# Extract git diff for a specific beads task ID.
#
# Finds all commits whose message contains [bd:{task_id}] and produces
# a combined diff spanning the earliest to latest of those commits.
#
# Usage:
#   task-diff.sh <task-id> [--summary] [--worktree <path>]
#
# Flags:
#   --summary          Output one-line stats only (files_changed, insertions, deletions)
#   --worktree <path>  Run all git commands with `git -C <path>`
#
# Exit codes:
#   0  Success
#   1  No matching commits found
#   2  Invalid arguments (missing task ID, bad flags)

set -euo pipefail

# --- Argument parsing ---

TASK_ID=""
SUMMARY=false
WORKTREE_PATH=""

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --summary)
        SUMMARY=true
        shift
        ;;
      --worktree)
        if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
          echo "error: --worktree requires a path argument" >&2
          exit 2
        fi
        WORKTREE_PATH="$2"
        shift 2
        ;;
      --*)
        echo "error: unknown flag '$1'" >&2
        exit 2
        ;;
      *)
        if [[ -z "$TASK_ID" ]]; then
          TASK_ID="$1"
        else
          echo "error: unexpected argument '$1' (task ID already set to '$TASK_ID')" >&2
          exit 2
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$TASK_ID" ]]; then
    echo "error: task ID is required" >&2
    echo "usage: task-diff.sh <task-id> [--summary] [--worktree <path>]" >&2
    exit 2
  fi
}

# --- Git helpers ---

# Build the base git command, optionally with -C <path>
git_cmd() {
  if [[ -n "$WORKTREE_PATH" ]]; then
    git -C "$WORKTREE_PATH" "$@"
  else
    git "$@"
  fi
}

# Find all commit hashes matching [bd:{task_id}] in their message
find_commits() {
  local task_id="$1"
  git_cmd log --all --grep="\[bd:${task_id}\]" --format=%H
}

# --- Main logic ---

main() {
  parse_args "$@"

  # Validate worktree path if provided
  if [[ -n "$WORKTREE_PATH" && ! -d "$WORKTREE_PATH" ]]; then
    echo "error: worktree path does not exist: $WORKTREE_PATH" >&2
    exit 2
  fi

  # Find matching commits
  local commits
  commits=$(find_commits "$TASK_ID")

  if [[ -z "$commits" ]]; then
    echo "No commits found for task ${TASK_ID}. This task may have been completed before commit attribution was enabled." >&2
    exit 1
  fi

  # Get the earliest and latest commits (chronological order from git log is newest-first)
  local latest oldest
  latest=$(echo "$commits" | head -n 1)
  oldest=$(echo "$commits" | tail -n 1)

  # Produce diff from just before the oldest commit to the latest commit
  # Using oldest~1 as the base so the oldest commit's changes are included
  local base
  base=$(git_cmd rev-parse "${oldest}~1" 2>/dev/null) || base=$(git_cmd hash-object -t tree /dev/null)

  if [[ "$SUMMARY" == true ]]; then
    # --stat output parsed into one-line summary
    local stat_output
    stat_output=$(git_cmd diff --stat "$base" "$latest")

    # The last line of --stat is like: " 3 files changed, 10 insertions(+), 2 deletions(-)"
    local summary_line
    summary_line=$(echo "$stat_output" | tail -n 1)

    local files_changed=0
    local insertions=0
    local deletions=0

    # Extract numbers from the summary line
    if [[ "$summary_line" =~ ([0-9]+)\ file ]]; then
      files_changed="${BASH_REMATCH[1]}"
    fi
    if [[ "$summary_line" =~ ([0-9]+)\ insertion ]]; then
      insertions="${BASH_REMATCH[1]}"
    fi
    if [[ "$summary_line" =~ ([0-9]+)\ deletion ]]; then
      deletions="${BASH_REMATCH[1]}"
    fi

    echo "files_changed=$files_changed insertions=$insertions deletions=$deletions"
  else
    git_cmd diff "$base" "$latest"
  fi
}

main "$@"
