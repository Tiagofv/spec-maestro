# Pattern Catalog: Maestro Task Creation on Beads

**Spec:** 019 - Improve Maestro Task Creation on Beads  
**Research Date:** 2026-02-23  
**Purpose:** Patterns for efficient, idempotent, and robust task creation with dependency linking

---

## Table of Contents

1. [Pattern 1: Idempotent Task Creation](#pattern-1-idempotent-task-creation)
2. [Pattern 2: Two-Pass Dependency Linking](#pattern-2-two-pass-dependency-linking)
3. [Pattern 3: Progress Indication in CLI Scripts](#pattern-3-progress-indication-in-cli-scripts)
4. [Pattern 4: Error Handling with Immediate Stop](#pattern-4-error-handling-with-immediate-stop)
5. [Pattern 5: CLI Wrapper Patterns](#pattern-5-cli-wrapper-patterns)
6. [Pattern 6: Dependency Resolution Algorithms](#pattern-6-dependency-resolution-algorithms)

---

## Pattern 1: Idempotent Task Creation

### Problem

Creating tasks multiple times should not result in duplicates. Need to detect existing tasks efficiently without querying the database for every single task (N+1 problem).

### Solution: Check-Before-Create with Batch Lookup

\`\`\`bash
#!/usr/bin/env bash
# Idempotent task creation pattern

set -euo pipefail

# Pre-fetch all existing tasks to avoid N+1 queries
# Strategy: Query by title prefix (e.g., "F019-") to get all feature tasks
fetch_existing_tasks() {
  local feature_prefix="$1"
  # Use bd list with title filter and --json for machine-readable output
  bd list --title-contains="${feature_prefix}" --json 2>/dev/null | \
    jq -r '.[] | select(.title | startswith("'"$feature_prefix"'")) | .title'
}

# Store existing titles in an associative array for O(1) lookups
declare -A EXISTING_TASKS

build_task_index() {
  local prefix="$1"
  while IFS= read -r title; do
    [[ -n "$title" ]] && EXISTING_TASKS["$title"]=1
  done < <(fetch_existing_tasks "$prefix")
}

task_exists() {
  local title="$1"
  [[ -n "${EXISTING_TASKS[$title]:-}" ]]
}

create_task_idempotent() {
  local title="$1"
  local description="$2"
  local label="$3"
  local estimate="$4"
  local epic_id="$5"
  local assignee="${6:-general}"

  if task_exists "$title"; then
    echo "SKIP: Task '$title' already exists"
    return 0
  fi

  # Create the task
  bd create \
    --title="$title" \
    --type=task \
    --priority=2 \
    --labels="$label" \
    --estimate="$estimate" \
    --assignee="$assignee" \
    --description="$description" \
    --parent="$epic_id" \
    --silent 2>/dev/null
}
\`\`\`

### Alternative: External-Ref Based Idempotency

\`\`\`bash
# Use beads' --external-ref flag to store unique identifiers
# This allows detection without title matching

create_task_with_ref() {
  local task_id="$1"  # e.g., "F019-T001"
  local title="$2"
  # ... other params

  # Check if task with this external ref exists
  if bd list --json 2>/dev/null | jq -e ".[] | select(.external_ref == \"$task_id\")" >/dev/null 2>&1; then
    echo "SKIP: $task_id already exists"
    return 0
  fi

  bd create \
    --title="$title" \
    --external-ref="$task_id" \
    # ... other flags
    --silent
}
\`\`\`

### Comparison

| Approach | Pros | Cons |
|----------|------|------|
| Title-based lookup | Simple, no schema changes | Title must be unique; renames break idempotency |
| External-ref | Stable across title changes | Requires external-ref support; extra field management |
| ID-based (beads native) | Most reliable | Requires storing beads IDs in task plan |

### Recommendation

**Use title-based lookup for Maestro** because:
1. Maestro already generates unique titles with feature prefixes (e.g., "019-improve...")
2. No dependency on beads schema extensions
3. Matches current Maestro naming conventions
4. Can combine with `bd list --title-contains` for efficient batch queries

---

## Pattern 2: Two-Pass Dependency Linking

### Problem

Dependencies cannot be created until all tasks exist. If Task B depends on Task A, we need Task A's beads ID before creating the dependency.

### Solution: Phase 1 Create, Phase 2 Link

\`\`\`bash
#!/usr/bin/env bash
# Two-pass dependency linking pattern

set -euo pipefail

# Phase 1: Create all tasks, capture their IDs
declare -A TASK_ID_MAP  # Maps local task ID -> beads task ID

pass1_create_tasks() {
  local tasks_json="$1"

  # Read tasks from JSON input
  while IFS= read -r task; do
    local local_id title description label estimate epic_id assignee
    local_id=$(echo "$task" | jq -r '.id')
    title=$(echo "$task" | jq -r '.title')
    description=$(echo "$task" | jq -r '.description')
    label=$(echo "$task" | jq -r '.label')
    estimate=$(echo "$task" | jq -r '.estimate')
    epic_id=$(echo "$task" | jq -r '.epic_id')
    assignee=$(echo "$task" | jq -r '.assignee // "general"')

    # Skip if already exists (idempotency check)
    if task_exists "$title"; then
      # Get existing task ID
      local existing_id
      existing_id=$(bd list --title-contains="$title" --json 2>/dev/null | \
        jq -r '.[0].id')
      TASK_ID_MAP["$local_id"]="$existing_id"
      echo "SKIP: $local_id -> $existing_id (existing)"
      continue
    fi

    # Create task and capture ID
    local beads_id
    beads_id=$(bd create \
      --title="$title" \
      --type=task \
      --priority=2 \
      --labels="$label" \
      --estimate="$estimate" \
      --assignee="$assignee" \
      --description="$description" \
      --parent="$epic_id" \
      --json 2>/dev/null | jq -r '.id')

    if [[ -z "$beads_id" || "$beads_id" == "null" ]]; then
      echo "ERROR: Failed to create task '$title'" >&2
      exit 1
    fi

    TASK_ID_MAP["$local_id"]="$beads_id"
    echo "CREATE: $local_id -> $beads_id"
  done < <(echo "$tasks_json" | jq -c '.tasks[]')
}

# Phase 2: Link dependencies using captured IDs
pass2_link_dependencies() {
  local tasks_json="$1"

  while IFS= read -r task; do
    local local_id deps
    local_id=$(echo "$task" | jq -r '.id')
    deps=$(echo "$task" | jq -r '.dependencies[]? // empty')

    [[ -z "$deps" ]] && continue

    local dependent_beads_id="${TASK_ID_MAP[$local_id]}"

    while IFS= read -r dep_local_id; do
      [[ -z "$dep_local_id" ]] && continue

      local blocker_beads_id="${TASK_ID_MAP[$dep_local_id]:-}"

      if [[ -z "$blocker_beads_id" ]]; then
        echo "ERROR: Dependency $dep_local_id not found for task $local_id" >&2
        exit 1
      fi

      # Add dependency: dependent is blocked by blocker
      bd dep add "$dependent_beads_id" "$blocker_beads_id" 2>/dev/null || {
        echo "ERROR: Failed to link dependency $dep_local_id -> $local_id" >&2
        exit 1
      }
      echo "LINK: $dep_local_id -> $local_id"
    done <<< "$deps"
  done < <(echo "$tasks_json" | jq -c '.tasks[]')
}

# Main execution
main() {
  local input_file="$1"
  local tasks_json
  tasks_json=$(cat "$input_file")

  echo "=== Phase 1: Creating tasks ==="
  pass1_create_tasks "$tasks_json"

  echo "=== Phase 2: Linking dependencies ==="
  pass2_link_dependencies "$tasks_json"

  echo "=== Complete ==="
}

main "$@"
\`\`\`

### Transaction Safety Consideration

Two-pass linking creates a partial-state risk: if Phase 1 succeeds but Phase 2 fails, tasks exist without dependencies. Mitigations:

1. **Continue on dependency failure (default):** Tasks remain usable; user manually fixes
2. **Rollback on Phase 2 failure:** Delete all created tasks (complex, risky)
3. **Mark incomplete:** Add label `deps-pending` to tasks, allow retry

### Recommendation

**Use Option 3 (mark incomplete)** for Maestro:
- Store created task IDs in state file
- On dependency failure, record status as `tasks_created_deps_pending`
- Allow `/maestro.tasks` to resume from Phase 2 on retry
- Matches Maestro's existing state-driven workflow

---

## Pattern 3: Progress Indication in CLI Scripts

### Problem

Batch operations need user feedback without cluttering output. For 50+ tasks, need clear progress.

### Solution A: Simple Counter (Recommended for Maestro)

\`\`\`bash
#!/usr/bin/env bash
# Simple progress counter - suitable for non-TTY output

progress_counter() {
  local current="$1"
  local total="$2"
  local operation="${3:-Processing}"

  printf "[%d/%d] %s...\n" "$current" "$total" "$operation"
}

# Usage in loop
total_tasks=50
current=0
while IFS= read -r task; do
  ((current++))
  progress_counter "$current" "$total_tasks" "Creating task"
  # ... create task
done < tasks.txt

echo "Completed: $current/$total_tasks tasks created"
\`\`\`

### Solution B: Progress Bar (TTY only)

\`\`\`bash
#!/usr/bin/env bash
# ASCII progress bar for interactive terminals

progress_bar() {
  local current="$1"
  local total="$2"
  local width="${3:-40}"

  local percentage=$((current * 100 / total))
  local filled=$((width * current / total))
  local empty=$((width - filled))

  printf "\r[%-${filled}s%${empty}s] %d%% (%d/%d)" \
    "$(printf '%*s' "$filled" | tr ' ' '#')" \
    "" \
    "$percentage" \
    "$current" \
    "$total"
}

# Usage - only show if TTY
if [[ -t 1 ]]; then
  for i in {1..50}; do
    progress_bar "$i" 50
    sleep 0.1
  done
  echo  # newline after completion
else
  # Non-TTY: simple output
  echo "Processing 50 tasks..."
fi
\`\`\`

### Solution C: Structured JSON Progress (for Agent Parsing)

\`\`\`bash
#!/usr/bin/env bash
# JSON progress events for machine consumption

emit_progress() {
  local phase="$1"
  local current="$2"
  local total="$3"
  local status="${4:-in_progress}"  # in_progress|complete|error
  local message="${5:-}"

  jq -n \
    --arg phase "$phase" \
    --argjson current "$current" \
    --argjson total "$total" \
    --arg status "$status" \
    --arg message "$message" \
    '{
      event: "progress",
      phase: $phase,
      current: $current,
      total: $total,
      status: $status,
      message: $message,
      timestamp: now | todateiso8601
    }'
}

# Usage
emit_progress "task_creation" 5 50 "in_progress" "Creating: Setup database schema"
\`\`\`

### Comparison

| Approach | Best For | Complexity | Agent Friendly |
|----------|----------|------------|----------------|
| Counter | All cases | Low | Yes |
| Progress Bar | Interactive CLI | Medium | No (ANSI codes) |
| JSON Events | Automation, Agents | Medium | Yes |

### Recommendation

**Use Solution A (Simple Counter)** for Maestro because:
1. Works in all contexts (TTY, piped, agent)
2. Simplest implementation
3. Maestro commands already output structured JSON at end
4. Can enhance with `--verbose` flag later for detailed output

**Enhancement:** Add `--json` flag to output progress events for agent integration.

---

## Pattern 4: Error Handling with Immediate Stop

### Problem

Task creation must fail fast on first error to prevent partial state. But need cleanup/logging before exit.

### Solution: errexit + ERR Trap + Cleanup Handler

\`\`\`bash
#!/usr/bin/env bash
# Robust error handling pattern

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="${MAESTRO_LOG:-/dev/stderr}"

# Track state for cleanup
declare -a CREATED_TASK_IDS=()
declare -a CREATED_EPIC_IDS=()
declare ERROR_OCCURRED=false

# Cleanup function - runs on exit
cleanup() {
  local exit_code=$?

  if [[ "$ERROR_OCCURRED" == "true" ]]; then
    # Log failure for potential retry/resume
    jq -n \
      --arg script "$SCRIPT_NAME" \
      --argjson exit_code "$exit_code" \
      --argjson created_tasks "$(printf '%s\n' "${CREATED_TASK_IDS[@]}" | jq -R . | jq -s .)" \
      --argjson created_epics "$(printf '%s\n' "${CREATED_EPIC_IDS[@]}" | jq -R . | jq -s .)" \
      '{
        error: true,
        script: $script,
        exit_code: $exit_code,
        created_tasks: $created_tasks,
        created_epics: $created_epics,
        timestamp: now | todateiso8601
      }' >> "$LOG_FILE" 2>/dev/null || true
  fi
}

# Set trap to run cleanup on exit
trap cleanup EXIT

# Error handler - runs on ERR signal
error_handler() {
  local line_no=$1
  local exit_code=$2

  ERROR_OCCURRED=true

  echo "{" >&2
  echo "  \"error\": true," >&2
  echo "  \"message\": \"Script failed at line $line_no with exit code $exit_code\"," >&2
  echo "  \"suggestion\": \"Check task validity and retry with same input\"," >&2
  echo "}" >&2

  # Exit immediately (cleanup trap runs next)
  exit "$exit_code"
}

# Set ERR trap to capture line number
trap 'error_handler ${LINENO} $?' ERR

# Function with explicit error handling
create_task_or_fail() {
  local title="$1"
  shift 1
  local output

  # Capture both stdout and stderr
  if ! output=$(bd create --title="$title" "$@" --json 2>&1); then
    echo "ERROR: Failed to create task '$title'" >&2
    echo "Details: $output" >&2
    return 1  # Triggers ERR trap due to set -e
  fi

  # Validate output is valid JSON
  if ! echo "$output" | jq -e '.' >/dev/null 2>&1; then
    echo "ERROR: Invalid JSON response for task '$title'" >&2
    return 1
  fi

  # Extract and return ID
  echo "$output" | jq -r '.id'
}

# Main logic
main() {
  # ... script logic

  local task_id
  task_id=$(create_task_or_fail "My Task" --type=task)
  CREATED_TASK_IDS+=("$task_id")

  # ... more tasks
}

main "$@"
\`\`\`

### Best Practice: Scoped Error Handling

\`\`\`bash
# Allow specific commands to fail without script exit
temp_file="$(mktemp)"

# This command can fail (optional cleanup)
rm "$temp_file" 2>/dev/null || true  # || true prevents exit

# For critical commands, ensure they succeed
critical_command || exit 1

# Or use if statement (also immune from set -e inside condition)
if critical_command; then
  echo "Success"
else
  echo "Failed"
  exit 1
fi
\`\`\`

### Recommendation

**Adopt the errexit + ERR trap pattern** from the solution above:

1. `set -euo pipefail` at top of every script
2. ERR trap for structured error logging
3. EXIT trap for cleanup (resumes, state tracking)
4. Always output JSON error for agent consumption

---

## Pattern 5: CLI Wrapper Patterns

### Problem

Wrapping `bd` CLI requires handling: subprocess execution, JSON parsing, exit codes, timeouts.

### Solution: Layered Wrapper Functions

\`\`\`bash
#!/usr/bin/env bash
# CLI wrapper pattern with retry, timeout, and output validation

set -euo pipefail

# Configuration
readonly BD_TIMEOUT="${BD_TIMEOUT:-30}"  # seconds
readonly BD_MAX_RETRIES="${BD_MAX_RETRIES:-3}"
readonly BD_RETRY_DELAY="${BD_RETRY_DELAY:-1}"

# Low-level: Execute bd with timeout and capture output
_bd_exec() {
  local args=("$@")
  local output
  local exit_code=0

  # Use timeout to prevent hanging
  if output=$(timeout "$BD_TIMEOUT" bd "${args[@]}" 2>&1); then
    echo "$output"
    return 0
  else
    exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      echo "ERROR: bd command timed out after ${BD_TIMEOUT}s" >&2
    else
      echo "ERROR: bd command failed with exit code $exit_code" >&2
      echo "Output: $output" >&2
    fi
    return $exit_code
  fi
}

# Mid-level: Execute with retry logic
_bd_with_retry() {
  local attempt=1
  local output
  local exit_code

  while [[ $attempt -le $BD_MAX_RETRIES ]]; do
    exit_code=0
    output=$(_bd_exec "$@") || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
      echo "$output"
      return 0
    fi

    # Don't retry on certain errors
    if [[ "$output" == *"not found"* ]] || [[ "$output" == *"already exists"* ]]; then
      return $exit_code
    fi

    if [[ $attempt -lt $BD_MAX_RETRIES ]]; then
      echo "Retry $attempt/$BD_MAX_RETRIES after ${BD_RETRY_DELAY}s..." >&2
      sleep "$BD_RETRY_DELAY"
    fi

    ((attempt++))
  done

  return $exit_code
}

# High-level: Typed operations with validation

# Create task - returns task ID
create_task() {
  local title="$1"
  local description="$2"
  local label="$3"
  local estimate="$4"
  local epic_id="$5"
  local assignee="${6:-general}"

  local output
  output=$(_bd_with_retry \
    create \
    --title="$title" \
    --type=task \
    --priority=2 \
    --labels="$label" \
    --estimate="$estimate" \
    --assignee="$assignee" \
    --description="$description" \
    --parent="$epic_id" \
    --json)

  # Validate and extract ID
  local task_id
  task_id=$(echo "$output" | jq -r '.id // empty')

  if [[ -z "$task_id" ]]; then
    echo "ERROR: Failed to extract task ID from response" >&2
    return 1
  fi

  echo "$task_id"
}

# List tasks with filter - returns JSON array
list_tasks() {
  local filter="${1:-}"
  local args=(list --json)

  [[ -n "$filter" ]] && args+=(--title-contains="$filter")

  _bd_with_retry "${args[@]}"
}

# Add dependency - idempotent (succeeds if already exists)
add_dependency() {
  local dependent="$1"
  local blocker="$2"

  # bd dep add fails if dependency exists - we want idempotency
  local output
  if output=$(_bd_exec dep add "$dependent" "$blocker" 2>&1); then
    return 0
  elif [[ "$output" == *"already exists"* ]] || [[ "$output" == *"duplicate"* ]]; then
    # Consider this success
    return 0
  else
    echo "ERROR: Failed to add dependency: $output" >&2
    return 1
  fi
}
\`\`\`

### Pattern: Input Validation Before CLI Call

\`\`\`bash
# Validate inputs before calling external CLI to fail fast
validate_task_input() {
  local title="$1"
  local description="$2"
  local estimate="$3"
  local errors=()

  # Title validation
  if [[ -z "$title" ]]; then
    errors+=("Title is required")
  elif [[ ${#title} -gt 200 ]]; then
    errors+=("Title exceeds 200 characters")
  fi

  # Estimate validation
  if ! [[ "$estimate" =~ ^[0-9]+$ ]]; then
    errors+=("Estimate must be a positive integer (minutes)")
  elif [[ $estimate -gt 10080 ]]; then  # 1 week in minutes
    errors+=("Estimate exceeds maximum (10080 minutes = 1 week)")
  fi

  # Description validation
  if [[ -z "$description" ]]; then
    errors+=("Description is required")
  fi

  if [[ ${#errors[@]} -gt 0 ]]; then
    echo "Validation errors:" >&2
    printf '  - %s\n' "${errors[@]}" >&2
    return 1
  fi

  return 0
}
\`\`\`

### Recommendation

**Implement a 3-layer wrapper architecture:**

1. **Low-level (`_bd_exec`):** Timeout, raw execution, exit code handling
2. **Mid-level (`_bd_with_retry`):** Retry logic, transient error detection
3. **High-level (`create_task`, `list_tasks`, etc.):** Domain operations, validation

This matches patterns from `gh` CLI and `kubectl` wrappers.

---

## Pattern 6: Dependency Resolution Algorithms

### Problem

Task dependencies form a DAG (Directed Acyclic Graph). Need to:
1. Detect cycles
2. Determine creation order
3. Batch independent tasks for efficiency

### Solution A: Topological Sort (Kahn's Algorithm)

\`\`\`bash
#!/usr/bin/env bash
# Topological sort for task ordering using Kahn's algorithm

# Input: JSON array of tasks with dependencies
# Output: Tasks in dependency order (ready to create)

topological_sort() {
  local tasks_json="$1"

  python3 << 'PYTHON' - "$tasks_json"
import json
import sys
from collections import defaultdict, deque

tasks_json = sys.argv[1]
tasks = json.loads(tasks_json)

# Build graph
graph = defaultdict(list)  # task -> list of dependents
in_degree = defaultdict(int)  # task -> number of dependencies
all_tasks = set()

for task in tasks:
    task_id = task['id']
    all_tasks.add(task_id)
    in_degree[task_id]  # Ensure entry exists

    for dep in task.get('dependencies', []):
        graph[dep].append(task_id)
        in_degree[task_id] += 1

# Kahn's algorithm
queue = deque([t for t in all_tasks if in_degree[t] == 0])
result = []

while queue:
    current = queue.popleft()
    result.append(current)

    for dependent in graph[current]:
        in_degree[dependent] -= 1
        if in_degree[dependent] == 0:
            queue.append(dependent)

# Check for cycles
if len(result) != len(all_tasks):
    # Find tasks in cycle
    remaining = [t for t in all_tasks if t not in result]
    print(f"ERROR: Cycle detected in tasks: {remaining}", file=sys.stderr)
    sys.exit(1)

# Output sorted task IDs
print(json.dumps(result))
PYTHON
}

# Usage
order=$(topological_sort '[
  {"id": "T001", "dependencies": []},
  {"id": "T002", "dependencies": ["T001"]},
  {"id": "T003", "dependencies": ["T001"]}
]')

echo "Creation order: $order"  # ["T001", "T002", "T003"] or ["T001", "T003", "T002"]
\`\`\`

### Solution B: Parallel Wave Detection

\`\`\`bash
#!/usr/bin/env bash
# Detect which tasks can be created in parallel (same wave)

# Output: Array of waves, each containing tasks that can be created together

parallel_waves() {
  local tasks_json="$1"

  python3 << 'PYTHON' - "$tasks_json"
import json
import sys
from collections import defaultdict

tasks_json = sys.argv[1]
tasks = json.loads(tasks_json)

# Build graph
dependencies = {}  # task -> set of dependencies
dependents = defaultdict(set)  # task -> set of dependents

for task in tasks:
    task_id = task['id']
    deps = set(task.get('dependencies', []))
    dependencies[task_id] = deps
    for dep in deps:
        dependents[dep].add(task_id)

# Find waves
waves = []
remaining = set(dependencies.keys())

while remaining:
    # Find tasks with all dependencies satisfied
    wave = [
        t for t in remaining
        if dependencies[t].issubset(
            set(t for wave in waves for t in wave)  # All previously created tasks
        )
    ]

    if not wave:
        # Cycle detected
        print(f"ERROR: Unable to resolve dependencies for: {remaining}", file=sys.stderr)
        sys.exit(1)

    waves.append(wave)
    remaining -= set(wave)

print(json.dumps(waves))
PYTHON
}

# Usage: Can create all tasks in wave[0] in parallel, then wave[1], etc.
\`\`\`

### Recommendation for Maestro

**Use Solution A (Topological Sort) with two-pass creation:**

1. **Phase 1:** Create all tasks in topological order (ensures parents exist before children)
2. **Phase 2:** Link dependencies (all IDs available)

**Why not parallel waves?**
- Maestro creates tasks sequentially (no parallelism needed per spec)
- Topological sort is simpler and sufficient
- Cycle detection happens naturally during sort

---

## Summary Recommendations

### Patterns to Adopt

| Pattern | Priority | Implementation Notes |
|---------|----------|------------------------|
| **Idempotent Task Creation** | High | Title-based lookup with batch query; store ID mapping |
| **Two-Pass Dependency Linking** | High | Phase 1: create all tasks; Phase 2: link deps; use state file for resume |
| **Progress Counter** | High | Simple `[N/M]` format; works in all contexts |
| **errexit + ERR Trap** | High | Standard in all Maestro scripts; JSON error output |
| **3-Layer CLI Wrapper** | Medium | `_bd_exec` -> `_bd_with_retry` -> `create_task` |
| **Topological Sort** | Medium | Python helper for DAG validation and ordering |

### Patterns to Avoid

| Pattern | Reason |
|---------|--------|
| Naive N+1 queries | Querying db for each task existence check |
| Single-pass dependency creation | Cannot link until all IDs known |
| Progress bars in non-TTY | Breaks agent parsing; ANSI escape issues |
| set -e without pipefail | Misses errors in pipeline middle |
| Automatic retry on all errors | Should not retry "not found" or auth errors |

### Risk Mitigations

| Risk | Mitigation |
|------|------------|
| Partial state (tasks created, deps not linked) | Store progress in state.json; allow resume |
| beads CLI timeout/unavailable | 30s timeout; clear error message; suggest check |
| Cycle in task dependencies | Topological sort detects and reports |
| Duplicate task creation | Title-based idempotency check |
| JSON parsing failure | Validate beads output; fail fast with details |

---

## References

### Shell Scripting Best Practices

1. **Google Shell Style Guide** - https://google.github.io/styleguide/shellguide.html
   - Functions, error handling, quoting patterns
   - Arrays, parameter expansion

2. **BashFAQ/105 - Greg's Wiki** - https://mywiki.wooledge.org/BashFAQ/105
   - `set -e` pitfalls and proper usage
   - Error handling edge cases

3. **ShellCheck** - https://www.shellcheck.net/
   - Static analysis for shell scripts

### CLI Design Patterns

1. **git-extras** - https://github.com/tj/git-extras
   - Shell-based CLI extension patterns
   - Subcommand dispatch, error handling

2. **gh CLI** - https://cli.github.com/
   - JSON output handling
   - Progress indication in batch operations

### Dependency Resolution

1. **Kahn's Algorithm** - Topological sort for DAGs
   - O(V + E) complexity
   - Cycle detection built-in

2. **Task Management Systems**
   - Make: dependency resolution for builds
   - Airflow: DAG scheduling patterns
   - Temporal: workflow state management

---

## Appendix: Example Integration

### Complete Task Creation Script Structure

\`\`\`
.maestro/scripts/
├── bd-helpers.sh          # Existing: low-level bd wrappers
├── create-tasks.sh        # NEW: Main task creation script
└── lib/
    ├── progress.sh        # NEW: Progress reporting utilities
    ├── idempotency.sh     # NEW: Task existence checking
    └── validation.sh      # NEW: Input validation
\`\`\`

### Input Format (JSON)

\`\`\`json
{
  "feature_id": "019-improve-maestro-task-creation",
  "epic": {
    "title": "019: Improve Maestro Task Creation",
    "description": "..."
  },
  "tasks": [
    {
      "id": "T001",
      "title": "Create bd-helpers.sh wrapper",
      "description": "...",
      "label": "backend",
      "estimate": 60,
      "assignee": "general",
      "dependencies": []
    },
    {
      "id": "T002",
      "title": "Implement two-pass dependency linking",
      "description": "...",
      "label": "backend",
      "estimate": 90,
      "assignee": "general",
      "dependencies": ["T001"]
    }
  ]
}
\`\`\`

### Expected Output (JSON)

\`\`\`json
{
  "ok": true,
  "epic_id": "bd-abc123",
  "tasks_created": 10,
  "tasks_skipped": 0,
  "duration_seconds": 5.2,
  "created_ids": {
    "T001": "bd-xyz001",
    "T002": "bd-xyz002"
  }
}
\`\`\`

Or on error:

\`\`\`json
{
  "ok": false,
  "error": "Failed to create task T003: beads timeout",
  "phase": "task_creation",
  "tasks_created_before_error": 2,
  "created_ids": {
    "T001": "bd-xyz001",
    "T002": "bd-xyz002"
  },
  "suggestion": "Check beads daemon status and retry"
}
\`\`\`

---

*End of Pattern Catalog*
