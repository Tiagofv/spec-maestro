#!/usr/bin/env bash
#
# worktree-cleanup.sh — Safely remove a git worktree and optionally its branch
#
# Usage: worktree-cleanup.sh <worktree-path> [--delete-branch]
#
# Output JSON: {"removed":true,"branch_deleted":false}
#
# Exit 1 on error (uncommitted changes, path doesn't exist, not a worktree)

set -euo pipefail

DELETE_BRANCH=false
WORKTREE_PATH=""

for arg in "$@"; do
  case "$arg" in
    --delete-branch)
      DELETE_BRANCH=true
      ;;
    --help|-h)
      echo "Usage: worktree-cleanup.sh <worktree-path> [--delete-branch]"
      echo "  --delete-branch  Also delete the branch if it is merged"
      exit 0
      ;;
    -*)
      echo "Unknown flag: $arg" >&2
      exit 1
      ;;
    *)
      WORKTREE_PATH="$arg"
      ;;
  esac
done

if [[ -z "$WORKTREE_PATH" ]]; then
  echo "Usage: worktree-cleanup.sh <worktree-path> [--delete-branch]" >&2
  exit 1
fi

error() {
  echo "$1" >&2
  exit 1
}

check_inside_git_repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error "Not inside a git repository"
  fi
}

get_worktree_branch() {
  local wt_path="$1"
  local branch
  branch=$(git worktree list --porcelain 2>/dev/null | awk -v path="$wt_path" '
    /^worktree/ { in_this_worktree = 0 }
    $1 == "worktree" && $2 == path { in_this_worktree = 1 }
    /^branch/ && in_this_worktree { print $2; exit }
  ')
  
  if [[ "$branch" == refs/* ]]; then
    echo "${branch#refs/heads/}"
  else
    echo "$branch"
  fi
}

is_worktree() {
  local wt_path="$1"
  git worktree list --porcelain 2>/dev/null | grep -q "^worktree $wt_path$"
}

check_no_uncommitted_changes() {
  local wt_path="$1"
  
  if [[ ! -d "$wt_path" ]]; then
    return 0
  fi
  
  if [[ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]]; then
    error "Worktree has uncommitted changes. Commit or stash them first."
  fi
}

check_branch_merged() {
  local branch="$1"
  local current_branch
  
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  
  if git branch --merged "$current_branch" 2>/dev/null | grep -qF "$branch"; then
    return 0
  fi
  
  return 1
}

delete_branch() {
  local branch="$1"
  
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    if check_branch_merged "$branch"; then
      git branch -d "$branch" 2>/dev/null || error "Failed to delete branch $branch"
      return 0
    else
      echo "Branch $branch is not merged. Skipping deletion." >&2
      return 1
    fi
  fi
  
  return 1
}

check_inside_git_repo

ROOT_DIR="$(git rev-parse --show-toplevel)"
if [[ "$WORKTREE_PATH" != /* ]]; then
  WORKTREE_PATH="$ROOT_DIR/$WORKTREE_PATH"
fi

if [[ ! -d "$WORKTREE_PATH" ]]; then
  if is_worktree "$WORKTREE_PATH"; then
    echo "Worktree already removed. Running prune..." >&2
    git worktree prune
    cat <<EOF
{"removed":true,"branch_deleted":false}
EOF
    exit 0
  fi
  error "Path does not exist: $WORKTREE_PATH"
fi

if ! is_worktree "$WORKTREE_PATH"; then
  error "Path is not a worktree: $WORKTREE_PATH"
fi

check_no_uncommitted_changes "$WORKTREE_PATH"

BRANCH=""
BRANCH_DELETED=false

if [[ "$DELETE_BRANCH" == true ]]; then
  BRANCH=$(get_worktree_branch "$WORKTREE_PATH")
fi

if git worktree remove "$WORKTREE_PATH" 2>/dev/null; then
  REMOVED=true
else
  error "Failed to remove worktree at $WORKTREE_PATH"
fi

git worktree prune

if [[ "$DELETE_BRANCH" == true ]] && [[ -n "$BRANCH" ]]; then
  if delete_branch "$BRANCH"; then
    BRANCH_DELETED=true
  fi
fi

cat <<EOF
{"removed":$REMOVED,"branch_deleted":$BRANCH_DELETED}
EOF
