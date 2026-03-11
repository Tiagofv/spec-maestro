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
# Extract key words (remove articles, prepositions), then generate slug
STOP_WORDS='^(a|an|the|and|or|but|for|nor|on|at|to|from|in|into|with|by|of|is|are|was|were|be|been|being|over|under|above|below|through|about|around|before|after|since|until|while|during|we|our|i|this|that|need|build|tauri)$'

SLUG=$(echo "$DESCRIPTION" \
  | tr '[:upper:]' '[:lower:]' \
  | tr '[:space:]' '\n' \
  | grep -vE "$STOP_WORDS" \
  | grep -vE '^[[:space:]]*$' \
  | tr '\n' ' ' \
  | sed 's/[^a-z0-9]/-/g' \
  | sed 's/--*/-/g' \
  | sed 's/^-//;s/-$//')

# --- Word-boundary truncation (10-40 chars) ---
DUPLICATE_INFO=""
if [ ${#SLUG} -gt 40 ]; then
  TRUNCATED="${SLUG:0:40}"
  LAST_HYPHEN=$(echo "$TRUNCATED" | rev | cut -d'-' -f2- | rev)
  if [ ${#LAST_HYPHEN} -ge 10 ]; then
    SLUG="$LAST_HYPHEN"
  else
    SLUG="${TRUNCATED:0:40}"
  fi
  SLUG=$(echo "$SLUG" | sed 's/-$//')
fi

# --- Scan for potential duplicates ---
if [ -d "$SPECS_DIR" ]; then
  EXISTING_DUPLICATES=$(ls -1 "$SPECS_DIR" 2>/dev/null \
    | grep -E "^[0-9]+-${SLUG}(-[a-z0-9-]*)?$" \
    | sort -n \
    || true)
  if [ -n "$EXISTING_DUPLICATES" ]; then
    DUPLICATE_COUNT=$(echo "$EXISTING_DUPLICATES" | wc -l | tr -d ' ')
    DUPLICATE_LIST=$(echo "$EXISTING_DUPLICATES" | tr '\n' ',' | sed 's/,$//')
    DUPLICATE_INFO=",\"duplicate_count\":${DUPLICATE_COUNT},\"duplicates\":\"${DUPLICATE_LIST}\""
    
    # Extract highest number from duplicates to reuse
    HIGHEST_DUP_NUM=$(echo "$EXISTING_DUPLICATES" | grep -oE '^[0-9]+' | sort -n | tail -1)
    if [ -n "${HIGHEST_DUP_NUM:-}" ]; then
      NEXT_NUM=$((10#$HIGHEST_DUP_NUM))
    fi
  fi
fi

# --- Find next feature number (only if no duplicates found) ---
NEXT_NUM="${NEXT_NUM:-1}"

if [ -z "$EXISTING_DUPLICATES" ] && [ -d "$SPECS_DIR" ]; then
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
BASE_FEATURE_ID="${PADDED}-${SLUG}"

# --- Find first available suffix for duplicates ---
# Check if exact ID already exists; if so, add suffix while keeping same number
FEATURE_ID="$BASE_FEATURE_ID"
SUFFIX_NUM=2
CHECK_SLUG="$SLUG"

# If duplicates exist, find highest version suffix
if [ -n "$EXISTING_DUPLICATES" ]; then
  HIGHEST_SUFFIX=$(echo "$EXISTING_DUPLICATES" | grep -oE '\-v[0-9]+$' | grep -oE '[0-9]+' | sort -n | tail -1 || true)
  if [ -n "${HIGHEST_SUFFIX:-}" ]; then
    SUFFIX_NUM=$((10#$HIGHEST_SUFFIX + 1))
    FEATURE_ID="${BASE_FEATURE_ID}-v${SUFFIX_NUM}"
    CHECK_SLUG="${SLUG}-v${SUFFIX_NUM}"
  fi
fi

while [ -d "${SPECS_DIR}/${FEATURE_ID}" ] || [ -d ".worktrees/${CHECK_SLUG}" ]; do
  FEATURE_ID="${BASE_FEATURE_ID}-v${SUFFIX_NUM}"
  CHECK_SLUG="${SLUG}-v${SUFFIX_NUM}"
  SUFFIX_NUM=$((SUFFIX_NUM + 1))
done

# Update slug and worktree name if versioned
# Check if FEATURE_ID has a version suffix
if echo "$FEATURE_ID" | grep -qE '\-v[0-9]+$'; then
  FINAL_SUFFIX=$(echo "$FEATURE_ID" | grep -oE 'v[0-9]+$' | grep -oE '[0-9]+')
  SLUG="${SLUG}-v${FINAL_SUFFIX}"
fi

SPEC_DIR="${SPECS_DIR}/${FEATURE_ID}"
BRANCH="feat/${SLUG}"
WORKTREE_NAME="${SLUG}"
WORKTREE_PATH=".worktrees/${SLUG}"

# --- Create spec directory ---
mkdir -p "$SPEC_DIR"

# --- Output JSON ---
cat <<EOF
{"feature_id":"${FEATURE_ID}","spec_dir":"${SPEC_DIR}","branch":"${BRANCH}","slug":"${SLUG}","worktree_name":"${WORKTREE_NAME}","worktree_path":"${WORKTREE_PATH}"${DUPLICATE_INFO}}
EOF
