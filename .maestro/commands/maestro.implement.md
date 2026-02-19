---
description: >
  Implement all available tasks for a feature. Loops through ready tasks,
  routes by label, spawns sub-agents, runs reviews, enforces compile gates,
  triggers PM validation, and runs post-epic analysis when done.
  Never implements directly — always delegates to sub-agents.
argument-hint: [feature-id]
---

# maestro.implement

Implement feature: **$ARGUMENTS**

## Step 1: Find the Feature

If `$ARGUMENTS` contains a feature ID, use it. Otherwise, find the most recent feature.

**Resolving the feature ID:**

1. If `$ARGUMENTS` is provided:
   - Use it as the feature ID directly
   - Read the state file: `.maestro/state/{feature_id}.json`

2. If `$ARGUMENTS` is empty:
   - List all state files: `.maestro/state/*.json`
   - Sort by `updated_at` descending
   - Use the most recently updated feature

**From the state file, extract:**

- `feature_id` — the NNN-slug identifier
- `epic_id` — the bd epic ID (set during `/maestro.tasks`)
- `spec_path` — path to the spec for context
- `branch` — the git branch to work on
- `stage` — current stage (should be "tasks" or later)

**Validation:**

- If no state file exists → tell the user to run `/maestro.specify` first and stop
- If no `epic_id` exists → tell the user to run `/maestro.tasks` first to create the bd epic and stop
- If the current git branch doesn't match the feature branch → switch to it: `git checkout {branch}`

## Step 2: Get Ready Tasks

```bash
bd ready --json
```

Parse the output to get tasks that belong to this epic.

**If no tasks are ready:**

- Check for blocked tasks:
  ```bash
  bd blocked
  ```
- Check for in-progress tasks:
  ```bash
  bd list --status in_progress --json
  ```
- **If all tasks are closed** → Go to Step 8 (Post-Epic Analysis)
- **If tasks are in progress** → Wait and report which tasks are being worked on. Re-check after they complete.
- **If tasks are blocked** → Show the blocking graph: which tasks are blocked and what they depend on. Ask the user if they want to intervene or wait.

**If 1 task is ready:**

- Proceed directly to Step 3 with that single task

**If 2+ tasks are ready:**

- Proceed to Step 2b to assess parallelism

## Step 2b: Assess Parallelism

When multiple tasks are ready, determine which can safely execute in parallel.

**Independence criteria — ALL must be true for a pair of tasks:**

1. Tasks target different directories/modules (check file paths in descriptions)
2. No shared file paths appear in both task descriptions
3. No dependency relationship exists between them (neither blocks the other)
4. Both are implementation tasks (not a review paired with its implementation)

**Parallel execution rules:**

- Maximum **3** concurrent sub-agents at any time
- Same-directory tasks MUST run sequentially (merge conflicts risk)
- A review task runs AFTER its corresponding implementation task completes
- PM-validation runs AFTER all reviews in the epic complete
- Fix tasks run sequentially to avoid compounding failures

**Example parallel scenarios:**

| Scenario                                                | Execution                      |
| ------------------------------------------------------- | ------------------------------ |
| Backend task in `src/api/` + Frontend task in `src/ui/` | Parallel                       |
| Two backend tasks both modifying `src/api/routes.go`    | Sequential                     |
| Implementation task + its paired review task            | Sequential (review after impl) |
| Two reviews for independent implementations             | Parallel                       |
| Fix task + unrelated implementation                     | Sequential (fix first)         |

**Grouping output:**

After assessment, produce an ordered execution plan:

```
Batch 1 (parallel): [T001, T003]    — independent modules
Batch 2 (sequential): [T002-review] — review of T001
Batch 3 (parallel): [T004, T005]    — independent modules
```

## Step 3: Route by Label

For each ready task, inspect its labels to determine which handler to invoke.

**Routing table:**

| Label           | Action                                            |
| --------------- | ------------------------------------------------- |
| `backend`       | Execute as implementation task (Step 4)           |
| `frontend`      | Execute as implementation task (Step 4)           |
| `test`          | Execute as implementation task (Step 4)           |
| `fix`           | Execute as implementation task (Step 4)           |
| `refactor`      | Execute as implementation task (Step 4)           |
| `review`        | Execute as review task → `/maestro.review {id}`   |
| `pm-validation` | Execute as PM validation → `/maestro.pm-validate` |

**Label resolution rules:**

1. Read the task labels from `bd show {task_id} --json`
2. Match against the routing table above
3. If a task has multiple labels, use the FIRST match in the table order
4. If no label matches → default to implementation task (Step 4)
5. Log the routing decision:
   ```
   Routing: {task_id} ({title}) → {handler} [label: {matched_label}]
   ```

## Step 4: Execute Implementation Task

For implementation tasks (backend, frontend, test, fix, refactor):

### 4a: Read task details

```bash
bd show {task_id} --json
```

Extract: `id`, `title`, `description`, `assignee`, `labels`, `status`.

If task is not ready (has blocking dependencies), show blocking tasks and skip.

### 4b: Mark in progress

```bash
bd update {task_id} --status in_progress
```

### 4c: Read context

Read files mentioned in the task description, plus:

- `.maestro/constitution.md` — for architectural constraints

### 4d: Spawn implementation agent

```
Task(
  subagent_type="{assignee from task}",
  description="Implement: {task_title}",
  prompt="Implement the following task:

  Task ID: {task_id}
  Title: {task_title}

  ## Description
  {full task description from bd show}

  ## Files to Modify
  {files list from task description}

  ## Acceptance Criteria
  {criteria from task description}

  ## Constitution Constraints
  {relevant sections from constitution}

  ## Instructions
  1. Read the referenced files
  2. Implement the changes following any code examples provided
  3. CRITICAL — PRESERVE EXISTING FUNCTIONALITY:
     - Before modifying any file, read it fully and understand ALL existing
       features, handlers, switch cases, and registered routes/topics
     - Your task is ADDITIVE: add new code without removing or breaking
       existing code paths
     - If a file handles multiple entities/features, keep ALL of them intact
     - If you need to refactor a shared file, ensure every pre-existing
       behavior still works after your changes
     - When in doubt, ADD a new case/handler rather than replacing an
       existing one
  4. After implementing, you MUST run the compile gate:
     bash .maestro/scripts/compile-gate.sh
  5. If the compile gate fails, fix the errors and re-run until it passes
  6. Do NOT report your work as complete until the gate passes
  7. Ensure all acceptance criteria are met

  ## Output Format
  When complete, report using this exact format:
  DONE | files: {comma-separated list} | pattern: {pattern used} | ref: {reference file if any}

  If you cannot complete the task, report:
  BLOCKED | reason: {why} | needs: {what is needed}"
)
```

### 4e: Parse result and close

**If DONE:**

```bash
bd close {task_id} --reason "{sub-agent result}"
```

**If BLOCKED:**

- Show the user why and what's needed
- Do NOT close the task
- Continue with other ready tasks

## Step 5: Execute Review Task

For tasks with label `review`, spawn `/maestro.review`:

```
Task(
  description="Review: {task_id} - {task_title}",
  prompt="Run the following command and report the result:

  /maestro.review {task_id}

  When complete, report:
  REVIEW_DONE | task: {task_id} | verdict: {PASS|MINOR|CRITICAL}

  If CRITICAL, report any fix tasks created."
)
```

Wait for the review to complete. If CRITICAL, new fix tasks will appear in `bd ready`.

## Step 6: Execute PM Validation

For tasks with label `pm-validation`, spawn `/maestro.pm-validate`:

```
Task(
  description="PM Validate: {feature_id}",
  prompt="Run the following command and report the result:

  /maestro.pm-validate {feature_id}

  Report the verdict: COMPLETE | GAPS_FOUND | REGRESSION"
)
```

## Step 7: Track Progress and Continue Loop

After each task or batch completes, display progress:

```bash
bd stats
```

**Display format:**

```
━━━ Implementation Progress ━━━
Feature: {feature_id} — {feature_title}
Epic: {epic_id}

Tasks: {completed}/{total} ({percentage}%)
├─ Completed: {count}
├─ In Progress: {count}
├─ Ready: {count}
├─ Blocked: {count}
└─ Total: {count}

Current Stage: {implementing | reviewing | validating}
Last Completed: {task_id} — {task_title} ({close_reason})
Next Up: {next_task_ids}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Update the state file** with current progress:

```json
{
  "stage": "implement",
  "progress": {
    "completed": 0,
    "total": 0,
    "percentage": 0
  }
}
```

**Then go back to Step 2.**

The loop continues until one of these exit conditions:

**Normal exit — All tasks closed:**

- `bd ready` returns no tasks
- `bd blocked` returns no tasks
- `bd list --status open --json` returns no tasks
- → Proceed to Step 8

**Abnormal exit — Human intervention required:**

- A review returned GAPS_FOUND 3 times for the same implementation
- 3+ tasks are blocked simultaneously
- A task failed 3 times
- → Stop and report with full context

**Between iterations:**

- Always re-run `bd ready --json` to get fresh task list (new fix tasks may have appeared)
- Always re-assess parallelism (dependencies may have changed)
- Show progress (Step 7)

## Step 8: Post-Epic Analysis

When all tasks are closed, trigger:

```
/maestro.analyze {feature_id}
```

This collects metrics, computes patterns, and proposes improvements for human approval.

## Step 9: Report Completion

```
━━━ Feature Complete ━━━━━━━━━━━━━━━━━━━━

Feature: {feature_id} — {feature_title}
Branch: {branch}

Metrics
  Total Tasks:         {count}
  Reviews:             {passed}/{total} ({pass_rate}%)
  Fix Tasks Created:   {count}
  Regressions Found:   {count}

Files Modified: {total unique files}

Next Steps:
  1. Create PR:          /maestro.commit then create PR
  2. Deploy to staging:  (manual)
  3. Start next feature: /maestro.specify <next feature>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Update the state file** to reflect completion:

```json
{
  "stage": "complete",
  "completed_at": "{ISO timestamp}"
}
```

---

## Rules

1. **Never implement directly** — ALL work is delegated to sub-agents. The orchestrator reads state, routes, tracks, and delegates. It never writes application code.

2. **Parallel when possible** — Execute independent tasks across different modules in parallel using multiple Task() calls in a single message. Max 3 concurrent.

3. **Route by label** — Always check the task label to determine the correct handler. Never assume a task type.

4. **Compile gate is mandatory** — Every implementation task must pass the compile gate before being considered done. Delegated to sub-agents.

5. **Fix tasks need reviews** — When a review finds CRITICAL gaps, it creates a fix task AND a review task. Both must execute in order.

6. **Structured close reasons** — Every task close uses the pipe-delimited format: `DONE | files: ... | pattern: ...`. This feeds post-epic learning.
