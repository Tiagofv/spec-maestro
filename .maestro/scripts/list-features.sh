#!/usr/bin/env bash
# List Features — Core Discovery and JSON Output
# Scans .maestro/specs/ for feature directories, merges with state from
# .maestro/state/{feature_id}.json, and outputs a JSON array to stdout.
#
# Usage: list-features.sh [--stage <stage>]
# Output: JSON array of feature objects to stdout; errors go to stderr.

set -euo pipefail

# ── Argument parsing ────────────────────────────────────────────────
VALID_STAGES=("specify" "clarify" "research" "plan" "tasks" "implement" "complete" "no-state")
FILTER_STAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage)
      if [[ $# -lt 2 ]]; then
        echo "Error: --stage requires a value. Valid stages: ${VALID_STAGES[*]}" >&2
        exit 1
      fi
      FILTER_STAGE="$2"
      # Validate stage value
      local_valid=false
      for valid in "${VALID_STAGES[@]}"; do
        if [[ "$FILTER_STAGE" == "$valid" ]]; then
          local_valid=true
          break
        fi
      done
      if [[ "$local_valid" == "false" ]]; then
        echo "Error: invalid stage '$FILTER_STAGE'. Valid stages: ${VALID_STAGES[*]}" >&2
        exit 1
      fi
      shift 2
      ;;
    *)
      echo "Error: unknown argument '$1'. Usage: list-features.sh [--stage <stage>]" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAESTRO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPECS_DIR="$MAESTRO_ROOT/.maestro/specs"
STATE_DIR="$MAESTRO_ROOT/.maestro/state"

# ── Dependency check ────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed"}' >&2
  exit 1
fi

# ── Helper: extract title from spec.md first line ───────────────────
# Expects "# Feature: <title>"; falls back to reformatted slug.
extract_title() {
  local spec_dir="$1"
  local feature_id="$2"
  local spec_file="$spec_dir/spec.md"

  if [[ -f "$spec_file" ]]; then
    local first_line
    first_line=$(head -1 "$spec_file" 2>/dev/null || true)
    # Strip the "# Feature: " prefix if present
    if [[ "$first_line" =~ ^#[[:space:]]+Feature:[[:space:]]+(.*) ]]; then
      echo "${BASH_REMATCH[1]}"
      return
    fi
  fi

  # Fallback: reformat slug — strip numeric prefix + dash, replace dashes with spaces, title-case
  local slug="${feature_id#[0-9]*-}"
  slug="${slug//-/ }"
  # Capitalize first letter
  echo "${slug^}"
}

# ── Helper: extract numeric_id from feature_id ──────────────────────
# feature_id format: NNN-slug-here  →  numeric_id: NNN (as integer)
extract_numeric_id() {
  local feature_id="$1"
  local prefix="${feature_id%%-*}"
  # Strip leading zeros and convert to integer; default to 0
  echo $(( 10#$prefix )) 2>/dev/null || echo 0
}

# ── Stalled detection constants ─────────────────────────────────────
STALLED_THRESHOLD_SECONDS=1209600  # 14 days

# ── Helper: compute stalled status ──────────────────────────────────
# Given an updated_at timestamp and a stage, returns JSON fragment:
#   { "is_stalled": bool, "days_since_update": int }
# Rules:
#   - No state / "unknown" timestamp → never stalled
#   - Completed features → never stalled
#   - Handles 3 formats: full ISO, millisecond ISO, date-only
compute_stalled() {
  local updated_at="$1"
  local stage="$2"
  local has_state="$3"

  # Features without state are never stalled
  if [[ "$has_state" == "false" ]]; then
    echo '{"is_stalled":false,"days_since_update":0}'
    return
  fi

  # Completed features are never stalled
  if [[ "$stage" == "complete" ]]; then
    echo '{"is_stalled":false,"days_since_update":0}'
    return
  fi

  # Unknown timestamp → not stalled
  if [[ -z "$updated_at" || "$updated_at" == "unknown" || "$updated_at" == "null" ]]; then
    echo '{"is_stalled":false,"days_since_update":0}'
    return
  fi

  # Parse timestamp using jq — handles 3 formats:
  #   1. Full ISO:        2026-03-16T00:00:00Z
  #   2. Millisecond ISO: 2026-03-16T00:00:00.000Z
  #   3. Date-only:       2026-03-16
  local result
  result=$(jq -n --arg ts "$updated_at" --argjson threshold "$STALLED_THRESHOLD_SECONDS" '
    def parse_ts:
      # Try full ISO first (strip trailing Z, handle with strptime)
      if test("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d+Z?$") then
        # Millisecond ISO — strip milliseconds and Z, then parse
        sub("\\.[0-9]+Z?$"; "") | strptime("%Y-%m-%dT%H:%M:%S") | mktime
      elif test("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z?$") then
        # Full ISO — strip Z, then parse
        sub("Z$"; "") | strptime("%Y-%m-%dT%H:%M:%S") | mktime
      elif test("^\\d{4}-\\d{2}-\\d{2}$") then
        # Date-only
        strptime("%Y-%m-%d") | mktime
      else
        # Cannot parse — treat as not stalled
        -1
      end;

    ($ts | parse_ts) as $epoch |
    if $epoch < 0 then
      { is_stalled: false, days_since_update: 0 }
    else
      (now - $epoch) as $diff |
      (($diff / 86400) | floor) as $days |
      {
        is_stalled: ($diff >= $threshold),
        days_since_update: $days
      }
    end
  ' 2>/dev/null) || result='{"is_stalled":false,"days_since_update":0}'

  echo "$result"
}

# ── Helper: compute next action ─────────────────────────────────────
# Given a stage and clarification_count, returns JSON fragment:
#   { "next_action": string, "next_action_reason": string }
compute_next_action() {
  local stage="$1"
  local clarification_count="$2"

  # Validate clarification_count is numeric; default to 0
  if ! [[ "$clarification_count" =~ ^[0-9]+$ ]]; then
    clarification_count=0
  fi

  local next_action=""
  local reason=""

  case "$stage" in
    no-state)
      next_action="/maestro.specify"
      reason="No state file found"
      ;;
    specify)
      if (( clarification_count > 0 )); then
        next_action="/maestro.clarify"
        reason="${clarification_count} clarification markers pending"
      else
        next_action="/maestro.plan"
        reason="Spec is ready"
      fi
      ;;
    clarify)
      next_action="/maestro.plan"
      reason="All clarifications resolved"
      ;;
    research)
      next_action="/maestro.plan"
      reason="Research complete, ready to plan"
      ;;
    plan)
      next_action="/maestro.tasks"
      reason="Plan ready for task creation"
      ;;
    tasks)
      next_action="/maestro.implement"
      reason="Tasks created, ready to implement"
      ;;
    implement)
      next_action=""
      reason="Implementation in progress"
      ;;
    complete)
      next_action="/maestro.analyze"
      reason="Ready for post-epic analysis"
      ;;
    *)
      next_action=""
      reason="Unknown stage"
      ;;
  esac

  jq -n \
    --arg action "$next_action" \
    --arg reason "$reason" \
    '{ next_action: $action, next_action_reason: $reason }'
}

# ── Helper: read state file safely ──────────────────────────────────
# Outputs a JSON object with the merged feature fields.
# If the state file is missing or malformed, returns defaults.
build_feature_json() {
  local feature_id="$1"
  local title="$2"
  local numeric_id="$3"
  local state_file="$STATE_DIR/${feature_id}.json"

  if [[ -f "$state_file" ]]; then
    # Attempt to parse — if jq fails, treat as malformed
    local parsed
    if parsed=$(jq -e '.' "$state_file" 2>/dev/null); then
      local stage
      stage=$(echo "$parsed" | jq -r '.stage // "unknown"')
      local updated_at
      updated_at=$(echo "$parsed" | jq -r '.updated_at // "unknown"')
      local clarification_count
      clarification_count=$(echo "$parsed" | jq -r '.clarification_count // 0')

      local stalled_json
      stalled_json=$(compute_stalled "$updated_at" "$stage" "true")
      local action_json
      action_json=$(compute_next_action "$stage" "$clarification_count")

      local forked_from
      forked_from=$(echo "$parsed" | jq -r '.forked_from // empty')
      local forks
      forks=$(echo "$parsed" | jq '.forks // []')

      local group="active"
      if [[ "$stage" == "complete" ]]; then
        group="completed"
      fi

      # Build --arg or --argjson for forked_from depending on null vs string
      local forked_from_args=()
      if [[ -z "$forked_from" ]]; then
        forked_from_args=(--argjson forked_from "null")
      else
        forked_from_args=(--arg forked_from "$forked_from")
      fi

      jq -n \
        --arg fid "$feature_id" \
        --argjson nid "$numeric_id" \
        --arg title "$title" \
        --arg grp "$group" \
        --argjson state "$parsed" \
        --argjson stalled "$stalled_json" \
        --argjson action "$action_json" \
        "${forked_from_args[@]}" \
        --argjson forks "$forks" \
        '{
          feature_id:          $fid,
          numeric_id:          $nid,
          title:               $title,
          stage:               ($state.stage           // "unknown"),
          group:               $grp,
          updated_at:          ($state.updated_at      // "unknown"),
          has_state:           true,
          user_stories:        ($state.user_stories        // 0),
          clarification_count: ($state.clarification_count // 0),
          task_count:          ($state.task_count           // 0),
          is_stalled:          $stalled.is_stalled,
          days_since_update:   $stalled.days_since_update,
          next_action:         $action.next_action,
          next_action_reason:  $action.next_action_reason,
          forked_from:         $forked_from,
          forks:               $forks
        }'
      return
    fi
    # Malformed JSON — fall through to defaults
    echo "Warning: malformed state file for $feature_id, treating as no-state" >&2
  fi

  # No state file or malformed — compute next action for no-state
  local action_json
  action_json=$(compute_next_action "no-state" "0")

  jq -n \
    --arg fid "$feature_id" \
    --argjson nid "$numeric_id" \
    --arg title "$title" \
    --argjson action "$action_json" \
    '{
      feature_id:          $fid,
      numeric_id:          $nid,
      title:               $title,
      stage:               "no-state",
      group:               "active",
      updated_at:          "unknown",
      has_state:           false,
      user_stories:        0,
      clarification_count: 0,
      task_count:          0,
      is_stalled:          false,
      days_since_update:   0,
      next_action:         $action.next_action,
      next_action_reason:  $action.next_action_reason,
      forked_from:         null,
      forks:               []
    }'
}

# ── Main ─────────────────────────────────────────────────────────────

# Validate that specs directory exists
if [[ ! -d "$SPECS_DIR" ]]; then
  echo "[]"
  exit 0
fi

# Collect feature JSON objects into an array
features="[]"

for spec_dir in "$SPECS_DIR"/*/; do
  # Guard: skip if glob didn't expand (empty directory)
  [[ -d "$spec_dir" ]] || continue

  feature_id=$(basename "$spec_dir")

  # Skip hidden directories
  [[ "$feature_id" == .* ]] && continue

  title=$(extract_title "$spec_dir" "$feature_id")
  numeric_id=$(extract_numeric_id "$feature_id")

  feature_json=$(build_feature_json "$feature_id" "$title" "$numeric_id")

  # Append to array
  features=$(echo "$features" | jq --argjson obj "$feature_json" '. += [$obj]')
done

# ── Sorting: active first (by numeric_id desc), then completed (by numeric_id desc)
features=$(echo "$features" | jq '
  ([.[] | select(.group == "active")] | sort_by(-.numeric_id)) +
  ([.[] | select(.group == "completed")] | sort_by(-.numeric_id))
')

# ── Filtering: apply --stage filter if provided
if [[ -n "$FILTER_STAGE" ]]; then
  features=$(echo "$features" | jq --arg stage "$FILTER_STAGE" '
    [.[] | select(.stage == $stage)]
  ')
fi

# Output final JSON array
echo "$features" | jq '.'
