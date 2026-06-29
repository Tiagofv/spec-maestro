#!/usr/bin/env bash
# update-state.sh — create or update a feature's pipeline state with REAL timestamps.
#
# Why: every command used to tell the agent to hand-write .maestro/state/<id>.json,
# including created_at/updated_at/history timestamps. A model has no clock, so those
# were fabricated (e.g. T00:00:00Z / T00:01:00Z), making /maestro.analyze metrics
# meaningless. This script stamps real UTC time and appends history atomically, so
# commands only supply real DECISIONS (stage, action, field values) — never timestamps.
#
# Usage:
#   update-state.sh <feature_id> <stage> <action> [field=value ...]
#
#   <feature_id>  e.g. 001-add-task-tracker
#   <stage>       specify|clarify|research|plan|tasks|implement|pm-validate|commit|analyze|complete
#   <action>      short history note, e.g. "plan generated: 5 tasks"
#   field=value   optional top-level fields to set; values are JSON if parseable, else string.
#                 (e.g. user_stories=5 spec_path=.maestro/specs/001/spec.md worktree_required=false)
#
# Behaviour:
#   - first call creates the file with created_at = now
#   - every call sets stage, updated_at = now, and appends {stage,timestamp,action} to history
#   - prints the resulting JSON
#
# Requires: jq, date (GNU or BSD both fine for -u +%Y-%m-%dT%H:%M:%SZ).
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "update-state.sh: jq required" >&2; exit 2; }

FEATURE_ID="${1:?usage: update-state.sh <feature_id> <stage> <action> [field=value ...]}"
STAGE="${2:?stage required}"
ACTION="${3:?action required}"
shift 3

MAESTRO_BASE="${MAESTRO_MAIN_REPO:-.}"
STATE_DIR="${MAESTRO_BASE}/.maestro/state"
STATE_FILE="${STATE_DIR}/${FEATURE_ID}.json"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$STATE_DIR"

# build a jq object of the extra field=value args (JSON-typed when possible)
FIELDS_JSON='{}'
for kv in "$@"; do
  key="${kv%%=*}"; val="${kv#*=}"
  if printf '%s' "$val" | jq empty >/dev/null 2>&1; then
    FIELDS_JSON=$(jq --arg k "$key" --argjson v "$val" '. + {($k): $v}' <<<"$FIELDS_JSON")
  else
    FIELDS_JSON=$(jq --arg k "$key" --arg v "$val" '. + {($k): $v}' <<<"$FIELDS_JSON")
  fi
done

if [ ! -f "$STATE_FILE" ]; then
  BASE=$(jq -n --arg id "$FEATURE_ID" --arg now "$NOW" \
    '{feature_id:$id, created_at:$now, updated_at:$now, stage:"", history:[]}')
else
  BASE=$(cat "$STATE_FILE")
fi

echo "$BASE" \
  | jq \
      --arg stage "$STAGE" \
      --arg action "$ACTION" \
      --arg now "$NOW" \
      --argjson fields "$FIELDS_JSON" \
      '. + $fields
       | .stage = $stage
       | .updated_at = $now
       | .history = ((.history // []) + [{stage:$stage, timestamp:$now, action:$action}])' \
  | tee "$STATE_FILE"
