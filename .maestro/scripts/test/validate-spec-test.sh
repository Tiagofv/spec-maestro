#!/usr/bin/env bash
# Test suite for validate-spec-format.sh
# Usage: ./validate-spec-test.sh

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
VALIDATOR_SCRIPT="$SCRIPT_DIR/../validate-spec-format.sh"

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

# Run validator and capture both exit code and output. Extra args (e.g.
# --strict) are forwarded to the validator.
run_validator() {
    local spec_file="$1"
    shift
    local temp_output=$(mktemp)
    local exit_code=0

    # Run validator, capturing all output
    "$VALIDATOR_SCRIPT" "$spec_file" "$@" > "$temp_output" 2>&1 || exit_code=$?

    # Output the result to stdout so tests can capture it
    cat "$temp_output"

    # Clean up
    rm -f "$temp_output"

    # Return the exit code
    return $exit_code
}

# Test: Valid EARS spec passes validation
test_valid_spec() {
    local output
    local exit_code=0

    output=$(run_validator "$FIXTURES_DIR/valid-spec-ears.md") || exit_code=$?

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

    return 0
}

# Test: Non-EARS criteria rejected
test_non_ears() {
    local output
    local exit_code=0

    output=$(run_validator "$FIXTURES_DIR/invalid-spec-non-ears.md") || exit_code=$?

    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1, got $exit_code"
        echo "Output: $output"
        return 1
    fi

    if [[ ! "$output" == *"not EARS-shaped"* ]]; then
        echo "Missing 'not EARS-shaped' error message"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# Test: Missing failure-path pairing rejected
test_missing_failure_paths() {
    local output
    local exit_code=0

    output=$(run_validator "$FIXTURES_DIR/invalid-spec-missing-failure-paths.md") || exit_code=$?

    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1, got $exit_code"
        echo "Output: $output"
        return 1
    fi

    if [[ ! "$output" == *"no matching If…then"* ]]; then
        echo "Missing 'no matching If…then' error message"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# Test: --strict promotes the zero-marker warning to a failure
test_strict_zero_markers() {
    local output
    local exit_code=0

    # Reuse the missing-failure fixture body but strip its marker via a temp copy
    # so the ONLY remaining trigger under --strict could be the zero-marker rule;
    # the non-ears fixture also fails, so for a clean strict-only signal we build
    # a tiny inline spec with valid EARS, a paired If…then, and zero markers.
    local tmp_spec
    tmp_spec=$(mktemp /tmp/strict-spec-XXXX.md)
    cat > "$tmp_spec" <<'EOF'
# Feature: Strict (no markers)

**Repos:** example-app

## 1. Problem Statement
Trivial.

## 2. Proposed Solution
Trivial.

## 3. User Stories

### Story 1: Save

**Acceptance Criteria (EARS):**

- [ ] When the user saves, the store shall persist the record.
- [ ] If the save fails, then the store shall report an error.
EOF

    output=$(run_validator "$tmp_spec" --strict) || exit_code=$?
    rm -f "$tmp_spec"

    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1 under --strict with zero markers, got $exit_code"
        echo "Output: $output"
        return 1
    fi

    if [[ ! "$output" == *"zero [NEEDS CLARIFICATION]"* ]]; then
        echo "Missing zero-marker strict-failure message"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# Test: Solution-leakage criteria rejected (rule G)
test_solution_leakage() {
    local output
    local exit_code=0

    output=$(run_validator "$FIXTURES_DIR/invalid-spec-solution-leakage.md") || exit_code=$?

    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1, got $exit_code"
        echo "Output: $output"
        return 1
    fi

    if [[ ! "$output" == *"names implementation detail"* ]]; then
        echo "Missing 'names implementation detail' error message"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# Test: Implementation-neutral spec passes the leakage check (rule G no false-fire)
test_solution_leakage_passes() {
    local output
    local exit_code=0

    output=$(run_validator "$FIXTURES_DIR/valid-spec-ears.md") || exit_code=$?

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

    if [[ ! "$output" == *"No spec.md file path provided"* ]]; then
        echo "Missing 'No spec.md file path provided' error message"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# Test: Non-existent file
test_nonexistent_file() {
    local output
    local exit_code=0

    output=$(run_validator "/nonexistent/path/spec.md") || exit_code=$?

    if [[ $exit_code -ne 1 ]]; then
        echo "Expected exit code 1, got $exit_code"
        echo "Output: $output"
        return 1
    fi

    if [[ ! "$output" == *"File not found"* ]]; then
        echo "Missing 'File not found' error message"
        echo "Output: $output"
        return 1
    fi

    return 0
}

# Main test runner
main() {
    echo -e "${BLUE}=== Validate Spec Format Test Suite ===${NC}"
    echo ""

    # Check prerequisites
    if [[ ! -f "$VALIDATOR_SCRIPT" ]]; then
        echo -e "${RED}ERROR: validate-spec-format.sh not found at $VALIDATOR_SCRIPT${NC}"
        exit 1
    fi

    if ! command -v perl &>/dev/null; then
        echo -e "${RED}ERROR: perl is required for testing${NC}"
        exit 1
    fi

    echo "Running tests..."
    echo ""

    # Run all tests
    run_test "Valid EARS spec passes validation" test_valid_spec
    run_test "Non-EARS criteria rejected" test_non_ears
    run_test "Missing failure-path pairing rejected" test_missing_failure_paths
    run_test "Zero markers under --strict rejected" test_strict_zero_markers
    run_test "Solution-leakage criteria rejected" test_solution_leakage
    run_test "Implementation-neutral spec passes leakage check" test_solution_leakage_passes
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
