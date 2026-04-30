#!/usr/bin/env bash
# Assert current execution context matches expected maestro worktree path.
#
# Usage (new form — per-repo, multi-repo aware):
#   assert-worktree-context.sh --repo <name> [--feature <feature-id>]
#
# Usage (legacy form — explicit path):
#   assert-worktree-context.sh <expected-worktree-path>
#
# New form: resolves expected path from state.worktrees[repo].path via
# read_state_worktrees() in bd-helpers.sh. If --repo is omitted, falls back
# to the first entry in state.worktrees (single-repo / legacy compat).
#
# Exit 0 when cwd is inside expected path, else exit 1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Argument parsing — distinguish new (--repo/--feature) from legacy
# (single positional expected-path).
# ---------------------------------------------------------------------------
REPO_FLAG=""
FEATURE_FLAG=""
LEGACY_PATH=""
NEW_FORM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "assert-worktree-context: --repo requires a value" >&2; exit 1; }
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
      [[ $# -ge 2 ]] || { echo "assert-worktree-context: --feature requires a value" >&2; exit 1; }
      FEATURE_FLAG="$2"
      NEW_FORM=true
      shift 2
      ;;
    --feature=*)
      FEATURE_FLAG="${1#--feature=}"
      NEW_FORM=true
      shift
      ;;
    -*)
      echo "assert-worktree-context: unknown flag: $1" >&2
      exit 1
      ;;
    *)
      if [[ "$NEW_FORM" == true ]]; then
        echo "assert-worktree-context: cannot mix positional path with --repo/--feature flags" >&2
        exit 1
      fi
      LEGACY_PATH="$1"
      shift
      ;;
  esac
done

# ---------------------------------------------------------------------------
# New form: resolve expected path from state file via read_state_worktrees.
# ---------------------------------------------------------------------------
if [[ "$NEW_FORM" == true ]]; then
  # Source worktree-detect.sh to get MAESTRO_BASE / MAESTRO_MAIN_REPO.
  # shellcheck source=worktree-detect.sh
  source "$SCRIPT_DIR/worktree-detect.sh" 2>/dev/null || true

  # shellcheck source=bd-helpers.sh
  source "$SCRIPT_DIR/bd-helpers.sh" 2>/dev/null || true

  # Locate the state directory under the main repo (MAESTRO_MAIN_REPO).
  MAIN_REPO="${MAESTRO_MAIN_REPO:-}"
  if [[ -z "$MAIN_REPO" ]]; then
    MAIN_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
  fi
  STATE_DIR="$MAIN_REPO/.maestro/state"

  # Resolve feature id — default to most-recently-modified state file.
  if [[ -n "$FEATURE_FLAG" ]]; then
    STATE_FILE="$STATE_DIR/${FEATURE_FLAG}.json"
  else
    # Most-recently-modified state file (same heuristic as other scripts).
    STATE_FILE="$(ls -t "$STATE_DIR"/*.json 2>/dev/null | head -1 || true)"
  fi

  if [[ -z "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
    echo "assert-worktree-context: state file not found (feature='${FEATURE_FLAG:-<latest>}', state_dir='$STATE_DIR')" >&2
    exit 1
  fi

  # Read the worktrees map.
  WORKTREES_JSON="$(read_state_worktrees "$STATE_FILE" 2>/dev/null)"

  if [[ "$WORKTREES_JSON" == "{}" || -z "$WORKTREES_JSON" ]]; then
    echo "assert-worktree-context: no worktrees found in state file: $STATE_FILE" >&2
    exit 1
  fi

  # Resolve target repo key.
  if [[ -n "$REPO_FLAG" ]]; then
    TARGET_REPO="$REPO_FLAG"
  else
    # Fall back to first entry in state.worktrees (backward-compat for
    # single-repo features and legacy callers that omit --repo).
    TARGET_REPO="$(printf '%s' "$WORKTREES_JSON" | jq -r 'keys | .[0]')"
  fi

  # Look up the path for that repo.
  EXPECTED_PATH="$(printf '%s' "$WORKTREES_JSON" | jq -r --arg repo "$TARGET_REPO" '.[$repo].path // empty')"

  if [[ -z "$EXPECTED_PATH" ]]; then
    echo "assert-worktree-context: repo '$TARGET_REPO' not found in state.worktrees (state: $STATE_FILE)" >&2
    exit 1
  fi

  # Resolve a relative path against MAIN_REPO (state files may store paths
  # relative to the project root, e.g. ".worktrees/feature-slug").
  if [[ "$EXPECTED_PATH" != /* ]]; then
    EXPECTED_PATH="$MAIN_REPO/$EXPECTED_PATH"
  fi

# ---------------------------------------------------------------------------
# Legacy form: single positional <expected-worktree-path>.
# ---------------------------------------------------------------------------
else
  if [[ -z "$LEGACY_PATH" ]]; then
    echo "Usage:" >&2
    echo "  assert-worktree-context.sh --repo <name> [--feature <feature-id>]" >&2
    echo "  assert-worktree-context.sh <expected-worktree-path>" >&2
    exit 1
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not inside a git repository" >&2
    exit 1
  fi

  ROOT_DIR="$(git rev-parse --show-toplevel)"

  EXPECTED_PATH="$LEGACY_PATH"
  if [[ "$EXPECTED_PATH" != /* ]]; then
    EXPECTED_PATH="$ROOT_DIR/$EXPECTED_PATH"
  fi
fi

# ---------------------------------------------------------------------------
# Canonicalize the expected path (resolve without requiring it to exist yet).
# If the directory exists, use cd -P for a fully resolved physical path.
# Otherwise, resolve the nearest existing ancestor with cd -P, then append
# the remaining components — this avoids erroring on worktrees that haven't
# been created yet.
# ---------------------------------------------------------------------------
if [[ -d "$EXPECTED_PATH" ]]; then
  EXPECTED_PATH="$(cd -P "$EXPECTED_PATH" && pwd)"
else
  # Walk up until we find an existing directory, then re-append the suffix.
  _ep_remaining="$(basename "$EXPECTED_PATH")"
  _ep_parent="$(dirname "$EXPECTED_PATH")"
  while [[ "$_ep_parent" != "/" && "$_ep_parent" != "." && ! -d "$_ep_parent" ]]; do
    _ep_remaining="$(basename "$_ep_parent")/$_ep_remaining"
    _ep_parent="$(dirname "$_ep_parent")"
  done
  if [[ -d "$_ep_parent" ]]; then
    EXPECTED_PATH="$(cd -P "$_ep_parent" && pwd)/$_ep_remaining"
  fi
  # If still not resolvable, keep as-is (comparison will fail gracefully below).
fi

# ---------------------------------------------------------------------------
# Assert cwd is inside expected path.
# Unlike the legacy check (which compared git toplevel == expected path),
# the new check verifies that the actual cwd is a path prefix of or equal to
# expected path — handling both "cwd IS the worktree root" and
# "cwd is a subdirectory inside the worktree root".
# ---------------------------------------------------------------------------
ACTUAL_CWD="$(pwd)"

# Normalize: ensure expected path ends without trailing slash for prefix check.
EXPECTED_NORM="${EXPECTED_PATH%/}"

inside=false
if [[ "$ACTUAL_CWD" == "$EXPECTED_NORM" || "$ACTUAL_CWD" == "$EXPECTED_NORM/"* ]]; then
  inside=true
fi

if [[ "$inside" == false ]]; then
  echo "assert-worktree-context: expected cwd inside '${EXPECTED_PATH}', got '${ACTUAL_CWD}'" >&2
  exit 1
fi

echo "{\"ok\":true,\"worktree\":\"$EXPECTED_PATH\"}"
