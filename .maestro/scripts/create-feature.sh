#!/usr/bin/env bash
#
# create-feature.sh — Create a numbered feature directory
#
# Usage: bash .maestro/scripts/create-feature.sh "Feature description"
#
# Outputs JSON:
#   {"feature_id":"001-feature-name","spec_dir":".maestro/specs/001-feature-name","branch":"feat/feature-name","slug":"feature-name","worktree_name":"feature-name","worktree_path":".worktrees/feature-name"}
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
BRANCH="feat/${SLUG}"
WORKTREE_NAME="${SLUG}"
WORKTREE_PATH=".worktrees/${SLUG}"

# --- Create spec directory ---
mkdir -p "$SPEC_DIR"

# --- Output JSON ---
cat <<EOF
{"feature_id":"${FEATURE_ID}","spec_dir":"${SPEC_DIR}","branch":"${BRANCH}","slug":"${SLUG}","worktree_name":"${WORKTREE_NAME}","worktree_path":"${WORKTREE_PATH}"}
EOF
