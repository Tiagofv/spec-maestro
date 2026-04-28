#!/usr/bin/env bash
# Parse Plan Tasks
# Extracts tasks from plan.md using TASK:BEGIN/TASK:END markers
# Outputs structured JSON for task creation
#
# Usage: parse-plan-tasks.sh <plan_file_path>
# Output: JSON array of task objects

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
PLAN_FILE=""
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      echo "Usage: parse-plan-tasks.sh <plan_file_path> [--verbose]"
      echo ""
      echo "Extracts tasks from plan.md using TASK:BEGIN/TASK:END markers"
      echo ""
      echo "Options:"
      echo "  -v, --verbose    Show detailed parsing output"
      echo "  -h, --help       Show this help message"
      echo ""
      echo "Output: JSON array of task objects"
      exit 0
      ;;
    -*)
      echo "Error: Unknown option $1" >&2
      exit 1
      ;;
    *)
      PLAN_FILE="$1"
      shift
      ;;
  esac
done

# Validate input
if [[ -z "$PLAN_FILE" ]]; then
  echo "Error: Plan file path required" >&2
  echo "Usage: parse-plan-tasks.sh <plan_file_path>" >&2
  exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "Error: Plan file not found: $PLAN_FILE" >&2
  exit 1
fi

# Valid labels
VALID_LABELS=("infrastructure" "agent" "core" "ui" "integration" "template" "testing" "review" "pm-validation")

# Function to check if label is valid
is_valid_label() {
  local label="$1"
  for valid in "${VALID_LABELS[@]}"; do
    if [[ "$label" == "$valid" ]]; then
      return 0
    fi
  done
  return 1
}

# Function to validate task ID format
is_valid_task_id() {
  local id="$1"
  [[ "$id" =~ ^T[0-9]{3}$ ]]
}

# Temporary file for building JSON
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

echo "{" > "$TEMP_FILE"
echo '  "tasks": [' >> "$TEMP_FILE"

TASK_COUNT=0
ERRORS=()
WARNINGS=()

if $VERBOSE; then
  echo "Parsing $PLAN_FILE..." >&2
fi

# Read file and extract tasks
# Use awk to handle multi-line task blocks
awk '
BEGIN { in_task = 0; task_content = "" }
/<!-- TASK:BEGIN id=T[0-9]{3} -->/ {
  in_task = 1
  task_content = ""
  match($0, /id=(T[0-9]{3})/, arr)
  task_id = arr[1]
  next
}
/<!-- TASK:END -->/ {
  if (in_task) {
    print "TASK_START|" task_id "|" task_content
    in_task = 0
    task_content = ""
  }
  next
}
in_task {
  task_content = task_content $0 "\n"
}
' "$PLAN_FILE" | while IFS='|' read -r marker task_id task_content; do
  if [[ "$marker" != "TASK_START" ]]; then
    continue
  fi
  
  ((TASK_COUNT++))
  
  if $VERBOSE; then
    echo "Processing task $task_id..." >&2
  fi
  
  # Initialize task fields
  title=""
  label=""
  size=""
  assignee=""
  dependencies=""
  description=""
  files=""
  
  # Extract title (first H3 after TASK:BEGIN)
  title=$(echo "$task_content" | grep -m 1 '^### ' | sed 's/^### //')
  
  if [[ -z "$title" ]]; then
    ERRORS+=("$task_id: Missing title (no H3 header)")
    title="Unknown"
  fi
  
  # Extract metadata fields
  label=$(echo "$task_content" | grep -A 1 '**Label:**' | tail -1 | sed 's/.*- //' | tr -d '[:space:]')
  size=$(echo "$task_content" | grep -A 1 '**Size:**' | tail -1 | sed 's/.*- //' | tr -d '[:space:]')
  # Assignee: capture only the agent name and discard any bracket annotations
  # appended by feature 060's SelectionAnnotation grammar (data-model.md §Entity:
  # SelectionAnnotation). Recognized markers include [harness: <name>],
  # [no-match: <reason>], [tie-broken], [review-fallback], and
  # [divergence: was X, plan now suggests Y]. The legacy form `Assignee: general`
  # (no annotations) must continue to parse identically.
  # Pattern: take the first whitespace-delimited token after `Assignee:` that
  # contains no whitespace and no `[`, then ignore everything else on the line.
  assignee=$(echo "$task_content" | sed -nE 's/.*Assignee:[*]*[[:space:]]+([^[:space:][]+).*/\1/p' | head -1)
  dependencies=$(echo "$task_content" | grep -A 1 '**Dependencies:**' | tail -1 | sed 's/.*- //')

  # Extract description (between metadata and Files section, or until next section)
  description=$(echo "$task_content" | awk '/\*\*Description:\*\*/,/\*\*Files/' | head -n -1 | tail -n +2 | sed 's/^- //')
  
  # Extract files
  files=$(echo "$task_content" | awk '/\*\*Files to Modify:\*\*/,/^-/' | tail -n +2 | grep '^- ' | sed 's/^- //')
  
  # Validation
  # Check ID format
  if ! is_valid_task_id "$task_id"; then
    ERRORS+=("$task_id: Invalid ID format (expected T###)")
  fi
  
  # Check size
  if [[ "$size" == "M" ]] || [[ "$size" == "L" ]]; then
    WARNINGS+=("$task_id: Size $size is too large (must be XS or S)")
    # Skip M/L tasks
    continue
  fi
  
  # Check label
  if ! is_valid_label "$label"; then
    if [[ -n "$label" ]]; then
      WARNINGS+=("$task_id: Invalid label '$label', using 'general'")
    fi
    label="general"
  fi
  
  # Default assignee
  if [[ -z "$assignee" ]]; then
    assignee="general"
  fi
  
  # Parse dependencies into array
  deps_array=""
  if [[ -n "$dependencies" && "$dependencies" != "None" ]]; then
    # Split by comma and trim
    IFS=',' read -ra DEPS <<< "$dependencies"
    deps_array="["
    first=true
    for dep in "${DEPS[@]}"; do
      dep=$(echo "$dep" | tr -d '[:space:]')
      if [[ -n "$dep" ]]; then
        if [[ "$first" == true ]]; then
          first=false
        else
          deps_array+=", "
        fi
        deps_array+="\"$dep\""
      fi
    done
    deps_array+="]"
  else
    deps_array="[]"
  fi
  
  # Escape strings for JSON
  title_escaped=$(echo "$title" | sed 's/"/\\"/g' | tr '\n' ' ')
  description_escaped=$(echo "$description" | sed 's/"/\\"/g' | tr '\n' ' ')
  
  # Build files array
  files_array="["
  first_file=true
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    file_escaped=$(echo "$file" | sed 's/"/\\"/g')
    if [[ "$first_file" == true ]]; then
      first_file=false
    else
      files_array+=", "
    fi
    files_array+="\"$file_escaped\""
  done <<< "$files"
  files_array+="]"
  
  # Output task JSON
  if [[ $TASK_COUNT -gt 1 ]]; then
    echo "," >> "$TEMP_FILE"
  fi
  
  cat >> "$TEMP_FILE" << EOF
    {
      "id": "$task_id",
      "title": "$title_escaped",
      "label": "$label",
      "size": "$size",
      "assignee": "$assignee",
      "dependencies": $deps_array,
      "description": "$description_escaped",
      "files": $files_array
    }
EOF
done

echo "" >> "$TEMP_FILE"
echo "  ]," >> "$TEMP_FILE"
echo "  \"count\": $TASK_COUNT," >> "$TEMP_FILE"
echo "  \"errors\": [" >> "$TEMP_FILE"

# Output errors
first_error=true
for error in "${ERRORS[@]}"; do
  if [[ "$first_error" == true ]]; then
    first_error=false
  else
    echo "," >> "$TEMP_FILE"
  fi
  error_escaped=$(echo "$error" | sed 's/"/\\"/g')
  echo "    \"$error_escaped\"" >> "$TEMP_FILE"
done
echo "" >> "$TEMP_FILE"
echo "  ]," >> "$TEMP_FILE"
echo "  \"warnings\": [" >> "$TEMP_FILE"

# Output warnings
first_warning=true
for warning in "${WARNINGS[@]}"; do
  if [[ "$first_warning" == true ]]; then
    first_warning=false
  else
    echo "," >> "$TEMP_FILE"
  fi
  warning_escaped=$(echo "$warning" | sed 's/"/\\"/g')
  echo "    \"$warning_escaped\"" >> "$TEMP_FILE"
done
echo "" >> "$TEMP_FILE"
echo "  ]" >> "$TEMP_FILE"
echo "}" >> "$TEMP_FILE"

# Output JSON
cat "$TEMP_FILE"

if $VERBOSE; then
  echo "" >&2
  echo "Parsing complete:" >&2
  echo "  Tasks: $TASK_COUNT" >&2
  echo "  Errors: ${#ERRORS[@]}" >&2
  echo "  Warnings: ${#WARNINGS[@]}" >&2
fi

# Return error code if there were errors
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  exit 1
fi

exit 0
