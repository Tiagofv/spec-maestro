#!/usr/bin/env bash
# Test suite for list-features.sh
# Usage: ./test-list-features.sh

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
FIXTURES_DIR="$SCRIPT_DIR/fixtures/list-features"
LIST_FEATURES_SCRIPT="$SCRIPT_DIR/../list-features.sh"
TEST_DIR=""

# Test names array
declare -a TEST_NAMES

# Setup test environment — creates a temporary .maestro structure
# mirroring a real project with specs/ and state/ from fixtures.
setup_test_env() {
    TEST_DIR=$(mktemp -d)

    # Create .maestro structure
    mkdir -p "$TEST_DIR/.maestro/specs"
    mkdir -p "$TEST_DIR/.maestro/state"
    mkdir -p "$TEST_DIR/.maestro/scripts"

    # Copy spec directories from fixtures
    cp -r "$FIXTURES_DIR/specs/"* "$TEST_DIR/.maestro/specs/"

    # Copy state files from fixtures
    cp -r "$FIXTURES_DIR/state/"* "$TEST_DIR/.maestro/state/"

    # Symlink the list-features.sh script into the test .maestro/scripts
    # so that SCRIPT_DIR resolution finds the right .maestro root
    cp "$LIST_FEATURES_SCRIPT" "$TEST_DIR/.maestro/scripts/list-features.sh"
    chmod +x "$TEST_DIR/.maestro/scripts/list-features.sh"

    export TEST_DIR
}

# Cleanup test environment
cleanup_test_env() {
    if [[ -n "${TEST_DIR:-}" && -d "${TEST_DIR:-}" ]]; then
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
        fail_test "$test_name" "${FAIL_REASON:-}"
    fi

    # Cleanup
    cleanup_test_env
}

# Helper: run list-features.sh against the test environment
run_list_features() {
    bash "$TEST_DIR/.maestro/scripts/list-features.sh" "$@"
}

# ── Test: Correct feature count ─────────────────────────────────────
test_feature_count() {
    local output
    output=$(run_list_features 2>/dev/null)

    local count
    count=$(echo "$output" | jq 'length')

    if [[ "$count" -ne 5 ]]; then
        FAIL_REASON="Expected 5 features, got $count"
        return 1
    fi
    return 0
}

# ── Test: Specify stage with clarification markers ──────────────────
test_specify_stage() {
    local output
    output=$(run_list_features 2>/dev/null)

    # Find 001-basic-invoicing
    local feature
    feature=$(echo "$output" | jq '.[] | select(.feature_id == "001-basic-invoicing")')

    # Check stage
    local stage
    stage=$(echo "$feature" | jq -r '.stage')
    if [[ "$stage" != "specify" ]]; then
        FAIL_REASON="Expected stage 'specify', got '$stage'"
        return 1
    fi

    # Check clarification_count
    local cc
    cc=$(echo "$feature" | jq '.clarification_count')
    if [[ "$cc" -ne 3 ]]; then
        FAIL_REASON="Expected clarification_count 3, got $cc"
        return 1
    fi

    # Check user_stories
    local us
    us=$(echo "$feature" | jq '.user_stories')
    if [[ "$us" -ne 4 ]]; then
        FAIL_REASON="Expected user_stories 4, got $us"
        return 1
    fi

    # With clarification_count > 0, next_action should be /maestro.clarify
    local next
    next=$(echo "$feature" | jq -r '.next_action')
    if [[ "$next" != "/maestro.clarify" ]]; then
        FAIL_REASON="Expected next_action '/maestro.clarify', got '$next'"
        return 1
    fi

    # has_state should be true
    local hs
    hs=$(echo "$feature" | jq '.has_state')
    if [[ "$hs" != "true" ]]; then
        FAIL_REASON="Expected has_state true, got $hs"
        return 1
    fi

    return 0
}

# ── Test: Complete stage with task count ─────────────────────────────
test_complete_stage() {
    local output
    output=$(run_list_features 2>/dev/null)

    local feature
    feature=$(echo "$output" | jq '.[] | select(.feature_id == "002-payment-reconciliation")')

    # Check stage
    local stage
    stage=$(echo "$feature" | jq -r '.stage')
    if [[ "$stage" != "complete" ]]; then
        FAIL_REASON="Expected stage 'complete', got '$stage'"
        return 1
    fi

    # Check task_count
    local tc
    tc=$(echo "$feature" | jq '.task_count')
    if [[ "$tc" -ne 15 ]]; then
        FAIL_REASON="Expected task_count 15, got $tc"
        return 1
    fi

    # Completed features should never be stalled
    local stalled
    stalled=$(echo "$feature" | jq '.is_stalled')
    if [[ "$stalled" != "false" ]]; then
        FAIL_REASON="Completed feature should not be stalled, got $stalled"
        return 1
    fi

    # Group should be "completed"
    local grp
    grp=$(echo "$feature" | jq -r '.group')
    if [[ "$grp" != "completed" ]]; then
        FAIL_REASON="Expected group 'completed', got '$grp'"
        return 1
    fi

    # Next action for complete is /maestro.analyze
    local next
    next=$(echo "$feature" | jq -r '.next_action')
    if [[ "$next" != "/maestro.analyze" ]]; then
        FAIL_REASON="Expected next_action '/maestro.analyze', got '$next'"
        return 1
    fi

    return 0
}

# ── Test: Orphan spec (no state file) ───────────────────────────────
test_orphan_spec() {
    local output
    output=$(run_list_features 2>/dev/null)

    local feature
    feature=$(echo "$output" | jq '.[] | select(.feature_id == "003-orphan-feature")')

    # has_state should be false
    local hs
    hs=$(echo "$feature" | jq '.has_state')
    if [[ "$hs" != "false" ]]; then
        FAIL_REASON="Expected has_state false for orphan, got $hs"
        return 1
    fi

    # Stage should be "no-state"
    local stage
    stage=$(echo "$feature" | jq -r '.stage')
    if [[ "$stage" != "no-state" ]]; then
        FAIL_REASON="Expected stage 'no-state', got '$stage'"
        return 1
    fi

    # Next action should be /maestro.specify
    local next
    next=$(echo "$feature" | jq -r '.next_action')
    if [[ "$next" != "/maestro.specify" ]]; then
        FAIL_REASON="Expected next_action '/maestro.specify', got '$next'"
        return 1
    fi

    # Orphans should not be stalled
    local stalled
    stalled=$(echo "$feature" | jq '.is_stalled')
    if [[ "$stalled" != "false" ]]; then
        FAIL_REASON="Orphan should not be stalled, got $stalled"
        return 1
    fi

    # Group should be "active"
    local grp
    grp=$(echo "$feature" | jq -r '.group')
    if [[ "$grp" != "active" ]]; then
        FAIL_REASON="Expected group 'active', got '$grp'"
        return 1
    fi

    return 0
}

# ── Test: Malformed JSON state file ─────────────────────────────────
test_malformed_state() {
    local output
    output=$(run_list_features 2>/dev/null)

    local feature
    feature=$(echo "$output" | jq '.[] | select(.feature_id == "004-malformed-state")')

    # Should be treated as no-state (malformed JSON fallback)
    local hs
    hs=$(echo "$feature" | jq '.has_state')
    if [[ "$hs" != "false" ]]; then
        FAIL_REASON="Expected has_state false for malformed, got $hs"
        return 1
    fi

    # Stage should be "no-state"
    local stage
    stage=$(echo "$feature" | jq -r '.stage')
    if [[ "$stage" != "no-state" ]]; then
        FAIL_REASON="Expected stage 'no-state', got '$stage'"
        return 1
    fi

    # Next action should be /maestro.specify
    local next
    next=$(echo "$feature" | jq -r '.next_action')
    if [[ "$next" != "/maestro.specify" ]]; then
        FAIL_REASON="Expected next_action '/maestro.specify', got '$next'"
        return 1
    fi

    return 0
}

# ── Test: Stalled detection (30 days old, in plan stage) ────────────
test_stalled_detection() {
    local output
    output=$(run_list_features 2>/dev/null)

    local feature
    feature=$(echo "$output" | jq '.[] | select(.feature_id == "005-stalled-feature")')

    # Should be marked as stalled (30 days > 14 day threshold)
    local stalled
    stalled=$(echo "$feature" | jq '.is_stalled')
    if [[ "$stalled" != "true" ]]; then
        FAIL_REASON="Expected is_stalled true for 30-day old feature, got $stalled"
        return 1
    fi

    # Days since update should be >= 28 (approximately 30, allowing drift)
    local days
    days=$(echo "$feature" | jq '.days_since_update')
    if [[ "$days" -lt 28 ]]; then
        FAIL_REASON="Expected days_since_update >= 28, got $days"
        return 1
    fi

    # Stage should be plan
    local stage
    stage=$(echo "$feature" | jq -r '.stage')
    if [[ "$stage" != "plan" ]]; then
        FAIL_REASON="Expected stage 'plan', got '$stage'"
        return 1
    fi

    # Next action for plan stage is /maestro.tasks
    local next
    next=$(echo "$feature" | jq -r '.next_action')
    if [[ "$next" != "/maestro.tasks" ]]; then
        FAIL_REASON="Expected next_action '/maestro.tasks', got '$next'"
        return 1
    fi

    # Group should be "active"
    local grp
    grp=$(echo "$feature" | jq -r '.group')
    if [[ "$grp" != "active" ]]; then
        FAIL_REASON="Expected group 'active', got '$grp'"
        return 1
    fi

    return 0
}

# ── Test: JSON output structure ─────────────────────────────────────
test_json_structure() {
    local output
    output=$(run_list_features 2>/dev/null)

    # Must be valid JSON array
    if ! echo "$output" | jq -e 'type == "array"' >/dev/null 2>&1; then
        FAIL_REASON="Output is not a JSON array"
        return 1
    fi

    # Every element must have all required fields
    local required_fields='["feature_id","numeric_id","title","stage","group","has_state","user_stories","task_count","is_stalled","days_since_update","next_action","next_action_reason"]'

    local missing
    missing=$(echo "$output" | jq --argjson req "$required_fields" '
        [.[] | . as $obj | $req[] | select($obj[.] == null)] | unique
    ')

    if [[ "$missing" != "[]" ]]; then
        FAIL_REASON="Missing required fields: $missing"
        return 1
    fi

    return 0
}

# ── Test: Sorting order (active first desc, then completed desc) ────
test_sorting_order() {
    local output
    output=$(run_list_features 2>/dev/null)

    # Active features should come before completed
    local first_completed_idx
    first_completed_idx=$(echo "$output" | jq '[.[] | .group] | to_entries | map(select(.value == "completed")) | .[0].key // -1')

    local last_active_idx
    last_active_idx=$(echo "$output" | jq '[.[] | .group] | to_entries | map(select(.value == "active")) | .[-1].key // -1')

    if [[ "$first_completed_idx" -ne -1 && "$last_active_idx" -ne -1 ]]; then
        if [[ "$last_active_idx" -ge "$first_completed_idx" ]]; then
            FAIL_REASON="Active features should come before completed (last_active=$last_active_idx, first_completed=$first_completed_idx)"
            return 1
        fi
    fi

    # Active features should be sorted by numeric_id descending
    local active_ids
    active_ids=$(echo "$output" | jq '[.[] | select(.group == "active") | .numeric_id]')
    local active_sorted
    active_sorted=$(echo "$active_ids" | jq 'sort_by(-.) == .')

    if [[ "$active_sorted" != "true" ]]; then
        FAIL_REASON="Active features not sorted by numeric_id descending: $active_ids"
        return 1
    fi

    return 0
}

# ── Test: --stage filter ────────────────────────────────────────────
test_stage_filter() {
    local output
    output=$(run_list_features --stage specify 2>/dev/null)

    local count
    count=$(echo "$output" | jq 'length')

    if [[ "$count" -ne 1 ]]; then
        FAIL_REASON="Expected 1 feature in 'specify' stage, got $count"
        return 1
    fi

    local fid
    fid=$(echo "$output" | jq -r '.[0].feature_id')
    if [[ "$fid" != "001-basic-invoicing" ]]; then
        FAIL_REASON="Expected 001-basic-invoicing, got $fid"
        return 1
    fi

    return 0
}

# ── Test: Empty specs directory ─────────────────────────────────────
test_empty_specs() {
    # Remove all spec directories
    rm -rf "$TEST_DIR/.maestro/specs/"*

    local output
    output=$(run_list_features 2>/dev/null)

    local count
    count=$(echo "$output" | jq 'length')

    if [[ "$count" -ne 0 ]]; then
        FAIL_REASON="Expected 0 features for empty specs, got $count"
        return 1
    fi

    return 0
}

# Main test runner
main() {
    echo -e "${BLUE}=== List Features Test Suite ===${NC}"
    echo ""

    # Check prerequisites
    if [[ ! -f "$LIST_FEATURES_SCRIPT" ]]; then
        echo -e "${RED}ERROR: list-features.sh not found at $LIST_FEATURES_SCRIPT${NC}"
        exit 1
    fi

    if ! command -v jq &>/dev/null; then
        echo -e "${RED}ERROR: jq is required for testing${NC}"
        exit 1
    fi

    echo "Running tests..."
    echo ""

    # Run all tests
    run_test "Feature count: discovers all 5 fixtures"           test_feature_count
    run_test "Specify stage: clarification markers + next action" test_specify_stage
    run_test "Complete stage: task count + group assignment"      test_complete_stage
    run_test "Orphan spec: no state file detected"               test_orphan_spec
    run_test "Malformed state: treated as no-state"              test_malformed_state
    run_test "Stalled detection: 30-day old feature flagged"     test_stalled_detection
    run_test "JSON structure: all required fields present"        test_json_structure
    run_test "Sorting order: active desc, then completed desc"   test_sorting_order
    run_test "Stage filter: --stage specify returns 1 result"    test_stage_filter
    run_test "Empty specs: returns empty array"                  test_empty_specs

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
