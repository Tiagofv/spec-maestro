#!/usr/bin/env bash
#
# worktree-create.sh — Create a git worktree for a feature
#
# Usage: worktree-create.sh <worktree-name> <branch-name> [base-branch]
#   base-branch defaults to 'main' (from config.yaml project.base_branch)
#
# Output JSON: {"worktree_path":".worktrees/kanban-board","branch":"feat/kanban-board","created":true}
#
# Exit 1 on error with message to stderr

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAESTRO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$MAESTRO_DIR/config.yaml"

WORKTREE_NAME="${1:?Usage: worktree-create.sh <worktree-name> <branch-name> [base-branch]}"
BRANCH_NAME="${2:?Usage: worktree-create.sh <worktree-name> <branch-name> [base-branch]}"
BASE_BRANCH="${3:-main}"

if [[ "$#" -lt 3 ]] && [[ -f "$CONFIG_FILE" ]]; then
  CONFIG_BASE_BRANCH=$(grep -E '^\s+base_branch:' "$CONFIG_FILE" | awk '{print $2}' || true)
  if [[ -n "$CONFIG_BASE_BRANCH" ]]; then
    BASE_BRANCH="$CONFIG_BASE_BRANCH"
  fi
fi

WORKTREES_DIR=".worktrees"
WORKTREE_PATH="${WORKTREES_DIR}/${WORKTREE_NAME}"

error() {
  echo "$1" >&2
  exit 1
}

check_git_version() {
  local git_version
  git_version=$(git --version | sed 's/git version //' | cut -d. -f1-2)
  local major minor
  major=$(echo "$git_version" | cut -d. -f1)
  minor=$(echo "$git_version" | cut -d. -f2)
  
  if [[ "$major" -lt 2 ]] || { [[ "$major" -eq 2 ]] && [[ "$minor" -lt 5 ]]; }; then
    error "Git version must be >= 2.5. Current version: $git_version"
  fi
}

check_inside_git_repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error "Not inside a git repository"
  fi
}

ensure_worktrees_dir() {
  mkdir -p "$WORKTREES_DIR"
}

ensure_worktrees_in_gitignore() {
  if [[ -f ".gitignore" ]]; then
    if ! grep -qE '^(\.worktrees/|\.worktrees$)' ".gitignore" 2>/dev/null; then
      echo ".worktrees/" >> ".gitignore"
    fi
  else
    echo ".worktrees/" > ".gitignore"
  fi
}

check_worktree_not_exists() {
  if [[ -d "$WORKTREE_PATH" ]]; then
    error "Worktree already exists at path: $WORKTREE_PATH"
  fi
}

BRANCH_EXISTS=false

check_branch_not_exists() {
  if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
    BRANCH_EXISTS=true
  fi
}

create_worktree() {
  if [[ "$BRANCH_EXISTS" == true ]]; then
    # Branch exists but worktree path doesn't — attach to existing branch
    git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
  else
    git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" "$BASE_BRANCH"
  fi
}

symlink_maestro() {
  if git ls-files --error-unmatch ".maestro/" >/dev/null 2>&1; then
    return
  fi
  
  local symlink_path="$WORKTREE_PATH/.maestro"
  local relative_path="../../.maestro"
  
  if [[ ! -L "$symlink_path" ]]; then
    ln -s "$relative_path" "$symlink_path"
  fi
}

check_git_version
check_inside_git_repo
ensure_worktrees_dir
ensure_worktrees_in_gitignore
check_worktree_not_exists
check_branch_not_exists
create_worktree
symlink_maestro

cat <<EOF
{"worktree_path":"$WORKTREE_PATH","branch":"$BRANCH_NAME","created":true}
EOF
