# Implementation Plan: Improve Maestro Task Creation on Beads

**Feature ID:** 019-improve-maestroe-task-creation-on-beads-currently-
**Spec:** `.maestro/specs/019-improve-maestroe-task-creation-on-beads-currently-/spec.md`
**Created:** 2024-02-23
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

This feature introduces a two-layer architecture for task creation:

1. **Parseable Plan Format**: Plans use structured HTML comment markers that are both human-readable and machine-parseable
2. **Validation Layer**: A validation script ensures plan compliance before processing
3. **Conversion Layer**: `/maestro.tasks` extracts task data and converts to JSON
4. **Execution Layer**: A bash script efficiently creates tasks using beads CLI

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   maestro.plan  │────▶│   plan.md        │────▶│  maestro.tasks  │
│  (generates)    │     │ (parseable fmt)  │     │  (validates &   │
└─────────────────┘     └──────────────────┘     │   converts)     │
                                                  └────────┬────────┘
                                                           │
                           ┌───────────────────────────────┘
                           ▼
                  ┌─────────────────┐
                  │   tasks.json    │
                  │ (structured)    │
                  └────────┬────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │ create-tasks.sh │
                  │ (fast execution)│
                  └────────┬────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │   beads CLI     │
                  │  (bd create)    │
                  └─────────────────┘
```

### 1.2 Component Interactions

**Phase 1: Plan Generation**

1. `/maestro.plan` reads spec and research
2. Generates `plan.md` with parseable task blocks
3. Each task wrapped in `<!-- TASK:BEGIN id=T### -->...<!-- TASK:END -->`

**Phase 2: Task Creation**

1. `/maestro.tasks` reads `plan.md`
2. Runs `.maestro/scripts/validate-plan-format.sh`
3. Extracts task blocks using regex
4. Converts to JSON format
5. Calls `.maestro/scripts/create-tasks.sh` with JSON path

**Phase 3: Task Execution (Script)**

1. Parse JSON input
2. Query existing tasks by title + parent epic (idempotency check)
3. Phase 1: Create all tasks, capture IDs
4. Phase 2: Link dependencies using captured IDs
5. Show progress counter [N/M]
6. Exit on first failure

### 1.3 Key Design Decisions

| Decision            | Options Considered                             | Chosen                               | Rationale                                                          |
| ------------------- | ---------------------------------------------- | ------------------------------------ | ------------------------------------------------------------------ |
| Parseable format    | Free-form markdown vs structured blocks        | Structured blocks with HTML comments | Machine-parseable while remaining human-readable; clear boundaries |
| Validation          | Inline in maestro.tasks vs separate script     | Separate validation script           | Reusable, testable, clear separation of concerns                   |
| JSON generation     | maestro.tasks generates vs plan generates both | maestro.tasks converts               | Preserves existing workflow; plan stays single source of truth     |
| Idempotency         | Title-based vs external-ref vs ID-based        | Title + Parent Epic                  | No state file needed; simple; matches existing conventions         |
| Dependency linking  | Single-pass vs two-pass                        | Two-pass                             | All IDs available before linking; proven pattern from Jira CLI     |
| Progress indication | Real-time streaming vs batch vs progress bar   | Simple counter [N/M]                 | Works in all contexts; minimal overhead                            |

---

## 2. Component Design

### 2.1 New Components

#### Component: Task Creation Script

- **Purpose:** Efficiently create beads tasks from JSON input with idempotency and dependency linking
- **Location:** `.maestro/scripts/create-tasks.sh`
- **Dependencies:** `bd` CLI, `jq`, `sqlite3` (beads DB access)
- **Dependents:** `/maestro.tasks` command

**Interface:**

```bash
.maestro/scripts/create-tasks.sh <tasks.json-path>
```

**Input Format:**

```json
{
  "feature_id": "019-improve-maestro-task-creation",
  "feature_title": "Improve Maestro Task Creation on Beads",
  "epic_title": "MST-019: Improve Maestro Task Creation on Beads",
  "tasks": [
    {
      "id": "T001",
      "title": "Create task creation script",
      "description": "Implement bash script...",
      "label": "backend",
      "size": "S",
      "estimate_minutes": 360,
      "assignee": "general",
      "dependencies": []
    }
  ]
}
```

**Output:**

- Exit code 0 on success, 1 on failure
- Progress output to stderr: "Creating tasks... [5/50]"
- Final summary to stdout: JSON with created task IDs

#### Component: Plan Format Validator

- **Purpose:** Validate that plan.md follows parseable format before task creation
- **Location:** `.maestro/scripts/validate-plan-format.sh`
- **Dependencies:** `grep` (with PCRE support), `bash`
- **Dependents:** `/maestro.tasks` command

**Validations:**

- All tasks have TASK:BEGIN/TASK:END markers
- Task IDs are unique and match format T###
- Required fields present: Label, Size, Assignee, Dependencies
- Size is XS or S (no M or L allowed)
- Dependencies reference existing task IDs

**Interface:**

```bash
.maestro/scripts/validate-plan-format.sh <plan.md-path>
```

**Output:**

- Exit code 0 if valid, 1 if invalid
- Detailed error messages to stderr
- Summary: "Validation PASSED (N task(s) found)"

### 2.2 Modified Components

#### Component: Plan Template

- **Current:** Tasks listed as free-form bullet points
- **Change:** Update template to use structured parseable format
- **Risk:** Low - documentation change
- **Location:** `.maestro/templates/plan-template.md`

**New Format Example:**

```markdown
## 5. Implementation Tasks

<!-- TASK:BEGIN id=T000 -->

### T000: Example task (not real)

- **Label:** backend
- **Size:** S
- **Assignee:** general
- **Dependencies:** —

**Description:**
Example task showing the format structure.

**Files to modify:**

- `.maestro/scripts/example.sh` (new)

**Acceptance Criteria:**

- [ ] Example criterion
<!-- TASK:END -->
```

- [ ] Script accepts JSON file path as argument
- [ ] Script validates JSON structure
- [ ] Script exits with error code 1 on failure
<!-- TASK:END -->

````

#### Component: maestro.tasks Command

- **Current:** Parses free-form bullet points, spawns agent per task
- **Change:**
  - Run validation script first
  - Extract task blocks using regex
  - Convert to JSON
  - Call create-tasks.sh instead of spawning agents
- **Risk:** Medium - changes core workflow
- **Location:** `.maestro/commands/maestro.tasks.md`

---

## 3. Data Model

### 3.1 New Entities

#### Entity: Task JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["feature_id", "feature_title", "tasks"],
  "properties": {
    "feature_id": {
      "type": "string",
      "description": "Feature identifier"
    },
    "feature_title": {
      "type": "string",
      "description": "Human-readable feature title"
    },
    "epic_title": {
      "type": "string",
      "description": "Title for the epic issue"
    },
    "tasks": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "title", "label", "size", "assignee"],
        "properties": {
          "id": {
            "type": "string",
            "pattern": "^T[0-9]{3}$",
            "description": "Task identifier (e.g., T001)"
          },
          "title": {
            "type": "string",
            "description": "Task title"
          },
          "description": {
            "type": "string",
            "description": "Detailed task description"
          },
          "label": {
            "type": "string",
            "enum": ["backend", "frontend", "test", "docs", "infrastructure"],
            "description": "Task category"
          },
          "size": {
            "type": "string",
            "enum": ["XS", "S"],
            "description": "Task size estimate"
          },
          "estimate_minutes": {
            "type": "integer",
            "description": "Time estimate in minutes"
          },
          "assignee": {
            "type": "string",
            "description": "Agent responsible for implementation"
          },
          "dependencies": {
            "type": "array",
            "items": {
              "type": "string",
              "pattern": "^T[0-9]{3}$"
            },
            "description": "Task IDs this task depends on"
          }
        }
      }
    }
  }
}
````

### 3.2 Data Flow

**Input:** plan.md (parseable format)
↓
**Validation:** validate-plan-format.sh checks structure
↓
**Extraction:** regex extracts task blocks
↓
**Conversion:** transform to tasks.json
↓
**Execution:** create-tasks.sh processes JSON
↓
**Phase 1:** Create tasks, store ID mapping
↓
**Phase 2:** Link dependencies using stored IDs
↓
**Output:** Created tasks in beads with dependencies

---

## 4. API Contracts

### 4.1 New Methods

#### Script: create-tasks.sh

- **Purpose:** Create beads tasks from JSON input
- **Input:** Path to JSON file (see schema above)
- **Output:**
  - Exit code: 0 (success) or 1 (failure)
  - Stderr: Progress messages ("[5/50] Created: T001 - Create task script")
  - Stdout: JSON result

**Success Output:**

```json
{
  "success": true,
  "epic_id": "beads-123",
  "tasks_created": 10,
  "tasks_skipped": 2,
  "tasks": [
    { "id": "T001", "beads_id": "beads-124", "status": "created" },
    { "id": "T002", "beads_id": "beads-125", "status": "created" }
  ]
}
```

**Error Output:**

```json
{
  "success": false,
  "error": "Failed to create task T003",
  "details": "beads CLI error: ...",
  "partial_results": [{ "id": "T001", "beads_id": "beads-124", "status": "created" }]
}
```

#### Script: validate-plan-format.sh

- **Purpose:** Validate plan.md format
- **Input:** Path to plan.md
- **Output:**
  - Exit code: 0 (valid) or 1 (invalid)
  - Stderr: Validation messages

**Valid Output:**

```
=== Validating Plan Format: plan.md ===
=== Validation PASSED (7 task(s) found) ===
```

**Invalid Output:**

```
=== Validating Plan Format: plan.md ===
ERROR: Task T001 - Missing 'Size:' field
ERROR: Task T003 - Invalid size 'M' (must be XS or S)
=== Validation FAILED with 2 error(s) ===
```

### 4.2 Modified Methods

#### Command: /maestro.tasks

- **Current behavior:** Parses free-form bullet points, spawns agent per task
- **New behavior:**
  1. Validate plan format
  2. Extract task blocks
  3. Convert to JSON
  4. Call create-tasks.sh
  5. Report results
- **Breaking:** No - output to user remains similar

---

## 5. Implementation Tasks

<!-- TASK:BEGIN id=T001 -->

### T001: Create task creation script

- **Label:** infrastructure
- **Size:** S
- **Assignee:** general
- **Dependencies:** —

**Description:**
Implement `.maestro/scripts/create-tasks.sh` that accepts JSON input and creates beads tasks efficiently. The script must: parse JSON, query existing tasks by title + parent epic, implement two-pass creation (create tasks, then link dependencies), show progress counter [N/M], and exit immediately on first failure.

**Files to modify:**

- `.maestro/scripts/create-tasks.sh` (new file)

**Acceptance Criteria:**

- [ ] Script accepts JSON file path as argument
- [ ] Script validates JSON structure against schema
- [ ] Script queries existing tasks by title (idempotency)
- [ ] Phase 1: Creates all tasks and captures IDs
- [ ] Phase 2: Links dependencies using captured IDs
- [ ] Shows progress [N/M] during execution
- [ ] Exits with code 1 on first failure
- [ ] Outputs JSON result on success
<!-- TASK:END -->

<!-- TASK:BEGIN id=T002 -->

### T002: Create plan format validator

- **Label:** infrastructure
- **Size:** S
- **Assignee:** general
- **Dependencies:** T001

**Description:**
Implement `.maestro/scripts/validate-plan-format.sh` that validates plan.md follows the parseable format. Validations include: TASK:BEGIN/TASK:END markers present, task IDs are unique and match T### format, required fields present (Label, Size, Assignee, Dependencies), size is XS or S only, dependencies reference existing IDs.

**Files to modify:**

- `.maestro/scripts/validate-plan-format.sh` (new file)

**Acceptance Criteria:**

- [ ] Script accepts plan.md path as argument
- [ ] Validates all task blocks have markers
- [ ] Validates task ID format and uniqueness
- [ ] Validates required fields present
- [ ] Validates size constraints (XS/S only)
- [ ] Validates dependencies reference existing IDs
- [ ] Exits 0 on valid, 1 on invalid
- [ ] Provides detailed error messages
<!-- TASK:END -->

<!-- TASK:BEGIN id=T003 -->

### T003: Update plan template

- **Label:** docs
- **Size:** XS
- **Assignee:** general
- **Dependencies:** T002

**Description:**
Update `.maestro/templates/plan-template.md` to use the parseable task format with TASK:BEGIN/TASK:END markers. Replace Section 5 (Implementation Phases) with structured task blocks. Include validation rules in template comments.

**Files to modify:**

- `.maestro/templates/plan-template.md`

**Acceptance Criteria:**

- [ ] Template uses TASK:BEGIN/TASK:END markers
- [ ] Each task has required metadata fields
- [ ] Template includes format validation rules
- [ ] Example task shows proper structure
<!-- TASK:END -->

<!-- TASK:BEGIN id=T004 -->

### T004: Update maestro.tasks command

- **Label:** infrastructure
- **Size:** S
- **Assignee:** general
- **Dependencies:** T001, T002

**Description:**
Modify `.maestro/commands/maestro.tasks.md` to use the new workflow: run validation script first, extract task blocks using regex, convert to JSON format, call create-tasks.sh instead of spawning agents, and handle script output. Remove old agent-spawning logic.

**Files to modify:**

- `.maestro/commands/maestro.tasks.md`

**Acceptance Criteria:**

- [ ] Step added to run validation script
- [ ] Step added to extract task blocks from plan
- [ ] Step added to convert to JSON
- [ ] Step calls create-tasks.sh with JSON path
- [ ] Old agent-spawning logic removed
- [ ] Error handling for validation failures
- [ ] Progress reporting from script output
<!-- TASK:END -->

<!-- TASK:BEGIN id=T005 -->

### T005: Add idempotency to task creation

- **Label:** infrastructure
- **Size:** XS
- **Assignee:** general
- **Dependencies:** T001

**Description:**
Enhance create-tasks.sh to check if tasks already exist before creating. Query beads by title + parent epic. Skip existing tasks and continue. Show "skipped" status in progress output. Handle edge cases (multiple tasks with same title).

**Files to modify:**

- `.maestro/scripts/create-tasks.sh`

**Acceptance Criteria:**

- [ ] Queries existing tasks by title + epic
- [ ] Skips tasks that already exist
- [ ] Shows "[5/50] Skipped: T002 - Task already exists"
- [ ] Continues with remaining tasks
- [ ] Existing tasks included in dependency mapping
<!-- TASK:END -->

<!-- TASK:BEGIN id=T006 -->

### T006: Write tests for task creation script

- **Label:** test
- **Size:** S
- **Assignee:** general
- **Dependencies:** T001, T005

**Description:**
Create comprehensive tests for create-tasks.sh. Test happy path (create tasks), idempotency (skip existing), error handling (fail on error), dependency linking (link deps), and JSON validation (reject invalid input). Use test fixtures and mock beads CLI.

**Files to modify:**

- `.maestro/scripts/test/create-tasks-test.sh` (new file)
- Create test fixtures in `.maestro/scripts/test/fixtures/`

**Acceptance Criteria:**

- [ ] Test: Create 5 tasks successfully
- [ ] Test: Skip existing tasks (idempotency)
- [ ] Test: Stop on first failure
- [ ] Test: Link dependencies correctly
- [ ] Test: Reject invalid JSON input
- [ ] Test: Progress output format
- [ ] All tests pass
<!-- TASK:END -->

<!-- TASK:BEGIN id=T007 -->

### T007: Write tests for plan validator

- **Label:** test
- **Size:** XS
- **Assignee:** general
- **Dependencies:** T002

**Description:**
Create tests for validate-plan-format.sh. Test valid plan (passes), missing markers (fails), duplicate IDs (fails), invalid size (fails), missing fields (fails), and invalid dependencies (fails).

**Files to modify:**

- `.maestro/scripts/test/validate-plan-test.sh` (new file)
- Create test fixtures in `.maestro/scripts/test/fixtures/`

**Acceptance Criteria:**

- [ ] Test: Valid plan passes validation
- [ ] Test: Missing TASK markers detected
- [ ] Test: Duplicate task IDs detected
- [ ] Test: Invalid size (M/L) rejected
- [ ] Test: Missing required fields detected
- [ ] Test: Invalid dependency references detected
- [ ] All tests pass
<!-- TASK:END -->

---

## 6. Task Sizing Guidance

### 6.1 Size Definitions

| Size   | Time Range      | Status      |
| ------ | --------------- | ----------- |
| **XS** | 0-120 minutes   | ✅ Accepted |
| **S**  | 121-360 minutes | ✅ Accepted |
| **M**  | 361-720 minutes | ❌ REJECTED |
| **L**  | 721+ minutes    | ❌ REJECTED |

### 6.2 Task Breakdown

All tasks are **XS** or **S** size:

1. **Create task creation script** — Size: S (~240 min)
2. **Create plan format validator** — Size: S (~240 min)
3. **Update plan template** — Size: XS (~60 min)
4. **Update maestro.tasks command** — Size: S (~240 min)
5. **Add idempotency to task creation** — Size: XS (~90 min)
6. **Write tests for task creation script** — Size: S (~300 min)
7. **Write tests for plan validator** — Size: XS (~120 min)

---

## 7. Testing Strategy

### 7.1 Unit Tests

- **create-tasks.sh**: JSON parsing, idempotency logic, dependency resolution
- **validate-plan-format.sh**: Regex extraction, field validation, error reporting

### 7.2 Integration Tests

- End-to-end test: plan.md → tasks created in beads
- Test idempotency: run twice, verify no duplicates
- Test error handling: fail mid-execution, verify partial state

### 7.3 End-to-End Tests

**Test Case 1: Full workflow**

- Create feature with 10 tasks
- Run /maestro.plan
- Run /maestro.tasks
- Verify all tasks created in <10 seconds
- Verify dependencies linked correctly

**Test Case 2: Idempotency**

- Run /maestro.tasks (creates tasks)
- Run /maestro.tasks again
- Verify tasks skipped, no duplicates

**Test Case 3: Error handling**

- Introduce invalid task in plan
- Run /maestro.tasks
- Verify validation catches error
- Verify no partial task creation

### 7.4 Test Data

- Sample plan.md with various task configurations
- Mock beads CLI responses
- Test fixtures for edge cases (duplicate titles, circular deps, etc.)

---

## 8. Risks and Mitigations

| Risk                                  | Likelihood | Impact | Mitigation                                               |
| ------------------------------------- | ---------- | ------ | -------------------------------------------------------- |
| Title changes break idempotency       | Medium     | Medium | Document limitation; validation warns on duplicates      |
| Script fails mid-execution            | Low        | High   | State file for resume capability; document partial state |
| Beads CLI output format changes       | Low        | High   | Pin Beads version; integration tests catch changes       |
| Large plans (>100 tasks) cause issues | Low        | Medium | Document soft limit; add batching in future              |
| Dependency cycles in plan             | Low        | Medium | Validate before linking; clear error message             |
| Plan format adoption resistance       | Medium     | Low    | Clear documentation; validation helps migration          |

---

## 9. Open Questions

None. All decisions resolved through research and clarification:

- ✅ Parseable format: HTML comment markers
- ✅ Validation: Separate script
- ✅ JSON generation: maestro.tasks converts
- ✅ Idempotency: Title + Parent Epic
- ✅ Dependency linking: Two-pass
- ✅ Progress: Simple counter [N/M]
