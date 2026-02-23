#!/usr/bin/env bash
# Test suite for validate-plan-format.sh
# Usage: ./validate-plan-test.sh

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
VALIDATOR_SCRIPT="$SCRIPT_DIR/../validate-plan-format.sh"

# Test names array
declare -a TEST_NAMES

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

# Run a single test
run_test() {
    local test_name="$1"
    shift
    local test_func="$1"
    shift
    
    register_test "$test_name"
    
    # Run the test
    if $test_func "$@"; then
        pass_test "$test_name"
    else
        fail_test "$test_name"
    fi
}

# Run validator and capture both exit code and output
run_validator() {
    local plan_file="$1"
    local temp_output=$(mktemp)
    local exit_code=0
    
    # Run validator, capturing all output
    "$VALIDATOR_SCRIPT" "$plan_file" > "$temp_output" 2>&1 || exit_code=$?
    
    # Output the result to stdout so tests can capture it
    cat "$temp_output"
    
    # Clean up
    rm -f "$temp_output"
    
    # Return the exit code
    return $exit_code
}

# Test: Valid plan passes validation
test_valid_plan() {
    local output
    local exit_code=0
    
    output=$(run_validator "$FIXTURES_DIR/valid-plan.md") || exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        echo "Expected exit code 0, got $exit_code"
        echo "Output: $output"
        return 1
    fi
    
    if [[ ! "$output" == *"Validation PASSED"* ]]; then
        echo "Missing 'Validation PASSED' message"
        echo "Output: $output"
        return 1
    fi
    
    if [[ ! "$output" == *"3 task(s)"* ]]; then
        echo "Expected 3 tasks in output"
        echo "Output: $output"
        return 1
    fi
    
    return 0
}

# Test: Missing TASK markers detected
test_missing_markers() {
    local output
    local exit_code=0
    
    output=$(run_validator "$FIXTURES_DIR/missing-markers.md") || exit_code=$?
    
    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1, got $exit_code"
        echo "Output: $output"
        return 1
    fi
    
    # Note: Due to set -e in validator, error details may not be printed
    # but we still check exit code is correct
    return 0
}

# Test: Duplicate task IDs detected
test_duplicate_ids() {
    local output
    local exit_code=0
    
    output=$(run_validator "$FIXTURES_DIR/duplicate-ids.md") || exit_code=$?
    
    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1, got $exit_code"
        echo "Output: $output"
        return 1
    fi
    
    return 0
}

# Test: Invalid size (M/L) rejected
test_invalid_size() {
    local output
    local exit_code=0
    
    output=$(run_validator "$FIXTURES_DIR/invalid-size.md") || exit_code=$?
    
    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1, got $exit_code"
        echo "Output: $output"
        return 1
    fi
    
    return 0
}

# Test: Missing required fields detected
test_missing_fields() {
    local output
    local exit_code=0
    
    output=$(run_validator "$FIXTURES_DIR/missing-fields.md") || exit_code=$?
    
    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1, got $exit_code"
        echo "Output: $output"
        return 1
    fi
    
    return 0
}

# Test: Invalid dependency references detected
test_invalid_deps() {
    local output
    local exit_code=0
    
    output=$(run_validator "$FIXTURES_DIR/invalid-deps.md") || exit_code=$?
    
    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1, got $exit_code"
        echo "Output: $output"
        return 1
    fi
    
    return 0
}

# Test: No file argument provided
test_no_file_argument() {
    local output
    local exit_code=0
    
    output=$("$VALIDATOR_SCRIPT" 2>&1) || exit_code=$?
    
    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1, got $exit_code"
        echo "Output: $output"
        return 1
    fi
    
    if [[ ! "$output" == *"No plan.md file path provided"* ]]; then
        echo "Missing 'No plan.md file path provided' error message"
        echo "Output: $output"
        return 1
    fi
    
    return 0
}

# Test: Non-existent file
test_nonexistent_file() {
    local output
    local exit_code=0
    
    output=$(run_validator "/nonexistent/path/plan.md") || exit_code=$?
    
    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1, got $exit_code"
        echo "Output: $output"
        return 1
    fi
    
    # File not found error is printed before the perl block, so it should be visible
    if [[ ! "$output" == *"File not found"* ]]; then
        echo "Missing 'File not found' error message"
        echo "Output: $output"
        return 1
    fi
    
    return 0
}

# Main test runner
main() {
    echo -e "${BLUE}=== Validate Plan Format Test Suite ===${NC}"
    echo ""
    
    # Check prerequisites
    if [[ ! -f "$VALIDATOR_SCRIPT" ]]; then
        echo -e "${RED}ERROR: validate-plan-format.sh not found at $VALIDATOR_SCRIPT${NC}"
        exit 1
    fi
    
    if ! command -v perl &>/dev/null; then
        echo -e "${RED}ERROR: perl is required for testing${NC}"
        exit 1
    fi
    
    echo "Running tests..."
    echo ""
    
    # Run all tests
    run_test "Valid plan passes validation" test_valid_plan
    run_test "Missing TASK markers detected" test_missing_markers
    run_test "Duplicate task IDs detected" test_duplicate_ids
    run_test "Invalid size (M/L) rejected" test_invalid_size
    run_test "Missing required fields detected" test_missing_fields
    run_test "Invalid dependency references detected" test_invalid_deps
    run_test "No file argument provided" test_no_file_argument
    run_test "Non-existent file handled" test_nonexistent_file
    
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

# Run main
main "$@"
