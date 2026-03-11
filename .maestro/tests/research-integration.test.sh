#!/usr/bin/env bash
# Integration Tests for Research CLI
# Tests the complete research workflow end-to-end

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAESTRO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="$MAESTRO_ROOT/.maestro/tests/tmp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Setup test environment
setup() {
    echo "Setting up test environment..."
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
    mkdir -p "$MAESTRO_ROOT/.maestro/state/research"
    mkdir -p "$MAESTRO_ROOT/.maestro/research"
}

# Cleanup test environment
teardown() {
    echo "Cleaning up..."
    rm -rf "$TEST_DIR"
}

# Test helper functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
        ((TESTS_FAILED++))
    fi
}

assert_file_exists() {
    local file="$1"
    local test_name="$2"
    
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  File not found: $file"
        ((TESTS_FAILED++))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    
    if echo "$haystack" | grep -q "$needle"; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected to contain: $needle"
        ((TESTS_FAILED++))
    fi
}

# Test 1: Research State Manager - Create
test_research_state_create() {
    echo -e "\n${YELLOW}Test 1: Research State Manager - Create${NC}"
    
    local research_id="20250311-test-research"
    local result
    
    result=$(bash "$MAESTRO_ROOT/.maestro/scripts/research-state.sh" create \
        "$research_id" \
        "Test Research Title" \
        "Test research query" \
        "external" \
        ".maestro/research/$research_id.md" 2>&1)
    
    assert_equals "0" "$?" "Create command returns success"
    assert_file_exists "$MAESTRO_ROOT/.maestro/state/research/$research_id.json" \
        "State file created"
    assert_contains "$result" "Created:" "Output confirms creation"
}

# Test 2: Research State Manager - Link to Feature
test_research_state_link() {
    echo -e "\n${YELLOW}Test 2: Research State Manager - Link${NC}"
    
    local research_id="20250311-test-research"
    local feature_id="test-feature-001"
    local result
    
    result=$(bash "$MAESTRO_ROOT/.maestro/scripts/research-state.sh" link \
        "$research_id" \
        "$feature_id" 2>&1)
    
    assert_equals "0" "$?" "Link command returns success"
    assert_contains "$result" "Linked" "Output confirms linking"
    
    # Verify feature is in linked_features
    local linked
    linked=$(jq -r '.linked_features | contains(["'$feature_id'"])' \
        "$MAESTRO_ROOT/.maestro/state/research/$research_id.json")
    assert_equals "true" "$linked" "Feature ID in linked_features"
}

# Test 3: Research State Manager - List
test_research_state_list() {
    echo -e "\n${YELLOW}Test 3: Research State Manager - List${NC}"
    
    local result
    result=$(bash "$MAESTRO_ROOT/.maestro/scripts/research-state.sh" list 2>&1)
    
    assert_equals "0" "$?" "List command returns success"
    assert_contains "$result" "20250311-test-research" "List includes test research"
    assert_contains "$result" "external" "List shows source type"
}

# Test 4: Research State Manager - Search
test_research_state_search() {
    echo -e "\n${YELLOW}Test 4: Research State Manager - Search${NC}"
    
    local result
    result=$(bash "$MAESTRO_ROOT/.maestro/scripts/research-state.sh" search "test" 2>&1)
    
    assert_equals "0" "$?" "Search command returns success"
    assert_contains "$result" "Found:" "Search shows results count"
}

# Test 5: Research State Manager - Get
test_research_state_get() {
    echo -e "\n${YELLOW}Test 5: Research State Manager - Get${NC}"
    
    local research_id="20250311-test-research"
    local result
    result=$(bash "$MAESTRO_ROOT/.maestro/scripts/research-state.sh" get "$research_id" 2>&1)
    
    assert_equals "0" "$?" "Get command returns success"
    assert_contains "$result" '"research_id"' "JSON contains research_id"
    assert_contains "$result" '"title"' "JSON contains title"
}

# Test 6: Research Agents Directory Structure
test_research_agents_structure() {
    echo -e "\n${YELLOW}Test 6: Research Agents Directory Structure${NC}"
    
    assert_file_exists "$MAESTRO_ROOT/.maestro/agents/research/README.md" \
        "README exists"
    assert_file_exists "$MAESTRO_ROOT/.maestro/agents/research/technology-agent.md" \
        "Technology agent exists"
    assert_file_exists "$MAESTRO_ROOT/.maestro/agents/research/pattern-agent.md" \
        "Pattern agent exists"
    assert_file_exists "$MAESTRO_ROOT/.maestro/agents/research/pitfall-agent.md" \
        "Pitfall agent exists"
    assert_file_exists "$MAESTRO_ROOT/.maestro/agents/research/best-practices-agent.md" \
        "Best practices agent exists"
}

# Test 7: Research Commands - List Command
test_research_list_command() {
    echo -e "\n${YELLOW}Test 7: Research List Command${NC}"
    
    assert_file_exists "$MAESTRO_ROOT/.maestro/commands/maestro.research.list.md" \
        "List command file exists"
}

# Test 8: Research Commands - Search Command
test_research_search_command() {
    echo -e "\n${YELLOW}Test 8: Research Search Command${NC}"
    
    assert_file_exists "$MAESTRO_ROOT/.maestro/commands/maestro.research.search.md" \
        "Search command file exists"
}

# Test 9: Spec Template - Research Section
test_spec_template_research_section() {
    echo -e "\n${YELLOW}Test 9: Spec Template Research Section${NC}"
    
    local template_content
    template_content=$(cat "$MAESTRO_ROOT/.maestro/templates/spec-template.md")
    
    assert_contains "$template_content" "## 6. Research" \
        "Template has Research section"
    assert_contains "$template_content" "Linked Research Items" \
        "Template has linked research placeholder"
}

# Test 10: Specify Command - Research Integration
test_specify_research_integration() {
    echo -e "\n${YELLOW}Test 10: Specify Command Research Integration${NC}"
    
    local command_content
    command_content=$(cat "$MAESTRO_ROOT/.maestro/commands/maestro.specify.md")
    
    assert_contains "$command_content" "Parse Research References" \
        "Specify command parses research refs"
    assert_contains "$command_content" "Load Research Context" \
        "Specify command loads research context"
}

# Test 11: Plan Command - Research Integration
test_plan_research_integration() {
    echo -e "\n${YELLOW}Test 11: Plan Command Research Integration${NC}"
    
    local command_content
    command_content=$(cat "$MAESTRO_ROOT/.maestro/commands/maestro.plan.md")
    
    assert_contains "$command_content" "Load Research Findings" \
        "Plan command loads research findings"
    assert_contains "$command_content" "Research-Informed Context" \
        "Plan command uses research context"
}

# Test 12: Research Command - Parallel Orchestration
test_research_parallel_orchestration() {
    echo -e "\n${YELLOW}Test 12: Research Command Parallel Orchestration${NC}"
    
    local command_content
    command_content=$(cat "$MAESTRO_ROOT/.maestro/commands/maestro.research.md")
    
    assert_contains "$command_content" "Detect Query Complexity" \
        "Research command detects complexity"
    assert_contains "$command_content" "parallel agent orchestration" \
        "Research command supports parallel execution"
    assert_contains "$command_content" "4 agents" \
        "Research command uses 4 agents"
}

# Run all tests
run_all_tests() {
    echo "========================================"
    echo "Research CLI Integration Tests"
    echo "========================================"
    
    setup
    
    test_research_state_create
    test_research_state_link
    test_research_state_list
    test_research_state_search
    test_research_state_get
    test_research_agents_structure
    test_research_list_command
    test_research_search_command
    test_spec_template_research_section
    test_specify_research_integration
    test_plan_research_integration
    test_research_parallel_orchestration
    
    teardown
    
    echo -e "\n========================================"
    echo "Test Results"
    echo "========================================"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo "Total: $((TESTS_PASSED + TESTS_FAILED))"
    echo "========================================"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run tests
run_all_tests
