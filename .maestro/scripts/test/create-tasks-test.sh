#!/usr/bin/env bash
# Test suite for create-tasks.sh
# Usage: ./create-tasks-test.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
CREATE_TASKS_SCRIPT="$SCRIPT_DIR/../create-tasks.sh"
TEST_DIR=""
MOCK_DIR=""

# Test names array
declare -a TEST_NAMES

# Setup test environment
setup_test_env() {
    TEST_DIR=$(mktemp -d)
    MOCK_DIR="$TEST_DIR/mock"
    mkdir -p "$MOCK_DIR"
    
    # Copy fixtures to test directory
    cp -r "$FIXTURES_DIR"/* "$TEST_DIR/"
    
    # Create mock bd command - use environment file for state
    cat > "$MOCK_DIR/bd" << 'EOF'
#!/usr/bin/env bash
# Mock bd CLI for testing

# Get test state file from environment or default
STATE_FILE="${BD_MOCK_STATE_FILE:-/tmp/bd-mock-state}"
COMMAND="${1:-}"

case "$COMMAND" in
    "create")
        shift
        TITLE=""
        PARENT=""
        
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --title=*) TITLE="${1#*=}" ;;
                --parent=*) PARENT="${1#*=}" ;;
            esac
            shift
        done
        
        # Generate deterministic ID based on title
        TASK_ID="bd-$(echo "$TITLE" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | head -c 20)-$(date +%s)"
        echo "{\"id\":\"$TASK_ID\",\"title\":\"$TITLE\",\"parent\":\"$PARENT\"}"
        ;;
    
    "list")
        shift
        # Check state file for existing tasks
        if [[ -f "$STATE_FILE" ]] && grep -q "existing_mode" "$STATE_FILE" 2>/dev/null; then
            # Simulate existing tasks
            echo '[
                {"id":"existing-001","title":"Existing task one"},
                {"id":"existing-002","title":"Existing task two"}
            ]'
        else
            echo '[]'
        fi
        ;;
    
    "dep")
        shift
        if [[ "$1" == "add" ]]; then
            # Simulate dependency addition (always succeeds)
            exit 0
        fi
        ;;
    
    *)
        # Unknown command
        exit 1
        ;;
esac
EOF
    chmod +x "$MOCK_DIR/bd"
    
    # Set up PATH to use mock
    export PATH="$MOCK_DIR:$PATH"
    export TEST_DIR
    export BD_MOCK_STATE_FILE="$TEST_DIR/bd-mock-state"
}

# Cleanup test environment
cleanup_test_env() {
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# Register test for reporting
register_test() {
    local name="$1"
    TEST_NAMES+=("$name")
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

# Pass a test
pass_test() {
    local name="$1"
    echo -e "${GREEN}✓ PASS${NC}: $name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

# Fail a test
fail_test() {
    local name="$1"
    local reason="${2:-}"
    echo -e "${RED}✗ FAIL${NC}: $name"
    if [[ -n "$reason" ]]; then
        echo "  Reason: $reason"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Run a single test with setup/cleanup
run_test() {
    local test_name="$1"
    shift
    local test_func="$1"
    shift
    
    register_test "$test_name"
    
    # Setup fresh environment for each test
    setup_test_env || return 1
    
    # Run the test
    if $test_func "$@"; then
        pass_test "$test_name"
    else
        fail_test "$test_name"
    fi
    
    # Cleanup
    cleanup_test_env
}

# Test: Create 5 tasks successfully
test_happy_path() {
    local stdout_output
    local stderr_output
    local exit_code=0
    
    # Capture stdout and stderr separately
    stdout_output=$("$CREATE_TASKS_SCRIPT" "$TEST_DIR/valid-tasks.json" 2>/dev/null) || exit_code=$?
    stderr_output=$("$CREATE_TASKS_SCRIPT" "$TEST_DIR/valid-tasks.json" 2>&1 >/dev/null) || exit_code=$?
    
    # Check exit code
    if [[ $exit_code -ne 0 ]]; then
        echo "Expected exit code 0, got $exit_code"
        return 1
    fi
    
    # Check stdout contains expected JSON structure
    if ! echo "$stdout_output" | jq -e '.feature_id' >/dev/null 2>&1; then
        echo "Output missing feature_id"
        return 1
    fi
    
    # Check all 5 tasks were created
    local task_count
    task_count=$(echo "$stdout_output" | jq '.tasks | length')
    if [[ "$task_count" -ne 5 ]]; then
        echo "Expected 5 tasks, got $task_count"
        return 1
    fi
    
    # Check progress messages in stderr
    if [[ ! "$stderr_output" == *"Phase 1"* ]]; then
        echo "Missing Phase 1 progress message"
        return 1
    fi
    
    if [[ ! "$stderr_output" == *"Phase 2"* ]]; then
        echo "Missing Phase 2 progress message"
        return 1
    fi
    
    return 0
}

# Test: Skip existing tasks (idempotency)
test_idempotency() {
    local stdout_output
    local stderr_output
    local exit_code=0
    
    # Create state file to indicate existing tasks should be returned
    echo "existing_mode" > "$BD_MOCK_STATE_FILE"
    
    stdout_output=$("$CREATE_TASKS_SCRIPT" "$TEST_DIR/existing-tasks.json" 2>/dev/null) || exit_code=$?
    stderr_output=$("$CREATE_TASKS_SCRIPT" "$TEST_DIR/existing-tasks.json" 2>&1 >/dev/null) || exit_code=$?
    
    # Check exit code
    if [[ $exit_code -ne 0 ]]; then
        echo "Expected exit code 0, got $exit_code"
        return 1
    fi
    
    # Check that existing tasks are skipped
    if [[ ! "$stderr_output" == *"Skipped"* ]]; then
        echo "Missing 'Skipped' message for existing tasks"
        return 1
    fi
    
    # Should still have 3 tasks in output
    local task_count
    task_count=$(echo "$stdout_output" | jq '.tasks | length')
    if [[ "$task_count" -ne 3 ]]; then
        echo "Expected 3 tasks in output, got $task_count"
        return 1
    fi
    
    return 0
}

# Test: Stop on first failure
test_error_handling() {
    # Test with non-existent file
    local output
    local exit_code=0
    
    output=$("$CREATE_TASKS_SCRIPT" "/nonexistent/file.json" 2>&1) || exit_code=$?
    
    # Should exit with code 1
    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1 for missing file, got $exit_code"
        return 1
    fi
    
    # Should contain ERROR message
    if [[ ! "$output" == *"ERROR:"* ]]; then
        echo "Missing ERROR message for missing file"
        return 1
    fi
    
    return 0
}

# Test: Link dependencies correctly
test_dependency_linking() {
    local stdout_output
    local exit_code=0
    
    stdout_output=$("$CREATE_TASKS_SCRIPT" "$TEST_DIR/tasks-with-deps.json" 2>/dev/null) || exit_code=$?
    
    # Check exit code
    if [[ $exit_code -ne 0 ]]; then
        echo "Expected exit code 0, got $exit_code"
        return 1
    fi
    
    # Check that 4 tasks were created
    local task_count
    task_count=$(echo "$stdout_output" | jq '.tasks | length')
    if [[ "$task_count" -ne 4 ]]; then
        echo "Expected 4 tasks, got $task_count"
        return 1
    fi
    
    # Verify task IDs are present
    if ! echo "$stdout_output" | jq -e '.tasks[0].id' >/dev/null 2>&1; then
        echo "Missing task IDs in output"
        return 1
    fi
    
    return 0
}

# Test: Reject invalid JSON input
test_json_validation() {
    local output
    local exit_code=0
    
    # Test invalid JSON format
    output=$("$CREATE_TASKS_SCRIPT" "$TEST_DIR/invalid-json.json" 2>&1) || exit_code=$?
    
    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1 for invalid JSON, got $exit_code"
        return 1
    fi
    
    if [[ ! "$output" == *"Invalid JSON"* ]]; then
        echo "Missing 'Invalid JSON' error message"
        return 1
    fi
    
    # Test missing feature_id
    exit_code=0
    output=$("$CREATE_TASKS_SCRIPT" "$TEST_DIR/missing-feature.json" 2>&1) || exit_code=$?
    
    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1 for missing feature_id, got $exit_code"
        return 1
    fi
    
    if [[ ! "$output" == *"feature_id"* ]]; then
        echo "Missing feature_id error message"
        return 1
    fi
    
    # Test empty tasks array
    exit_code=0
    output=$("$CREATE_TASKS_SCRIPT" "$TEST_DIR/empty-tasks.json" 2>&1) || exit_code=$?
    
    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1 for empty tasks, got $exit_code"
        return 1
    fi
    
    return 0
}

# Test: Progress output format
test_progress_output() {
    local stderr_output
    local exit_code=0
    
    stderr_output=$("$CREATE_TASKS_SCRIPT" "$TEST_DIR/valid-tasks.json" 2>&1 >/dev/null) || exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        echo "Script failed with exit code $exit_code"
        return 1
    fi
    
    # Check for progress format [X/Y]
    if ! echo "$stderr_output" | grep -q '\[.*[0-9]\+/[0-9]\+.*\]'; then
        echo "Progress format [X/Y] not found in output"
        return 1
    fi
    
    # Check for "Phase 1" message
    if [[ ! "$stderr_output" == *"Phase 1"* ]]; then
        echo "Missing 'Phase 1' progress message"
        return 1
    fi
    
    # Check for "Phase 2" message
    if [[ ! "$stderr_output" == *"Phase 2"* ]]; then
        echo "Missing 'Phase 2' progress message"
        return 1
    fi
    
    # Check for "Complete!" message
    if [[ ! "$stderr_output" == *"Complete!"* ]]; then
        echo "Missing 'Complete!' progress message"
        return 1
    fi
    
    # Check for Created messages
    if [[ ! "$stderr_output" == *"Created:"* ]]; then
        echo "Missing 'Created:' messages"
        return 1
    fi
    
    return 0
}

# Test: Missing required fields
test_missing_required_fields() {
    # Create a JSON missing tasks field
    cat > "$TEST_DIR/missing-tasks.json" << 'EOF'
{
  "feature_id": "feat-test"
}
EOF
    
    local output
    local exit_code=0
    
    output=$("$CREATE_TASKS_SCRIPT" "$TEST_DIR/missing-tasks.json" 2>&1) || exit_code=$?
    
    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1 for missing tasks field, got $exit_code"
        return 1
    fi
    
    if [[ ! "$output" == *"tasks"* ]]; then
        echo "Missing tasks field error message"
        return 1
    fi
    
    # Create a JSON with non-array tasks
    cat > "$TEST_DIR/bad-tasks-type.json" << 'EOF'
{
  "feature_id": "feat-test",
  "tasks": "not-an-array"
}
EOF
    
    exit_code=0
    output=$("$CREATE_TASKS_SCRIPT" "$TEST_DIR/bad-tasks-type.json" 2>&1) || exit_code=$?
    
    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1 for non-array tasks, got $exit_code"
        return 1
    fi
    
    if [[ ! "$output" == *"array"* ]]; then
        echo "Missing array validation error message"
        return 1
    fi
    
    return 0
}

# Test: Usage message
test_usage_message() {
    local output
    local exit_code=0
    
    output=$("$CREATE_TASKS_SCRIPT" 2>&1) || exit_code=$?
    
    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1 for missing argument, got $exit_code"
        return 1
    fi
    
    if [[ ! "$output" == *"Usage:"* ]]; then
        echo "Missing Usage message"
        return 1
    fi
    
    return 0
}

# Main test runner
main() {
    echo -e "${BLUE}=== Create Tasks Test Suite ===${NC}"
    echo ""
    
    # Check prerequisites
    if [[ ! -f "$CREATE_TASKS_SCRIPT" ]]; then
        echo -e "${RED}ERROR: create-tasks.sh not found at $CREATE_TASKS_SCRIPT${NC}"
        exit 1
    fi
    
    if ! command -v jq &>/dev/null; then
        echo -e "${RED}ERROR: jq is required for testing${NC}"
        exit 1
    fi
    
    echo "Running tests..."
    echo ""
    
    # Run all tests
    run_test "Happy path: Create 5 tasks successfully" test_happy_path
    run_test "Idempotency: Skip existing tasks" test_idempotency
    run_test "Error handling: Stop on first failure" test_error_handling
    run_test "Dependency linking: Link deps correctly" test_dependency_linking
    run_test "JSON validation: Reject invalid input" test_json_validation
    run_test "Progress output: Verify format" test_progress_output
    run_test "Missing required fields validation" test_missing_required_fields
    run_test "Usage message displayed correctly" test_usage_message
    
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

# Handle signals
trap cleanup_test_env EXIT

# Run main
main "$@"
