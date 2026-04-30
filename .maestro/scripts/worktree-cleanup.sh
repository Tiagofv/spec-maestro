#!/usr/bin/env bash
#
# worktree-cleanup.sh — Remove git worktrees and update feature state
#
# Two CLI forms are supported (T006, feature 062):
#
#   NEW (per-repo, multi-repo aware):
#     worktree-cleanup.sh --repo <name>  [--feature <feature-id-or-slug>] [--delete-branch]
#     worktree-cleanup.sh --all          [--feature <feature-id-or-slug>] [--delete-branch]
#
#   LEGACY (positional, single-repo, pre-062):
#     worktree-cleanup.sh <worktree-path> [--delete-branch]
#
# NEW form resolves the repo root, runs `git worktree remove` inside it, then
# updates the feature state file via write_state_worktrees from bd-helpers.sh.
# Safety check (Risk #3): refuses to act when the resolved worktree path does
# not start with the resolved repo root.
#
# Output JSON:
#   NEW:    {"repo":"<name>","removed":true,"branch_deleted":false}
#   --all:  [{"repo":"...","removed":true,"branch_deleted":false}, ...]
#   LEGACY: {"removed":true,"branch_deleted":false}
#
# Exit 1 on error (uncommitted changes, path outside repo root, etc.)

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve maestro install base + helpers.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=worktree-detect.sh
source "$SCRIPT_DIR/worktree-detect.sh" 2>/dev/null || true

# shellcheck source=bd-helpers.sh
source "$SCRIPT_DIR/bd-helpers.sh" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
NEW_FORM=false
LEGACY_FORM=false
REPO_FLAG=""
ALL_FLAG=false
FEATURE_FLAG=""
DELETE_BRANCH=false
LEGACY_POSITIONAL=()

if [[ $# -eq 0 ]]; then
  echo "Usage: worktree-cleanup.sh <worktree-path> [--delete-branch]" >&2
  echo "       worktree-cleanup.sh --repo <name>  [--feature <id>] [--delete-branch]" >&2
  echo "       worktree-cleanup.sh --all          [--feature <id>] [--delete-branch]" >&2
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      cat <<'USAGE'
Usage:
  worktree-cleanup.sh --repo <name> [--feature <id-or-slug>] [--delete-branch]
  worktree-cleanup.sh --all         [--feature <id-or-slug>] [--delete-branch]
  worktree-cleanup.sh <worktree-path> [--delete-branch]

Options (new form):
  --repo <name>      Remove the worktree for this repo only.
  --all              Remove worktrees for every repo in state.worktrees.
  --feature <id>     Feature whose state file to read/update. Defaults to
                     the most-recent spec under .maestro/specs/.
  --delete-branch    Also delete the branch if it is merged (same as legacy).
USAGE
      exit 0
      ;;
    --repo)
      [[ $# -ge 2 ]] || { echo "--repo requires a value" >&2; exit 1; }
      REPO_FLAG="$2"
      NEW_FORM=true
      shift 2
      ;;
    --repo=*)
      REPO_FLAG="${1#--repo=}"
      NEW_FORM=true
      shift
      ;;
    --all)
      ALL_FLAG=true
      NEW_FORM=true
      shift
      ;;
    --feature)
      [[ $# -ge 2 ]] || { echo "--feature requires a value" >&2; exit 1; }
      FEATURE_FLAG="$2"
      NEW_FORM=true
      shift 2
      ;;
    --feature=*)
      FEATURE_FLAG="${1#--feature=}"
      NEW_FORM=true
      shift
      ;;
    --delete-branch)
      DELETE_BRANCH=true
      shift
      ;;
    -*)
      echo "Unknown flag: $1 (try --help)" >&2
      exit 1
      ;;
    *)
      LEGACY_POSITIONAL+=("$1")
      shift
      ;;
  esac
done

# Decide form
if [[ "$NEW_FORM" == false ]]; then
  if [[ ${#LEGACY_POSITIONAL[@]} -ge 1 ]]; then
    LEGACY_FORM=true
  else
    echo "Usage: worktree-cleanup.sh <worktree-path> [--delete-branch]" >&2
    exit 1
  fi
fi

if [[ "$NEW_FORM" == true && ${#LEGACY_POSITIONAL[@]} -gt 0 ]]; then
  echo "Cannot mix legacy positional args with --repo / --all / --feature flags" >&2
  exit 1
fi

if [[ "$NEW_FORM" == true && "$ALL_FLAG" == false && -z "$REPO_FLAG" ]]; then
  echo "New form requires either --repo <name> or --all" >&2
  exit 1
fi

if [[ "$REPO_FLAG" != "" && "$ALL_FLAG" == true ]]; then
  echo "worktree-cleanup: --repo and --all are mutually exclusive" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Shared error helper
# ---------------------------------------------------------------------------
error() {
  echo "$1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Common helpers (shared between both forms)
# ---------------------------------------------------------------------------

_is_worktree() {
  local wt_path="$1"
  local repo_root="$2"
  git -C "$repo_root" worktree list --porcelain 2>/dev/null | grep -q "^worktree $wt_path$"
}

_check_no_uncommitted_changes() {
  local wt_path="$1"
  if [[ ! -d "$wt_path" ]]; then
    return 0
  fi
  if [[ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]]; then
    error "Worktree has uncommitted changes at $wt_path. Commit or stash them first."
  fi
}

_get_worktree_branch() {
  local wt_path="$1"
  local repo_root="$2"
  local branch
  branch=$(git -C "$repo_root" worktree list --porcelain 2>/dev/null | awk -v path="$wt_path" '
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

_check_branch_merged() {
  local branch="$1"
  local repo_root="$2"
  local current_branch
  current_branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD)
  git -C "$repo_root" branch --merged "$current_branch" 2>/dev/null | grep -qF "$branch"
}

_delete_branch_if_merged() {
  local branch="$1"
  local repo_root="$2"
  if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
    if _check_branch_merged "$branch" "$repo_root"; then
      git -C "$repo_root" branch -d "$branch" 2>/dev/null || true
      echo "true"
      return 0
    else
      echo "Branch $branch is not merged. Skipping deletion." >&2
    fi
  fi
  echo "false"
}

# ---------------------------------------------------------------------------
# Repo root resolution (same logic as worktree-create.sh)
# ---------------------------------------------------------------------------
resolve_repo_root() {
  local repo="$1"
  local base="${MAESTRO_BASE:-$(pwd)}"

  # Absolute path passed verbatim.
  if [[ "$repo" = /* ]]; then
    printf '%s' "$repo"
    return 0
  fi

  # Same name as the install base — the implicit single-repo case.
  if [[ "$(basename "$base")" == "$repo" ]]; then
    printf '%s' "$base"
    return 0
  fi

  # Look inside MAESTRO_BASE first (sibling-of-.maestro layout).
  if [[ -d "$base/$repo" ]]; then
    printf '%s' "$base/$repo"
    return 0
  fi

  # Fall back to dirname(MAESTRO_BASE) (folder-of-repos layout).
  local parent
  parent="$(dirname "$base")"
  if [[ -d "$parent/$repo" ]]; then
    printf '%s' "$parent/$repo"
    return 0
  fi

  error "Repo root not found for '$repo' (looked in $base/$repo and $parent/$repo)"
}

# ---------------------------------------------------------------------------
# Feature resolution (same as worktree-create.sh)
# ---------------------------------------------------------------------------
_resolve_feature_id() {
  local input="$1"
  local specs_dir="${MAESTRO_BASE:-$(pwd)}/.maestro/specs"

  if [[ ! -d "$specs_dir" ]]; then
    error "Specs directory not found: $specs_dir"
  fi

  if [[ -z "$input" ]]; then
    local latest
    latest="$(ls -1 "$specs_dir" 2>/dev/null | grep -E '^[0-9]+-' | sort | tail -1 || true)"
    if [[ -z "$latest" ]]; then
      error "No feature specs found under $specs_dir; pass --feature <id>"
    fi
    printf '%s' "$latest"
    return 0
  fi

  if [[ "$input" =~ ^[0-9]+- ]] && [[ -d "$specs_dir/$input" ]]; then
    printf '%s' "$input"
    return 0
  fi

  local matches match_count
  matches="$(ls -1 "$specs_dir" 2>/dev/null | grep -E "^[0-9]+-${input}$" || true)"
  match_count="$(printf '%s\n' "$matches" | grep -c . || true)"

  if [[ "$match_count" -eq 0 ]]; then
    matches="$(ls -1 "$specs_dir" 2>/dev/null | grep -E "^[0-9]+-${input}" || true)"
    match_count="$(printf '%s\n' "$matches" | grep -c . || true)"
  fi

  if [[ "$match_count" -eq 0 ]]; then
    error "No feature spec matches --feature '$input' under $specs_dir"
  elif [[ "$match_count" -gt 1 ]]; then
    error "--feature '$input' is ambiguous; matches multiple specs. Pass the full feature id."
  fi
  printf '%s' "$matches"
}

# ---------------------------------------------------------------------------
# Core per-repo cleanup logic
# ---------------------------------------------------------------------------

# _remove_repo_worktree <repo-name> <repo-root> <worktree-path>
# Runs git worktree remove inside repo-root, prunes, optionally deletes branch.
# Returns JSON fragment: {"repo":"...","removed":true,"branch_deleted":false}
_remove_repo_worktree() {
  local repo="$1"
  local repo_root="$2"
  local wt_path="$3"

  # --- Safety check (Risk #3): worktree path must start with repo root ------
  # Resolve both to real paths so symlinks / relative segments don't fool us.
  local real_root real_wt
  real_root="$(cd "$repo_root" && pwd -P 2>/dev/null)" || real_root="$repo_root"
  # wt_path may not exist yet (already removed), use dirname fallback.
  if [[ -d "$wt_path" ]]; then
    real_wt="$(cd "$wt_path" && pwd -P 2>/dev/null)" || real_wt="$wt_path"
  else
    # Normalize without requiring the directory to exist.
    real_wt="$(cd "$(dirname "$wt_path")" 2>/dev/null && pwd -P)/$(basename "$wt_path")" || real_wt="$wt_path"
  fi

  # Add trailing slash to root for prefix comparison so /repo-foo doesn't
  # match /repo-foobar.
  local root_prefix="${real_root%/}/"
  if [[ "$real_wt" != "${root_prefix}"* ]]; then
    error "safety: worktree path '$wt_path' is outside repo root '$repo_root'; refusing cleanup"
  fi

  # --- Handle already-gone worktree ----------------------------------------
  if [[ ! -d "$wt_path" ]]; then
    if _is_worktree "$wt_path" "$repo_root"; then
      echo "Worktree directory already removed. Running prune..." >&2
      git -C "$repo_root" worktree prune
      printf '{"repo":"%s","removed":true,"branch_deleted":false}\n' "$repo"
      return 0
    fi
    echo "Worktree path does not exist and is not registered: $wt_path" >&2
    printf '{"repo":"%s","removed":false,"branch_deleted":false}\n' "$repo"
    return 0
  fi

  # --- Verify it's actually a registered worktree ---------------------------
  if ! _is_worktree "$wt_path" "$repo_root"; then
    error "Path is not a git worktree in $repo_root: $wt_path"
  fi

  # --- Uncommitted changes check --------------------------------------------
  _check_no_uncommitted_changes "$wt_path"

  # --- Capture branch before removal (needed for --delete-branch) ----------
  local branch=""
  if [[ "$DELETE_BRANCH" == true ]]; then
    branch="$(_get_worktree_branch "$wt_path" "$repo_root")"
  fi

  # --- Remove ---------------------------------------------------------------
  git -C "$repo_root" worktree remove "$wt_path" 2>/dev/null \
    || error "Failed to remove worktree at $wt_path"

  git -C "$repo_root" worktree prune

  # --- Optionally delete branch --------------------------------------------
  local branch_deleted=false
  if [[ "$DELETE_BRANCH" == true ]] && [[ -n "$branch" ]]; then
    branch_deleted="$(_delete_branch_if_merged "$branch" "$repo_root")"
  fi

  printf '{"repo":"%s","removed":true,"branch_deleted":%s}\n' "$repo" "$branch_deleted"
}

# ---------------------------------------------------------------------------
# State update: remove a repo entry from state.worktrees and state.repos
# ---------------------------------------------------------------------------
_remove_from_state() {
  local feature_id="$1"
  local repo="$2"

  if ! command -v jq >/dev/null 2>&1; then
    echo "WARN[worktree-cleanup]: jq not found; skipping state update" >&2
    return 0
  fi

  declare -f write_state_worktrees >/dev/null 2>&1 || { echo "worktree-cleanup: bd-helpers.sh not loaded (write_state_worktrees missing)" >&2; exit 1; }

  local state_file="${MAESTRO_BASE:-$(pwd)}/.maestro/state/${feature_id}.json"
  if [[ ! -f "$state_file" ]]; then
    echo "WARN[worktree-cleanup]: state file not found: $state_file; nothing to update" >&2
    return 0
  fi

  local current_json
  current_json="$(cat "$state_file")"

  # Remove only the named repo entry.
  # Note: the --all path calls this function once per repo (with "false") so
  # that a partial failure leaves state consistent after each individual removal.
  local updated_json
  updated_json="$(printf '%s' "$current_json" | jq \
    --arg repo "$repo" \
    'del(.worktrees[$repo]) | .repos = (.repos // [] | map(select(. != $repo)))' \
    2>&1)" \
    || { echo "WARN[worktree-cleanup]: jq failed removing $repo from state" >&2; return 0; }

  write_state_worktrees "$state_file" "$updated_json" \
    || echo "WARN[worktree-cleanup]: write_state_worktrees failed for $state_file" >&2
}

# ===========================================================================
# NEW FORM
# ===========================================================================
run_new_form() {
  if ! command -v jq >/dev/null 2>&1; then
    error "jq is required for the new --repo/--all form but was not found in PATH"
  fi

  local feature_id
  feature_id="$(_resolve_feature_id "$FEATURE_FLAG")"

  declare -f read_state_worktrees >/dev/null 2>&1 || { echo "worktree-cleanup: bd-helpers.sh not loaded (read_state_worktrees missing)" >&2; exit 1; }

  local state_file="${MAESTRO_BASE:-$(pwd)}/.maestro/state/${feature_id}.json"
  local worktrees_json="{}"

  worktrees_json="$(read_state_worktrees "$state_file" 2>/dev/null || echo '{}')"

  # Build list of repos to process.
  # macOS bash 3.2 compatibility: no associative arrays — use indexed arrays
  # of keys and values derived from jq output.
  local repos_to_process=()
  local paths_to_process=()

  if [[ "$ALL_FLAG" == true ]]; then
    # Collect every repo key from state.worktrees.
    while IFS= read -r repo_name; do
      [[ -n "$repo_name" ]] || continue
      repos_to_process+=("$repo_name")
      local wt_path
      wt_path="$(printf '%s' "$worktrees_json" | jq -r --arg r "$repo_name" '.[$r].path // empty' 2>/dev/null || true)"
      paths_to_process+=("$wt_path")
    done < <(printf '%s' "$worktrees_json" | jq -r 'keys[]' 2>/dev/null || true)

    if [[ ${#repos_to_process[@]} -eq 0 ]]; then
      echo "No worktrees found in state for feature $feature_id" >&2
      echo "[]"
      return 0
    fi
  else
    # Single --repo.
    repos_to_process+=("$REPO_FLAG")
    local wt_path
    wt_path="$(printf '%s' "$worktrees_json" | jq -r --arg r "$REPO_FLAG" '.[$r].path // empty' 2>/dev/null || true)"
    if [[ -z "$wt_path" ]]; then
      error "Repo '$REPO_FLAG' has no worktree entry in state for feature $feature_id"
    fi
    paths_to_process+=("$wt_path")
  fi

  # Process each repo.
  local results=()
  local i
  for i in "${!repos_to_process[@]}"; do
    local repo="${repos_to_process[$i]}"
    local wt_path="${paths_to_process[$i]}"

    if [[ -z "$wt_path" ]]; then
      echo "WARN[worktree-cleanup]: no path found in state for repo '$repo'; skipping" >&2
      results+=("{\"repo\":\"$repo\",\"removed\":false,\"branch_deleted\":false}")
      continue
    fi

    # Resolve the canonical repo root.
    local repo_root
    repo_root="$(resolve_repo_root "$repo")" || {
      echo "WARN[worktree-cleanup]: cannot resolve repo root for '$repo'; skipping" >&2
      results+=("{\"repo\":\"$repo\",\"removed\":false,\"branch_deleted\":false}")
      continue
    }

    local result
    result="$(_remove_repo_worktree "$repo" "$repo_root" "$wt_path")"
    results+=("$result")

    # Update state regardless of whether --all (after each removal so a
    # partial failure leaves state consistent).
    _remove_from_state "$feature_id" "$repo"
  done

  # For --all, emit the results array; for --repo, emit single object.
  if [[ "$ALL_FLAG" == true ]]; then
    # Build JSON array from results elements.
    local array="["
    local sep=""
    for r in "${results[@]}"; do
      array="${array}${sep}${r}"
      sep=","
    done
    array="${array}]"
    printf '%s\n' "$array"
  else
    printf '%s\n' "${results[0]}"
  fi
}

# ===========================================================================
# LEGACY FORM (pre-062 behavior, preserved verbatim)
# ===========================================================================
run_legacy_form() {
  local WORKTREE_PATH="${LEGACY_POSITIONAL[0]}"

  error_legacy() {
    echo "$1" >&2
    exit 1
  }

  check_inside_git_repo_legacy() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      error_legacy "Not inside a git repository"
    fi
  }

  get_worktree_branch_legacy() {
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

  is_worktree_legacy() {
    local wt_path="$1"
    git worktree list --porcelain 2>/dev/null | grep -q "^worktree $wt_path$"
  }

  check_no_uncommitted_changes_legacy() {
    local wt_path="$1"
    if [[ ! -d "$wt_path" ]]; then
      return 0
    fi
    if [[ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]]; then
      error_legacy "Worktree has uncommitted changes. Commit or stash them first."
    fi
  }

  check_branch_merged_legacy() {
    local branch="$1"
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    if git branch --merged "$current_branch" 2>/dev/null | grep -qF "$branch"; then
      return 0
    fi
    return 1
  }

  delete_branch_legacy() {
    local branch="$1"
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      if check_branch_merged_legacy "$branch"; then
        git branch -d "$branch" 2>/dev/null || error_legacy "Failed to delete branch $branch"
        return 0
      else
        echo "Branch $branch is not merged. Skipping deletion." >&2
        return 1
      fi
    fi
    return 1
  }

  check_inside_git_repo_legacy

  ROOT_DIR="$(git rev-parse --show-toplevel)"
  if [[ "$WORKTREE_PATH" != /* ]]; then
    WORKTREE_PATH="$ROOT_DIR/$WORKTREE_PATH"
  fi

  if [[ ! -d "$WORKTREE_PATH" ]]; then
    if is_worktree_legacy "$WORKTREE_PATH"; then
      echo "Worktree already removed. Running prune..." >&2
      git worktree prune
      cat <<EOF
{"removed":true,"branch_deleted":false}
EOF
      exit 0
    fi
    error_legacy "Path does not exist: $WORKTREE_PATH"
  fi

  if ! is_worktree_legacy "$WORKTREE_PATH"; then
    error_legacy "Path is not a worktree: $WORKTREE_PATH"
  fi

  check_no_uncommitted_changes_legacy "$WORKTREE_PATH"

  BRANCH=""
  BRANCH_DELETED=false

  if [[ "$DELETE_BRANCH" == true ]]; then
    BRANCH=$(get_worktree_branch_legacy "$WORKTREE_PATH")
  fi

  if git worktree remove "$WORKTREE_PATH" 2>/dev/null; then
    REMOVED=true
  else
    error_legacy "Failed to remove worktree at $WORKTREE_PATH"
  fi

  git worktree prune

  if [[ "$DELETE_BRANCH" == true ]] && [[ -n "$BRANCH" ]]; then
    if delete_branch_legacy "$BRANCH"; then
      BRANCH_DELETED=true
    fi
  fi

  cat <<EOF
{"removed":$REMOVED,"branch_deleted":$BRANCH_DELETED}
EOF
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
if [[ "$LEGACY_FORM" == true ]]; then
  run_legacy_form
else
  run_new_form
fi
