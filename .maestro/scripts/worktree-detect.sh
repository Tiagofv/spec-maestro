#!/usr/bin/env bash
# Detect worktree context and set environment variables
# Source this file: source .maestro/scripts/worktree-detect.sh

set -euo pipefail

MAESTRO_IN_WORKTREE=false
MAESTRO_MAIN_REPO=""
MAESTRO_WORKTREE_FEATURE=""
export MAESTRO_IN_WORKTREE
export MAESTRO_MAIN_REPO
export MAESTRO_WORKTREE_FEATURE

detect_worktree() {
    local current_toplevel
    local main_worktree
    local current_branch
    
    current_toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
    
    main_worktree=$(git worktree list --porcelain 2>/dev/null | head -n 1 | awk '{print $2}') || return 1
    
    MAESTRO_MAIN_REPO="$main_worktree"
    
    if [[ "$current_toplevel" != "$main_worktree" ]]; then
        MAESTRO_IN_WORKTREE=true
        
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || current_branch="unknown"
        
        local feature_id=""
        case "$current_branch" in
            feature/*)
                feature_id="${current_branch#feature/}"
                ;;
            feat/*)
                feature_id="${current_branch#feat/}"
                ;;
            bugfix/*)
                feature_id="${current_branch#bugfix/}"
                ;;
            fix/*)
                feature_id="${current_branch#fix/}"
                ;;
            hotfix/*)
                feature_id="${current_branch#hotfix/}"
                ;;
            release/*)
                feature_id="${current_branch#release/}"
                ;;
            *)
                feature_id="$current_branch"
                ;;
        esac
        
        MAESTRO_WORKTREE_FEATURE="$feature_id"
        
        echo "You are inside worktree for feature: $feature_id" >&2
    fi
}

detect_worktree || { MAESTRO_IN_WORKTREE=false; MAESTRO_MAIN_REPO=""; MAESTRO_WORKTREE_FEATURE=""; return 0; }
