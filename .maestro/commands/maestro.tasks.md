---
description: >
  Break the implementation plan into bd issues with dependencies.
  Creates an epic with implementation tasks, review tasks, and PM validation.
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
- The config: `.maestro/config.yaml`
- The state: `.maestro/state/{feature_id}.json`
- `worktree_path` — from state.json (may be absent for pre-worktree features)

## Step 3: Idempotency Check

Check if tasks already exist for this feature:

- If state.json has `epic_id` field, tasks exist
- Warn the user: "Tasks already exist for this feature (epic: {epic_id})"
- Show current task status: `bd show {epic_id} --children`
- Offer options:
  1. **Abort**: Stop and preserve existing tasks (default)
  2. **Regenerate**: Archive existing epic and create fresh tasks
- If user doesn't explicitly choose Regenerate, abort.

## Step 4: Parse the Plan

Extract from the plan:

1. **Feature title** — from the header
2. **Phases** — each implementation phase
3. **Components** — new and modified components
4. **Tests** — from testing strategy

Create a task list with:

- Title (imperative verb + what)
- Description (detailed implementation guidance)
- Size estimate (XS/S/M/L based on complexity)
- Label (backend/frontend/test based on type)
- Dependencies (which tasks must complete first)

## Step 5: Map Sizes and Assignees

Read from `.maestro/config.yaml`:

For each task:

1. Convert size to minutes using `size_mapping`
2. Determine assignee using `agent_routing[label]`
3. Determine review assignee using `agent_routing.review`
4. Calculate review size using `review_sizing`

## Step 6: Generate Task Table

Build a table of all tasks:

| #   | ID   | Title        | Label   | Size | Minutes | Assignee | Blocked By |
| --- | ---- | ------------ | ------- | ---- | ------- | -------- | ---------- |
| 1   | T001 | {title}      | backend | S    | 360     | {agent}  | —          |
| 2   | R001 | Review: T001 | review  | XS   | 120     | {agent}  | T001       |

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

**Worktree context:** If `worktree_path` is set in state.json, append the following section to every task description:

```
## Worktree
Work in worktree: {worktree_path}
All file operations and git commands should be executed from this directory.
```

If `worktree_path` is null or absent (pre-worktree feature), omit this section.

Store task IDs for dependency wiring.

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
