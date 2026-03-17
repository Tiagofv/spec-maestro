# Implementation Plan: Feature Dashboard Command (maestro.list)

**Feature ID:** 031-lets-add-agent-maestro-new-command-list
**Spec:** .maestro/specs/031-lets-add-agent-maestro-new-command-list/spec.md
**Created:** 2026-03-16
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

The `maestro.list` command follows the established maestro dual-layer architecture:

1. **Shell helper script** (`list-features.sh`) — Deterministic data aggregation layer that scans directories, parses JSON state files, reads spec titles, computes stalled status, applies filters, and outputs a structured JSON array.

2. **Markdown command file** (`maestro.list.md`) — AI-readable instruction file that calls the script, formats the JSON output into a human-readable table, and renders contextual next-action suggestions.

This mirrors the proven pattern used by `maestro.research.list` (with `research-state.sh`) and `maestro.tasks` (with `parse-plan-tasks.sh`).

```
User runs /maestro.list [--stage X]
          │
          ▼
┌─────────────────────┐
│  maestro.list.md    │  ← AI agent reads instructions
│  (command file)     │
└─────────┬───────────┘
          │ calls
          ▼
┌─────────────────────┐
│  list-features.sh   │  ← Deterministic data aggregation
│  (shell script)     │
│                     │
│  Scans:             │
│  - .maestro/specs/  │
│  - .maestro/state/  │
│  - spec.md titles   │
│                     │
│  Outputs: JSON array│
└─────────┬───────────┘
          │ returns JSON
          ▼
┌─────────────────────┐
│  maestro.list.md    │  ← Formats table, groups, next-actions
│  (output rendering) │
└─────────────────────┘
```

### 1.2 Component Interactions

1. `maestro.list.md` is invoked by the AI agent when user types `/maestro.list`
2. The command calls `bash .maestro/scripts/list-features.sh [--stage X]`
3. The script scans `.maestro/specs/*/` directories for feature discovery
4. For each feature directory, it reads `.maestro/state/{feature_id}.json` (if exists)
5. For each feature, it reads the first line of `.maestro/specs/{feature_id}/spec.md` for the title
6. The script computes stalled status by comparing `updated_at` against current time (14-day threshold)
7. The script returns a JSON array of feature objects to stdout
8. The command file formats the JSON into a table with grouping and next-action suggestions
9. Registration happens via `init.sh` which copies `maestro.list.md` to `.claude/commands/` and `.opencode/commands/`

### 1.3 Key Design Decisions

| Decision                        | Options Considered                                  | Chosen                              | Rationale                                                                                                 |
| ------------------------------- | --------------------------------------------------- | ----------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Implementation architecture     | Pure markdown, Markdown + script, Go CLI subcommand | Markdown + shell script             | Consistent with `maestro.research.list` pattern; script provides deterministic JSON parsing and date math |
| Data discovery                  | State-only, spec-only, dual scan                    | Dual scan (specs + state)           | Ensures orphan specs are discovered; state enriches with stage/metrics                                    |
| Feature name source             | Slug reformatting, state field, spec title          | Read `# Feature:` line from spec.md | Title is always in spec; single line read is fast; no schema migration needed                             |
| Date math for stalled detection | `date` command, Python, `jq`                        | `jq` (`now`, `strptime`, `mktime`)  | Portable across macOS and Linux; `jq` is already a project dependency                                     |
| Output format                   | Markdown table, indented cards, column-aligned text | Column-aligned plain text table     | Consistent with `maestro.research.list`; most scannable for CLI output                                    |
| Sort order                      | `updated_at` descending, file mtime, feature ID     | Feature ID descending (numeric)     | Most predictable; zero-padded numbers enable natural sort                                                 |

---

## 2. Component Design

### 2.1 New Components

#### Component: list-features.sh

- **Purpose:** Scan specs and state directories, aggregate feature data, output structured JSON
- **Location:** `.maestro/scripts/list-features.sh`
- **Dependencies:** `jq` (for JSON parsing and date math), `.maestro/specs/*/`, `.maestro/state/*.json`
- **Dependents:** `maestro.list.md` (calls this script)

#### Component: maestro.list.md

- **Purpose:** AI-readable command definition that orchestrates the list display
- **Location:** `.maestro/commands/maestro.list.md`
- **Dependencies:** `list-features.sh`, existing maestro command infrastructure
- **Dependents:** None (end-user facing command)

#### Component: test-list-features.sh

- **Purpose:** Test script for list-features.sh with fixture data
- **Location:** `.maestro/scripts/test/test-list-features.sh`
- **Dependencies:** `list-features.sh`, test fixtures
- **Dependents:** None (test only)

#### Component: Test Fixtures

- **Purpose:** Sample state files and spec directories for testing edge cases
- **Location:** `.maestro/scripts/test/fixtures/list-features/`
- **Dependencies:** None
- **Dependents:** `test-list-features.sh`

### 2.2 Modified Components

#### Component: init.sh

- **Current:** Copies all `.maestro/commands/maestro.*.md` files to agent command directories
- **Change:** No code change needed — the existing glob pattern `maestro.*.md` will automatically pick up the new `maestro.list.md` file
- **Risk:** Low — no modification to init.sh logic

---

## 3. Data Model

### 3.1 New Entities

#### Entity: Feature List Item (JSON output from list-features.sh)

```json
{
  "feature_id": "031-slug-name",
  "numeric_id": 31,
  "title": "Feature Dashboard Command",
  "stage": "clarify",
  "updated_at": "2026-03-16T00:00:00Z",
  "is_stalled": false,
  "days_since_update": 0,
  "has_state": true,
  "user_stories": 4,
  "clarification_count": 0,
  "task_count": 0,
  "next_action": "/maestro.plan",
  "next_action_reason": "All clarifications resolved"
}
```

### 3.2 Modified Entities

No existing entities are modified. This command is read-only.

### 3.3 Data Flow

```
.maestro/specs/*/            .maestro/state/*.json
       │                              │
       ▼                              ▼
  [dir listing]                 [JSON parsing]
       │                              │
       └──────────┬───────────────────┘
                  ▼
        [merge by feature_id]
                  │
                  ▼
        [compute stalled status]
                  │
                  ▼
        [compute next action]
                  │
                  ▼
        [apply --stage filter]
                  │
                  ▼
        [sort: active by ID desc,
         completed at bottom]
                  │
                  ▼
         JSON array to stdout
```

---

## 4. API Contracts

### 4.1 New Endpoints/Methods

#### SCRIPT: list-features.sh

- **Purpose:** Aggregate all feature data into a JSON array
- **Input:** Optional `--stage <stage>` flag to filter results
- **Output:** JSON array of feature objects (schema in Section 3.1), one per feature
- **Errors:**
  - Exit 0 with empty JSON array `[]` if no features found
  - Exit 0 with partial data if individual state files are unreadable (show `"has_state": false`)
  - Exit 1 only for fatal errors (`.maestro/` directory missing, `jq` not installed)

**Example invocations:**

```bash
# List all features
bash .maestro/scripts/list-features.sh

# List only features in "specify" stage
bash .maestro/scripts/list-features.sh --stage specify

# List only features with pending clarifications
bash .maestro/scripts/list-features.sh --stage clarify
```

**Example output:**

```json
[
  {
    "feature_id": "031-lets-add-agent-maestro-new-command-list",
    "numeric_id": 31,
    "title": "Feature Dashboard Command",
    "stage": "clarify",
    "updated_at": "2026-03-16T00:00:00Z",
    "is_stalled": false,
    "days_since_update": 0,
    "has_state": true,
    "user_stories": 4,
    "clarification_count": 0,
    "task_count": 0,
    "next_action": "/maestro.plan",
    "next_action_reason": "All clarifications resolved"
  }
]
```

### 4.2 Modified Endpoints

None. This is a read-only command with no side effects.

---

## 5. Implementation Tasks

<!--
FORMAT VALIDATION RULES:
1. Each task MUST be wrapped in TASK:BEGIN/TASK:END markers
2. Task ID format: T### (e.g., T001, T002) - sequential numbering
3. Size MUST be one of: XS, S (M and L are rejected - must split)
4. Assignee MUST be a valid agent name from maestro.plan.md
5. Dependencies MUST reference valid task IDs (comma-separated for multiple)
6. Files to modify must use relative paths from repository root
7. All checkboxes in Acceptance Criteria must be unchecked initially
-->

<!-- TASK:BEGIN id=T001 -->

### T001: Create list-features.sh Shell Script — Core Discovery and JSON Output

**Metadata:**

- **Label:** backend
- **Size:** S
- **Assignee:** general
- **Dependencies:** None

**Description:**
Create the `list-features.sh` shell script that scans `.maestro/specs/` for feature directories and `.maestro/state/*.json` for state files, merges the data by feature ID, and outputs a JSON array to stdout.

The script must:

1. List all directories in `.maestro/specs/` (excluding `.` and `..`)
2. For each spec directory, attempt to read `.maestro/state/{feature_id}.json`
3. For each spec directory, read the first line of `spec.md` and extract the title after `# Feature: `
4. Extract `numeric_id` from the feature_id (the NNN prefix)
5. Use `jq` for all JSON parsing with defensive defaults (`// empty`, `// 0`, `// "unknown"`)
6. Output a JSON array of feature objects with fields: `feature_id`, `numeric_id`, `title`, `stage`, `updated_at`, `has_state`, `user_stories`, `clarification_count`, `task_count`
7. Handle edge cases: missing state file (set `has_state: false`, `stage: "no-state"`), missing spec.md (use reformatted slug as title), malformed JSON (set `has_state: false`)
8. Use `set -euo pipefail` and proper error handling

**Files to Modify:**

- `.maestro/scripts/list-features.sh`

**Acceptance Criteria:**

- [ ] Script exists at `.maestro/scripts/list-features.sh` and is executable (`chmod +x`)
- [ ] Running the script in the project root outputs valid JSON array to stdout
- [ ] Features with state files show `has_state: true` with correct `stage`, `user_stories`, `clarification_count`, `task_count` values
- [ ] Features without state files show `has_state: false` and `stage: "no-state"`
- [ ] Features with malformed/unreadable state files show `has_state: false` without crashing
- [ ] Empty project (no spec directories) outputs `[]`
- [ ] The `numeric_id` is correctly extracted as an integer from the feature_id prefix
- [ ] Title is extracted from `spec.md` first line; falls back to reformatted slug if missing

<!-- TASK:END -->

<!-- TASK:BEGIN id=T002 -->

### T002: Add Stalled Detection and Next-Action Logic to list-features.sh

**Metadata:**

- **Label:** backend
- **Size:** S
- **Assignee:** general
- **Dependencies:** T001

**Description:**
Extend `list-features.sh` to compute stalled status and contextual next-action suggestions for each feature.

Stalled detection:

1. Parse `updated_at` from state file using `jq` date functions (`strptime`, `mktime`, `now`)
2. Handle 3 timestamp formats: full ISO (`2026-03-16T00:00:00Z`), millisecond ISO (`2026-03-16T00:00:00.000Z`), date-only (`2026-03-16`)
3. Compare against current time; if difference >= 14 days (1209600 seconds), set `is_stalled: true`
4. Compute `days_since_update` as integer
5. Features without state files are never stalled (no timestamp to compare)
6. Completed features are never stalled

Next-action logic (stage-to-action mapping):

- `no-state` → `/maestro.specify` (reason: "No state file found")
- `specify` + `clarification_count > 0` → `/maestro.clarify` (reason: "N clarification markers pending")
- `specify` + `clarification_count == 0` → `/maestro.plan` (reason: "Spec is ready")
- `clarify` → `/maestro.plan` (reason: "All clarifications resolved")
- `plan` → `/maestro.tasks` (reason: "Plan ready for task creation")
- `tasks` → `/maestro.implement` (reason: "Tasks created, ready to implement")
- `implement` → (empty; reason: "Implementation in progress")
- `complete` → `/maestro.analyze` (reason: "Ready for post-epic analysis")
- `unknown` or other → (empty; reason: "Unknown stage")

Add `is_stalled`, `days_since_update`, `next_action`, `next_action_reason` fields to each feature object.

**Files to Modify:**

- `.maestro/scripts/list-features.sh`

**Acceptance Criteria:**

- [ ] Features with `updated_at` older than 14 days have `is_stalled: true` and correct `days_since_update`
- [ ] Features with `updated_at` within 14 days have `is_stalled: false`
- [ ] All 3 timestamp formats are parsed correctly without errors
- [ ] Completed features always have `is_stalled: false` regardless of `updated_at`
- [ ] Each feature has a `next_action` field with the correct command based on its stage
- [ ] Features in `specify` stage with `clarification_count > 0` suggest `/maestro.clarify`
- [ ] Features in `specify` stage with `clarification_count == 0` suggest `/maestro.plan`
- [ ] `next_action_reason` provides a human-readable explanation

<!-- TASK:END -->

<!-- TASK:BEGIN id=T003 -->

### T003: Add Filtering and Sorting to list-features.sh

**Metadata:**

- **Label:** backend
- **Size:** XS
- **Assignee:** general
- **Dependencies:** T002

**Description:**
Add `--stage` filter argument and sorting logic to `list-features.sh`.

Filtering:

1. Accept `--stage <value>` argument (optional)
2. Valid stage values: `specify`, `clarify`, `plan`, `tasks`, `implement`, `complete`, `no-state`
3. When provided, filter the output JSON array to only include features matching that stage
4. Invalid stage values should produce an error message to stderr and exit 1

Sorting:

1. Sort features into two groups: active (stage != "complete") and completed (stage == "complete")
2. Within each group, sort by `numeric_id` descending (newest first)
3. Output active features first, then completed features
4. Add a `group` field to each feature object: `"active"` or `"completed"`

**Files to Modify:**

- `.maestro/scripts/list-features.sh`

**Acceptance Criteria:**

- [ ] `--stage specify` returns only features with `stage == "specify"`
- [ ] `--stage complete` returns only completed features
- [ ] Running without `--stage` returns all features
- [ ] Invalid `--stage` value produces error message to stderr and exits with code 1
- [ ] Active features appear before completed features in the output
- [ ] Within each group, features are sorted by `numeric_id` descending
- [ ] Each feature object includes a `group` field ("active" or "completed")

<!-- TASK:END -->

<!-- TASK:BEGIN id=T004 -->

### T004: Create maestro.list.md Command Definition

**Metadata:**

- **Label:** backend
- **Size:** S
- **Assignee:** general
- **Dependencies:** T003

**Description:**
Create the `maestro.list.md` command file following the established command definition pattern (YAML frontmatter + numbered steps).

The command must:

1. Have correct frontmatter: `description` (list all features with status and suggested actions) and `argument-hint` (`[--stage {specify|clarify|plan|tasks|implement|complete}]`)
2. Step 1: Prerequisites check — verify `.maestro/` exists
3. Step 2: Parse arguments — extract optional `--stage` filter
4. Step 3: Run `bash .maestro/scripts/list-features.sh [--stage X]` and capture JSON output
5. Step 4: Handle empty results — if JSON array is empty and no filter, show onboarding message: "No features found. Run `/maestro.specify` to create your first feature."
6. Step 5: Format output — render a column-aligned table with columns: ID, Name, Stage, Stories, Tasks, Next Action
7. Step 6: Add stage summary header — show counts per stage: `Summary: N specify | N clarify | N plan | ...`
8. Step 7: Group output — active features first (sorted by ID desc), then a separator line, then completed features
9. Step 8: Show stalled indicators — features with `is_stalled: true` show `⚠ STALLED (Nd)` next to stage
10. Step 9: Show orphan warnings — features with `has_state: false` show `⚠ No state` and next action suggests `/maestro.specify`
11. Step 10: Suggest next steps — recommend the most impactful action based on the overall feature landscape

**Files to Modify:**

- `.maestro/commands/maestro.list.md`

**Acceptance Criteria:**

- [ ] File exists at `.maestro/commands/maestro.list.md` with valid YAML frontmatter
- [ ] Frontmatter includes `description` and `argument-hint` fields
- [ ] Command follows the numbered step pattern consistent with other maestro commands
- [ ] Empty project shows onboarding message
- [ ] Table output includes 6 columns: ID, Name, Stage, Stories, Tasks, Next Action
- [ ] Stage summary header shows per-stage counts
- [ ] Active and completed features are visually separated
- [ ] Stalled features show `⚠ STALLED` indicator with days count
- [ ] Orphan specs show `⚠ No state` warning
- [ ] Next steps section suggests actionable commands

<!-- TASK:END -->

<!-- TASK:BEGIN id=T005 -->

### T005: Register Command and Create Test Fixtures

**Metadata:**

- **Label:** backend
- **Size:** XS
- **Assignee:** general
- **Dependencies:** T004

**Description:**
Register the new command with AI agent directories and create test fixtures for `list-features.sh`.

Registration:

1. Copy `maestro.list.md` to `.claude/commands/maestro.list.md`
2. Copy `maestro.list.md` to `.opencode/commands/maestro.list.md` (if `.opencode/` exists)
3. Note: `init.sh` already handles this via its glob pattern, but for immediate availability, copy now

Test fixtures:

1. Create `.maestro/scripts/test/fixtures/list-features/` directory
2. Create fixture state files representing: a feature in `specify` stage with clarifications, a feature in `complete` stage, a feature with no state file (orphan spec), a feature with malformed JSON state, a feature stalled for 30 days
3. Create corresponding minimal spec directories with `spec.md` files
4. Create `test-list-features.sh` that uses these fixtures to validate script behavior

**Files to Modify:**

- `.claude/commands/maestro.list.md`
- `.opencode/commands/maestro.list.md` (if exists)
- `.maestro/scripts/test/fixtures/list-features/` (new directory with fixtures)
- `.maestro/scripts/test/test-list-features.sh`

**Acceptance Criteria:**

- [ ] `.claude/commands/maestro.list.md` exists and matches `.maestro/commands/maestro.list.md`
- [ ] `.opencode/commands/maestro.list.md` exists if `.opencode/` directory exists
- [ ] Test fixture directory contains 5 fixture scenarios (specify with clarifications, complete, orphan, malformed, stalled)
- [ ] `test-list-features.sh` runs successfully and validates all 5 scenarios
- [ ] Test script verifies JSON output structure, stalled detection, next-action logic, and error handling

<!-- TASK:END -->

---

## 6. Task Sizing Guidance

When breaking down implementation into tasks, ensure all tasks are **XS** or **S** size only. **M** and **L** tasks must be split before they can be assigned.

### 6.1 Size Definitions

| Size   | Time Range                   | Status                |
| ------ | ---------------------------- | --------------------- |
| **XS** | 0-120 minutes (0-2 hours)    | Accepted              |
| **S**  | 121-360 minutes (2-6 hours)  | Accepted              |
| **M**  | 361-720 minutes (6-12 hours) | REJECTED - must split |
| **L**  | 721+ minutes (12+ hours)     | REJECTED - must split |

**Agent Assignment:** All tasks are assigned to `general` since the `agent_routing` config maps all labels to `general`.

### 6.2 Task Size Justification

| Task | Size | Justification                                                                      |
| ---- | ---- | ---------------------------------------------------------------------------------- |
| T001 | S    | Create new script with directory scanning, JSON parsing, error handling — ~4 hours |
| T002 | S    | Date math with 3 formats, stage-to-action mapping table — ~4 hours                 |
| T003 | XS   | Add argument parsing and `jq` sort/filter — ~1.5 hours                             |
| T004 | S    | Create full command definition with 10 steps, output formatting — ~5 hours         |
| T005 | XS   | Copy files, create fixtures and test script — ~2 hours                             |

---

## 7. Testing Strategy

### 7.1 Unit Tests

- **list-features.sh JSON output:** Verify each field in the output JSON matches expected values for known fixture data
- **Stalled detection:** Test with timestamps at exactly 13 days (not stalled), 14 days (stalled), 30 days (stalled), and today (not stalled)
- **Next-action mapping:** Test each stage value produces the correct command suggestion
- **Filter validation:** Test `--stage` with each valid value and with an invalid value
- **Title extraction:** Test with spec files that have the title, spec files that are missing, and spec files with unexpected first lines

### 7.2 Integration Tests

- **Full pipeline:** Run `list-features.sh` against the real `.maestro/` directory and verify the output is valid JSON with correct feature count
- **End-to-end command:** Run `/maestro.list` in the AI agent and verify the table renders correctly

### 7.3 End-to-End Tests

- Run `/maestro.list` with no arguments and verify all features appear
- Run `/maestro.list --stage complete` and verify only completed features appear
- Run `/maestro.list --stage specify` and verify filtering works
- Verify the stalled indicator appears for old features

### 7.4 Test Data

Test fixtures needed (in `.maestro/scripts/test/fixtures/list-features/`):

1. **Normal specify feature:** State with `stage: "specify"`, `clarification_count: 3`, `user_stories: 4`
2. **Completed feature:** State with `stage: "complete"`, `completed_at`, `task_count: 15`
3. **Orphan spec:** Spec directory exists but no state file
4. **Malformed state:** State file with invalid JSON
5. **Stalled feature:** State with `stage: "plan"`, `updated_at` set to 30 days ago
6. **Recently updated feature:** State with `stage: "implement"`, `updated_at` set to today

---

## 8. Risks and Mitigations

| Risk                                                   | Likelihood | Impact | Mitigation                                                                                   |
| ------------------------------------------------------ | ---------- | ------ | -------------------------------------------------------------------------------------------- |
| Date parsing fails on some macOS versions              | Medium     | Medium | Use `jq` for all date math instead of `date` command; test on macOS                          |
| Malformed state files crash the script                 | Medium     | Low    | Wrap `jq` calls with error suppression (`2>/dev/null`); default to `has_state: false`        |
| Orphan spec directories (test data) clutter the output | High       | Low    | Show with `⚠ No state` warning; users can ignore or clean up manually                        |
| Feature count grows beyond 100                         | Low        | Medium | Current design handles this; filtering by stage reduces output. Pagination deferred.         |
| `jq` not installed on user's system                    | Low        | High   | Check for `jq` at script start; if missing, print error with install instructions and exit 1 |
| init.sh glob doesn't pick up new command               | Low        | Low    | Glob pattern `maestro.*.md` already matches; T005 manually copies as backup                  |

---

## 9. Open Questions

None. All questions were resolved during clarification and research phases.
