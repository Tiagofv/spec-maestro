#!/usr/bin/env bash
# Create tasks from JSON input with idempotency and dependency linking
# Usage: create-tasks.sh <json-file-path>
# Outputs JSON result with created task IDs
# Exits with code 1 on first failure

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Progress counters
CURRENT=0
TOTAL=0

# Data storage using JSON file for cross-reference mapping
DATA_FILE=""

# Cleanup function
cleanup() {
    if [[ -n "$DATA_FILE" && -f "$DATA_FILE" ]]; then
        rm -f "$DATA_FILE"
    fi
}
trap cleanup EXIT

# Show progress to stderr
show_progress() {
    local current="$1"
    local total="$2"
    local message="${3:-}"
    printf "[%s%s/%s%s] %s\n" "$YELLOW" "$current" "$total" "$NC" "$message" >&2
}

# Error handler - exit with code 1
fail() {
    local message="$1"
    printf "%sERROR: %s%s\n" "$RED" "$message" "$NC" >&2
    exit 1
}

# Check if bd is available
check_bd() {
    if ! command -v bd &>/dev/null; then
        fail "bd CLI not found. Please install beads."
    fi
}

# Validate JSON structure
validate_json() {
    local json_file="$1"
    
    if [[ ! -f "$json_file" ]]; then
        fail "JSON file not found: $json_file"
    fi
    
    # Check if valid JSON
    if ! jq empty "$json_file" 2>/dev/null; then
        fail "Invalid JSON format in file: $json_file"
    fi
    
    # Check required fields
    if ! jq -e '.feature_id' "$json_file" &>/dev/null; then
        fail "Missing required field: feature_id"
    fi
    
    if ! jq -e '.tasks' "$json_file" &>/dev/null; then
        fail "Missing required field: tasks"
    fi
    
    if ! jq -e '.tasks | arrays' "$json_file" &>/dev/null; then
        fail "Field 'tasks' must be an array"
    fi
    
    local task_count
    task_count=$(jq '.tasks | length' "$json_file")
    if [[ "$task_count" -eq 0 ]]; then
        fail "Tasks array is empty"
    fi
}

# Initialize data storage
init_data() {
    DATA_FILE=$(mktemp)
    echo '{"tasks":{}}' > "$DATA_FILE"
}

# Store task data
store_task() {
    local ref_id="$1"
    local task_id="$2"
    local title="$3"
    local deps="$4"
    
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg ref "$ref_id" --arg id "$task_id" --arg title "$title" --arg deps "$deps" \
        '.tasks[$ref] = {"id": $id, "title": $title, "dependencies": ($deps | fromjson)}' \
        "$DATA_FILE" > "$tmp_file" && mv "$tmp_file" "$DATA_FILE"
}

# Get task ID by reference
get_task_id() {
    local ref_id="$1"
    jq -r --arg ref "$ref_id" '.tasks[$ref].id // empty' "$DATA_FILE"
}

# Get task dependencies by reference
get_task_deps() {
    local ref_id="$1"
    jq --arg ref "$ref_id" '.tasks[$ref].dependencies // []' "$DATA_FILE"
}

# Query existing task by title + epic
query_existing_task() {
    local title="$1"
    local epic_id="$2"
    
    # Search for task with matching title under the epic
    bd list --parent "$epic_id" --json 2>/dev/null | \
        jq -r --arg title "$title" '.[] | select(.title == $title) | .id' 2>/dev/null | head -1 || echo ""
}

# Create a task and return its ID
create_task() {
    local title="$1"
    local description="$2"
    local label="$3"
    local estimate="$4"
    local epic_id="$5"
    local assignee="${6:-general}"
    
    local task_id
    task_id=$(bd create \
        --title="$title" \
        --type=task \
        --priority=2 \
        --labels="$label" \
        --estimate="$estimate" \
        --assignee="$assignee" \
        --description="$description" \
        --parent="$epic_id" \
        --json 2>/dev/null | \
        jq -r '.id' 2>/dev/null) || true
    
    if [[ -z "$task_id" ]]; then
        fail "Failed to create task: $title"
    fi
    
    echo "$task_id"
}

# Add dependency between tasks (idempotent - ignores if already exists)
add_dependency() {
    local dependent_id="$1"
    local blocker_id="$2"
    
    # Try to add dependency, but don't fail if it already exists
    bd dep add "$dependent_id" "$blocker_id" 2>/dev/null || true
}

# Phase 1: Create all tasks
phase1_create_tasks() {
    local json_file="$1"
    local epic_id
    epic_id=$(jq -r '.feature_id' "$json_file")
    
    TOTAL=$(jq '.tasks | length' "$json_file")
    CURRENT=0
    
    show_progress "0" "$TOTAL" "Phase 1: Creating tasks..."
    
    local i=0
    while [[ $i -lt $TOTAL ]]; do
        local task
        task=$(jq -c ".tasks[$i]" "$json_file")
        
        local title
        title=$(echo "$task" | jq -r '.title')
        local description
        description=$(echo "$task" | jq -r '.description // ""')
        local label
        label=$(echo "$task" | jq -r '.label // "general"')
        local size
        size=$(echo "$task" | jq -r '.size // "S"')
        local assignee
        assignee=$(echo "$task" | jq -r '.assignee // "general"')
        local task_ref_id
        task_ref_id=$(echo "$task" | jq -r '.id // ""')
        local dependencies
        dependencies=$(echo "$task" | jq -c '.dependencies // []')
        
        # Check for existing task
        local existing_id
        existing_id=$(query_existing_task "$title" "$epic_id")
        
        if [[ -n "$existing_id" ]]; then
            store_task "$task_ref_id" "$existing_id" "$title" "$dependencies"
            CURRENT=$((CURRENT + 1))
            show_progress "$CURRENT" "$TOTAL" "Skipped: $existing_id - Task already exists"
        else
            # Map size to minutes
            local estimate
            case "$size" in
                XS) estimate=120 ;;
                S) estimate=360 ;;
                M) estimate=720 ;;
                L) estimate=1200 ;;
                *) estimate=360 ;;
            esac
            
            # Create task
            local new_id
            new_id=$(create_task "$title" "$description" "$label" "$estimate" "$epic_id" "$assignee")
            
            store_task "$task_ref_id" "$new_id" "$title" "$dependencies"
            
            CURRENT=$((CURRENT + 1))
            show_progress "$CURRENT" "$TOTAL" "Created: $title ($new_id)"
        fi
        
        i=$((i + 1))
    done
}

# Phase 2: Link dependencies
phase2_link_dependencies() {
    local json_file="$1"
    local epic_id
    epic_id=$(jq -r '.feature_id' "$json_file")
    
    show_progress "0" "$TOTAL" "Phase 2: Linking dependencies..."
    
    local linked_count=0
    local i=0
    while [[ $i -lt $TOTAL ]]; do
        local task_ref_id
        task_ref_id=$(jq -r ".tasks[$i].id // \"\"" "$json_file")
        
        local dependent_id
        dependent_id=$(get_task_id "$task_ref_id")
        
        local dependencies
        dependencies=$(get_task_deps "$task_ref_id")
        
        if [[ -n "$dependent_id" && "$dependencies" != "[]" && "$dependencies" != "null" ]]; then
            local dep_count
            dep_count=$(echo "$dependencies" | jq 'length')
            local j=0
            while [[ $j -lt $dep_count ]]; do
                local dep_ref
                dep_ref=$(echo "$dependencies" | jq -r ".[$j]")
                local blocker_id
                blocker_id=$(get_task_id "$dep_ref")
                
                if [[ -n "$blocker_id" && "$blocker_id" != "$dependent_id" ]]; then
                    add_dependency "$dependent_id" "$blocker_id"
                    linked_count=$((linked_count + 1))
                fi
                
                j=$((j + 1))
            done
        fi
        
        i=$((i + 1))
    done
    
    show_progress "$TOTAL" "$TOTAL" "Linked $linked_count dependencies"
}

# Generate JSON output
generate_output() {
    local epic_id="$1"
    
    # Build result using jq
    jq --arg epic "$epic_id" '
        {
            feature_id: $epic,
            tasks: [
                .tasks | to_entries | .[] | {
                    ref_id: .key,
                    id: .value.id,
                    title: .value.title
                }
            ]
        }
    ' "$DATA_FILE"
}

# Main function
main() {
    if [[ $# -lt 1 ]]; then
        fail "Usage: create-tasks.sh <json-file-path>"
    fi
    
    local json_file="$1"
    
    check_bd
    validate_json "$json_file"
    init_data
    
    local epic_id
    epic_id=$(jq -r '.feature_id' "$json_file")
    
    phase1_create_tasks "$json_file"
    phase2_link_dependencies "$json_file"
    
    show_progress "$TOTAL" "$TOTAL" "Complete!"
    
    generate_output "$epic_id"
}

main "$@"
