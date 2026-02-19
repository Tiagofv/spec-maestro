#!/usr/bin/env bash
# Helper functions for bd operations
# Source this file: source .maestro/scripts/bd-helpers.sh

set -euo pipefail

# Check if bd is available
bd_check() {
  if ! command -v bd &>/dev/null; then
    echo "{\"error\":\"bd CLI not found\"}" >&2
    return 1
  fi
  return 0
}

# Create epic and return ID
# Usage: bd_create_epic "Title" "Description"
bd_create_epic() {
  local title="$1"
  local desc="${2:-}"
  bd create --title="$title" --type=epic --priority=2 ${desc:+--description="$desc"} --json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4
}

# Create task under epic
# Usage: bd_create_task "Title" "Description" "label" estimate_minutes epic_id assignee
bd_create_task() {
  local title="$1"
  local desc="$2"
  local label="$3"
  local estimate="$4"
  local epic_id="$5"
  local assignee="${6:-general}"

  bd create \
    --title="$title" \
    --type=task \
    --priority=2 \
    --labels="$label" \
    --estimate="$estimate" \
    --assignee="$assignee" \
    --description="$desc" \
    --parent="$epic_id" \
    --json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4
}

# Add dependency between tasks
# Usage: bd_add_dep dependent_id blocker_id
bd_add_dep() {
  local dependent="$1"
  local blocker="$2"
  bd dep add "$dependent" "$blocker" 2>/dev/null || true
}

# Get ready tasks as JSON
bd_ready_json() {
  bd ready --json 2>/dev/null || echo "[]"
}

# Close task with structured reason
# Usage: bd_close task_id "VERDICT | key: value"
bd_close() {
  local task_id="$1"
  local reason="$2"
  bd close "$task_id" --reason "$reason" 2>/dev/null
}
