---
description: >
  View diffs per task or per epic/feature.
  Shows full git diff for a single task, or a summary table of changes across all tasks in an epic.
argument-hint: [task_id | feature_id]
---

# maestro.diff

Display git diffs for a task or a summary of changes across an entire feature/epic.

## Step 0: Worktree Detection

Source the worktree detection script to determine context:

```bash
source .maestro/scripts/worktree-detect.sh
```

If `MAESTRO_IN_WORKTREE` is `true`, note the worktree path for later use:

- Store `MAESTRO_WORKTREE_PATH` as the current git toplevel (`git rev-parse --show-toplevel`)
- All calls to `task-diff.sh` must include `--worktree {MAESTRO_WORKTREE_PATH}`

## Step 1: Parse Arguments and Detect Mode

Examine `$ARGUMENTS` to determine the operating mode:

| Argument Pattern | Mode | Description |
| --- | --- | --- |
| Beads task ID (e.g. `agent-maestro-2zi.3`) | **task** | Contains a dot — show full diff for this task |
| Beads epic/feature ID (e.g. `agent-maestro-2zi`) | **epic** | No dot, looks like a bd ID — show summary table for all tasks |
| Feature directory name (e.g. `009-i-want-to-build-...`) | **epic** | Numeric prefix — look up epic_id from state file |
| Empty / no argument | **auto** | Auto-detect most recent feature from state |

**Detection logic:**

1. If `$ARGUMENTS` is empty, go to **auto-detect** (Step 2)
2. If `$ARGUMENTS` contains a `.` (dot), treat as a **task ID** — go to Step 3
3. If `$ARGUMENTS` matches a bd ID pattern (like `agent-maestro-xxx`), treat as an **epic ID** — go to Step 4 with this epic_id
4. If `$ARGUMENTS` starts with a digit (like `009-...`), look up the matching state file in `.maestro/state/` that starts with that prefix, read the `epic_id` field — go to Step 4

If the argument does not match any pattern, show an error:

```
Error: Could not parse argument "{argument}".

Usage:
  /maestro.diff                          — auto-detect most recent feature, show epic summary
  /maestro.diff {task_id}                — full diff for a single task (e.g. agent-maestro-2zi.3)
  /maestro.diff {epic_id}               — summary table for all tasks in epic
  /maestro.diff {feature_dir}           — summary by feature directory name (e.g. 009-my-feature)
```

Stop.

## Step 2: Auto-Detect Most Recent Feature

Find the most recently updated state file:

```bash
ls -t .maestro/state/*.json | head -n 1
```

Read that file and extract the `epic_id` field. If no state files exist:

```
No features found in .maestro/state/. Run /maestro.specify to create a feature first.
```

Stop if no features. Otherwise, show which feature was auto-detected:

```
Auto-detected feature: {feature_id} (epic: {epic_id})
```

Proceed to Step 4 with the extracted `epic_id`.

## Step 3: Single Task Diff

Run the task-diff script for the given task ID:

```bash
bash .maestro/scripts/task-diff.sh {task_id} [--worktree {path}]
```

Include `--worktree {MAESTRO_WORKTREE_PATH}` if running inside a worktree (from Step 0).

**Handle exit codes:**

- **Exit 0**: Display the full diff output. Format it as a fenced code block with `diff` syntax highlighting:

  ````
  ## Diff for task {task_id}

  ```diff
  {diff output}
  ```
  ````

- **Exit 1**: No commits found for this task:

  ```
  No commits found for task {task_id}.

  This task may not have been implemented yet, or commits may not include the [bd:{task_id}] tag.
  ```

- **Exit 2**: Invalid arguments — display the error message from stderr.

Stop after displaying the diff.

## Step 4: Epic/Feature Summary Table

### 4a: Get All Tasks in the Epic

Run bd to list all child tasks of the epic:

```bash
bd list --parent {epic_id} --json
```

Parse the JSON output. Extract for each task:

- `id` — task ID
- `title` — task title
- `status` — task status (open, closed, etc.)
- `dependencies` — list of dependency IDs (for ordering)

If no tasks are found:

```
No tasks found for epic {epic_id}. Run /maestro.tasks to create implementation tasks.
```

Stop.

### 4b: Sort Tasks by Dependency Order

Sort tasks so that dependencies come before dependents (topological sort):

1. Tasks with no dependencies come first
2. Tasks whose dependencies are all satisfied come next
3. Within the same dependency level, sort by task ID (natural order)

This produces the execution order.

### 4c: Collect Diff Stats for Each Task

For each task (in dependency order), run:

```bash
bash .maestro/scripts/task-diff.sh {task_id} --summary [--worktree {path}]
```

Include `--worktree {MAESTRO_WORKTREE_PATH}` if in a worktree context.

Parse the output line: `files_changed=N insertions=N deletions=N`

If the script exits with code 1 (no commits), record that task as having 0 changes:

- `files_changed=0`, `insertions=0`, `deletions=0`

Skip tasks that exit with code 2 (invalid args) and note the error.

### 4d: Display Summary Table

Render a column-aligned summary table:

```
## Feature Diff Summary: {feature_id}
Epic: {epic_id}

Task ID                  Title                              Files   +Lines   -Lines
---------------------    -------------------------------    -----   ------   ------
agent-maestro-2zi.1      Create task-diff.sh script             3      142       12
agent-maestro-2zi.2      Add worktree support to diff            1       38        0
agent-maestro-2zi.3      Create maestro.diff command             2       95        0
agent-maestro-2zi.4      Review: Create task-diff.sh             0        0        0
─────────────────────────────────────────────────────────────────────────────────────
TOTAL                                                          6      275       12
```

**Column details:**

- **Task ID**: The beads task ID
- **Title**: Task title, truncated to 35 characters with `..` if longer
- **Files**: Number of files changed (`files_changed`)
- **+Lines**: Number of lines added (`insertions`)
- **-Lines**: Number of lines removed (`deletions`)

**Table footer:**

- Show a separator line
- Show **TOTAL** row with summed values across all tasks

### 4e: Show Task Status Indicators

Append status indicators to task titles in the table when relevant:

- Closed/completed tasks: no indicator (normal display)
- Open/in-progress tasks: append `(in progress)` after the title
- Tasks with 0 changes that are closed: append `(no diff)` — these may be review tasks or tasks completed without code changes

## Step 5: Error Handling

Wrap all errors with context:

- If `bd` is not installed: "Error: bd CLI not found. Install beads to use epic/feature diff mode."
- If state file cannot be read: "Error: Could not read state file for feature {id}: {error}"
- If task-diff.sh is not found: "Error: .maestro/scripts/task-diff.sh not found. Ensure the maestro scripts are installed."
- If bd list fails: "Error: Failed to list tasks for epic {epic_id}: {error}"

Always include the original error message for debugging.

---

**Remember:** This command is for inspecting what changed. It should be fast, read-only, and never modify any files or state. The single-task mode shows the actual diff content; the epic mode shows a high-level overview to understand the scope of changes across the feature.
