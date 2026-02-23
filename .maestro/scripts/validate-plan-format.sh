#!/usr/bin/env bash
# Validate plan.md follows parseable task format
# Usage: validate-plan-format.sh <plan.md-path>
# Exit 0 = valid, exit 1 = invalid with error messages

set -euo pipefail

PLAN_FILE="${1:-}"
ERRORS=0

if [[ -z "$PLAN_FILE" ]]; then
  echo "FAIL: No plan file specified" >&2
  echo "Usage: validate-plan-format.sh <plan.md-path>" >&2
  exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "FAIL: Plan file not found: $PLAN_FILE" >&2
  exit 1
fi

echo "=== Validating Plan Format: $PLAN_FILE ===" >&2

# Extract task IDs - only match actual task blocks (with TASK:END)
extract_task_ids() {
  # Read file and find blocks that have both BEGIN and END
  awk '
    /<!-- TASK:BEGIN id=T[0-9]{3} -->/ {
      match($0, /id=(T[0-9]{3})/, arr)
      id = arr[1]
      getline
      while (!/<!-- TASK:END -->/ && NF > 0) {
        getline
      }
      if (/<!-- TASK:END -->/) {
        print id
      }
    }
  ' "$1" 2>/dev/null || perl -nle 'print $1 if /<!-- TASK:BEGIN id=(T[0-9]{3}) -->/' "$1"
}

# Get all task IDs
task_ids=$(extract_task_ids "$PLAN_FILE")

if [[ -z "$task_ids" ]]; then
  echo "ERROR: No task blocks found (expected <!-- TASK:BEGIN -->...<!-- TASK:END -->)" >&2
  ERRORS=$((ERRORS + 1))
  
  echo "" >&2
  echo "=== Validation FAILED with $ERRORS error(s) ===" >&2
  echo "Fix the errors above and re-run." >&2
  echo "" >&2
  echo "Required format:" >&2
  echo '  <!-- TASK:BEGIN id=T001 -->' >&2
  echo '  ### T001: Short title' >&2
  echo '  ' >&2
  echo '  - **Label:** backend' >&2
  echo '  - **Size:** S' >&2
  echo '  - **Assignee:** general' >&2
  echo '  - **Dependencies:** —' >&2
  echo '  ' >&2
  echo '  **Description:**' >&2
  echo '  Task description here...' >&2
  echo '  <!-- TASK:END -->' >&2
  exit 1
fi

# Count actual tasks ( Implementation Tasks section)
task_count=$(echo "$task_ids" | grep -c "^T" || echo "0")

# Check for duplicate IDs
duplicates=$(echo "$task_ids" | sort | uniq -d)
if [[ -n "$duplicates" ]]; then
  echo "ERROR: Duplicate task IDs found: $duplicates" >&2
  ERRORS=$((ERRORS + 1))
fi

# Validate each task
seen_ids=""
while IFS= read -r task_id; do
  [[ -z "$task_id" ]] && continue
  
  # Validate ID format (T followed by 3 digits)
  if [[ ! "$task_id" =~ ^T[0-9]{3}$ ]]; then
    echo "ERROR: Task $task_id - Invalid ID format (expected T###, e.g., T001)" >&2
    ERRORS=$((ERRORS + 1))
    continue
  fi
  
  # Skip if we've already processed this ID (duplicate handling)
  if echo "$seen_ids" | grep -qx "$task_id" 2>/dev/null; then
    continue
  fi
  seen_ids="$seen_ids
$task_id"
  
  # Extract task block using sed
  block=$(sed -n "/<!-- TASK:BEGIN id=$task_id/,/<!-- TASK:END/p" "$PLAN_FILE")
  
  if [[ -z "$block" ]]; then
    echo "ERROR: Task $task_id - Could not extract task block" >&2
    ERRORS=$((ERRORS + 1))
    continue
  fi
  
  # Check for required fields using grep
  if ! echo "$block" | grep -qE '^[[:space:]]*-[[:space:]]+\*?\*?Label:\*?\*[[:space:]]+'; then
    echo "ERROR: Task $task_id - Missing 'Label:' field" >&2
    ERRORS=$((ERRORS + 1))
  fi
  
  if ! echo "$block" | grep -qE '^[[:space:]]*-[[:space:]]+\*?\*?Size:\*?\*[[:space:]]+'; then
    echo "ERROR: Task $task_id - Missing 'Size:' field" >&2
    ERRORS=$((ERRORS + 1))
  fi
  
  if ! echo "$block" | grep -qE '^[[:space:]]*-[[:space:]]+\*?\*?Assignee:\*?\*[[:space:]]+'; then
    echo "ERROR: Task $task_id - Missing 'Assignee:' field" >&2
    ERRORS=$((ERRORS + 1))
  fi
  
  if ! echo "$block" | grep -qE '^[[:space:]]*-[[:space:]]+\*?\*?Dependencies:\*?\*[[:space:]]+'; then
    echo "ERROR: Task $task_id - Missing 'Dependencies:' field" >&2
    ERRORS=$((ERRORS + 1))
  fi
  
  # Validate size is XS or S
  size=$(echo "$block" | grep -oE 'Size:[[:space:]]*[A-Z]+' | head -1 | sed 's/Size:[[:space:]]*//' || true)
  if [[ -n "$size" && "$size" != "XS" && "$size" != "S" ]]; then
    echo "ERROR: Task $task_id - Invalid size '$size' (must be XS or S)" >&2
    ERRORS=$((ERRORS + 1))
  fi
  
  # Validate label
  label=$(echo "$block" | grep -oE 'Label:[[:space:]]*[a-z-]+' | head -1 | sed 's/Label:[[:space:]]*//' || true)
  if [[ -n "$label" && ! "$label" =~ ^(backend|frontend|test|docs|infrastructure)$ ]]; then
    echo "WARNING: Task $task_id - Unusual label '$label' (expected: backend, frontend, test, docs, infrastructure)" >&2
  fi
  
  # Validate header matches ID
  if ! echo "$block" | grep -qE "^###[[:space:]]+$task_id:"; then
    echo "ERROR: Task $task_id - Header doesn't match ID (expected '### $task_id: ...')" >&2
    ERRORS=$((ERRORS + 1))
  fi
  
done <<< "$task_ids"

# Summary
if [[ $ERRORS -gt 0 ]]; then
  echo "" >&2
  echo "=== Validation FAILED with $ERRORS error(s) ===" >&2
  echo "Fix the errors above and re-run." >&2
  echo "" >&2
  echo "Required format:" >&2
  echo '  <!-- TASK:BEGIN id=T001 -->' >&2
  echo '  ### T001: Short title' >&2
  echo '  ' >&2
  echo '  - **Label:** backend' >&2
  echo '  - **Size:** S' >&2
  echo '  - **Assignee:** general' >&2
  echo '  - **Dependencies:** —' >&2
  echo '  ' >&2
  echo '  **Description:**' >&2
  echo '  Task description here...' >&2
  echo '  <!-- TASK:END -->' >&2
  exit 1
else
  echo "=== Validation PASSED ($task_count task(s) found) ===" >&2
  exit 0
fi
