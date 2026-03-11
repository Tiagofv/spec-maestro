#!/usr/bin/env bash
# Research State Manager
# Provides CRUD operations for research state files
# Usage: research-state.sh <command> [args]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAESTRO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="$MAESTRO_ROOT/.maestro/state/research"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Function to generate research ID from query
generate_research_id() {
    local query="$1"
    local date_prefix=$(date +%Y%m%d)
    local slug=$(echo "$query" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-40)
    echo "${date_prefix}-${slug}"
}

# Function to create new research state
cmd_create() {
    local research_id="${1:-}"
    local title="${2:-}"
    local query="${3:-}"
    local source_type="${4:-}"
    local file_path="${5:-}"
    
    if [[ -z "$research_id" ]]; then
        echo "Error: research_id is required" >&2
        return 1
    fi
    
    local state_file="$STATE_DIR/${research_id}.json"
    
    if [[ -f "$state_file" ]]; then
        echo "Error: Research state already exists: $state_file" >&2
        return 1
    fi
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat > "$state_file" << EOF
{
  "research_id": "$research_id",
  "title": "$title",
  "query": "$query",
  "source_type": "$source_type",
  "created_at": "$timestamp",
  "updated_at": "$timestamp",
  "file_path": "$file_path",
  "tags": [],
  "linked_features": [],
  "agents_used": [],
  "status": "completed",
  "history": [
    {
      "action": "created",
      "timestamp": "$timestamp"
    }
  ]
}
EOF
    
    echo "Created: $state_file"
    return 0
}

# Function to link research to feature
cmd_link() {
    local research_id="${1:-}"
    local feature_id="${2:-}"
    
    if [[ -z "$research_id" || -z "$feature_id" ]]; then
        echo "Error: research_id and feature_id are required" >&2
        return 1
    fi
    
    local state_file="$STATE_DIR/${research_id}.json"
    
    if [[ ! -f "$state_file" ]]; then
        echo "Error: Research not found: $research_id" >&2
        return 1
    fi
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Update the state file
    local temp_file=$(mktemp)
    jq --arg feature "$feature_id" --arg ts "$timestamp" '
        if (.linked_features | contains([$feature])) then
            .  # Already linked, no change
        else
            .linked_features += [$feature] |
            .updated_at = $ts |
            .history += [{"action": "linked", "timestamp": $ts, "details": {"feature_id": $feature}}]
        end
    ' "$state_file" > "$temp_file"
    
    mv "$temp_file" "$state_file"
    echo "Linked $research_id to $feature_id"
    return 0
}

# Function to list research items
cmd_list() {
    local filter_type="${1:-}"
    local filter_tag="${2:-}"
    
    local count=0
    
    echo "Research Items:"
    echo "==============="
    
    for state_file in "$STATE_DIR"/*.json; do
        [[ -f "$state_file" ]] || continue
        
        local research_id=$(jq -r '.research_id' "$state_file" 2>/dev/null)
        local title=$(jq -r '.title' "$state_file" 2>/dev/null)
        local source_type=$(jq -r '.source_type' "$state_file" 2>/dev/null)
        local created_at=$(jq -r '.created_at' "$state_file" 2>/dev/null | cut -d'T' -f1)
        local linked_count=$(jq '.linked_features | length' "$state_file" 2>/dev/null)
        
        # Apply filters
        if [[ -n "$filter_type" && "$source_type" != "$filter_type" ]]; then
            continue
        fi
        
        if [[ -n "$filter_tag" ]]; then
            local has_tag=$(jq --arg tag "$filter_tag" '.tags | contains([$tag])' "$state_file" 2>/dev/null)
            [[ "$has_tag" == "true" ]] || continue
        fi
        
        echo ""
        echo "$research_id"
        echo "  Title: $title"
        echo "  Type: $source_type"
        echo "  Created: $created_at"
        echo "  Linked Features: $linked_count"
        
        ((count++))
    done
    
    echo ""
    echo "Total: $count research items"
    return 0
}

# Function to search research items
cmd_search() {
    local query="${1:-}"
    
    if [[ -z "$query" ]]; then
        echo "Error: search query is required" >&2
        return 1
    fi
    
    local query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')
    local count=0
    
    echo "Search Results for \"$query\":"
    echo "================================"
    
    for state_file in "$STATE_DIR"/*.json; do
        [[ -f "$state_file" ]] || continue
        
        local research_id=$(jq -r '.research_id' "$state_file" 2>/dev/null)
        local title=$(jq -r '.title' "$state_file" 2>/dev/null)
        local source_type=$(jq -r '.source_type' "$state_file" 2>/dev/null)
        
        # Check for matches (case-insensitive)
        local match_found=false
        
        # Title match (highest priority)
        if echo "$title" | grep -qi "$query_lower"; then
            match_found=true
        fi
        
        # Query match
        if ! $match_found; then
            local research_query=$(jq -r '.query' "$state_file" 2>/dev/null)
            if echo "$research_query" | grep -qi "$query_lower"; then
                match_found=true
            fi
        fi
        
        # Tag match
        if ! $match_found; then
            local tags=$(jq -r '.tags | join(" ")' "$state_file" 2>/dev/null)
            if echo "$tags" | grep -qi "$query_lower"; then
                match_found=true
            fi
        fi
        
        if $match_found; then
            echo ""
            echo "$research_id"
            echo "  Title: $title"
            echo "  Type: $source_type"
            ((count++))
        fi
    done
    
    echo ""
    echo "Found: $count matches"
    return 0
}

# Function to get research state
cmd_get() {
    local research_id="${1:-}"
    
    if [[ -z "$research_id" ]]; then
        echo "Error: research_id is required" >&2
        return 1
    fi
    
    local state_file="$STATE_DIR/${research_id}.json"
    
    if [[ ! -f "$state_file" ]]; then
        echo "Error: Research not found: $research_id" >&2
        return 1
    fi
    
    cat "$state_file"
    return 0
}

# Function to add tags
cmd_add_tag() {
    local research_id="${1:-}"
    local tag="${2:-}"
    
    if [[ -z "$research_id" || -z "$tag" ]]; then
        echo "Error: research_id and tag are required" >&2
        return 1
    fi
    
    local state_file="$STATE_DIR/${research_id}.json"
    
    if [[ ! -f "$state_file" ]]; then
        echo "Error: Research not found: $research_id" >&2
        return 1
    fi
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local temp_file=$(mktemp)
    jq --arg tag "$tag" --arg ts "$timestamp" '
        if (.tags | contains([$tag])) then
            .
        else
            .tags += [$tag] |
            .updated_at = $ts
        end
    ' "$state_file" > "$temp_file"
    
    mv "$temp_file" "$state_file"
    echo "Added tag '$tag' to $research_id"
    return 0
}

# Main command dispatcher
case "${1:-}" in
    create)
        shift
        cmd_create "$@"
        ;;
    link)
        shift
        cmd_link "$@"
        ;;
    list)
        shift
        cmd_list "$@"
        ;;
    search)
        shift
        cmd_search "$@"
        ;;
    get)
        shift
        cmd_get "$@"
        ;;
    add-tag)
        shift
        cmd_add_tag "$@"
        ;;
    *)
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  create <research_id> <title> <query> <source_type> <file_path>  Create new research state"
        echo "  link <research_id> <feature_id>                                 Link research to feature"
        echo "  list [type] [tag]                                               List research items"
        echo "  search <query>                                                  Search research items"
        echo "  get <research_id>                                               Get research state JSON"
        echo "  add-tag <research_id> <tag>                                     Add tag to research"
        echo ""
        exit 1
        ;;
esac
