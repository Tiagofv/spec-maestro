#!/usr/bin/env bash
# Copy resource directories from repo root into pkg/embedded/resources/
# Usage: copy-resources.sh
# Run from anywhere — resolves paths from script location.
# Exit 0 = success, exit 1 = failure

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Script lives at cmd/maestro-cli/scripts/ — repo root is 3 levels up
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET_DIR="$SCRIPT_DIR/../pkg/embedded/resources"
TARGET_DIR="$(cd "$(dirname "$TARGET_DIR")" && pwd)/resources"

echo "=== copy-resources ===" >&2
echo "  repo root : $REPO_ROOT" >&2
echo "  target    : $TARGET_DIR" >&2

# ---------------------------------------------------------------------------
# Validate sources exist
# ---------------------------------------------------------------------------
MAESTRO_SUBDIRS=(commands scripts templates skills cookbook reference)
MISSING=()

for dir in "${MAESTRO_SUBDIRS[@]}"; do
  [[ -d "$REPO_ROOT/.maestro/$dir" ]] || MISSING+=(".maestro/$dir")
done

[[ -f "$REPO_ROOT/.maestro/constitution.md" ]] || MISSING+=(".maestro/constitution.md")
[[ -d "$REPO_ROOT/.claude" ]]                  || MISSING+=(".claude")
[[ -d "$REPO_ROOT/.opencode" ]]                || MISSING+=(".opencode")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "FAIL: missing source(s):" >&2
  printf "  - %s\n" "${MISSING[@]}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Prepare target (idempotent — always start clean)
# ---------------------------------------------------------------------------
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

# ---------------------------------------------------------------------------
# Helper: copy directory with optional excludes
# Uses rsync when available, falls back to cp + find.
# Usage: copy_dir <src> <dest> [exclude...]
# ---------------------------------------------------------------------------
copy_dir() {
  local src="$1"
  local dest="$2"
  shift 2

  mkdir -p "$dest"

  if command -v rsync &>/dev/null; then
    local rsync_args=( -a --delete )
    for excl in "$@"; do
      rsync_args+=(--exclude "$excl")
    done
    rsync "${rsync_args[@]}" "$src/" "$dest/"
  else
    # Fallback: cp -R then remove excluded patterns
    cp -R "$src/." "$dest/"
    for excl in "$@"; do
      find "$dest" -name "$excl" -exec rm -rf {} + 2>/dev/null || true
    done
  fi
}

# ---------------------------------------------------------------------------
# 1. Copy 6 .maestro subdirectories
# ---------------------------------------------------------------------------
COPIED=0
for dir in "${MAESTRO_SUBDIRS[@]}"; do
  copy_dir "$REPO_ROOT/.maestro/$dir" "$TARGET_DIR/.maestro/$dir"
  COPIED=$((COPIED + 1))
  echo "  copied .maestro/$dir" >&2
done

# ---------------------------------------------------------------------------
# 2. Copy .maestro/constitution.md
# ---------------------------------------------------------------------------
mkdir -p "$TARGET_DIR/.maestro"
cp "$REPO_ROOT/.maestro/constitution.md" "$TARGET_DIR/.maestro/constitution.md"
COPIED=$((COPIED + 1))
echo "  copied .maestro/constitution.md" >&2

# ---------------------------------------------------------------------------
# 3. Copy .claude/ (exclude .git, node_modules)
# ---------------------------------------------------------------------------
copy_dir "$REPO_ROOT/.claude" "$TARGET_DIR/.claude" ".git" "node_modules"
COPIED=$((COPIED + 1))
echo "  copied .claude/ (excluding .git, node_modules)" >&2

# ---------------------------------------------------------------------------
# 4. Copy .opencode/ (exclude node_modules, bun.lock)
# ---------------------------------------------------------------------------
copy_dir "$REPO_ROOT/.opencode" "$TARGET_DIR/.opencode" "node_modules" "bun.lock"
COPIED=$((COPIED + 1))
echo "  copied .opencode/ (excluding node_modules, bun.lock)" >&2

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== copy-resources: $COPIED resource sets copied ===" >&2
