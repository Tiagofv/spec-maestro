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
create_epic() {
  # Idempotency: reuse if state.json already has epic_id
  if [[ -f "$STATE_FILE" ]]; then
    local existing_epic
    existing_epic=$(jq -r '.epic_id // empty' "$STATE_FILE" 2>/dev/null || true)
    if [[ -n "$existing_epic" ]]; then
      EPIC_BD_ID="$existing_epic"
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

# create_tasks: For each parsed task call bd_create_task, store T###->altpay-ID map.
create_tasks() {
  echo "TODO: create_tasks" >&2
}

# wire_deps: Wire dependency edges using the T###->altpay-ID map.
# Behavior (single-call vs fan-out) driven by probe-bd-batch.md decision.
wire_deps() {
  echo "TODO: wire_deps" >&2
}

# update_state: Atomic write to state JSON (stage=tasks, epic_id, task_count, dep_count).
update_state() {
  echo "TODO: update_state" >&2
}

# report: One-line stdout summary + multi-line stderr breakdown.
report() {
  echo "TODO: report" >&2
}

# --- Main ---
main() {
  parse_plan
  build_table

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "Dry-run complete. No bd writes performed." >&2
    exit 0
  fi

  create_epic
  create_tasks
  wire_deps
  update_state
  report
}

main "$@"
