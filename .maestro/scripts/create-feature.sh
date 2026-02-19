#!/usr/bin/env bash
#
# create-feature.sh — Create a numbered feature directory and git branch
#
# Usage: bash .maestro/scripts/create-feature.sh "Feature description"
#
# Outputs JSON:
#   {"feature_id":"001-feature-name","spec_dir":".maestro/specs/001-feature-name","branch":"spec/001-feature-name"}
#

set -euo pipefail

DESCRIPTION="${1:?Usage: create-feature.sh \"Feature description\"}"
SPECS_DIR=".maestro/specs"

# --- Derive slug from description ---
# Lowercase, replace non-alphanumeric with hyphens, trim, truncate at 50 chars
SLUG=$(echo "$DESCRIPTION" \
  | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-z0-9]/-/g' \
  | sed 's/--*/-/g' \
  | sed 's/^-//;s/-$//' \
  | cut -c1-50)

# --- Find next feature number ---
NEXT_NUM=1

if [ -d "$SPECS_DIR" ]; then
  # Scan existing directories for NNN- prefix, find the highest
  HIGHEST=$(ls -1 "$SPECS_DIR" 2>/dev/null \
    | grep -oE '^[0-9]+' \
    | sort -n \
    | tail -1 \
    || true)
  if [ -n "${HIGHEST:-}" ]; then
    NEXT_NUM=$((10#$HIGHEST + 1))
  fi
fi

# Zero-pad to 3 digits
PADDED=$(printf "%03d" "$NEXT_NUM")
FEATURE_ID="${PADDED}-${SLUG}"
SPEC_DIR="${SPECS_DIR}/${FEATURE_ID}"
BRANCH="spec/${FEATURE_ID}"

# --- Create spec directory ---
mkdir -p "$SPEC_DIR"

# --- Create git branch ---
# Only create branch if we're in a git repo and the branch doesn't exist
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if ! git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    if ! git checkout -b "$BRANCH" 2>/dev/null; then
      # Branch creation failed (likely dirty working tree) — create branch without switching
      git branch "$BRANCH" 2>/dev/null || true
      echo "NOTE: Branch '${BRANCH}' created but not checked out (uncommitted changes)." >&2
      echo "Run 'git stash && git checkout ${BRANCH} && git stash pop' when ready." >&2
    fi
  else
    # Branch exists, try to switch to it
    git checkout "$BRANCH" 2>/dev/null || {
      echo "NOTE: Branch '${BRANCH}' exists but could not check out (uncommitted changes)." >&2
    }
  fi
fi

# --- Output JSON ---
cat <<EOF
{"feature_id":"${FEATURE_ID}","spec_dir":"${SPEC_DIR}","branch":"${BRANCH}","slug":"${SLUG}"}
EOF
