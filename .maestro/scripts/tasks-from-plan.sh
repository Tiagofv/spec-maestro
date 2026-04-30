#!/usr/bin/env bash
# tasks-from-plan.sh — Extract plan tasks and create bd epic+tasks for a feature.
# Usage: tasks-from-plan.sh <feature_id> [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bd-helpers.sh"

# --- Argument parsing ---
FEATURE_ID=""
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *)
      if [[ -z "$FEATURE_ID" ]]; then
        FEATURE_ID="$arg"
      else
        echo "Unexpected argument: $arg" >&2; exit 1
      fi
      ;;
  esac
done

if [[ -z "$FEATURE_ID" ]]; then
  echo "Usage: tasks-from-plan.sh <feature_id> [--dry-run]" >&2
  echo "  feature_id: e.g. 070-improve-maestro-tasks-command-speed" >&2
  exit 1
fi

# Resolve paths
MAESTRO_BASE="${MAESTRO_BASE:-.}"
PLAN_FILE="$MAESTRO_BASE/.maestro/specs/$FEATURE_ID/plan.md"
STATE_FILE="$MAESTRO_BASE/.maestro/state/$FEATURE_ID.json"

# --- Function stubs ---

# parse_plan: One-pass awk over plan.md TASK:BEGIN/TASK:END markers.
# Populates global TASKS_FILE (path to a temp TSV) with records:
#   id\ttitle\tlabel\tsize\tassignee\tdeps
parse_plan() {
  if [[ ! -f "$PLAN_FILE" ]]; then
    echo "parse_plan: plan file not found: $PLAN_FILE" >&2
    exit 1
  fi

  TASKS_FILE="$(mktemp /tmp/tasks-from-plan.XXXXXX)"

  awk '
    /^<!-- TASK:BEGIN id=/ {
      # Extract the id attribute from the marker (portable: no gawk arr form)
      line = $0
      sub(/.*id=/, "", line)
      sub(/ .*/, "", line)
      sub(/-->.*/, "", line)
      gsub(/[[:space:]]/, "", line)
      id = line
      in_block = 1
      title = ""
      label = ""
      size  = ""
      assignee = ""
      deps  = ""
      got_title = 0
      next
    }

    /^<!-- TASK:END -->/ {
      in_block = 0
      # Validate required fields
      if (id == "") next
      if (label == "") {
        print "parse_plan: task " id " missing Label" > "/dev/stderr"
        exit 2
      }
      if (size == "") {
        print "parse_plan: task " id " missing Size" > "/dev/stderr"
        exit 2
      }
      if (assignee == "") {
        print "parse_plan: task " id " missing Assignee" > "/dev/stderr"
        exit 2
      }
      if (size == "M" || size == "L") {
        print "parse_plan: task " id " has disallowed size " size " (only XS/S allowed)" > "/dev/stderr"
        exit 3
      }
      print id "\t" title "\t" label "\t" size "\t" assignee "\t" deps
      task_count++
      next
    }

    in_block {
      # Capture the first H3 header as title (### T001: ... or ### R001: ...)
      if (!got_title && /^### [A-Za-z0-9]+:/) {
        # Strip leading "### T001: " prefix
        line = $0
        sub(/^### [A-Za-z0-9]+: */, "", line)
        # Strip backticks
        gsub(/`/, "", line)
        title = line
        got_title = 1
        next
      }
      # Capture metadata fields
      if (/^- \*\*Label:\*\*/) {
        line = $0
        sub(/^- \*\*Label:\*\* */, "", line)
        gsub(/^ +| +$/, "", line)
        label = line
        next
      }
      if (/^- \*\*Size:\*\*/) {
        line = $0
        sub(/^- \*\*Size:\*\* */, "", line)
        gsub(/^ +| +$/, "", line)
        size = line
        next
      }
      if (/^- \*\*Assignee:\*\*/) {
        line = $0
        sub(/^- \*\*Assignee:\*\* */, "", line)
        # Strip any bracket annotations like [harness: claude] or [no-match: ...]
        gsub(/ *\[[^]]*\]/, "", line)
        gsub(/^ +| +$/, "", line)
        assignee = line
        next
      }
      if (/^- \*\*Dependencies:\*\*/) {
        line = $0
        sub(/^- \*\*Dependencies:\*\* */, "", line)
        # Strip any parenthetical annotations like "(some note)"
        gsub(/ *\([^)]*\)/, "", line)
        gsub(/^ +| +$/, "", line)
        # Normalize whitespace around commas
        gsub(/ *, */, ",", line)
        deps = line
        next
      }
    }

    END {
      if (task_count == 0) {
        print "parse_plan: plan.md has no tasks" > "/dev/stderr"
        exit 4
      }
    }
  ' task_count=0 "$PLAN_FILE" >> "$TASKS_FILE" || {
    local awk_exit=$?
    rm -f "$TASKS_FILE"
    exit $awk_exit
  }

  local count
  count=$(wc -l < "$TASKS_FILE")
  if [[ "$count" -eq 0 ]]; then
    echo "parse_plan: plan.md has no tasks" >&2
    rm -f "$TASKS_FILE"
    exit 4
  fi

  echo "parse_plan: parsed $count task(s) from $PLAN_FILE" >&2
}

# build_table: Pretty-print parsed tasks in column-aligned format for dry-run + report.
build_table() {
  if [[ -z "${TASKS_FILE:-}" || ! -f "$TASKS_FILE" ]]; then
    echo "build_table: no TASKS_FILE to display" >&2
    return
  fi
  printf "%-7s %-40s %-11s %-5s %-9s %s\n" "ID" "Title" "Label" "Size" "Assignee" "Deps"
  printf "%-7s %-40s %-11s %-5s %-9s %s\n" "-------" "----------------------------------------" "-----------" "-----" "---------" "----------"
  while IFS=$'\t' read -r id title label size assignee deps; do
    [[ -z "$deps" || "$deps" == "None" ]] && deps="-"
    printf "%-7s %-40s %-11s %-5s %-9s %s\n" \
      "$id" "${title:0:40}" "$label" "$size" "$assignee" "$deps"
  done < "$TASKS_FILE"
}

# create_epic: Call bd_create_epic, store returned epic ID in EPIC_BD_ID.
# Idempotent: if epic already exists, reuse it.
EPIC_BD_ID=""
EPIC_WAS_PREEXISTING=false
create_epic() {
  # Idempotency: reuse if state.json already has epic_id
  if [[ -f "$STATE_FILE" ]]; then
    local existing_epic
    existing_epic=$(jq -r '.epic_id // empty' "$STATE_FILE" 2>/dev/null || true)
    if [[ -n "$existing_epic" ]]; then
      EPIC_BD_ID="$existing_epic"
      EPIC_WAS_PREEXISTING=true
      echo "create_epic: reusing existing epic $EPIC_BD_ID from state.json" >&2
      return 0
    fi
  fi

  # Read feature title from plan.md H1
  local feature_title
  feature_title=$(grep "^# Implementation Plan:" "$PLAN_FILE" | sed 's/^# Implementation Plan: //' | head -1)
  [[ -z "$feature_title" ]] && feature_title="$FEATURE_ID"

  EPIC_BD_ID=$(bd_create_epic "$FEATURE_ID: $feature_title" "Spec: $MAESTRO_BASE/.maestro/specs/$FEATURE_ID/spec.md")

  echo "Epic: $EPIC_BD_ID" >&2
}

# Global map: T001 -> altpay-woz.2 etc.
declare -A TASK_ID_MAP

# Global dep wiring counter (incremented per resolved dep passed at create time).
DEP_COUNT=0

# create_tasks: For each parsed task call bd_create_task, store T###->altpay-ID map.
# Deps are wired inline via --deps (SINGLE_CALL per probe-bd-batch.md).
create_tasks() {
  # Idempotency: if the epic was pre-existing, tasks already exist — skip creation.
  if [[ "$EPIC_WAS_PREEXISTING" == "true" ]]; then
    echo "create_tasks: epic was pre-existing; skipping task creation (tasks already created)" >&2
    return 0
  fi

  local plan_id title label size assignee deps

  while IFS=$'\t' read -r plan_id title label size assignee deps; do
    [[ -z "$plan_id" ]] && continue

    # Idempotency: skip if we already have this T### in TASK_ID_MAP
    if [[ -n "${TASK_ID_MAP[$plan_id]:-}" ]]; then
      echo "  skipping $plan_id (already in map: ${TASK_ID_MAP[$plan_id]})" >&2
      continue
    fi

    # Estimate minutes
    local estimate=120
    [[ "$size" == "S" ]] && estimate=360

    # Build description: use plan task title + worktree note
    local desc
    desc="$plan_id: $title
Size: $size | Label: $label | Deps: ${deps:-None}
Worktree: ${WORKTREE_PATH:-}"

    # Resolve dep T### plan IDs to altpay bd IDs (SINGLE_CALL strategy).
    # Validate each dep is already in TASK_ID_MAP before passing to bd create.
    local dep_ids=""
    if [[ -n "$deps" && "$deps" != "None" && "$deps" != "-" ]]; then
      local resolved_deps=()
      IFS=',' read -ra dep_list <<< "$deps"
      for dep_id in "${dep_list[@]}"; do
        dep_id="${dep_id// /}"  # trim spaces
        if [[ -n "${TASK_ID_MAP[$dep_id]:-}" ]]; then
          resolved_deps+=("${TASK_ID_MAP[$dep_id]}")
          (( DEP_COUNT++ )) || true
        else
          echo "  WARNING: dep $dep_id not yet in TASK_ID_MAP, skipping" >&2
        fi
      done
      [[ ${#resolved_deps[@]} -gt 0 ]] && dep_ids=$(IFS=,; echo "${resolved_deps[*]}")
    fi

    local bd_id
    bd_id=$(bd_create_task "$plan_id: $title" "$desc" "$label" "$estimate" "$EPIC_BD_ID" "$assignee" "$dep_ids") || {
      echo "create_tasks: bd_create_task failed for $plan_id" >&2
      exit 1
    }

    TASK_ID_MAP["$plan_id"]="$bd_id"
    if [[ -n "$dep_ids" ]]; then
      echo "  created $plan_id → $bd_id (deps: $dep_ids)" >&2
    else
      echo "  created $plan_id → $bd_id" >&2
    fi

  done < "$TASKS_FILE"

  echo "Created ${#TASK_ID_MAP[@]} tasks" >&2
}

# wire_deps: Deps are wired at create time via --deps flag (SINGLE_CALL per probe-bd-batch.md).
# This function is a no-op; DEP_COUNT is already populated by create_tasks.
wire_deps() {
  echo "wire_deps: $DEP_COUNT dep(s) wired at create time via --deps (SINGLE_CALL)" >&2
}

# update_state: Atomic write to state JSON (stage=tasks, epic_id, task_count, dep_count).
update_state() {
  local feature_num
  feature_num=$(echo "$FEATURE_ID" | grep -oE '^[0-9]+')
  local task_count=${#TASK_ID_MAP[@]}
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq \
    --arg epic_id "$EPIC_BD_ID" \
    --arg bd_label "feature:$feature_num" \
    --argjson task_count "$task_count" \
    --argjson dep_count "$DEP_COUNT" \
    --arg stage "tasks" \
    --arg ts "$timestamp" \
    --arg note "epic=$EPIC_BD_ID; tasks=$task_count; deps=$DEP_COUNT" \
    '.epic_id = $epic_id |
     .bd_label = $bd_label |
     .task_count = $task_count |
     .dep_count = $dep_count |
     .stage = $stage |
     .updated_at = $ts |
     .history += [{"stage": "tasks", "timestamp": $ts, "action": "tasks created", "note": $note}]' \
    "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

  echo "Updated state file: $STATE_FILE" >&2
}

# report: One-line stdout summary + multi-line stderr breakdown.
report() {
  local task_count=${#TASK_ID_MAP[@]}

  # Stdout: machine-parseable
  echo "epic=$EPIC_BD_ID tasks=$task_count deps=$DEP_COUNT"

  # Stderr: human-readable
  echo "" >&2
  echo "━━━ Tasks Created ━━━" >&2
  echo "Feature:  $FEATURE_ID" >&2
  echo "Epic:     $EPIC_BD_ID" >&2
  echo "Tasks:    $task_count" >&2
  echo "Deps:     $DEP_COUNT" >&2
  if [[ "$EPIC_WAS_PREEXISTING" == "true" ]]; then
    echo "Note:     Epic existed; no tasks created (idempotent re-run)" >&2
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "" >&2
  echo "Run 'bd show $EPIC_BD_ID --children' to view created tasks." >&2
}

# --- Main ---
main() {
  parse_plan
  build_table

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "Dry-run complete. No bd writes performed." >&2
    exit 0
  fi

  WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$STATE_FILE" 2>/dev/null || echo "")
  create_epic
  create_tasks
  wire_deps
  update_state
  report
}

main "$@"
