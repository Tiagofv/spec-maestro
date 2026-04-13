#!/usr/bin/env bash
# Test suite for task-diff.sh
# Usage: ./task-diff-test.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIFF_SCRIPT="$SCRIPT_DIR/../task-diff.sh"

# Temp directory for test git repos
TEST_TMPDIR=""

# --- Test harness ---

register_test() {
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

pass_test() {
    local name="$1"
    echo -e "${GREEN}✓ PASS${NC}: $name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail_test() {
    local name="$1"
    local reason="${2:-}"
    echo -e "${RED}✗ FAIL${NC}: $name"
    if [[ -n "$reason" ]]; then
        echo "  Reason: $reason"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

run_test() {
    local test_name="$1"
    shift
    local test_func="$1"
    shift

    register_test

    if $test_func "$@"; then
        pass_test "$test_name"
    else
        fail_test "$test_name" ""
    fi
}

# --- Fixtures: create a temporary git repo with known commits ---

setup_test_repo() {
    TEST_TMPDIR=$(mktemp -d)
    git -C "$TEST_TMPDIR" init -q
    git -C "$TEST_TMPDIR" config user.email "test@test.com"
    git -C "$TEST_TMPDIR" config user.name "Test"

    # Commit 1 — baseline (no task tag)
    echo "baseline" > "$TEST_TMPDIR/file1.txt"
    git -C "$TEST_TMPDIR" add file1.txt
    git -C "$TEST_TMPDIR" commit -q -m "Initial commit"

    # Commit 2 — tagged with [bd:task-abc]
    echo "change1" >> "$TEST_TMPDIR/file1.txt"
    echo "new file" > "$TEST_TMPDIR/file2.txt"
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "Add file2 and update file1 [bd:task-abc]"

    # Commit 3 — tagged with [bd:task-abc] (second commit for same task)
    echo "more changes" >> "$TEST_TMPDIR/file2.txt"
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "Update file2 again [bd:task-abc]"

    # Commit 4 — tagged with [bd:task-xyz] (different task)
    echo "xyz content" > "$TEST_TMPDIR/file3.txt"
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "Add file3 [bd:task-xyz]"
}

teardown_test_repo() {
    if [[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# --- Tests ---

# Test: No arguments → exit 2
test_no_arguments() {
    local exit_code=0
    local output
    output=$("$TASK_DIFF_SCRIPT" 2>&1) || exit_code=$?

    if [[ $exit_code -ne 2 ]]; then
        echo "Expected exit 2, got $exit_code"
        echo "Output: $output"
        return 1
    fi

    if [[ "$output" != *"task ID is required"* ]]; then
        echo "Missing expected error message"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# Test: Empty task ID (empty string) → exit 2
test_empty_task_id() {
    local exit_code=0
    local output
    output=$("$TASK_DIFF_SCRIPT" "" 2>&1) || exit_code=$?

    if [[ $exit_code -ne 2 ]]; then
        echo "Expected exit 2, got $exit_code"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# Test: Unknown flag → exit 2
test_unknown_flag() {
    local exit_code=0
    local output
    output=$("$TASK_DIFF_SCRIPT" "task-abc" --bogus 2>&1) || exit_code=$?

    if [[ $exit_code -ne 2 ]]; then
        echo "Expected exit 2, got $exit_code"
        echo "Output: $output"
        return 1
    fi

    if [[ "$output" != *"unknown flag"* ]]; then
        echo "Missing 'unknown flag' in error message"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# Test: --worktree without path → exit 2
test_worktree_missing_path() {
    local exit_code=0
    local output
    output=$("$TASK_DIFF_SCRIPT" "task-abc" --worktree 2>&1) || exit_code=$?

    if [[ $exit_code -ne 2 ]]; then
        echo "Expected exit 2, got $exit_code"
        echo "Output: $output"
        return 1
    fi

    if [[ "$output" != *"--worktree requires a path"* ]]; then
        echo "Missing expected error about path"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# Test: No matching commits → exit 1
test_no_matching_commits() {
    local exit_code=0
    local output
    output=$("$TASK_DIFF_SCRIPT" "nonexistent-task" --worktree "$TEST_TMPDIR" 2>&1) || exit_code=$?

    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit 1, got $exit_code"
        echo "Output: $output"
        return 1
    fi

    if [[ "$output" != *"no commits found"* ]]; then
        echo "Missing 'no commits found' message"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# Test: Diff output for task-abc includes expected changes
test_diff_output() {
    local exit_code=0
    local output
    output=$("$TASK_DIFF_SCRIPT" "task-abc" --worktree "$TEST_TMPDIR" 2>&1) || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "Expected exit 0, got $exit_code"
        echo "Output: $output"
        return 1
    fi

    # The diff should contain file2.txt changes (created in commit 2, modified in commit 3)
    if [[ "$output" != *"file2.txt"* ]]; then
        echo "Expected diff to reference file2.txt"
        echo "Output: $output"
        return 1
    fi

    # Should contain file1.txt changes
    if [[ "$output" != *"file1.txt"* ]]; then
        echo "Expected diff to reference file1.txt"
        echo "Output: $output"
        return 1
    fi

    # Should NOT contain file3.txt (that's task-xyz)
    if [[ "$output" == *"file3.txt"* ]]; then
        echo "Diff should not include file3.txt from task-xyz"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# Test: --summary flag produces one-line stats
test_summary_flag() {
    local exit_code=0
    local output
    output=$("$TASK_DIFF_SCRIPT" "task-abc" --summary --worktree "$TEST_TMPDIR" 2>&1) || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "Expected exit 0, got $exit_code"
        echo "Output: $output"
        return 1
    fi

    # Output should match pattern: files_changed=N insertions=N deletions=N
    if [[ ! "$output" =~ files_changed=[0-9]+\ insertions=[0-9]+\ deletions=[0-9]+ ]]; then
        echo "Summary output does not match expected format"
        echo "Output: $output"
        return 1
    fi

    # Should have files_changed > 0
    if [[ "$output" =~ files_changed=0 ]]; then
        echo "Expected files_changed > 0"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# Test: --worktree flag works with the test repo
test_worktree_flag() {
    local exit_code=0
    local output

    # Use --worktree to point at the test repo
    output=$("$TASK_DIFF_SCRIPT" "task-xyz" --worktree "$TEST_TMPDIR" 2>&1) || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "Expected exit 0, got $exit_code"
        echo "Output: $output"
        return 1
    fi

    # file3.txt should be in the diff for task-xyz
    if [[ "$output" != *"file3.txt"* ]]; then
        echo "Expected diff to reference file3.txt"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# Test: Invalid worktree path → exit 2
test_invalid_worktree_path() {
    local exit_code=0
    local output
    output=$("$TASK_DIFF_SCRIPT" "task-abc" --worktree "/nonexistent/path/12345" 2>&1) || exit_code=$?

    if [[ $exit_code -ne 2 ]]; then
        echo "Expected exit 2, got $exit_code"
        echo "Output: $output"
        return 1
    fi

    if [[ "$output" != *"worktree path does not exist"* ]]; then
        echo "Missing expected error about nonexistent path"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# --- Main ---

main() {
    echo -e "${BLUE}=== Task Diff Test Suite ===${NC}"
    echo ""

    if [[ ! -f "$TASK_DIFF_SCRIPT" ]]; then
        echo -e "${RED}ERROR: task-diff.sh not found at $TASK_DIFF_SCRIPT${NC}"
        exit 1
    fi

    # Set up test git repo
    setup_test_repo
    trap teardown_test_repo EXIT

    echo "Running tests..."
    echo ""

    # Argument validation tests (no git repo needed)
    run_test "No arguments exits with code 2" test_no_arguments
    run_test "Empty task ID exits with code 2" test_empty_task_id
    run_test "Unknown flag exits with code 2" test_unknown_flag
    run_test "--worktree without path exits with code 2" test_worktree_missing_path
    run_test "Invalid worktree path exits with code 2" test_invalid_worktree_path

    # Functional tests (require test repo)
    run_test "No matching commits exits with code 1" test_no_matching_commits
    run_test "Diff output includes expected files for task" test_diff_output
    run_test "--summary flag produces stats line" test_summary_flag
    run_test "--worktree flag scopes git to path" test_worktree_flag

    echo ""
    echo -e "${BLUE}=== Test Results ===${NC}"
    echo -e "Total:  $TESTS_TOTAL"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

main "$@"
