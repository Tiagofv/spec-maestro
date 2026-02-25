# Pitfall Register: Maestro Task Creation on Beads

**Feature:** 019 - Improve Maestro Task Creation on Beads  
**Research Date:** 2024-02-23  
**Author:** Research Agent

---

## Executive Summary

This document catalogs known pitfalls, failure modes, and mitigation strategies for implementing an optimized task creation script. The current approach (individual agent invocations) takes ~10 minutes for 50 tasks; the optimized script approach targets <30 seconds.

**Risk Level:** MEDIUM - Task creation is a critical path operation; failures leave the system in inconsistent states.

---

## 1. Task Creation Scripts

### Pitfall 1.1: Silent Failures from Error Suppression

**Description:** The current `bd-helpers.sh` uses `2>/dev/null` extensively, which suppresses error messages that could indicate partial failures or API issues.

**Evidence:**

- Line 21: `bd create ... --json 2>/dev/null | grep ...`
- Line 43: Same pattern in `bd_create_task`
- Line 51: `bd dep add ... 2>/dev/null || true`

**Impact:** HIGH - Failures are invisible; scripts appear to succeed when they actually failed.

**Mitigation:**

```bash
# Capture stderr separately instead of suppressing
BD_OUTPUT=$(bd create ... --json 2>"$TMPDIR/bd_error_$$.log")
BD_EXIT=$?
if [[ $BD_EXIT -ne 0 ]]; then
  echo "Error: Task creation failed" >&2
  cat "$TMPDIR/bd_error_$$.log" >&2
  exit $BD_EXIT
fi
```

**War Story:** In PRM-001 implementation, dependency linking silently failed for 12 tasks due to `|| true` pattern, leaving orphaned dependencies that were only discovered during manual review.

---

### Pitfall 1.2: JSON Parsing Fragility

**Description:** Using `grep` and `cut` to parse JSON is fragile and will break when:

- Field order changes
- IDs contain special characters
- Output format changes slightly

**Evidence:**

- `grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4`

**Impact:** MEDIUM - Will fail unpredictably when bd CLI output format changes.

**Mitigation:**

```bash
# Use jq for robust JSON parsing
TASK_ID=$(bd create ... --json | jq -r '.id')
# Fallback to Python if jq unavailable
TASK_ID=$(bd create ... --json | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
```

**Recommendation:** Add `jq` as a prerequisite in `check-prerequisites.sh`.

---

### Pitfall 1.3: No Transaction Boundaries

**Description:** Task creation is not atomic. If the script fails mid-way, some tasks exist while others don't. There's no rollback mechanism.

**Impact:** HIGH - Partial state leaves the system inconsistent; requires manual cleanup.

**Mitigation:**

1. **Dry-run mode first** (already in spec): Validate entire plan before creating
2. **Staged creation**: Create all tasks in a staging state, then activate
3. **Cleanup on failure**: Track created tasks and delete on failure

```bash
# Track created tasks for cleanup
CREATED_TASKS=()
trap 'cleanup_on_failure' EXIT

cleanup_on_failure() {
  if [[ $? -ne 0 ]]; then
    echo "Rolling back created tasks..." >&2
    for task_id in "${CREATED_TASKS[@]}"; do
      bd delete "$task_id" --force 2>/dev/null || true
    done
  fi
}
```

---

## 2. Idempotency Implementation

### Pitfall 2.1: Title-Based Identity is Unreliable

**Description:** The spec mentions "check if each task already exists" but doesn't define the identity key. Using titles is problematic:

- Titles can change after creation
- Titles may not be unique
- Title matching is case-sensitive and whitespace-sensitive

**Impact:** MEDIUM - Can create duplicates or skip tasks that should be updated.

**Mitigation:**
Use a composite identifier stored in the task:

```bash
# Store feature_id + task_number in external_ref
EXTERNAL_REF="${FEATURE_ID}.${TASK_NUMBER}"

# Check existing
EXISTING=$(bd list --external-ref="$EXTERNAL_REF" --json | jq -r '.[0].id // empty')
if [[ -n "$EXISTING" ]]; then
  echo "Task already exists: $EXISTING"
  TASK_ID="$EXISTING"
else
  TASK_ID=$(bd create --external-ref="$EXTERNAL_REF" ...)
fi
```

**Deferred Decision:** The spec defers "Task identification strategy" to brainstorming. This must be resolved before implementation.

---

### Pitfall 2.2: State File vs. Beads State Drift

**Description:** The `state.json` file tracks `epic_id`, but if someone manually deletes tasks in beads, the state file becomes out of sync.

**Impact:** MEDIUM - Idempotency check passes (epic_id exists) but tasks don't exist.

**Mitigation:**

```bash
# Verify epic still exists before assuming idempotency
if [[ -n "$EPIC_ID" ]]; then
  if ! bd show "$EPIC_ID" --json >/dev/null 2>&1; then
    echo "Epic $EPIC_ID from state file no longer exists in beads"
    EPIC_ID=""
  fi
fi
```

---

## 3. Dependency Linking

### Pitfall 3.1: Two-Pass Creation Race Condition

**Description:** The spec calls for "two-pass creation": first pass creates tasks, second pass links dependencies. If a task creation fails in pass 1 but dependency linking proceeds in pass 2, it will reference non-existent tasks.

**Impact:** HIGH - Dependency linking will fail or create broken references.

**Mitigation:**

```bash
# Pass 1: Create tasks and validate all succeeded
for task in "${TASKS[@]}"; do
  TASK_ID=$(create_task "$task")
  if [[ -z "$TASK_ID" ]]; then
    echo "FAIL: Task creation failed, aborting before dependency phase"
    exit 1
  fi
  TASK_IDS["${task[id]}"]="$TASK_ID"
done

# Only proceed if all tasks created
if [[ ${#TASK_IDS[@]} -ne ${#TASKS[@]} ]]; then
  exit 1
fi

# Pass 2: Link dependencies (now safe)
```

---

### Pitfall 3.2: Dependency Cycles

**Description:** The task plan may contain circular dependencies (A depends on B, B depends on A). The script doesn't detect this, leading to infinite loops or bd errors.

**Impact:** MEDIUM - bd may reject the dependency or enter an inconsistent state.

**Mitigation:**

```bash
# Topological sort before linking
detect_cycle() {
  local -A in_degree
  local -A graph

  # Build graph
  for task_id in "${!DEPS[@]}"; do
    for dep_id in ${DEPS[$task_id]}; do
      graph[$dep_id]+=" $task_id"
      ((in_degree[$task_id]++))
    done
  done

  # Kahn's algorithm for cycle detection
  # ... implementation ...
}
```

**Note:** The spec mentions "dependency cycles" as a risk but doesn't require cycle detection in the script.

---

### Pitfall 3.3: Dependency Linking Failures Leave Partial Graph

**Description:** If dependency linking fails mid-way, some tasks have dependencies while others don't. There's no way to resume from where it left off.

**Impact:** MEDIUM - Manual intervention required to complete linking.

**Mitigation:**

- Track successfully linked dependencies in a temporary file
- Resume from last successful link on retry
- Store linking progress in state.json

---

## 4. Linear API Integration (Beads Backend)

### Pitfall 4.1: API Rate Limiting

**Description:** Creating 50+ tasks in rapid succession may trigger rate limiting on the Linear API (beads backend). The current script has no backoff mechanism.

**Evidence:**

- beads.db has 409 issues; likely backed by Linear
- No rate limiting handling in current scripts

**Impact:** HIGH - 429 errors will fail the entire task creation process.

**Mitigation:**

```bash
# Add delay between requests
RATE_LIMIT_DELAY=0.1  # 100ms between requests

for task in "${TASKS[@]}"; do
  create_task "$task"
  sleep "$RATE_LIMIT_DELAY"
done
```

**Alternative:** Use beads' bulk creation API if available (`bd create --file` with markdown).

---

### Pitfall 4.2: Database Lock Timeouts

**Description:** beads uses SQLite with a 30s busy timeout (`--lock-timeout 30s`). Under load, concurrent access may cause timeouts.

**Impact:** MEDIUM - "database is locked" errors.

**Mitigation:**

- Set higher timeout: `--lock-timeout 60s`
- Check if daemon mode is running (faster than file-based)
- Serialize operations (already planned)

---

### Pitfall 4.3: Network Failures Mid-Operation

**Description:** If the Linear API is temporarily unavailable or network flakes during task creation, the script will fail partway through.

**Impact:** HIGH - Partial state, requires cleanup.

**Mitigation:**

```bash
# Retry with exponential backoff
with_retry() {
  local max_attempts=3
  local delay=1

  for ((i=1; i<=max_attempts; i++)); do
    if "$@"; then
      return 0
    fi

    if [[ $i -lt $max_attempts ]]; then
      echo "Retry $i/$max_attempts: waiting ${delay}s..." >&2
      sleep $delay
      delay=$((delay * 2))
    fi
  done

  return 1
}

TASK_ID=$(with_retry bd create ...)
```

---

## 5. CLI Wrapper Scripts

### Pitfall 5.1: Environment Variable Pollution

**Description:** Scripts may inherit unexpected environment variables that affect bd behavior (e.g., `BEADS_DB`, `BD_ACTOR`).

**Impact:** LOW - Tasks created in wrong database or with wrong actor.

**Mitigation:**

```bash
#!/usr/bin/env bash
# Explicitly set required env vars
export BD_ACTOR="${BD_ACTOR:-maestro}"
# Clear potentially problematic vars
unset BEADS_DB  # Use auto-discovery
```

---

### Pitfall 5.2: Shell Word Splitting in Descriptions

**Description:** Task descriptions may contain special characters (quotes, newlines) that break shell command construction.

**Evidence:**

- `bd create --description="$desc"` - unquoted expansion vulnerable

**Impact:** MEDIUM - Tasks with complex descriptions fail to create.

**Mitigation:**

```bash
# Use a file for complex descriptions
cat > "$TMPDIR/desc_$$.txt" << 'EOF'
{task_description}
EOF

bd create --body-file="$TMPDIR/desc_$$.txt" ...
```

---

### Pitfall 5.3: POSIX vs. Bash Compatibility

**Description:** Scripts use `set -euo pipefail` (bash-specific) but some systems may have `/bin/sh` as dash.

**Impact:** LOW - Script may fail on some systems.

**Mitigation:**
Ensure shebang is `#!/usr/bin/env bash` (already correct in existing scripts).

---

## 6. Race Conditions

### Pitfall 6.1: Concurrent Task Creation

**Description:** If two agents run `/maestro.tasks` simultaneously for different features, they may race on:

- State file writes
- Epic ID generation
- Beads database access

**Impact:** MEDIUM - Corrupted state files or duplicate epics.

**Mitigation:**

```bash
# File locking for state file
exec 200>".maestro/state/${FEATURE_ID}.lock"
flock -x 200 || exit 1

# ... operations ...

# Lock released automatically on exit
```

---

### Pitfall 6.2: Git Worktree Conflicts

**Description:** Task creation may occur in a worktree context. If the worktree is deleted during task creation, relative paths in descriptions become invalid.

**Impact:** LOW - Broken paths in task descriptions.

**Mitigation:**

```bash
# Verify worktree still exists before adding worktree context
if [[ -n "$worktree_path" && ! -d "$worktree_path" ]]; then
  echo "Warning: Worktree $worktree_path no longer exists" >&2
  worktree_path=""
fi
```

---

## 7. Partial Failures

### Pitfall 7.1: Epic Created but Tasks Failed

**Description:** The spec says "stop immediately on first failure" but doesn't specify cleanup. If epic creation succeeds but first task fails, we have an empty epic.

**Impact:** MEDIUM - Orphaned epic requires manual cleanup.

**Mitigation:**

```bash
# Create epic only after validating all tasks can be created
# Or: Delete epic on failure
if [[ ${#CREATED_TASKS[@]} -eq 0 ]]; then
  # No tasks created, epic is useless
  bd delete "$EPIC_ID" --force 2>/dev/null || true
fi
```

---

### Pitfall 7.2: Dependency Linking Partial Failure

**Description:** Pass 1 succeeds (all tasks created), Pass 2 partially fails (some dependencies linked). Result: tasks exist but dependency graph is incomplete.

**Impact:** MEDIUM - Orchestrator may make incorrect scheduling decisions.

**Mitigation:**

- Store linking progress and allow resumption
- Add validation step: `bd dep tree $EPIC_ID` to verify graph integrity

---

## 8. Error Handling Edge Cases

### Pitfall 8.1: Non-Zero Exit Codes

**Description:** bd CLI may return non-zero exit codes in edge cases:

- Task with same title exists (if not using `--force`)
- Invalid assignee
- Label doesn't exist

**Impact:** MEDIUM - Script aborts without clear error message.

**Mitigation:**

```bash
# Capture and parse error output
capture_error() {
  local output exit_code
  output=$($* 2>&1)
  exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    echo "Command failed with exit code $exit_code:"
    echo "$output"
    return $exit_code
  fi
}
```

---

### Pitfall 8.2: Unicode and Special Characters

**Description:** Task titles and descriptions may contain Unicode, emoji, or special characters that cause encoding issues in shell scripts or JSON.

**Impact:** LOW - Task creation may fail or corrupt text.

**Mitigation:**

```bash
# Set UTF-8 locale
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# Validate JSON encoding
if ! echo "$DESCRIPTION" | jq . >/dev/null 2>&1; then
  echo "Warning: Description contains invalid characters" >&2
fi
```

---

## 9. State Consistency Issues

### Pitfall 9.1: State File Update Race

**Description:** Multiple scripts updating `state.json` concurrently can corrupt it.

**Evidence:**

- `maestro.tasks` updates state.json
- Other commands may also update it

**Impact:** MEDIUM - Corrupted JSON, lost state.

**Mitigation:**

```bash
# Atomic update using temp file
update_state() {
  local state_file="$1"
  local temp_file="${state_file}.tmp.$$"

  # Read, modify, write atomically
  jq '. + {"epic_id": "$EPIC_ID"}' "$state_file" > "$temp_file"
  mv "$temp_file" "$state_file"
}
```

---

### Pitfall 9.2: Out-of-Order State Transitions

**Description:** If task creation fails but state.json is updated anyway, the system thinks tasks exist when they don't.

**Impact:** HIGH - Idempotency check will skip creation on retry.

**Mitigation:**

- Update state.json ONLY after all operations succeed
- Use atomic transactions: write to temp file, rename on success

---

## 10. User Experience Problems

### Pitfall 10.1: Progress Indication Accuracy

**Description:** Simple progress bars can be misleading:

- "Creating task 1/50" but task 50 takes 10x longer than task 1
- No visibility into which phase (creation vs. dependency linking)

**Impact:** LOW - User confusion, premature cancellation.

**Mitigation:**

```bash
# Phase-aware progress
PHASES=("Creating epic" "Creating tasks" "Linking dependencies" "Updating state")
for phase in "${PHASES[@]}"; do
  echo "[$phase] ..."
done
```

---

### Pitfall 10.2: No Dry-Run Validation of Dependencies

**Description:** Dry-run mode shows what commands would be executed but doesn't validate that dependency references will resolve.

**Impact:** MEDIUM - User thinks plan is valid, but dependency linking will fail.

**Mitigation:**

```bash
# In dry-run mode, validate dependency references
if [[ "$DRY_RUN" == true ]]; then
  for task in "${TASKS[@]}"; do
    for dep in "${task[deps]}"; do
      if [[ -z "${TASK_IDS[$dep]}" ]]; then
        echo "ERROR: Task ${task[id]} depends on unknown task: $dep"
      fi
    done
  done
fi
```

---

### Pitfall 10.3: Error Messages Don't Suggest Recovery

**Description:** When task creation fails, the error doesn't tell the user how to recover (retry, abort, cleanup).

**Impact:** MEDIUM - User confusion.

**Mitigation:**
Include recovery suggestions in error output:

```bash
echo "Task creation failed at step $STEP" >&2
echo "" >&2
echo "Recovery options:" >&2
echo "  1. Retry: Run /maestro.tasks again (idempotent)" >&2
echo "  2. Cleanup: Run bd delete $EPIC_ID --force" >&2
echo "  3. Continue: Tasks created so far are valid; manually create remaining" >&2
```

---

## Recommendations Summary

### Must Implement (Critical)

1. **Remove `2>/dev/null` error suppression** - Replace with explicit error handling
2. **Add transaction boundaries** - Track created tasks, cleanup on failure
3. **Define idempotency key** - Use `external_ref` with feature_id + task_number
4. **Add rate limiting delay** - 100ms between API calls
5. **Validate before state update** - Only update state.json after all operations succeed

### Should Implement (High Priority)

6. **Use `jq` for JSON parsing** - More robust than grep/cut
7. **Add retry logic** - Exponential backoff for transient failures
8. **Detect dependency cycles** - Before attempting to link
9. **Add file locking** - Prevent concurrent state corruption
10. **Verify epic exists** - Before assuming idempotency

### Nice to Have (Medium Priority)

11. **Phase-aware progress** - Show which phase is running
12. **Better error messages** - Include recovery suggestions
13. **Unicode validation** - Prevent encoding issues
14. **Environment sanitization** - Clear/verify env vars

---

## References

### Existing Code

- `.maestro/scripts/bd-helpers.sh` - Current helper functions
- `.maestro/commands/maestro.tasks.md` - Task creation command spec
- `.maestro/specs/019-improve-maestroe-task-creation-on-beads-currently-/spec.md` - Feature spec

### Beads CLI Documentation

- `bd create --help` - Task creation options
- `bd dep --help` - Dependency management
- `bd info` - Database information

### War Stories

- **PRM-001:** Silent dependency linking failure due to `|| true` pattern
- **MST-001:** State file drift when tasks manually deleted
- **GSD:** Race condition in parallel task creation (mitigated by max 3 concurrent)

---

## Checklist for Implementation

Before marking this feature complete, verify:

- [ ] All `2>/dev/null` patterns removed or justified
- [ ] Error handling captures and reports stderr
- [ ] Idempotency key defined and documented
- [ ] Transaction boundaries implemented (cleanup on failure)
- [ ] Rate limiting delay added
- [ ] Retry logic with exponential backoff
- [ ] State file updates are atomic
- [ ] Progress indication shows phases
- [ ] Dependency cycle detection (or validation that beads handles it)
- [ ] Recovery suggestions in error messages

---

_Last Updated: 2024-02-23_
