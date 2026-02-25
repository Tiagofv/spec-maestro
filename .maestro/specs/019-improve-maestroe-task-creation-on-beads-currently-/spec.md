# Feature: Improve Maestro Task Creation on Beads

**Spec ID:** 019-improve-maestroe-task-creation-on-beads-currently-
**Author:** Maestro
**Created:** 2024-02-23
**Last Updated:** 2024-02-23
**Status:** Draft

---

## 1. Problem Statement

When agents generate task plans with many tasks, the current `/maestro.tasks` command takes too long to process and create those tasks on beads. Creating 50+ tasks currently takes approximately 10 minutes, which disrupts the agent workflow and creates a poor user experience.

The slowness occurs because tasks are currently created through individual agent invocations rather than an optimized script. Each task creation requires spawning an agent, which has significant overhead. Users experience significant wait times, and in some cases, the operation may timeout or feel unresponsive.

---

## 2. Proposed Solution

Create a script in `.maestro/scripts/` that wraps the beads CLI to create tasks efficiently. The workflow will be:

1. **`/maestro.plan`** generates `plan.md` with structured task blocks (using `<!-- TASK:BEGIN -->...<!-- TASK:END -->` markers)
2. **`/maestro.tasks`** validates the plan format using `.maestro/scripts/validate-plan-format.sh`
3. **`/maestro.tasks`** extracts task blocks and converts them to JSON
4. **`/maestro.tasks`** calls the new script with the JSON input
5. **Script** creates tasks efficiently using beads CLI

The script will:

- Run sequentially (no parallelization needed since script execution is fast)
- Be idempotent: if a task already exists, skip it and continue
- Use two-pass creation: first pass creates all tasks, second pass links dependencies
- Stop immediately on first failure (preserving current behavior)
- Provide progress indication using a simple counter format ([N/M])

This replaces the current agent-invocation approach with a direct script execution, dramatically reducing task creation time from ~10 minutes to seconds.

---

## 3. User Stories

### Story 1: Quick Task Creation for Agents

**As a** developer using the Maestro system,
**I want** the `/maestro.tasks` command to create tasks on beads quickly,
**so that** I can continue working without significant delays when planning complex features.

**Acceptance Criteria:**

- [ ] Creating 50 tasks completes in under 30 seconds (vs. current ~10 minutes)
- [ ] The agent receives confirmation that tasks were created successfully
- [ ] [DEFERRED TO BRAINSTORMING: Task identification strategy for idempotency - use @general agent]

### Story 2: Visibility into Task Creation Progress

**As a** developer using the Maestro system,
**I want** to see progress indicators during task creation,
**so that** I know the system is working even when processing many tasks.

**Acceptance Criteria:**

- [ ] Progress is shown when creating more than 5 tasks
- [ ] Progress indication updates at least every 2 seconds
- [ ] Completion status is clearly communicated
- [ ] Implementation uses simplest viable approach (streaming, batch confirmation, or progress bar)

### Story 3: Graceful Handling of Large Task Sets

**As a** developer using the Maestro system,
**I want** the system to handle large task plans without failure,
**so that** I can plan complex features without worrying about system limits.

**Acceptance Criteria:**

- [ ] Task creation succeeds with up to 100 tasks
- [ ] Clear error message is shown if task creation fails
- [ ] Successfully created tasks remain in the system even if some fail
- [ ] Current behavior preserved: stops immediately on first failure

### Story 4: Idempotent Task Creation

**As a** developer using the Maestro system,
**I want** the task creation script to be idempotent,
**so that** running the same task plan multiple times doesn't create duplicates.

**Acceptance Criteria:**

- [ ] Script checks if each task already exists before creating
- [ ] Existing tasks are skipped without error
- [ ] New tasks are created normally
- [ ] Progress indication shows "skipped" status for existing tasks

### Story 5: Automatic Dependency Linking

**As a** developer using the Maestro system,
**I want** task dependencies to be automatically linked after creation,
**so that** I don't have to manually configure task relationships.

**Acceptance Criteria:**

- [ ] Two-pass creation: first pass creates all tasks, second pass links dependencies
- [ ] Dependencies are linked using the created task IDs
- [ ] Dependency linking succeeds even when tasks were skipped (already existed)
- [ ] Clear error if a dependency references a task that doesn't exist

### Story 6: Parseable Plan Format

**As a** developer using the Maestro system,
**I want** tasks in plan.md to follow a structured, machine-parseable format,
**so that** `/maestro.tasks` can reliably extract task data and convert it to JSON.

**Acceptance Criteria:**

- [ ] Plan template updated to use `<!-- TASK:BEGIN id=T001 -->` and `<!-- TASK:END -->` markers
- [ ] Each task includes structured metadata: Label, Size, Assignee, Dependencies
- [ ] Validation script created at `.maestro/scripts/validate-plan-format.sh`
- [ ] Validation script checks: ID format, required fields, size constraints (XS/S only), duplicate IDs
- [ ] `/maestro.plan` enforces parseable format during plan generation
- [ ] `/maestro.tasks` runs validation before task creation

### Story 7: JSON Plan Generation

**As a** developer using the Maestro system,
**I want** the `/maestro.tasks` command to convert the markdown plan to JSON,
**so that** the task creation script can process tasks efficiently.

**Acceptance Criteria:**

- [ ] `/maestro.tasks` parses structured task blocks from plan.md
- [ ] `/maestro.tasks` generates valid JSON with all task fields
- [ ] JSON includes: task id, title, description, label, size, assignee, dependencies, estimate
- [ ] Generated JSON is passed to the task creation script

The feature is considered complete when:

1. Task creation time for 50 tasks is reduced from ~10 minutes to under 30 seconds
2. Script runs from `.maestro/scripts/` and wraps beads CLI
3. Script is idempotent - running twice doesn't create duplicates
4. Two-pass dependency linking works correctly
5. Progress indication provides visibility during task creation
6. Script handles errors gracefully, stopping on first failure
7. Plan uses parseable format with TASK:BEGIN/TASK:END markers
8. Validation script ensures plan format compliance
9. `/maestro.tasks` converts parseable plan to JSON

---

## 5. Scope

### 5.1 In Scope

- Script in `.maestro/scripts/` that wraps beads CLI for task creation
- Parseable task format with HTML comment markers (TASK:BEGIN/TASK:END)
- Validation script to ensure plan format compliance
- Idempotent task creation (check before create)
- Two-pass dependency linking
- Progress indication during task creation
- Error handling with immediate stop on failure
- JSON conversion from parseable markdown

### 5.2 Out of Scope

- Changes to beads CLI itself
- Parallel task creation (not needed - script execution is fast enough)
- Real-time updates during creation
- Caching of task plans
- Migration of existing tasks

### 5.3 Deferred

- Advanced progress visualization
- Task update capabilities (only creation)
- Batch size optimization
- Parallel task creation (if needed in future)

---

## 6. Dependencies

- Existing beads CLI (`bd` command)
- Linear API access for task creation
- Maestro task plan format (parseable blocks with TASK markers)
- `.maestro/scripts/validate-plan-format.sh` (format validation)
- `/maestro.tasks` command (modified to validate and convert)
- `/maestro.plan` command (modified to generate parseable format)
- `jq` or similar JSON processing tool

---

## 7. Open Questions

**Resolved Questions:**

- ✅ **Task identification strategy:** Title + Parent Epic composite (from research/synthesis.md)
- ✅ **Input format:** JSON (from research/synthesis.md)
- ✅ **JSON generation:** `/maestro.tasks` converts markdown plan to JSON (Option A)

**Remaining Questions:**

None. All critical decisions have been made and documented.

---

## 8. Risks

- Two-pass creation could leave tasks partially linked if second pass fails
- Idempotency logic might skip tasks that should be updated (not just created)
- Error handling with immediate stop could leave dependencies unlinked
- Dependency cycles in task plan could cause infinite loops or errors
- Input format changes could break existing task plans

---

## Changelog

| Date       | Change                                          | Author  |
| ---------- | ----------------------------------------------- | ------- |
| 2024-02-23 | Initial spec created                            | Maestro |
| 2024-02-23 | Clarified: 10min for 50+ tasks, script approach | User    |
| 2024-02-23 | Added: JSON generation workflow (Option A)      | User    |
| 2024-02-23 | Added: Parseable task format with validation    | User    |
