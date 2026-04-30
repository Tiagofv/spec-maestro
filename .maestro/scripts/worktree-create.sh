#!/usr/bin/env bash
#
# worktree-create.sh — Create a git worktree for a feature
#
# Two CLI forms are supported (T005, feature 062):
#
#   NEW (per-repo, multi-repo aware):
#     worktree-create.sh --repo <name> [--feature <feature-id-or-slug>] \
#                        [--base-branch <branch>]
#
#   LEGACY (positional, single-repo, pre-062):
#     worktree-create.sh <worktree-name> <branch-name> [base-branch]
#
# The new form resolves the repo's root path from the feature's spec
# **Repos:** header (or, for the implicit single-repo case, from
# `basename(MAESTRO_BASE)`), `cd`s into that root, runs `git fetch`, and
# creates the worktree at `<repo-root>/.worktrees/<feature-slug>`. State is
# updated via the canonical writer in bd-helpers.sh.
#
# Output JSON:
#   NEW:    {"repo":"<name>","path":"<absolute>","branch":"feat/<slug>","created":true}
#   LEGACY: {"worktree_path":"<rel>","branch":"<name>","created":true}
#
# Errors exit 1 with a message to stderr.

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve maestro install base + helpers.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=worktree-detect.sh
source "$SCRIPT_DIR/worktree-detect.sh" 2>/dev/null || true

# shellcheck source=bd-helpers.sh
source "$SCRIPT_DIR/bd-helpers.sh" 2>/dev/null || true

if [[ -n "${MAESTRO_BASE:-}" ]]; then
  MAESTRO_DIR="${MAESTRO_BASE}/.maestro"
else
  MAESTRO_DIR="$(dirname "$SCRIPT_DIR")"   # SCRIPT_DIR is .maestro/scripts/, parent is .maestro/
fi
CONFIG_FILE="$MAESTRO_DIR/config.yaml"

error() {
  echo "$1" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  worktree-create.sh --repo <name> [--feature <id-or-slug>] [--base-branch <branch>]
  worktree-create.sh <worktree-name> <branch-name> [base-branch]
  worktree-create.sh --help

Options (new form):
  --repo <name>          Repository name (matches a directory under MAESTRO_BASE
                         or its parent, or an entry in the spec's **Repos:**
                         header). Required unless state.repos has exactly one
                         entry; if omitted, defaults to that lone entry, then
                         to basename(MAESTRO_BASE).
  --feature <id-or-slug> Feature id (e.g. "059-partner-assistant-add-invoice-
                         download") or bare slug. Defaults to the most-recent
                         feature under .maestro/specs/.
  --base-branch <name>   Base branch to fork from (default: main, or
                         project.base_branch from .maestro/config.yaml).

The legacy positional form is preserved for backward compatibility with
in-flight callers; new code should use --repo / --feature.
USAGE
}

# ---------------------------------------------------------------------------
# Argument parsing — distinguishes new (--repo/--feature) from legacy
# (two positional args). The first non-flag positional triggers legacy mode.
# ---------------------------------------------------------------------------
NEW_FORM=false
LEGACY_FORM=false
REPO_FLAG=""
FEATURE_FLAG=""
BASE_BRANCH_FLAG=""
LEGACY_POSITIONAL=()

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --repo)
      [[ $# -ge 2 ]] || error "--repo requires a value"
      REPO_FLAG="$2"
      NEW_FORM=true
      shift 2
      ;;
    --repo=*)
      REPO_FLAG="${1#--repo=}"
      NEW_FORM=true
      shift
      ;;
    --feature)
      [[ $# -ge 2 ]] || error "--feature requires a value"
      FEATURE_FLAG="$2"
      NEW_FORM=true
      shift 2
      ;;
    --feature=*)
      FEATURE_FLAG="${1#--feature=}"
      NEW_FORM=true
      shift
      ;;
    --base-branch)
      [[ $# -ge 2 ]] || error "--base-branch requires a value"
      BASE_BRANCH_FLAG="$2"
      shift 2
      ;;
    --base-branch=*)
      BASE_BRANCH_FLAG="${1#--base-branch=}"
      shift
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        LEGACY_POSITIONAL+=("$1")
        shift
      done
      ;;
    -*)
      error "Unknown flag: $1 (try --help)"
      ;;
    *)
      LEGACY_POSITIONAL+=("$1")
      shift
      ;;
  esac
done

# Decide form: if any --repo/--feature/--base-branch was set, this is NEW
# regardless of any extra positionals; otherwise we look at positional count.
if [[ "$NEW_FORM" == true ]]; then
  if [[ ${#LEGACY_POSITIONAL[@]} -gt 0 ]]; then
    error "Cannot mix legacy positional args with --repo / --feature flags"
  fi
elif [[ ${#LEGACY_POSITIONAL[@]} -ge 2 ]]; then
  LEGACY_FORM=true
elif [[ ${#LEGACY_POSITIONAL[@]} -eq 1 ]]; then
  error "Legacy form requires both <worktree-name> and <branch-name>; got 1 positional arg. Try --help."
else
  # No flags, no positionals — treat as new form with all defaults.
  NEW_FORM=true
fi

# ---------------------------------------------------------------------------
# Default base branch (used by both forms).
# ---------------------------------------------------------------------------
config_base_branch() {
  if [[ -f "$CONFIG_FILE" ]]; then
    grep -E '^\s+base_branch:' "$CONFIG_FILE" 2>/dev/null \
      | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'"
  fi
}

# ===========================================================================
# Common git/worktree primitives
# ===========================================================================

check_git_version() {
  local git_version major minor
  git_version="$(git --version | sed 's/git version //' | cut -d. -f1-2)"
  major="$(echo "$git_version" | cut -d. -f1)"
  minor="$(echo "$git_version" | cut -d. -f2)"
  if [[ "$major" -lt 2 ]] || { [[ "$major" -eq 2 ]] && [[ "$minor" -lt 5 ]]; }; then
    error "Git version must be >= 2.5. Current version: $git_version"
  fi
}

check_inside_git_repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error "Not inside a git repository (cwd: $(pwd))"
  fi
}

check_clean_working_tree() {
  # Refuse to create a worktree off a dirty index or worktree. Untracked files
  # are tolerated — `git worktree add` does not touch them — but staged or
  # modified tracked files mean the user has in-progress work that could
  # confuse the implicit base-branch fork.
  if ! git diff --quiet --cached 2>/dev/null; then
    error "Working tree has staged changes; commit or stash before creating a worktree"
  fi
  if ! git diff --quiet 2>/dev/null; then
    error "Working tree has unstaged modifications; commit or stash before creating a worktree"
  fi
}

ensure_worktrees_in_gitignore() {
  # Adds `.worktrees/` to the repo's .gitignore if not already present. Done
  # in cwd (the repo root, after cd-ing in).
  local gitignore=".gitignore"
  if [[ -f "$gitignore" ]]; then
    if ! grep -qE '^(\.worktrees/|\.worktrees$)' "$gitignore" 2>/dev/null; then
      echo ".worktrees/" >> "$gitignore"
    fi
  else
    echo ".worktrees/" > "$gitignore"
  fi
}

# ===========================================================================
# Legacy form (preserves pre-062 behavior verbatim).
# ===========================================================================
run_legacy_form() {
  local worktree_name="${LEGACY_POSITIONAL[0]}"
  local branch_name="${LEGACY_POSITIONAL[1]}"
  local base_branch="${LEGACY_POSITIONAL[2]:-}"

  if [[ -z "$base_branch" ]]; then
    base_branch="$(config_base_branch)"
    base_branch="${base_branch:-main}"
  fi

  local worktrees_dir=".worktrees"
  local worktree_path="${worktrees_dir}/${worktree_name}"

  check_git_version
  check_inside_git_repo

  mkdir -p "$worktrees_dir"
  ensure_worktrees_in_gitignore

  if [[ -d "$worktree_path" ]]; then
    error "Worktree already exists at path: $worktree_path"
  fi

  local branch_exists=false
  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    branch_exists=true
  fi

  if [[ "$branch_exists" == true ]]; then
    git worktree add "$worktree_path" "$branch_name"
  else
    git worktree add "$worktree_path" -b "$branch_name" "$base_branch"
  fi

  # Symlink .maestro/ into the new worktree when .maestro/ is not git-tracked
  # (matches pre-062 behavior).
  if ! git ls-files --error-unmatch ".maestro/" >/dev/null 2>&1; then
    local symlink_path="$worktree_path/.maestro"
    if [[ ! -L "$symlink_path" ]]; then
      ln -s "../../.maestro" "$symlink_path"
    fi
  fi

  printf '{"worktree_path":"%s","branch":"%s","created":true}\n' \
    "$worktree_path" "$branch_name"
}

# ===========================================================================
# New form (per-repo, multi-repo aware).
# ===========================================================================

# resolve_feature_id <flag-value>
# Normalizes --feature input to a full feature id (NNN-slug) by looking it up
# under <MAESTRO_BASE>/.maestro/specs/. Accepts:
#   - exact directory name (e.g. "059-partner-assistant-add-invoice-download")
#   - bare slug (e.g. "partner-assistant-add-invoice-download")
#   - empty (in which case we pick the most-recent spec by sort order)
resolve_feature_id() {
  local input="$1"
  local specs_dir="${MAESTRO_BASE}/.maestro/specs"

  if [[ ! -d "$specs_dir" ]]; then
    error "Specs directory not found: $specs_dir"
  fi

  if [[ -z "$input" ]]; then
    # Most-recent spec dir by sort order.
    local latest
    latest="$(ls -1 "$specs_dir" 2>/dev/null | grep -E '^[0-9]+-' | sort | tail -1 || true)"
    if [[ -z "$latest" ]]; then
      error "No feature specs found under $specs_dir; pass --feature <id>"
    fi
    printf '%s' "$latest"
    return 0
  fi

  # If input already looks like NNN-slug and the dir exists, accept verbatim.
  if [[ "$input" =~ ^[0-9]+- ]] && [[ -d "$specs_dir/$input" ]]; then
    printf '%s' "$input"
    return 0
  fi

  # Otherwise treat input as a slug; find the unique NNN-<slug> directory.
  local matches
  matches="$(ls -1 "$specs_dir" 2>/dev/null | grep -E "^[0-9]+-${input}$" || true)"
  local match_count
  if [[ -z "$matches" ]]; then
    match_count=0
  else
    match_count="$(printf '%s\n' "$matches" | grep -c .)"
  fi

  if [[ "$match_count" -eq 0 ]]; then
    # Last resort: try prefix match, but only accept a single hit.
    matches="$(ls -1 "$specs_dir" 2>/dev/null | grep -E "^[0-9]+-${input}" || true)"
    if [[ -z "$matches" ]]; then
      match_count=0
    else
      match_count="$(printf '%s\n' "$matches" | grep -c .)"
    fi
  fi

  if [[ "$match_count" -eq 0 ]]; then
    error "No feature spec matches --feature '$input' under $specs_dir"
  elif [[ "$match_count" -gt 1 ]]; then
    error "--feature '$input' is ambiguous; matches multiple specs. Pass the full feature id."
  fi
  printf '%s' "$matches"
}

# feature_slug <feature-id>
# Strips the leading NNN- to produce the slug used for branch + worktree dir.
feature_slug() {
  local fid="$1"
  printf '%s' "${fid#[0-9][0-9][0-9]-}"
}

# parse_repos_header <spec-file>
# Reads the first `**Repos:**` line and emits one repo name per line. Handles
# both forms allowed by data-model.md §5:
#   - inline comma-separated:  **Repos:** repo-a, repo-b
#   - markdown bulleted list under the header (one per line)
# Strips an optional trailing HTML comment (the placeholder syntax used in
# the spec template).
parse_repos_header() {
  local spec_file="$1"
  [[ -f "$spec_file" ]] || return 0

  # Inline form: capture the first line that starts with `**Repos:**` and
  # everything after the label, on the same line.
  local inline rest yielded=0
  inline="$(grep -m1 -E '^\*\*Repos:\*\*' "$spec_file" 2>/dev/null || true)"
  if [[ -n "$inline" ]]; then
    rest="${inline#*\*\*Repos:\*\*}"
    # Strip trailing HTML comment (e.g. "<!-- ... -->") if present.
    rest="${rest%%<!--*}"
    # Append a trailing newline so the final item is always emitted by
    # `read` (otherwise items not followed by a comma+newline get dropped).
    local item
    while IFS= read -r item; do
      item="$(printf '%s' "$item" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      # Reject placeholder values from the spec template.
      case "$item" in
        ""|"<repo-a>"|"<repo-b>"|"<repo>"|"<repo-c>"|"<repo-name>") continue ;;
      esac
      printf '%s\n' "$item"
      yielded=$((yielded + 1))
    done < <(printf '%s\n' "$rest" | tr ',' '\n')
  fi

  # Bulleted list form: lines like "- repo-a" or "* repo-b" immediately
  # following the header. Only consume contiguous bullet lines until the
  # next blank line or non-bullet line. We fall through to this when the
  # inline branch yielded nothing (e.g. the header is on its own line and
  # the entries are listed below as a markdown bullet list).
  if [[ "$yielded" -eq 0 ]]; then
    awk '
      /^\*\*Repos:\*\*/ { in_block = 1; next }
      in_block {
        if ($0 ~ /^[[:space:]]*$/) { in_block = 0; next }
        if ($0 ~ /^[[:space:]]*[-*][[:space:]]+/) {
          sub(/^[[:space:]]*[-*][[:space:]]+/, "")
          # Strip trailing HTML comment if any.
          sub(/<!--.*$/, "")
          # Trim.
          gsub(/^[[:space:]]+|[[:space:]]+$/, "")
          if (length($0)) print $0
        } else {
          in_block = 0
        }
      }
    ' "$spec_file" 2>/dev/null
  fi
}

# resolve_repo_root <repo-name>
# Returns the absolute filesystem path to <repo-name>'s root by checking, in
# order: <MAESTRO_BASE>/<repo>, <dirname(MAESTRO_BASE)>/<repo>. Per spec §8.8
# we do NOT do filesystem-existence pre-validation at plan time, but at
# implement time (here) we do — that's the explicit contract in this spec.
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

  # Fall back to dirname(MAESTRO_BASE) (folder-of-repos layout where
  # MAESTRO_BASE *is* the install root and sibling repos live alongside it).
  local parent
  parent="$(dirname "$base")"
  if [[ -d "$parent/$repo" ]]; then
    printf '%s' "$parent/$repo"
    return 0
  fi

  # Not found anywhere we know.
  error "Repo root not found for '$repo' (looked in $base/$repo and $parent/$repo)"
}

# update_state_after_create <feature-id> <repo> <abs-path> <branch> <created>
# Reads the feature's state file (if any), folds in the new worktree entry,
# and writes via the canonical writer in bd-helpers.sh.
update_state_after_create() {
  local feature_id="$1"
  local repo="$2"
  local path="$3"
  local branch="$4"
  local created="$5"

  local state_file="${MAESTRO_BASE}/.maestro/state/${feature_id}.json"

  if ! command -v jq >/dev/null 2>&1; then
    echo "WARN[worktree-create]: jq not found; skipping state update for $feature_id" >&2
    return 0
  fi

  if ! declare -f write_state_worktrees >/dev/null 2>&1; then
    echo "WARN[worktree-create]: write_state_worktrees helper not loaded; skipping state update" >&2
    return 0
  fi

  # Build the new state JSON: read existing if present, otherwise start with a
  # minimal envelope.
  local existing="{}"
  if [[ -f "$state_file" ]]; then
    existing="$(cat "$state_file")"
  else
    mkdir -p "$(dirname "$state_file")"
  fi

  local repo_key
  repo_key="$(_legacy_repo_key "$state_file")"

  local merged
  merged="$(printf '%s' "$existing" | jq \
    --arg fid "$feature_id" \
    --arg repo "$repo" \
    --arg key "$repo_key" \
    --arg path "$path" \
    --arg branch "$branch" \
    --argjson created "$created" \
    '
      . as $s
      | (if (.feature_id // null) == null then .feature_id = $fid else . end)
      # Seed worktrees from existing new-shape, otherwise from legacy fold,
      # otherwise empty. write_state_worktrees does the same fold but we
      # need the merged object before we can add the new entry.
      | (
          if (.worktrees // null) | type == "object" then .worktrees
          elif ((.worktree_path // null) != null) and ((.worktree_branch // null) != null) then
            { ($key): {
                path: .worktree_path,
                branch: .worktree_branch,
                created: (.worktree_created // false),
              } }
          else {} end
        ) as $wts
      | .worktrees = ($wts + { ($repo): { path: $path, branch: $branch, created: $created } })
      | .repos = ((.repos // []) + [$repo] | unique)
    ' 2>&1)" || error "Failed to merge state JSON: $merged"

  write_state_worktrees "$state_file" "$merged" || \
    echo "WARN[worktree-create]: write_state_worktrees failed for $state_file" >&2
}

run_new_form() {
  check_git_version

  # ---- Resolve feature + slug --------------------------------------------
  local feature_id slug spec_file
  feature_id="$(resolve_feature_id "$FEATURE_FLAG")"
  slug="$(feature_slug "$feature_id")"
  spec_file="${MAESTRO_BASE}/.maestro/specs/${feature_id}/spec.md"

  # ---- Resolve --repo (with single-repo backward-compat fallback) --------
  local repo="$REPO_FLAG"
  if [[ -z "$repo" ]]; then
    # Try the lone entry from state.repos first (if state file exists).
    local state_file="${MAESTRO_BASE}/.maestro/state/${feature_id}.json"
    if [[ -f "$state_file" ]] && command -v jq >/dev/null 2>&1; then
      local sole_repo
      sole_repo="$(jq -r '
        if ((.repos // null) | type == "array") and ((.repos | length) == 1)
        then .repos[0] else empty end
      ' "$state_file" 2>/dev/null || true)"
      if [[ -n "$sole_repo" ]]; then
        repo="$sole_repo"
      fi
    fi
  fi
  if [[ -z "$repo" ]]; then
    # Try the lone entry from the spec's **Repos:** header.
    local header_repos
    header_repos="$(parse_repos_header "$spec_file" 2>/dev/null || true)"
    local header_count
    header_count="$(printf '%s\n' "$header_repos" | grep -c . || true)"
    if [[ "$header_count" -eq 1 ]]; then
      repo="$header_repos"
    fi
  fi
  if [[ -z "$repo" ]]; then
    # Final fallback: basename(MAESTRO_BASE) — the implicit single-repo case.
    if [[ -n "${MAESTRO_BASE:-}" ]]; then
      repo="$(basename "$MAESTRO_BASE")"
    else
      error "Cannot resolve --repo: no state.repos, no **Repos:** header, no MAESTRO_BASE"
    fi
  fi

  # Validate repo-name shape per data-model.md §6 (regex from spec §8.1).
  if ! [[ "$repo" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    error "--repo '$repo' is not a valid repo name (must match ^[a-z0-9][a-z0-9-]*\$)"
  fi

  # ---- Cross-check repo against the spec header (when present) -----------
  if [[ -f "$spec_file" ]]; then
    local header_repos
    header_repos="$(parse_repos_header "$spec_file" 2>/dev/null || true)"
    if [[ -n "$header_repos" ]]; then
      if ! printf '%s\n' "$header_repos" | grep -Fxq "$repo"; then
        # Allow basename(MAESTRO_BASE) even if not in header — that's the
        # implicit-single-repo escape hatch. Anything else fails loudly.
        if [[ "$repo" != "$(basename "${MAESTRO_BASE:-}")" ]]; then
          error "Repo '$repo' is not declared in the spec's **Repos:** header for feature $feature_id"
        fi
      fi
    fi
  fi

  # ---- Resolve repo root + cd into it ------------------------------------
  local repo_root
  repo_root="$(resolve_repo_root "$repo")"
  cd "$repo_root"

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error "Repo root '$repo_root' is not a git repository"
  fi

  # ---- Branch + paths -----------------------------------------------------
  local branch_name="feat/${slug}"
  local worktree_dir=".worktrees"
  local worktree_path_rel="${worktree_dir}/${slug}"
  local worktree_path_abs="${repo_root}/${worktree_path_rel}"

  local base_branch="$BASE_BRANCH_FLAG"
  if [[ -z "$base_branch" ]]; then
    base_branch="$(config_base_branch)"
    base_branch="${base_branch:-main}"
  fi

  # ---- Resumable shortcut: if the worktree already exists at the target
  # path, treat as success without further side effects. This must run before
  # the dirty-tree check so that an unrelated WIP in the main worktree of
  # this repo doesn't block --resume on a feature whose worktree is already
  # provisioned.
  if [[ -d "$worktree_path_rel" ]]; then
    update_state_after_create "$feature_id" "$repo" "$worktree_path_abs" "$branch_name" "true"
    printf '{"repo":"%s","path":"%s","branch":"%s","created":true,"already_existed":true}\n' \
      "$repo" "$worktree_path_abs" "$branch_name"
    return 0
  fi

  # Refuse to act on a dirty working tree (acceptance criterion).
  check_clean_working_tree

  mkdir -p "$worktree_dir"
  ensure_worktrees_in_gitignore

  # Branch already exists (without a matching worktree dir) is a
  # non-resumable invocation per the spec — fail loudly.
  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    error "Branch '$branch_name' already exists in $repo_root but the worktree directory '$worktree_path_rel' does not. Refusing to attach silently; remove the stale branch (\`git -C $repo_root branch -D $branch_name\`) or use the resumable path."
  fi

  # ---- Fetch (always, per spec) ------------------------------------------
  # Best-effort: a network failure here is informative but doesn't necessarily
  # block creation if the base branch already resolves locally. We fail only
  # when we cannot resolve the base branch afterward.
  if ! git fetch --quiet 2>/dev/null; then
    echo "WARN[worktree-create]: git fetch failed in $repo_root; falling back to local refs" >&2
  fi

  # ---- Create worktree ----------------------------------------------------
  # Prefer origin/<base> when available (post-fetch); fall back to local.
  local fork_point="$base_branch"
  if git show-ref --verify --quiet "refs/remotes/origin/${base_branch}"; then
    fork_point="origin/${base_branch}"
  elif ! git show-ref --verify --quiet "refs/heads/${base_branch}"; then
    error "Base branch '$base_branch' not found locally or as origin/${base_branch}"
  fi
  git worktree add "$worktree_path_rel" -b "$branch_name" "$fork_point"

  # ---- State update + JSON output ----------------------------------------
  update_state_after_create "$feature_id" "$repo" "$worktree_path_abs" "$branch_name" "true"

  printf '{"repo":"%s","path":"%s","branch":"%s","created":true}\n' \
    "$repo" "$worktree_path_abs" "$branch_name"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
if [[ "$LEGACY_FORM" == true ]]; then
  run_legacy_form
else
  run_new_form
fi
