#!/usr/bin/env bash
# Detect the maestro install base and (optionally) git worktree context.
# Source this file: source .maestro/scripts/worktree-detect.sh
#
# Resolution rule (T004, feature 062):
#   The maestro install base is the parent directory of the enclosing
#   `.maestro/` directory containing this script. We discover it by walking
#   upward from this script's physical location until we find a directory
#   whose basename is `.maestro`. This is independent of git: it works
#   whether `.maestro/` lives at a git repo root, below a git repo root
#   (consumer projects that ship `.maestro/` in a subdirectory of an
#   unrelated parent repo), or in no git repo at all.
#
# Exports:
#   MAESTRO_BASE              -> parent of `.maestro/` (the install root)
#   MAESTRO_MAIN_REPO         -> same as MAESTRO_BASE by default; if the
#                                install base is at the root of a git repo
#                                that uses `git worktree`, this is upgraded
#                                to the main worktree path (state files for
#                                features live in the main worktree under
#                                `.maestro/state/`).
#   MAESTRO_IN_WORKTREE       -> "true" if cwd is inside a non-main git
#                                worktree of the install base, else "false".
#   MAESTRO_WORKTREE_FEATURE  -> feature id parsed from branch name when in
#                                a worktree, empty otherwise.

set -euo pipefail

MAESTRO_BASE="${MAESTRO_BASE:-}"
MAESTRO_MAIN_REPO="${MAESTRO_MAIN_REPO:-}"
MAESTRO_IN_WORKTREE=false
MAESTRO_WORKTREE_FEATURE=""
export MAESTRO_BASE
export MAESTRO_MAIN_REPO
export MAESTRO_IN_WORKTREE
export MAESTRO_WORKTREE_FEATURE

# ---------------------------------------------------------------------------
# Step 1: walk up from ${BASH_SOURCE[0]} to find the enclosing `.maestro/`
# parent directory. This is the maestro install base and is independent of
# git. Bound the search to a reasonable depth (32) to fail loudly rather
# than spin if the script is sourced from a malformed location.
# ---------------------------------------------------------------------------
_maestro_resolve_base() {
    local source_path="$1"
    local script_dir
    # cd -P resolves symlinks to a physical path so symlink-style installs
    # (where a worktree's `.maestro/` is a relative symlink to the main
    # repo's `.maestro/`) end up pointing at the canonical install.
    script_dir="$(cd -P "$(dirname "$source_path")" && pwd)" || return 1

    local dir="$script_dir"
    local guard=0
    while [[ "$dir" != "/" && "$dir" != "" ]]; do
        if [[ "$(basename "$dir")" == ".maestro" && -d "$dir/scripts" ]]; then
            # Found the enclosing `.maestro/`. Its parent is the install base.
            MAESTRO_BASE="$(dirname "$dir")"
            return 0
        fi
        dir="$(dirname "$dir")"
        guard=$((guard + 1))
        if (( guard > 32 )); then
            return 1
        fi
    done
    return 1
}

if ! _maestro_resolve_base "${BASH_SOURCE[0]}"; then
    echo "ERROR[worktree-detect]: could not locate enclosing .maestro/ directory above ${BASH_SOURCE[0]}" >&2
    # When sourced, `return` exits the source. When executed directly, fall
    # through to `exit`. Keep both paths so the caller sees a non-zero status.
    return 1 2>/dev/null || exit 1
fi

# Default: main repo == install base. Git may upgrade this below when the
# install base is the root of a real git repo with worktrees.
MAESTRO_MAIN_REPO="$MAESTRO_BASE"

# ---------------------------------------------------------------------------
# Step 2 (optional): if `git` is available AND the install base is itself a
# git repo root (i.e. `.maestro/` sits at the repo root, not below it), then
# detect worktree state. This preserves backward compatibility with the
# spec-maestro repo (where `.maestro/` is at the repo root and feature
# branches live in `.worktrees/`). For the consumer-project case where
# `.maestro/` is below an unrelated parent git repo, we deliberately skip
# this block so the unrelated parent never overrides MAESTRO_MAIN_REPO.
# ---------------------------------------------------------------------------
_maestro_detect_worktree() {
    command -v git >/dev/null 2>&1 || return 0

    # What does git think the toplevel is, from the install base?
    local install_toplevel
    install_toplevel="$(cd "$MAESTRO_BASE" && git rev-parse --show-toplevel 2>/dev/null)" || return 0

    # Only treat git as authoritative when the install base IS the git repo
    # root. If `.maestro/` is below an unrelated git repo (consumer-project
    # case), `install_toplevel` will not equal `$MAESTRO_BASE` and we keep
    # the walk-up result as-is.
    if [[ "$install_toplevel" != "$MAESTRO_BASE" ]]; then
        return 0
    fi

    # Resolve the main worktree path (first entry of `git worktree list`).
    local main_worktree
    main_worktree="$(cd "$MAESTRO_BASE" && git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')" || return 0
    if [[ -n "$main_worktree" ]]; then
        MAESTRO_MAIN_REPO="$main_worktree"
    fi

    # Detect whether the *current working directory* is inside a non-main
    # worktree of this repo.
    local cwd_toplevel
    cwd_toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0

    if [[ -n "$cwd_toplevel" && -n "$main_worktree" && "$cwd_toplevel" != "$main_worktree" ]]; then
        # Confirm the cwd's toplevel is one of the registered worktrees of
        # the install base (avoids cross-repo false positives).
        local worktrees
        worktrees="$(cd "$MAESTRO_BASE" && git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')"
        if grep -qxF "$cwd_toplevel" <<<"$worktrees"; then
            MAESTRO_IN_WORKTREE=true

            local current_branch
            current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"

            local feature_id=""
            case "$current_branch" in
                feature/*) feature_id="${current_branch#feature/}" ;;
                feat/*)    feature_id="${current_branch#feat/}" ;;
                bugfix/*)  feature_id="${current_branch#bugfix/}" ;;
                fix/*)     feature_id="${current_branch#fix/}" ;;
                hotfix/*)  feature_id="${current_branch#hotfix/}" ;;
                release/*) feature_id="${current_branch#release/}" ;;
                *)         feature_id="$current_branch" ;;
            esac
            MAESTRO_WORKTREE_FEATURE="$feature_id"

            echo "You are inside worktree for feature: $feature_id" >&2
        fi
    fi
}

_maestro_detect_worktree || true
