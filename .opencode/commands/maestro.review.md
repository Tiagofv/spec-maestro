---
description: >
  Perform code review on a completed implementation task.
  Routes by risk level, injects conventions, checks for feature regression first.
argument-hint: <review-task-id>
---

# maestro.review

Review task: **$ARGUMENTS**

## Step 1: Read Review Task

`$ARGUMENTS` must contain a review task ID. If empty:

- List ready tasks: `bd ready`
- Ask the user which review task to run
- Stop until they provide a task ID

Read the review task:

```bash
bd show $ARGUMENTS --json
```

Extract:

- `id` — review task ID
- `title` — should start with "Review:"
- `description` — contains reference to implementation task
- `assignee` — reviewer agent

Find the implementation task ID from the description (the task this reviews). The description will contain a reference like "Reviews: Task {id}" or "Reviews task {id}".

If the task title does not start with "Review:", warn the user this may not be a review task and confirm before proceeding.

## Step 2: Get Implementation Details

Read the implementation task to find what files were modified:

```bash
bd show {implementation_task_id} --json
```

Extract the `close_reason` to get the file list. The close reason follows this format:

```
DONE | files: x.go,y.go | pattern: consumer | ref: z.go
```

Parse the `files:` field to get the list of modified files.

**Worktree context:** Look up the feature's state.json using the epic ID from the task. If the state has `worktree_path` set, store it as `{worktree_path}` for use in Step 3 and Step 5.

If the implementation task is not closed (no close_reason):

- Tell the user the implementation must complete before review
- Show the implementation task status
- Stop

## Step 3: Risk Classification

Read the risk classification cookbook:

```bash
cat .maestro/cookbook/review-routing.md
```

Classify each file from Step 2 according to the risk levels:

- **HIGH RISK**: Always review (business logic, handlers, data access, auth, payments, API endpoints, migrations)
- **MEDIUM RISK**: Review if >50 lines changed (wiring, middleware, DTOs, adapters, build scripts)
- **LOW RISK**: Skip review (generated code, pure structs, type definitions, constants, test fixtures, docs, import-only)

For MEDIUM RISK files, check the diff size:

```bash
git diff HEAD~1 -- {file} | wc -l
```

If `worktree_path` is set, run the diff from within the worktree:
git -C {worktree_path} diff HEAD~1 -- {file} | wc -l
Otherwise use the standard form.

If the diff is 50 lines or fewer, downgrade MEDIUM to LOW for that file.

**If ALL files are LOW RISK:**

Close the review task as skipped and stop:

```bash
bd close $ARGUMENTS --reason "SKIPPED | risk: low | files: {comma-separated list}"
```

Report to the user that all files were low risk and the review was skipped.

Otherwise, proceed with the files classified as HIGH or MEDIUM (with >50 lines changed).

## Step 4: Load Conventions

Read conventions to inject into the reviewer:

1. **Global conventions**: Read `.maestro/reference/conventions.md`
2. **Local conventions**: Check for a `## Review Conventions` section in the project's `CLAUDE.md`

```bash
cat .maestro/reference/conventions.md
```

If `CLAUDE.md` exists in the project root:

```bash
cat CLAUDE.md
```

Look for a `## Review Conventions` section. If found, extract that section.

Local conventions take precedence over global ones. When there's a conflict, the local convention wins.

## Step 5: Spawn Reviewer

Spawn a sub-agent with the reviewer type from the task's assignee field. The sub-agent receives:

- The conventions from Step 4
- The file list from Step 3 (only HIGH and qualifying MEDIUM files)
- The review template schema
- Explicit instructions to check for feature regression FIRST

```
Task(
  subagent_type="{assignee from task}",
  description="Review: {implementation_task_title}",
  prompt="You are reviewing code changes for: {task_title}

  ## Conventions to Apply

  ### Global Conventions
  {content from .maestro/reference/conventions.md}

  ### Local Conventions
  {content from CLAUDE.md ## Review Conventions if exists, otherwise 'None specified'}

  Local conventions take precedence over global ones.

  ## Files to Review
  {file list with full paths — only HIGH and qualifying MEDIUM risk files}

  ## Worktree Context
  {If worktree_path is set:}
  The implementation was done in worktree: {worktree_path}
  Run git diff commands from within that directory using: git -C {worktree_path} diff HEAD~1 -- {file}
  {Otherwise:} Run git diff commands normally.

  ## FEATURE REGRESSION CHECK (DO THIS FIRST)

  For every modified file, use `git diff HEAD~1 -- {file}` to detect REMOVED functionality:
  - Deleted switch cases, event handlers, or consumer registrations
  - Removed function calls, route registrations, or feature branches
  - Replaced a multi-entity handler with a single-entity one
  - Dropped imports that were serving existing features

  If ANY existing functionality was removed that is NOT explicitly required by the task description, flag it as CRITICAL with cause 'feature-regression'.

  Feature regressions are the #1 priority check. A passing review means nothing if it broke something else.

  ## Code Quality Review

  After the regression check, review for:
  - Error handling correctness
  - Edge case coverage
  - Security vulnerabilities
  - Performance issues
  - Code style (per conventions)

  ## Output

  Return ONLY valid JSON. No markdown, no preamble, no explanation.

  Use this exact schema:
  {
    'verdict': 'PASS | MINOR | CRITICAL',
    'issues': [
      {
        'severity': 'CRITICAL | MINOR',
        'file': 'path/to/file',
        'line': 42,
        'cause': 'feature-regression | nil-pointer | wrong-error | missing-impl | etc',
        'description': 'One sentence describing the issue'
      }
    ],
    'summary': 'One sentence overall assessment'
  }

  If no issues found, return: { 'verdict': 'PASS', 'issues': [], 'summary': '...' }
  If only style/optimization issues: verdict is 'MINOR'
  If any blocking issue (regression, security, data loss, incorrect logic): verdict is 'CRITICAL'
  "
)
```

## Step 6: Parse Review Result

Parse the JSON output from the reviewer sub-agent.

**If PASS:**

Close the review task with a passing reason:

```bash
bd close $ARGUMENTS --reason "PASS | files: {list} | layer: {layer}"
```

Proceed to Step 8 to report results.

**If MINOR:**

Close the review task noting the minor issues:

```bash
bd close $ARGUMENTS --reason "MINOR | files: {list} | note: {summary from review}"
```

Proceed to Step 8 to report results. Minor issues are informational and do not block.

**If CRITICAL:**

Do NOT close the review task yet. Proceed to Step 7 to handle the critical issues.

## Step 7: Handle CRITICAL Issues

For each CRITICAL issue found by the reviewer:

### 7a: Create a Fix Task

Create a new task in bd for each critical issue:

```bash
bd create \
  --title="Fix: {issue description}" \
  --parent={implementation_task_id} \
  --labels=fix \
  --description="CRITICAL from review {review_task_id}:

  File: {file}
  Line: {line}
  Cause: {cause}
  Description: {description}

  ## Instructions
  Fix this issue while maintaining all existing functionality.
  After fixing, run compile gate: bash .maestro/scripts/compile-gate.sh"
```

### 7b: Implement the Fix

Run the implement command for each fix task:

```
/maestro.implement {fix_task_id}
```

This will spawn a sub-agent to fix the issue, run the compile gate, and close the fix task when done.

### 7c: Re-Review

After all fixes are implemented, go back to **Step 5** and re-run the review.

**Fix-Review Loop:** This loop continues until the review returns PASS or MINOR. There is no maximum iteration count — the code must be correct before proceeding.

If the same issue recurs 3 times, escalate to the user with context about what's been tried.

## Step 8: Report Results

Show the user:

1. **Review verdict**: PASS, MINOR, or CRITICAL (with resolution)
2. **Issues found** (if any): List each issue with file, line, cause, and description
3. **Fix tasks created** (if any): List each fix task ID and status
4. **Next ready tasks**: Run `bd ready` and show available work
5. **Completion check**: If all review tasks for the current feature are complete, suggest: "All reviews complete. Run `/maestro.pm-validate` to validate the feature."

---

**Feature regression check is non-negotiable.** It happens FIRST, before any other review activity. This was learned from production incidents where agents implemented new features but broke existing ones.

**ADDITIVE review philosophy.** The reviewer's primary job is to ensure existing functionality was preserved while new functionality was correctly added.
