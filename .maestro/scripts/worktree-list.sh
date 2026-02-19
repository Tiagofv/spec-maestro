#!/usr/bin/env bash
#
# worktree-list.sh — List all active worktrees with their associated features
#
# Usage: worktree-list.sh [--json]
#
# Default output: human-readable table
# --json output: JSON array of worktree objects

set -euo pipefail

JSON_OUTPUT=false

if [[ "${1:-}" == "--json" ]]; then
  JSON_OUTPUT=true
fi

jq_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

STATE_DIR=".maestro/state"
MAIN_PATH="$(cd "$(git rev-parse --show-toplevel)" && pwd)"

declare -a WORKTREES=()

while IFS= read -r line; do
  if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
    WORKTREES+=("${BASH_REMATCH[1]}")
  fi
done < <(git worktree list --porcelain)

declare -a RESULTS=()

for WT_PATH in "${WORKTREES[@]}"; do
  if [[ "$WT_PATH" == "$MAIN_PATH" ]]; then
    continue
  fi

  WT_BRANCH=""
  FEATURE_ID=""
  STAGE=""

  BRANCH_LINE=$(git worktree list --porcelain 2>/dev/null | awk -v path="$WT_PATH" '
    /^worktree/ { in_this_worktree = 0 }
    $1 == "worktree" && $2 == path { in_this_worktree = 1 }
    /^branch/ && in_this_worktree { print; exit }
  ')

  if [[ "$BRANCH_LINE" =~ ^branch\ refs/heads/(.+)$ ]]; then
    WT_BRANCH="${BASH_REMATCH[1]}"
  fi

  if [[ -d "$STATE_DIR" ]]; then
    for state_file in "$STATE_DIR"/*.json; do
      [[ -e "$state_file" ]] || continue

      MATCHED=false

      if grep -q '"worktree_path"' "$state_file" 2>/dev/null; then
        WT_PATH_IN_STATE=$(grep -o '"worktree_path"[[:space:]]*:[[:space:]]*"[^"]*"' "$state_file" | sed 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
        # Resolve state path to absolute for comparison
        if [[ "$WT_PATH_IN_STATE" != /* ]]; then
          ABS_STATE_PATH="$(cd "$MAIN_PATH/$WT_PATH_IN_STATE" 2>/dev/null && pwd)" || ABS_STATE_PATH=""
        else
          ABS_STATE_PATH="$WT_PATH_IN_STATE"
        fi
        if [[ "$ABS_STATE_PATH" == "$WT_PATH" ]]; then
          MATCHED=true
        fi
      fi

      if [[ "$MATCHED" == false ]] && grep -q '"worktree_branch"' "$state_file" 2>/dev/null; then
        WT_BRANCH_IN_STATE=$(grep -o '"worktree_branch"[[:space:]]*:[[:space:]]*"[^"]*"' "$state_file" | sed 's/.*"worktree_branch"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
        if [[ "$WT_BRANCH_IN_STATE" == "$WT_BRANCH" ]]; then
          MATCHED=true
        fi
      fi

      if [[ "$MATCHED" == false ]] && grep -q '"branch"' "$state_file" 2>/dev/null; then
        BRANCH_IN_STATE=$(grep -o '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' "$state_file" | sed 's/.*"branch"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
        if [[ "$BRANCH_IN_STATE" == "$WT_BRANCH" ]]; then
          MATCHED=true
        fi
      fi

      if [[ "$MATCHED" == true ]]; then
        FEATURE_ID=$(grep -o '"feature_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$state_file" | sed 's/.*"feature_id"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
        
        if grep -q '"stage"' "$state_file" 2>/dev/null; then
          STAGE=$(grep -o '"stage"[[:space:]]*:[[:space:]]*"[^"]*"' "$state_file" | sed 's/.*"stage"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
        fi
        break
      fi
    done
  fi

  if [[ -n "$WT_BRANCH" || -n "$FEATURE_ID" ]]; then
    if [[ "$JSON_OUTPUT" == true ]]; then
      RESULTS+=("{\"path\":\"$(jq_escape "$WT_PATH")\",\"branch\":\"$(jq_escape "${WT_BRANCH:-}")\",\"feature_id\":\"$(jq_escape "${FEATURE_ID:-}")\",\"stage\":\"$(jq_escape "${STAGE:-}")\"}")
    else
      RESULTS+=("$WT_PATH|$WT_BRANCH|$FEATURE_ID|$STAGE")
    fi
  fi
done

if [[ "$JSON_OUTPUT" == true ]]; then
  if [[ ${#RESULTS[@]} -eq 0 ]]; then
    echo "[]"
  else
    printf "["
    printf "%s" "${RESULTS[0]}"
    for ((i=1; i<${#RESULTS[@]}; i++)); do
      printf ",%s" "${RESULTS[i]}"
    done
    echo "]"
  fi
else
  if [[ ${#RESULTS[@]} -eq 0 ]]; then
    echo "No feature worktrees found."
    exit 0
  fi

  printf "%-45s %-35s %-45s %s\n" "PATH" "BRANCH" "FEATURE_ID" "STAGE"
  printf "%-45s %-35s %-45s %s\n" "----" "------" "----------" "-----"

  for result in "${RESULTS[@]}"; do
    IFS='|' read -r path branch feature_id stage <<< "$result"
    printf "%-45s %-35s %-45s %s\n" "$path" "$branch" "$feature_id" "$stage"
  done
fi
