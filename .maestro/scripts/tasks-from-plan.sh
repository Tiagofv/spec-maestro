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
# Populates global TASKS array with TSV records (id\ttitle\tlabel\tsize\tassignee\tdeps).
parse_plan() {
  echo "TODO: parse_plan" >&2
}

# build_table: Pretty-print parsed tasks in column-aligned format for dry-run + report.
build_table() {
  echo "TODO: build_table" >&2
}

# create_epic: Call bd_create_epic, store returned epic ID in EPIC_BD_ID.
# Idempotent: if epic already exists, reuse it.
create_epic() {
  echo "TODO: create_epic" >&2
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
