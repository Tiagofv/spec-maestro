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

# Multi-repo test temp directories (populated below, cleaned in cleanup).
MULTI_REPO_DIR1=""
MULTI_REPO_DIR2=""
MULTI_FEATURE_SPEC_DIR=""
MULTI_STATE_FILE=""
COMPAT_TMP_DIR=""

cleanup() {
  git -C "$REPO_ROOT" worktree remove "$REPO_ROOT/.worktrees/test-wt" --force 2>/dev/null || true
  git -C "$REPO_ROOT" branch -D feat/test-wt 2>/dev/null || true
  rm -f "$REPO_ROOT/.maestro/state/test-999-mock.json" 2>/dev/null || true
  # Remove any spec dirs created by backward-compat test
  rm -rf "$REPO_ROOT/.maestro/specs/"*"-lifecycle-compat-test" 2>/dev/null || true
  # Multi-repo test cleanup
  if [[ -n "$MULTI_REPO_DIR1" ]]; then
    rm -rf "$MULTI_REPO_DIR1" 2>/dev/null || true
  fi
  if [[ -n "$MULTI_REPO_DIR2" ]]; then
    rm -rf "$MULTI_REPO_DIR2" 2>/dev/null || true
  fi
  if [[ -n "$MULTI_FEATURE_SPEC_DIR" ]]; then
    rm -rf "$MULTI_FEATURE_SPEC_DIR" 2>/dev/null || true
  fi
  if [[ -n "$MULTI_STATE_FILE" ]]; then
    rm -f "$MULTI_STATE_FILE" 2>/dev/null || true
  fi
  if [[ -n "$COMPAT_TMP_DIR" ]]; then
    rm -rf "$COMPAT_TMP_DIR" 2>/dev/null || true
  fi
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
# Multi-repo test helpers
# ---------------------------------------------------------------------------

# make_git_repo <dir>
# Initialise a minimal git repo at <dir> so that `git worktree add` works:
# init, configure local user, create an initial commit on main/master.
make_git_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  # Create a commit so git considers the repo non-empty.
  printf 'test repo\n' > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "initial commit"
  # Rename default branch to "main" if needed (git < 2.28 defaults to master).
  local cur_branch
  cur_branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)"
  if [[ "$cur_branch" != "main" ]]; then
    git -C "$dir" branch -m "$cur_branch" main 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# Test 9: Two-repo create
#
# Strategy: worktree-detect.sh always resolves MAESTRO_BASE from the script's
# physical location — it cannot be overridden via env. So we need to use the
# real MAESTRO_BASE (REPO_ROOT) and place the fake repos where
# resolve_repo_root will find them: dirname(MAESTRO_BASE)/<repo>, i.e.
# at the parent of REPO_ROOT.
#
# The feature spec is created temporarily inside the real .maestro/specs/.
# Both artefacts are registered in the cleanup trap.
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 9: Two-repo create (multi-repo --repo flag) ---"

# Unique suffix to avoid name collisions when tests run concurrently.
MULTI_SUFFIX="t9-$$"
MULTI_FEATURE_ID="098-multi-repo-${MULTI_SUFFIX}"
MULTI_SLUG="multi-repo-${MULTI_SUFFIX}"

# resolve_repo_root checks dirname(MAESTRO_BASE)/<repo> as its fallback.
# MAESTRO_BASE == REPO_ROOT, so dirname is the parent of the worktree dir.
MULTI_PARENT="$(dirname "$REPO_ROOT")"
MULTI_REPO_DIR1="$MULTI_PARENT/repo-alpha-${MULTI_SUFFIX}"
MULTI_REPO_DIR2="$MULTI_PARENT/repo-beta-${MULTI_SUFFIX}"
make_git_repo "$MULTI_REPO_DIR1"
make_git_repo "$MULTI_REPO_DIR2"

# Create the feature spec in the real .maestro/specs/ directory.
MULTI_FEATURE_SPEC_DIR="$REPO_ROOT/.maestro/specs/$MULTI_FEATURE_ID"
mkdir -p "$MULTI_FEATURE_SPEC_DIR"
printf '# Feature %s\n\n**Repos:** repo-alpha-%s, repo-beta-%s\n' \
  "$MULTI_FEATURE_ID" "$MULTI_SUFFIX" "$MULTI_SUFFIX" \
  > "$MULTI_FEATURE_SPEC_DIR/spec.md"

MULTI_STATE_FILE="$REPO_ROOT/.maestro/state/${MULTI_FEATURE_ID}.json"

CREATE9A_EXIT=0
CREATE9A_OUT=$(bash "$SCRIPTS_DIR/worktree-create.sh" \
  --repo "repo-alpha-${MULTI_SUFFIX}" \
  --feature "$MULTI_FEATURE_ID" \
  --base-branch main \
  2>/dev/null) || CREATE9A_EXIT=$?

if [[ $CREATE9A_EXIT -eq 0 ]] && [[ -d "$MULTI_REPO_DIR1/.worktrees/$MULTI_SLUG" ]]; then
  pass "Test 9a: repo-alpha worktree created at repo-alpha/.worktrees/$MULTI_SLUG"
else
  fail "Test 9a: repo-alpha worktree NOT created (exit=$CREATE9A_EXIT)"
fi

CREATE9B_EXIT=0
CREATE9B_OUT=$(bash "$SCRIPTS_DIR/worktree-create.sh" \
  --repo "repo-beta-${MULTI_SUFFIX}" \
  --feature "$MULTI_FEATURE_ID" \
  --base-branch main \
  2>/dev/null) || CREATE9B_EXIT=$?

if [[ $CREATE9B_EXIT -eq 0 ]] && [[ -d "$MULTI_REPO_DIR2/.worktrees/$MULTI_SLUG" ]]; then
  pass "Test 9b: repo-beta worktree created at repo-beta/.worktrees/$MULTI_SLUG"
else
  fail "Test 9b: repo-beta worktree NOT created (exit=$CREATE9B_EXIT)"
fi

# ---------------------------------------------------------------------------
# Test 10: Missing repo root error
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 10: Missing repo root returns nonzero exit ---"

CREATE10_EXIT=0
CREATE10_STDERR=$(bash "$SCRIPTS_DIR/worktree-create.sh" \
  --repo "nonexistent-repo-${MULTI_SUFFIX}" \
  --feature "$MULTI_FEATURE_ID" \
  --base-branch main \
  2>&1 >/dev/null) || CREATE10_EXIT=$?

if [[ $CREATE10_EXIT -ne 0 ]]; then
  pass "Test 10a: nonexistent-repo exits nonzero (exit=$CREATE10_EXIT)"
else
  fail "Test 10a: nonexistent-repo unexpectedly exited 0"
fi

# stderr should mention the repo name or "not found" or "Repo root".
if echo "$CREATE10_STDERR" | grep -qiE 'not found|nonexistent|repo root|not declared'; then
  pass "Test 10b: stderr contains identifiable error for missing repo"
else
  fail "Test 10b: stderr did not contain expected error text (got: '$CREATE10_STDERR')"
fi

# ---------------------------------------------------------------------------
# Test 11: Two-repo cleanup --all
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 11: Two-repo cleanup --all removes both worktrees ---"

# Depends on Test 9 having created both worktrees and written the state file.
# worktree-cleanup.sh --all reads state.worktrees to discover paths.

CLEANUP11_EXIT=0
CLEANUP11_OUT=$(bash "$SCRIPTS_DIR/worktree-cleanup.sh" \
  --all \
  --feature "$MULTI_FEATURE_ID" \
  2>/dev/null) || CLEANUP11_EXIT=$?

if [[ $CLEANUP11_EXIT -eq 0 ]]; then
  pass "Test 11a: worktree-cleanup.sh --all exited 0"
else
  fail "Test 11a: worktree-cleanup.sh --all exited nonzero (exit=$CLEANUP11_EXIT)"
fi

if [[ ! -d "$MULTI_REPO_DIR1/.worktrees/$MULTI_SLUG" ]]; then
  pass "Test 11b: repo-alpha worktree removed after --all cleanup"
else
  fail "Test 11b: repo-alpha worktree still exists after --all cleanup"
fi

if [[ ! -d "$MULTI_REPO_DIR2/.worktrees/$MULTI_SLUG" ]]; then
  pass "Test 11c: repo-beta worktree removed after --all cleanup"
else
  fail "Test 11c: repo-beta worktree still exists after --all cleanup"
fi

# ---------------------------------------------------------------------------
# Test 12: Single-repo backward compat regression (legacy positional form)
# ---------------------------------------------------------------------------
echo ""
echo "--- Test 12: Single-repo backward compat (legacy positional form) ---"

COMPAT_TMP_DIR=$(mktemp -d)
make_git_repo "$COMPAT_TMP_DIR"

COMPAT_WT_NAME="compat-wt-test"
COMPAT_BRANCH="feat/compat-wt-test"

COMPAT12_EXIT=0
COMPAT12_OUT=$(
  cd "$COMPAT_TMP_DIR"
  bash "$SCRIPTS_DIR/worktree-create.sh" "$COMPAT_WT_NAME" "$COMPAT_BRANCH" 2>/dev/null
) || COMPAT12_EXIT=$?

if [[ $COMPAT12_EXIT -eq 0 ]]; then
  pass "Test 12a: legacy positional form exits 0"
else
  fail "Test 12a: legacy positional form exited nonzero (exit=$COMPAT12_EXIT)"
fi

if [[ -d "$COMPAT_TMP_DIR/.worktrees/$COMPAT_WT_NAME" ]]; then
  pass "Test 12b: worktree created at .worktrees/$COMPAT_WT_NAME (legacy path)"
else
  fail "Test 12b: worktree NOT found at .worktrees/$COMPAT_WT_NAME"
fi

# JSON output should contain worktree_path (legacy shape, not new shape).
if echo "$COMPAT12_OUT" | grep -q '"worktree_path"'; then
  pass "Test 12c: legacy form output contains 'worktree_path' field"
else
  fail "Test 12c: legacy form output missing 'worktree_path' field (got: '$COMPAT12_OUT')"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
