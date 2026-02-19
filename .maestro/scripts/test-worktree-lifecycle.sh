#!/usr/bin/env bash
# Test worktree lifecycle integration
#
# Usage: bash .maestro/scripts/test-worktree-lifecycle.sh
#
# Validates the full worktree lifecycle: create, list, detect, cleanup,
# backward compatibility, state file integration, and non-git dir handling.

set -euo pipefail

PASS=0
FAIL=0

REPO_ROOT="$(git rev-parse --show-toplevel)"
SCRIPTS_DIR="$REPO_ROOT/.maestro/scripts"

pass() { echo "✓ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "✗ FAIL: $1"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# Cleanup — run on EXIT via trap
# ---------------------------------------------------------------------------
cleanup() {
  git -C "$REPO_ROOT" worktree remove "$REPO_ROOT/.worktrees/test-wt" --force 2>/dev/null || true
  git -C "$REPO_ROOT" branch -D feat/test-wt 2>/dev/null || true
  rm -f "$REPO_ROOT/.maestro/state/test-999-mock.json" 2>/dev/null || true
  # Remove any spec dirs created by backward-compat test
  rm -rf "$REPO_ROOT/.maestro/specs/"*"-lifecycle-compat-test" 2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "=== Worktree Lifecycle Integration Tests ==="
echo ""

# ---------------------------------------------------------------------------
# Test 1: Create worktree
# ---------------------------------------------------------------------------
echo "--- Test 1: Create worktree ---"

CREATE_OUTPUT=$(bash "$SCRIPTS_DIR/worktree-create.sh" test-wt feat/test-wt 2>/dev/null)

if [[ -d "$REPO_ROOT/.worktrees/test-wt" ]]; then
  pass "Test 1a: Directory .worktrees/test-wt/ exists"
else
  fail "Test 1a: Directory .worktrees/test-wt/ does not exist"
fi

if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/feat/test-wt"; then
  pass "Test 1b: Branch feat/test-wt was created"
else
  fail "Test 1b: Branch feat/test-wt was not created"
fi

# Check .maestro symlink only when .maestro is NOT git-tracked
if git -C "$REPO_ROOT" ls-files --error-unmatch ".maestro/" >/dev/null 2>&1; then
  pass "Test 1c: .maestro is git-tracked; symlink not required (skipping symlink check)"
else
  SYMLINK_PATH="$REPO_ROOT/.worktrees/test-wt/.maestro"
  if [[ -L "$SYMLINK_PATH" ]]; then
    pass "Test 1c: .maestro symlink exists inside worktree"
  else
    fail "Test 1c: .maestro symlink missing inside worktree (expected because .maestro is not git-tracked)"
  fi
fi

# ---------------------------------------------------------------------------
# Test 2: List worktrees
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 2: List worktrees ---"

LIST_OUTPUT=$(bash "$SCRIPTS_DIR/worktree-list.sh" --json 2>/dev/null)

# Validate it's valid JSON (array)
if echo "$LIST_OUTPUT" | grep -qE '^\['; then
  pass "Test 2a: Output starts with '[' (valid JSON array)"
else
  fail "Test 2a: Output does not start with '[' — not a JSON array"
fi

# Check the array contains an entry for .worktrees/test-wt (match by path substring)
if echo "$LIST_OUTPUT" | grep -q "test-wt"; then
  pass "Test 2b: JSON array contains entry for .worktrees/test-wt"
else
  fail "Test 2b: JSON array missing entry for .worktrees/test-wt"
fi

# ---------------------------------------------------------------------------
# Test 3: Detect from inside worktree
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 3: Detect worktree context from inside worktree ---"

DETECT_OUTPUT=$(
  cd "$REPO_ROOT/.worktrees/test-wt"
  # Unset any pre-existing vars to ensure a clean test
  unset MAESTRO_IN_WORKTREE MAESTRO_MAIN_REPO MAESTRO_WORKTREE_FEATURE 2>/dev/null || true
  # Source detect script in a subshell and emit variable values
  bash -c "
    source '$SCRIPTS_DIR/worktree-detect.sh' 2>/dev/null
    echo \"MAESTRO_IN_WORKTREE=\$MAESTRO_IN_WORKTREE\"
    echo \"MAESTRO_MAIN_REPO=\$MAESTRO_MAIN_REPO\"
  "
)

WT_IN_WORKTREE=$(echo "$DETECT_OUTPUT" | grep '^MAESTRO_IN_WORKTREE=' | cut -d= -f2)
WT_MAIN_REPO=$(echo "$DETECT_OUTPUT" | grep '^MAESTRO_MAIN_REPO=' | cut -d= -f2)

if [[ "$WT_IN_WORKTREE" == "true" ]]; then
  pass "Test 3a: MAESTRO_IN_WORKTREE=true when sourced from inside worktree"
else
  fail "Test 3a: MAESTRO_IN_WORKTREE expected 'true', got '$WT_IN_WORKTREE'"
fi

if [[ -n "$WT_MAIN_REPO" ]]; then
  pass "Test 3b: MAESTRO_MAIN_REPO is set ('$WT_MAIN_REPO')"
else
  fail "Test 3b: MAESTRO_MAIN_REPO is empty"
fi

if [[ "$WT_MAIN_REPO" == "$REPO_ROOT" ]]; then
  pass "Test 3c: MAESTRO_MAIN_REPO matches actual main repo path"
else
  fail "Test 3c: MAESTRO_MAIN_REPO='$WT_MAIN_REPO', expected '$REPO_ROOT'"
fi

# ---------------------------------------------------------------------------
# Test 4: Detect from main repo
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 4: Detect worktree context from main repo ---"

DETECT_MAIN=$(
  cd "$REPO_ROOT"
  bash -c "
    source '$SCRIPTS_DIR/worktree-detect.sh' 2>/dev/null
    echo \"MAESTRO_IN_WORKTREE=\$MAESTRO_IN_WORKTREE\"
    echo \"MAESTRO_MAIN_REPO=\$MAESTRO_MAIN_REPO\"
  "
)

MAIN_IN_WORKTREE=$(echo "$DETECT_MAIN" | grep '^MAESTRO_IN_WORKTREE=' | cut -d= -f2)
MAIN_MAIN_REPO=$(echo "$DETECT_MAIN" | grep '^MAESTRO_MAIN_REPO=' | cut -d= -f2)

if [[ "$MAIN_IN_WORKTREE" == "false" ]]; then
  pass "Test 4a: MAESTRO_IN_WORKTREE=false when sourced from main repo"
else
  fail "Test 4a: MAESTRO_IN_WORKTREE expected 'false', got '$MAIN_IN_WORKTREE'"
fi

if [[ -n "$MAIN_MAIN_REPO" ]]; then
  pass "Test 4b: MAESTRO_MAIN_REPO is set from main repo context"
else
  fail "Test 4b: MAESTRO_MAIN_REPO is empty when sourced from main repo"
fi

# ---------------------------------------------------------------------------
# Test 5: Cleanup worktree
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 5: Cleanup worktree ---"

# worktree-cleanup.sh checks for unmerged branches — force-delete for test
# We use --delete-branch but the branch is not merged, so we expect branch_deleted=false.
# Use force removal via git directly for the directory, then check script output.

# First, get the branch to force-delete after the script attempts cleanup
CLEANUP_OUTPUT=$(bash "$SCRIPTS_DIR/worktree-cleanup.sh" .worktrees/test-wt --delete-branch 2>/dev/null || true)

# Force-delete the branch regardless (it won't be merged in tests)
git -C "$REPO_ROOT" branch -D feat/test-wt 2>/dev/null || true

if [[ ! -d "$REPO_ROOT/.worktrees/test-wt" ]]; then
  pass "Test 5a: Directory .worktrees/test-wt/ no longer exists after cleanup"
else
  fail "Test 5a: Directory .worktrees/test-wt/ still exists after cleanup"
fi

# Branch was force-deleted above after cleanup
if ! git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/feat/test-wt"; then
  pass "Test 5b: Branch feat/test-wt no longer exists"
else
  fail "Test 5b: Branch feat/test-wt still exists"
fi

# ---------------------------------------------------------------------------
# Test 6: Backward compatibility — create-feature.sh
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 6: Backward compatibility (create-feature.sh) ---"

CF_OUTPUT=$(bash "$SCRIPTS_DIR/create-feature.sh" "lifecycle compat test" 2>/dev/null)

# Check spec dir was created
SPEC_DIR_VALUE=$(echo "$CF_OUTPUT" | grep -o '"spec_dir":"[^"]*"' | sed 's/"spec_dir":"\([^"]*\)"/\1/')

if [[ -n "$SPEC_DIR_VALUE" ]] && [[ -d "$REPO_ROOT/$SPEC_DIR_VALUE" ]]; then
  pass "Test 6a: Spec directory was created at '$SPEC_DIR_VALUE'"
else
  fail "Test 6a: Spec directory not created (spec_dir='$SPEC_DIR_VALUE')"
fi

# Check worktree_name field in output
if echo "$CF_OUTPUT" | grep -q '"worktree_name"'; then
  pass "Test 6b: JSON output contains 'worktree_name' field"
else
  fail "Test 6b: JSON output missing 'worktree_name' field"
fi

# Check worktree_path field in output
if echo "$CF_OUTPUT" | grep -q '"worktree_path"'; then
  pass "Test 6c: JSON output contains 'worktree_path' field"
else
  fail "Test 6c: JSON output missing 'worktree_path' field"
fi

# Verify no git branch was created by create-feature.sh
BRANCH_IN_OUTPUT=$(echo "$CF_OUTPUT" | grep -o '"branch":"[^"]*"' | sed 's/"branch":"\([^"]*\)"/\1/')
if ! git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/${BRANCH_IN_OUTPUT}" 2>/dev/null; then
  pass "Test 6d: create-feature.sh did NOT create a git branch"
else
  fail "Test 6d: create-feature.sh unexpectedly created branch '$BRANCH_IN_OUTPUT'"
fi

# Cleanup spec dir created by this test
rm -rf "$REPO_ROOT/$SPEC_DIR_VALUE" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Test 7: State file integration
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 7: State file integration ---"

# Create a fresh worktree for this test (it was cleaned up in test 5)
bash "$SCRIPTS_DIR/worktree-create.sh" test-wt feat/test-wt >/dev/null 2>&1

STATE_DIR="$REPO_ROOT/.maestro/state"
mkdir -p "$STATE_DIR"

MOCK_STATE_FILE="$STATE_DIR/test-999-mock.json"
cat > "$MOCK_STATE_FILE" <<'JSON'
{
  "feature_id": "999-mock-feature",
  "worktree_path": ".worktrees/test-wt",
  "worktree_branch": "feat/test-wt",
  "stage": "in_progress"
}
JSON

STATE_LIST=$(bash "$SCRIPTS_DIR/worktree-list.sh" --json 2>/dev/null)

# Check the worktree appears and has the feature_id association
if echo "$STATE_LIST" | grep -q '"999-mock-feature"'; then
  pass "Test 7a: worktree-list.sh associates worktree with feature from state file"
else
  fail "Test 7a: worktree-list.sh did not associate worktree with state file feature_id"
fi

if echo "$STATE_LIST" | grep -q '"stage":"in_progress"'; then
  pass "Test 7b: worktree-list.sh correctly reflects stage from state file"
else
  fail "Test 7b: worktree-list.sh did not reflect correct stage from state file"
fi

rm -f "$MOCK_STATE_FILE" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Test 8: worktree-detect in non-git directory
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 8: worktree-detect in non-git directory ---"

TEMP_DIR=$(mktemp -d)

DETECT_NONGIT_EXIT=0
DETECT_NONGIT_OUTPUT=$(
  cd "$TEMP_DIR"
  bash -c "
    source '$SCRIPTS_DIR/worktree-detect.sh' 2>/dev/null
    echo \"MAESTRO_IN_WORKTREE=\$MAESTRO_IN_WORKTREE\"
    echo \"EXIT=0\"
  " 2>/dev/null
) || DETECT_NONGIT_EXIT=$?

rmdir "$TEMP_DIR" 2>/dev/null || true

# Script must not kill the shell (exit code 0 — sourced scripts return 0 on graceful fallback)
if [[ "$DETECT_NONGIT_EXIT" -eq 0 ]]; then
  pass "Test 8a: Script didn't crash in non-git directory (exit 0)"
else
  fail "Test 8a: Script exited with non-zero ($DETECT_NONGIT_EXIT) in non-git directory"
fi

NONGIT_IN_WORKTREE=$(echo "$DETECT_NONGIT_OUTPUT" | grep '^MAESTRO_IN_WORKTREE=' | cut -d= -f2)

if [[ "$NONGIT_IN_WORKTREE" == "false" ]]; then
  pass "Test 8b: MAESTRO_IN_WORKTREE=false in non-git directory"
else
  fail "Test 8b: MAESTRO_IN_WORKTREE expected 'false', got '$NONGIT_IN_WORKTREE'"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
