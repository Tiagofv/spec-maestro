---
description: Break the implementation plan into bd issues with dependencies. Creates an epic with implementation tasks, review tasks, and PM validation.
argument-hint: [feature-id] [--dry-run]
---

# maestro.tasks

Create bd issues from the implementation plan.

## Step 1: Prerequisites Check

Run the prerequisite check:

```bash
bash .maestro/scripts/check-prerequisites.sh tasks
```

If it fails, show the error and suggestion, then stop.

## Step 2: Find the Plan

If `$ARGUMENTS` contains a feature ID, use it. Otherwise, find the most recent feature in `.maestro/specs/`.

Read:

- The plan: `.maestro/specs/{feature_id}/plan.md`
- The config: `.maestro/config.yaml` (Note: `agent_routing` is no longer used. Assignees come from the plan.)
- The state: `.maestro/state/{feature_id}.json`
- `worktree_path` — from state.json (may be absent for pre-worktree features)
- `worktree_required` — optional; defaults to `true` when absent

## Step 2b: Enforce Worktree Invariant Metadata

Before creating tasks, normalize worktree metadata in state.json.

1. Determine `worktree_required`:
   - If state has `worktree_required`, use it
   - Otherwise set `worktree_required=true` (default)
2. If `worktree_required=true`, ensure state has:
   - `worktree_name`
   - `worktree_path`
   - `worktree_branch`
   - `worktree_created` (default `false` if missing)
3. For legacy features missing metadata, backfill using feature/branch defaults and append history action `"worktree metadata backfilled"`.
4. If `worktree_required=false`, keep metadata optional and append history action `"worktree opt-out preserved"`.

## Step 3: Idempotency Check

Check if tasks already exist for this feature:

- If state.json has `epic_id` field, tasks exist
- Warn the user: "Tasks already exist for this feature (epic: {epic_id})"
- Show current task status: `bd show {epic_id} --children`
- Offer options:
  1. **Abort**: Stop and preserve existing tasks (default)
  2. **Regenerate**: Archive existing epic and create fresh tasks
- If user doesn't explicitly choose Regenerate, abort.

### 3.1 Preserve In-Flight Assignees on Regenerate

When regenerating tasks against an existing bd epic, walk each task in the plan in
order. For each existing bd task that maps to a task in the regenerated plan:

1. Read the existing bd task's status: `bd show <task_id> --json | jq -r .status`.
2. If status is `open`:
   - Apply the new assignee from the regenerated plan (per Step 5.2).
   - No annotation needed.
3. If status is `in_progress`, `blocked`, or `closed`:
   - **Preserve the existing assignee.** Do not overwrite.
   - On the corresponding line in the regenerated `plan.md`, append a
     `[divergence: was X, plan now suggests Y]` annotation, where X is the preserved
     assignee from bd and Y is what the new selection would have chosen.
4. If a task in the regenerated plan does not exist in bd, create it with the new
   selection (no special handling).

This rule applies independently to impl and review tasks; both are scored independently
in the new plan, so divergence on either side is reported separately.

## Step 4: Parse the Plan

Extract from the plan:

1. **Feature title** — from the header
2. **Phases** — each implementation phase
3. **Components** — new and modified components
4. **Tests** — from testing strategy

## Step 4a: Parse Task Markers

Use regex to extract tasks from plan.md:

**Task Marker Pattern:**

```regex
<!-- TASK:BEGIN id=(T\d{3}) -->([\s\S]*?)<!-- TASK:END -->
```

**Extraction Rules:**

1. Find all TASK:BEGIN/TASK:END blocks
2. Extract `id` from marker attribute (format: T###)
3. Parse task metadata from content:
   - **Title**: First H3 header (### {title}) after TASK:BEGIN
   - **Label**: From `**Label:**` field (infrastructure/agent/core/ui/integration/template/testing/review/pm-validation)
   - **Size**: From `**Size:**` field (XS/S/M/L) — reject M/L with warning
   - **Assignee**: From `**Assignee:**` field — default to `general` if blank
   - **Dependencies**: From `**Dependencies:**` field (comma-separated T### IDs, or "None")
4. Extract file paths from `**Files to Modify:**` section (bullet list)
5. Store in structured array for processing

**Example parsing:**

```markdown
<!-- TASK:BEGIN id=T001 -->

### T001: Create Research State Manager

**Metadata:**

- **Label:** infrastructure
- **Size:** S
- **Assignee:** general
- **Dependencies:** None

**Files:**

- `.maestro/scripts/research-state.sh`
<!-- TASK:END -->
```

Extracts to:

```json
{
  "id": "T001",
  "title": "Create Research State Manager",
  "label": "infrastructure",
  "size": "S",
  "assignee": "general",
  "dependencies": [],
  "files": [".maestro/scripts/research-state.sh"]
}
```

## Step 4b: Validate Parsed Tasks

For each parsed task, validate:

| Check        | Rule                        | On Failure                  |
| ------------ | --------------------------- | --------------------------- |
| ID format    | Matches `T###`              | Log error, skip task        |
| Title        | Not empty                   | Log error, skip task        |
| Size         | XS or S only                | Log warning, skip M/L tasks |
| Label        | Valid label                 | Default to `general`        |
| Dependencies | Reference existing T### IDs | Log warning, set to empty   |

**Validation Output:**

```
Validated X tasks:
  ✓ Passed: Y
  ⚠ Skipped: Z (see logs)
```

Create a task list with validated tasks:

- Title (imperative verb + what)
- Description (detailed implementation guidance)
- Size estimate (XS/S based on complexity)
- Label (infrastructure/agent/core/ui/integration/template/testing)
- Dependencies (which tasks must complete first)

## Step 5: Map Sizes and Assignees

Read from `.maestro/config.yaml`:

For each task:

### 5.1 Size Mapping

Convert T-shirt size to minutes:

| Size | Default Minutes | Config Key                             |
| ---- | --------------- | -------------------------------------- |
| XS   | 120             | `size_mapping.XS`                      |
| S    | 360             | `size_mapping.S`                       |
| M    | 720             | `size_mapping.M` (reject, log warning) |
| L    | 1200            | `size_mapping.L` (reject, log warning) |

**Fallback:** If `size_mapping` missing from config, use defaults above.

### 5.2 Assignee Resolution

**Priority order:**

1. Use assignee from plan task metadata (parsed in Step 4) — this includes review tasks, which carry their own assignee picked independently in plan generation (see `maestro.plan.md` Step 4b.4)
2. If blank/missing → default to `general`
3. For PM-VAL task → default to `general`

**Validation:**

- Assignee must be non-empty string
- No validation against agent registry (bd will handle)
- Review-task assignees may be `general` (when no review-capable agent matched) but must NEVER equal the parent impl task's assignee unless both are `general`

### 5.3 Review Task Sizing

For each implementation task, create paired review task:

| Impl Size | Review Size | Review Minutes            |
| --------- | ----------- | ------------------------- |
| XS        | XS          | `review_sizing.XS` or 120 |
| S         | XS          | `review_sizing.S` or 120  |

**Fallback:** If `review_sizing` missing, use 120 minutes for all review tasks.

## Step 6: Generate Task Table

Build a table of all tasks with explicit generation rules:

### 6.1 Implementation Tasks

For each validated parsed task:

| Field      | Value        | Source                                |
| ---------- | ------------ | ------------------------------------- |
| ID         | `{task_id}`  | From parsed marker (T001, T002, etc.) |
| Title      | `{title}`    | From parsed H3 header                 |
| Label      | `{label}`    | From parsed metadata                  |
| Size       | `{size}`     | From parsed metadata (XS/S only)      |
| Minutes    | `{minutes}`  | From Step 5.1 size mapping            |
| Assignee   | `{assignee}` | From Step 5.2 resolution              |
| Blocked By | `{deps}`     | From parsed dependencies              |

### 6.2 Review Tasks (Auto-Generated)

For each implementation task, generate paired review:

| Field      | Value                  | Example                                 |
| ---------- | ---------------------- | --------------------------------------- |
| ID         | `R{task_num}`          | R001 for T001                           |
| Title      | `Review: {impl_title}` | "Review: Create Research State Manager" |
| Label      | `review`               | Fixed                                   |
| Size       | XS                     | From Step 5.3                           |
| Minutes    | 120                    | From Step 5.3                           |
| Assignee   | `{review_assignee_from_plan}`  | Independently selected review-capable agent (or `general` with `[review-fallback]`); see `maestro.plan.md` Step 4b.4 |
| Blocked By | `{impl_task_id}`       | T001 blocks R001                        |

**Review Task Description Template:**

```markdown
Code review for implementation task {task_id}.

**Files to Review:**
{impl_files_list}

**Review Checklist:**

- [ ] Implementation matches acceptance criteria
- [ ] Code follows project conventions
- [ ] No hardcoded secrets or credentials
- [ ] Error handling is complete
- [ ] Tests cover happy path and edge cases
- [ ] No breaking changes to public APIs
- [ ] Performance implications considered
- [ ] Constitutional compliance verified
```

### 6.3 PM Validation Task (Auto-Generated)

After all impl+review pairs, create final validation task:

| Field      | Value                                 |
| ---------- | ------------------------------------- |
| ID         | PM-VAL (or next sequential ID)        |
| Title      | `PM-VAL: {feature_title} Validation`  |
| Label      | `pm-validation`                       |
| Size       | XS                                    |
| Minutes    | 120                                   |
| Assignee   | `general` (or from config)            |
| Blocked By | ALL review task IDs (comma-separated) |

**PM-VAL Description Template:**

```markdown
PM validation for {feature_title}.

**Validation Checklist:**

- [ ] All acceptance criteria from spec met
- [ ] Integration tests pass
- [ ] No regressions in existing functionality
- [ ] Documentation complete
- [ ] Feature ready for release

Run `/maestro.pm-validate` to execute validation.
```

### 6.4 Task Table Format

```
| #   | ID     | Title                           | Label          | Size | Minutes | Assignee |
| --- | ------ | ------------------------------- | -------------- | ---- | ------- | -------- |
| 1   | T001   | Create Research State Manager   | infrastructure | S    | 360     | general  |
| 2   | R001   | Review: T001                    | review         | XS   | 120     | general  |
| 3   | T002   | Create Agents Directory         | infrastructure | XS   | 120     | general  |
| 4   | R002   | Review: T002                    | review         | XS   | 120     | general  |
| ... | ...    | ...                             | ...            | ...  | ...     | ...      |
| N   | PM-VAL | PM-VAL: Feature Validation        | pm-validation  | XS   | 120     | general  |
```

Include:

- Implementation tasks paired with review tasks
- Final PM-VAL task blocked by ALL review tasks

## Step 7: Dry Run Mode

If `$ARGUMENTS` contains `--dry-run`:

- Show the task table
- Show what commands would be executed
- Do NOT create any tasks
- Stop here

## Step 8: Create Epic

```bash
source .maestro/scripts/bd-helpers.sh
EPIC_ID=$(bd_create_epic "{feature_id}: {feature_title}" "{plan summary}")
```

Store the epic ID for later.

## Step 9: Create Tasks

For each task in the table:

```bash
TASK_ID=$(bd_create_task \
  "{task_title}" \
  "{task_description}" \
  "{label}" \
  {estimate_minutes} \
  "$EPIC_ID" \
  "{assignee}")
```

**Worktree context:**

If `worktree_required=true`, append the following section to every task description:

```
## Worktree
Work in worktree: {worktree_path}
All file operations and git commands should be executed from this directory.
```

If `worktree_required=false` (explicit opt-out), omit this section.

Store task IDs in a map: `{task_id} → {bd_task_id}`

## Step 9a: Handle Task Creation Failures

If bd_create_task fails for any task:

### 9a.1 Immediate Actions

- Log error: `Failed to create task {task_id}: {error_message}`
- Store failed task in retry list: `{task_id, error}`
- Continue processing remaining tasks (don't stop)

### 9a.2 Partial Success Reporting

After all tasks processed, report:

```
Task Creation Results:
━━━━━━━━━━━━━━━━━━━━━
✓ Created: {success_count} tasks
✗ Failed:  {fail_count} tasks

Failed Tasks:
- {task_id}: {error_message}
- {task_id}: {error_message}
```

### 9a.3 Decision Gate

If any tasks failed:

- **If < 50% failed**: Ask user:
  - "Retry failed tasks?" → Re-run Step 9 for failed tasks only
  - "Continue without failed tasks?" → Proceed to dependency wiring
  - "Abort?" → Stop, suggest manual review
- **If ≥ 50% failed**: Recommend abort:

  ```
  ⚠️ {fail_count}/{total_count} tasks failed to create.
  This indicates a systemic issue (e.g., bd connection, permissions).

  Options:
  1. Retry all failed tasks (may fail again)
  2. Abort and investigate
  3. Continue manually with `bd create`
  ```

### 9a.4 Retry Logic

For retry:

- Wait 2 seconds between attempts
- Max 3 retry attempts per task
- If still failing after 3 attempts → Mark as permanently failed

### 9a.5 State Tracking

Update state.json with task creation results.

## Step 9b: Validate Dependencies Before Wiring

Before calling bd_add_dep:

### 9b.1 Dependency Checks

- Verify blocker task ID exists in created_tasks map
- Verify dependent task ID exists
- Skip wiring if blocker not found (log warning)
- Detect circular dependencies (shouldn't happen if plan is valid)

### 9b.2 Dependency Resolution

For each dependency:

```
Dependent: T003
Blocker: T001
Action: bd_add_dep "{t3_bd_id}" "{t1_bd_id}"
```

**Edge Cases:**

- If blocker task failed to create → Log warning, skip wiring
- If dependent task failed to create → Skip (already logged)
- If circular dependency detected → Log error, skip wiring

## Step 10: Wire Dependencies

For each task with dependencies:

```bash
bd_add_dep "{dependent_task_id}" "{blocker_task_id}"
```

## Step 11: Update State

Update `.maestro/state/{feature_id}.json`:

- Add `epic_id` field
- Add `task_count` field
- Set `stage` to `tasks`
- Add history entry

## Step 12: Report Results

Show the user:

1. Epic created with ID
2. Task table with all created tasks
3. Dependency tree visualization (use `bd dep tree {epic_id}`)
4. Suggest: "Run `/maestro.implement` to begin automated implementation."

---

**Task ID format:** `{feature_acronym}-{feature_number}-{task_number}` (e.g., MST-001-001)

**Review task pairing:** Every implementation task (backend/frontend/test) gets a paired review task blocked by it.

**PM Validation:** The final task, blocked by ALL review tasks, validates the entire feature.
