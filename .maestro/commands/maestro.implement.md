---
description: >
  Implement all available tasks for a feature. Loops through ready tasks,
  routes by label, spawns sub-agents, runs reviews, enforces compile gates,
  triggers PM validation, and runs post-epic analysis when done.
  Never implements directly — always delegates to sub-agents.
argument-hint: "[feature-id] [--no-worktree] [--resume]"
---

# maestro.implement

Implement feature: **$ARGUMENTS**

## Step 1: Find the Feature

First parse arguments into:

- `feature_id_arg` — positional feature ID if provided
- `no_worktree_flag` — true when `--no-worktree` is present

If `feature_id_arg` is set, use it. Otherwise, find the most recent feature.

**Resolving the feature ID:**

1. If `feature_id_arg` is provided:
   - Use it as the feature ID directly
   - Read the state file: `.maestro/state/{feature_id}.json`

2. If `feature_id_arg` is empty:
   - List all state files: `.maestro/state/*.json`
   - Sort by `updated_at` descending
   - Use the most recently updated feature

**From the state file, extract:**

- `feature_id` — the NNN-slug identifier
- `epic_id` — the bd epic ID (set during `/maestro.tasks`)
- `spec_path` — path to the spec for context
- `branch` — the git branch to work on
- `stage` — current stage (should be "tasks" or later)
- `worktree_required` — optional; defaults to `true` when absent

**Validation:**

- If no state file exists → tell the user to run `/maestro.specify` first and stop
- If no `epic_id` exists → tell the user to run `/maestro.tasks` first to create the bd epic and stop
- Worktree invariant: use a worktree by default for all features. Only skip worktree when explicitly requested (`--no-worktree`) or when state has `worktree_required: false`.

## Step 1b: Worktree Setup

Determine worktree mode:

1. If `no_worktree_flag=true`, set `worktree_required=false` for this run.
2. Else if state has `worktree_required: false`, set `worktree_required=false`.
3. Else set `worktree_required=true` (default behavior).

> **Recovery flag:** Use `--resume {feature_id}` to resume a partially provisioned feature without triggering the half-provisioned guard. When `--resume` is present, the provisioning loop skips repos that are already created and only provisions the missing ones. Rerunning on a fully provisioned feature is a no-op.

If `worktree_required=true`, enforce the worktree invariant:

**Half-provisioned guard (check before any `worktree-create.sh` calls):**

Read `state.worktrees` and compute:
- `N_created` = count of repos where `state.worktrees[repo].created == true`
- `N_total`   = `len(state.repos)`

If `N_created > 0` AND `N_created < N_total` AND the invocation is NOT `--resume`:

```
╔══════════════════════════════════════════════════════╗
║  HALF-PROVISIONED WORKTREES DETECTED                 ║
║  {N_created}/{N_total} repos have worktrees.         ║
║                                                      ║
║  Recovery options:                                   ║
║  1. Resume:  /maestro.implement --resume {feature}   ║
║  2. Restart: bash .maestro/scripts/worktree-cleanup.sh --all --feature {feature}  ║
║             then /maestro.implement {feature}        ║
╚══════════════════════════════════════════════════════╝
```

Stop immediately. Do not silently re-provision. Do not auto-tear-down.

Fully provisioned (`N_created == N_total`) and fully unprovisioned (`N_created == 0`) proceed normally.

**Provision one worktree per repo.** Iterate over `state.repos` and run `worktree-create.sh` for each entry:

```
For each repo in state.repos:
  If invoked with --resume AND state.worktrees[repo].created == true:
    Skip this repo (already provisioned).
  Else:
    Run: bash .maestro/scripts/worktree-create.sh --repo {repo} --feature {feature_id}
    - If successful, record the worktree path in state.worktrees[repo].
    - If it fails with "worktree already exists", treat as already created (idempotent).
    - If any worktree creation fails for any other reason, stop immediately.
      See the recovery section below.

If invoked with --resume AND all repos were skipped (all already created):
  Emit: "All worktrees already provisioned; resuming task execution."
  Proceed directly to task execution.
```

> **Single-repo note:** For single-repo features, `state.repos` has exactly one entry. The loop above runs once; behavior is indistinguishable from pre-062.

After the loop, update state.json:

1. Set `worktree_created: true` for each successfully provisioned repo.
2. Append history action `"worktrees provisioned: {repos}"`.

**Empty `state.repos` guard:**

If `state.repos` is present but is an empty array (`[]`):

```
ERROR: state.repos is empty. Run /maestro.tasks first,
or add repo entries to .maestro/state/{feature_id}.json before running /maestro.implement.
```

Stop immediately. This is distinct from the legacy fallback below (which triggers only when `state.repos` is absent).

**Legacy/pre-worktree state (missing `state.repos`):**

If `state.repos` is absent, derive a single-entry default:

- `repo`: basename of the project root
- Derive `worktree_name`, `worktree_path`, `worktree_branch`, `worktree_created` as before.
- Update state.json with derived fields and append history action `"worktree metadata backfilled"`.
- Then run the loop above with the single derived entry.

If `worktree_required=false` (explicit opt-out only):

- Switch branch directly: `git checkout {branch}`.
- Append state history action `"worktree opt-out for implement"` (include source: `--no-worktree` or state override).

**Invariant:** Unless explicitly opted out, implementation must run from a feature worktree.

---

> **Recovery:** If any worktree creation fails, stop and do not proceed to task execution.

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

**Note:** Labels determine the **handler type** (implementation, review, or PM-validation) — they do NOT determine which agent is used. The agent is read from the task's assignee field, which was set during `/maestro.plan`.

For each ready task, inspect its labels to determine which handler to invoke.

**Routing table:**

| Label           | Action                                            |
| --------------- | ------------------------------------------------- |
| `backend`       | Execute as implementation task (Step 4)           |
| `frontend`      | Execute as implementation task (Step 4)           |
| `test`          | Execute as implementation task (Step 4)           |
| `fix`           | Execute as implementation task (Step 4)           |
| `refactor`      | Execute as implementation task (Step 4)           |
| `review`        | Spawn assignee subagent with the review skill loaded → returns REVIEW_DONE verdict line |
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
- Convention memories from project memory — for coding conventions learned from PR reviews

**Convention Loading:**
If convention memories exist in Claude Code project memory (files matching `convention_*.md`):
1. Read each convention memory file
2. Check the `[scope: X]` tag in each file
3. Filter by scope matching the current context:
   - `[scope: all]` — always include
   - `[scope: go]` — include when implementing in a Go repository (has go.mod)
   - `[scope: react]` — include when implementing in a React/TypeScript project (has package.json with react dependency)
   - `[scope: repo:{name}]` — include when the current repo name matches
4. Collect the convention text (the rule, Do/Don't examples) from matching files

If no convention memories exist, skip this step silently.

### 4d: Resolve repo and assert worktree context

Before spawning the implementer agent, identify which repo this task belongs to and verify the worktree is ready.

**1. Read the task's `repo:*` bd label:**

```bash
repo_label=$(bd show {task_id} | grep -oP 'repo:\K[^ ]+' | head -1)
```

> **Routing rule (Decision 8.1):** The bd `repo:*` label is the authoritative source for routing. If the label is absent, **fail loudly — do not guess.**
> ```
> ERROR: Task {task_id} has no repo:* label. Cannot determine worktree.
> Set the label with: bd update {task_id} --label repo:<name>
> ```

**2. Assert worktree context for this repo:**

```bash
bash .maestro/scripts/assert-worktree-context.sh --repo {repo_label} --feature {feature_id}
```

Stop if the script exits non-zero.

**3. Set the implementer agent's working directory:**

Resolve `worktree_path = state.worktrees[{repo_label}].path`. Pass this as the working directory when spawning the agent (see `## Worktree Context` in the prompt below).

---

### 4e: Spawn implementation agent

**Agent Resolution:**

1. Read the task's assignee from `bd show {task_id} --json`
2. If assignee is empty, null, or not set → use `general`
3. If assignee is set but doesn't match any available subagent_type → use `general` and log a warning:
   ```
   Warning: Agent "{assignee}" not found. Falling back to "general" for task {task_id}.
   ```
4. Log the agent routing decision:
   ```
   Agent: {task_id} ({title}) → {resolved_agent} [assignee: {original_assignee}]
   ```

```
Task(
  subagent_type="{resolved_agent}",
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

  ## Conventions (learned from PR reviews)
  {filtered convention text from matching convention_*.md memories — only conventions whose scope matches the current repo/language}
  {If no conventions match, omit this section entirely}

  ## Worktree Context
  {If worktree_required=true:}
  Repo: {repo_label}
  Work in directory: {worktree_path}   (= state.worktrees[{repo_label}].path)
  All file read/write operations and git commands must be performed from this worktree directory.
  Run preflight before editing: bash .maestro/scripts/assert-worktree-context.sh --repo {repo_label} --feature {feature_id}
  The compile gate is run as: bash .maestro/scripts/compile-gate.sh {worktree_path}
  {If worktree_required=false:}
  Worktree use was explicitly disabled for this run.

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
  4. If worktree_required=true, run preflight before edits:
     bash .maestro/scripts/assert-worktree-context.sh --repo {repo_label} --feature {feature_id}
  5. After implementing, you MUST run the compile gate:
     - worktree_required=true: bash .maestro/scripts/compile-gate.sh {worktree_path}
     - worktree_required=false: bash .maestro/scripts/compile-gate.sh
  6. If the compile gate fails, fix the errors and re-run until it passes
  7. Do NOT report your work as complete until the gate passes
  8. Ensure all acceptance criteria are met

  ## Output Format
  When complete, report using this exact format:
  DONE | files: {comma-separated list} | pattern: {pattern used} | ref: {reference file if any}

  If you cannot complete the task, report:
  BLOCKED | reason: {why} | needs: {what is needed}"
)
```

### 4f: Parse result and close

**If DONE:**

```bash
bd close {task_id} --reason "{sub-agent result}"
```

**If BLOCKED:**

- Show the user why and what's needed
- Do NOT close the task
- Continue with other ready tasks

## Step 5: Execute Review Task

For tasks with label `review`, the orchestrator dispatches the review **inline** by spawning the task's assignee as a subagent with the `review` skill loaded. The review playbook lives in the skill — this step only stitches inputs and parses the verdict.

### 5a: Read the review task

```bash
bd show {review_task_id} --json
```

Extract: `id`, `title`, `assignee`, `dependencies`. From `dependencies`, identify the implementation task this review pairs with (the impl task that this review is `blocked-by` / paired with via the `blocks` relation set during `/maestro.tasks`). Call it `impl_task_id`.

### 5b: Read the impl task and resolve the modified-files list

```bash
bd show {impl_task_id} --json
```

From the impl task's `close_reason`, parse the `files: ...` segment of its `DONE | files: ... | pattern: ... | ref: ...` close line. That list of files is what the review must inspect.

### 5c: Resolve the worktree path

Read `.maestro/state/{feature_id}.json` and extract `worktree_path`. The subagent will scope its review reads to that directory.

### 5d: Load the review skill content

Read the `review` skill body so it can be inlined into the subagent prompt:

- Harness-resolved path: `~/.maestro/skills/review/SKILL.md` (or the harness-specific equivalent — `.claude/skills/review/SKILL.md` / `.opencode/skills/review/SKILL.md` if a project-local copy is present).

The skill content is the playbook the subagent applies. The orchestrator does NOT interpret it — it just passes it through.

### 5e: Spawn the assignee subagent inline

```
Task(
  subagent_type="{review_task.assignee}",
  description="Review: {review_task_id} - {review_task_title}",
  prompt="You are performing the paired review for an implementation task.

  Review Task ID: {review_task_id}
  Review Task Title: {review_task_title}
  Implementation Task ID: {impl_task_id}
  Worktree: {worktree_path}

  ## Modified Files (from impl close_reason)
  {comma-separated files list parsed in 5b}

  ## Review Skill (playbook to apply)
  {full inline contents of the review SKILL.md read in 5d}

  ## Priority Order (apply strictly)
  regression > security > data integrity > error handling > logic > code quality

  ## Output Format
  Return your verdict as EXACTLY one line, then a short issue-details paragraph:

  REVIEW_DONE | task: {review_task_id} | verdict: {PASS|MINOR|CRITICAL}
  <one paragraph: top issues found, or 'no issues' if PASS>

  If verdict is CRITICAL, list each blocking issue as a bullet so the orchestrator can create fix tasks."
)
```

### 5f: Capture verdict and close

Parse the subagent reply. Extract the line beginning with `REVIEW_DONE | task:` — that is the captured verdict line. Then close the review task:

```bash
bd close {review_task_id} --reason "{captured REVIEW_DONE line}"
```

If the verdict is `CRITICAL`, the existing fix-task creation logic continues to apply (a fix task plus its paired review task get created and will surface via `bd ready` on the next loop iteration). If `PASS` or `MINOR`, no fix task is created and the loop moves on.

Wait for the review to complete before continuing. If CRITICAL, new fix tasks will appear in `bd ready`.

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

**Worktree Cleanup (if worktree-enabled feature):**

If `state.worktrees` is set in state.json:

1. Run: `bash .maestro/scripts/worktree-cleanup.sh --all --feature {feature_id}`
2. (`worktree-cleanup.sh` updates `state.worktrees[repo].created = false` for each repo internally.)
3. Add to Next Steps:
   - "Open PR per repo: run `bash .maestro/scripts/list-feature-branches.sh --feature {feature_id}` to get `<repo>:<branch>` pairs."

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

3. **Route by label for handler type** — Labels determine the handler type (implementation, review, or PM-validation). They do NOT determine the agent. Never assume a task type.

4. **Compile gate is mandatory** — Every implementation task must pass the compile gate before being considered done. Delegated to sub-agents.

5. **Fix tasks need reviews** — When a review finds CRITICAL gaps, it creates a fix task AND a review task. Both must execute in order.

6. **Structured close reasons** — Every task close uses the pipe-delimited format: `DONE | files: ... | pattern: ...`. This feeds post-epic learning.

7. **Agent from assignee** — The agent (subagent_type) is always read from the task's assignee field. If the assignee is empty or invalid, fall back to `general`. Never read agent_routing from config.yaml.

8. **Worktree-first invariant** — Worktree usage is mandatory by default. Only bypass when explicitly requested (`--no-worktree`) or state sets `worktree_required: false`.

---

## Final Step: Push Feature Branches

After all tasks close (following Step 9), push each repo's feature branch:

```
For each repo in state.repos:
  Run: git -C {state.worktrees[repo].path} push origin {state.worktrees[repo].branch}
```

Then remind the user:

```
Each repo's feature branch is now pushed. Open PRs manually per repo:
Run `bash .maestro/scripts/list-feature-branches.sh --feature {feature_id}`
to get the <repo>:<branch> pairs for your linear-pr workflow.
```

> **Note (Decision 8.2):** Do NOT run `gh pr create` or `linear-pr` — PR creation is out of scope for this command.
