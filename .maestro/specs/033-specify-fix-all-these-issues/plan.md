# Implementation Plan: Maestro Foundational Quality and DX Fixes

**Feature ID:** 033-specify-fix-all-these-issues
**Spec:** .maestro/specs/033-specify-fix-all-these-issues/spec.md
**Created:** 2026-03-16
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

This feature modifies existing infrastructure and documentation -- no new architectural components are introduced. Changes span four codebases (Go CLI, shell scripts, CI workflows, documentation) and touch configuration files. All changes are additive or corrective; no structural redesign is required.

### 1.2 Component Interactions

The changes are largely independent across the four work streams:

- **CI workflow** -- standalone GitHub Actions YAML, no code dependencies
- **Shell script fixes** -- `list-features.sh`, `parse-plan-tasks.sh`, `compile-gate.sh` are independent scripts
- **Go CLI doctor** -- `cmd/maestro-cli/cmd/doctor.go` reads system PATH, no new dependencies
- **Documentation** -- README.md, QUICKSTART.md are standalone files

The compile gate change (`compile-gate.sh`) interacts with `config.yaml` -- the config format changes to support multi-stack, so the script must be updated in lockstep with the config.

### 1.3 Key Design Decisions

| Decision                  | Options Considered                                                      | Chosen            | Rationale                                                                     |
| ------------------------- | ----------------------------------------------------------------------- | ----------------- | ----------------------------------------------------------------------------- |
| Multi-stack config format | (A) Comma-separated `stack: go,node` (B) YAML list `stacks: [go, node]` | (B) YAML list     | Cleaner to parse, extensible, consistent with YAML conventions                |
| CI rollout strategy       | (A) Blocking from day one (B) Non-blocking first                        | (B) Non-blocking  | Avoids PR deadlock if existing tests are broken; phased approach reduces risk |
| Orphan spec cleanup       | (A) Archive (B) Delete (C) Exclude from listing                         | (B) Delete        | Test/duplicate data with no state files and no unique content                 |
| Go test handling          | (A) Un-skip all (B) Remove all (C) Evaluate each                        | (C) Evaluate each | Some tests may be valid but need updating; others may be truly dead           |

---

## 2. Component Design

### 2.1 New Components

#### Component: QUICKSTART.md

- **Purpose:** Step-by-step tutorial walking through the maestro pipeline on a trivial example (install through tasks)
- **Location:** `QUICKSTART.md`
- **Dependencies:** Working `maestro init`, `bd` CLI
- **Dependents:** Linked from README.md

### 2.2 Modified Components

#### Component: CI Workflow

- **Current:** Single job running Go test/build/vet only
- **Change:** Add 3 new parallel jobs: TypeScript (tsc + vitest), Rust (cargo check + cargo test), Shell (bash test scripts). All new jobs start with `continue-on-error: true`.
- **Risk:** Medium -- may expose existing test failures in non-Go stacks

#### Component: compile-gate.sh

- **Current:** Reads single `stack` key from config, runs one command
- **Change:** Read new `stacks` list (array), iterate and run each stack's command. Report per-stack pass/fail. Maintain backward compatibility with single `stack` key.
- **Risk:** Medium -- breaking change to config format; must handle both old and new format

#### Component: config.yaml

- **Current:** `stack: go` (single value) under `compile_gate`
- **Change:** Add `stacks: [go]` list format. Add `elixir` and ensure all stack commands are valid. Fix `node` command to reference existing package.json scripts.
- **Risk:** Low -- additive change with backward compatibility

#### Component: list-features.sh

- **Current:** `VALID_STAGES` array missing `research`; `compute_next_action` has no `research)` case
- **Change:** Add `research` to `VALID_STAGES` and add `research)` case to `compute_next_action` suggesting `/maestro.plan`
- **Risk:** Low -- additive change to existing switch statement

#### Component: parse-plan-tasks.sh

- **Current:** Lines 251, 252, 267 produce malformed JSON due to bash double-quote consumption
- **Change:** Fix quoting so `"count"`, `"errors"`, `"warnings"` are valid JSON keys
- **Risk:** Low -- targeted fix to 3 lines

#### Component: doctor.go

- **Current:** Checks for `.maestro/` directory, `config.yaml`, `scripts/`, `specs/`, `state/`
- **Change:** Add system dependency checks for `bd`, `jq`, `python3`, `git` on PATH with actionable fix messages
- **Risk:** Low -- additive checks; existing checks unchanged

#### Component: commands_test.go

- **Current:** 10 of 17 tests skipped with stale message
- **Change:** Evaluate each skipped test: un-skip if the tested functionality exists, remove if dead code
- **Risk:** Medium -- may uncover real issues with init flags

#### Component: README.md

- **Current:** Missing 3 commands from table; no prerequisites section; broken bd install guidance
- **Change:** Add prerequisites section, update command table to 14 entries, fix bd install text, link to QUICKSTART.md
- **Risk:** Low -- documentation only

#### Component: dashboard.test.ts (duplicate)

- **Current:** Two test files: `dashboard.test.ts` (47 lines, 3 tests) and `dashboard.store.test.ts` (400 lines, comprehensive)
- **Change:** Delete `dashboard.test.ts`; keep `dashboard.store.test.ts`
- **Risk:** Low -- the smaller file is a subset of the larger

---

## 3. Data Model

### 3.1 New Entities

None -- no new data models are introduced.

### 3.2 Modified Entities

#### Entity: config.yaml compile_gate section

- **Current fields:** `go`, `node`, `python`, `rust`, `stack` (single value)
- **New fields:** `elixir`, `stacks` (list of stack names)
- **Migration notes:** Backward compatible. `compile-gate.sh` checks for `stacks` list first; falls back to `stack` single value if list is absent.

```yaml
compile_gate:
  go: "cd cmd/maestro-cli && go build ./... && go vet ./... && go test ./..."
  node: "pnpm run build && pnpm run test:run"
  python: "python -m py_compile **/*.py && ruff check ."
  rust: "cd src-tauri && cargo check && cargo test"
  elixir: "mix compile --warnings-as-errors && mix test"
  # New: list of stacks to run (replaces single 'stack' key)
  stacks:
    - go
  # Legacy: single stack (deprecated, kept for backward compatibility)
  stack: go
```

### 3.3 Data Flow

No new data flows. The compile gate reads config, executes commands, and reports results. The doctor command checks PATH for binaries. CI runs tests and reports status.

---

## 4. API Contracts

No APIs are added or modified. All changes are to CLI commands, shell scripts, CI workflows, and documentation.

---

## 5. Implementation Tasks

<!-- TASK:BEGIN id=T001 -->

### T001: Fix parse-plan-tasks.sh JSON Generation Bug

**Metadata:**

- **Label:** fix
- **Size:** XS
- **Assignee:** general
- **Dependencies:** None

**Description:**
Fix the malformed JSON output in `parse-plan-tasks.sh`. Lines 251, 252, and 267 use bash double-quoted strings where the inner double quotes for JSON keys (`"count"`, `"errors"`, `"warnings"`) are consumed by bash, producing invalid JSON like `count: 0,` instead of `"count": 0,`.

Replace the broken `echo` lines with properly escaped versions using `\"` or heredoc syntax to ensure valid JSON output.

**Files to Modify:**

- `.maestro/scripts/parse-plan-tasks.sh`

**Acceptance Criteria:**

- [ ] Line 251 outputs `  "count": $TASK_COUNT,` with valid JSON quoting
- [ ] Line 252 outputs `  "errors": [` with valid JSON quoting
- [ ] Line 267 outputs `  "warnings": [` with valid JSON quoting
- [ ] Running the script on a valid plan file produces output that passes `jq .` without errors

<!-- TASK:END -->

<!-- TASK:BEGIN id=T002 -->

### T002: Add Research Stage to list-features.sh

**Metadata:**

- **Label:** fix
- **Size:** XS
- **Assignee:** general
- **Dependencies:** None

**Description:**
Add `research` to the `VALID_STAGES` array on line 12 and add a `research)` case to the `compute_next_action` function (around line 191). The research stage should suggest `/maestro.plan` as the next action with reason "Research complete, ready to plan".

**Files to Modify:**

- `.maestro/scripts/list-features.sh`

**Acceptance Criteria:**

- [ ] `VALID_STAGES` array on line 12 includes `"research"` between `"clarify"` and `"plan"`
- [ ] `compute_next_action` has a `research)` case that returns `next_action="/maestro.plan"` and `reason="Research complete, ready to plan"`
- [ ] Running `bash .maestro/scripts/list-features.sh --stage research` does not error
- [ ] Existing shell tests still pass: `bash .maestro/scripts/test/test-list-features.sh`

<!-- TASK:END -->

<!-- TASK:BEGIN id=T003 -->

### T003: Fix Node Compile Gate Command and Add Multi-Stack Support

**Metadata:**

- **Label:** backend
- **Size:** S
- **Assignee:** general
- **Dependencies:** None

**Description:**
Update `compile-gate.sh` to support running multiple stacks in a single invocation. The script should:

1. Check for a `stacks` list in config.yaml (new format: YAML list)
2. Fall back to the single `stack` key if `stacks` is not present (backward compatibility)
3. Iterate over each stack, run its command, and collect per-stack pass/fail results
4. Report a summary showing each stack's status
5. Exit 1 if any stack fails, exit 0 if all pass

Also update `config.yaml` to:

- Fix the `node` command from `npm run build && npm run lint` to `pnpm run build && pnpm run test:run` (matching actual package.json scripts)
- Add `elixir: "mix compile --warnings-as-errors && mix test"` command
- Add `stacks` list key (defaulting to `[go]`)
- Keep the deprecated `stack: go` key for backward compatibility

**Files to Modify:**

- `.maestro/scripts/compile-gate.sh`
- `.maestro/config.yaml`

**Acceptance Criteria:**

- [ ] Running `compile-gate.sh` with `stacks: [go]` in config runs the Go command and passes
- [ ] Running `compile-gate.sh` with a single `stack: go` (no `stacks` list) still works (backward compatible)
- [ ] The `node` compile gate command references `pnpm run build && pnpm run test:run`
- [ ] The `elixir` stack entry exists with `mix compile --warnings-as-errors && mix test`
- [ ] When multiple stacks are configured, the output shows per-stack pass/fail
- [ ] If any stack fails, the overall gate fails (exit 1)

<!-- TASK:END -->

<!-- TASK:BEGIN id=T004 -->

### T004: Enhance maestro doctor with Dependency Checks

**Metadata:**

- **Label:** backend
- **Size:** S
- **Assignee:** general
- **Dependencies:** None

**Description:**
Extend `doctor.go` to check for system dependencies on PATH. Add checks for `bd`, `jq`, `python3`, and `git`. Each check should:

1. Use `exec.LookPath()` to check if the binary exists on PATH
2. If missing, provide an actionable fix message with install instructions
3. Mark `bd` and `git` as required (failure affects exit code); mark `jq` and `python3` as warnings (optional but recommended)

Install instruction suggestions:

- `bd`: "Install from https://github.com/anomalyco/beads"
- `jq`: "Install via: brew install jq (macOS) or apt-get install jq (Linux)"
- `python3`: "Install via: brew install python3 (macOS) or apt-get install python3 (Linux)"
- `git`: "Install via: brew install git (macOS) or apt-get install git (Linux)"

**Files to Modify:**

- `cmd/maestro-cli/cmd/doctor.go`

**Acceptance Criteria:**

- [ ] `maestro doctor` checks for `bd`, `jq`, `python3`, `git` on PATH
- [ ] Missing `bd` or `git` causes doctor to report failure (exit code 1)
- [ ] Missing `jq` or `python3` shows a warning but does not fail doctor
- [ ] Each missing dependency shows an actionable install instruction
- [ ] Existing directory/file checks still work unchanged

<!-- TASK:END -->

<!-- TASK:BEGIN id=T005 -->

### T005: Fix bd Install Guidance in check-prerequisites.sh

**Metadata:**

- **Label:** fix
- **Size:** XS
- **Assignee:** general
- **Dependencies:** None

**Description:**
Fix line 182 in `check-prerequisites.sh` which currently outputs a broken install suggestion with literal ellipsis: `"Install bd: go install github.com/..."`. Replace with the actual install URL for the beads CLI.

**Files to Modify:**

- `.maestro/scripts/check-prerequisites.sh`

**Acceptance Criteria:**

- [ ] Line 182 outputs a real install command or URL (not `github.com/...` with ellipsis)
- [ ] The install suggestion points to `https://github.com/anomalyco/beads`
- [ ] The JSON output is valid (parseable by `jq`)

<!-- TASK:END -->

<!-- TASK:BEGIN id=T006 -->

### T006: Resolve Skipped Go Tests in commands_test.go

**Metadata:**

- **Label:** test
- **Size:** S
- **Assignee:** general
- **Dependencies:** None

**Description:**
Evaluate the 10 skipped tests in `cmd/maestro-cli/cmd/commands_test.go`. Each test is skipped with `t.Skip("Flags withOpenCode and withClaude not yet implemented in init command")`. The `--with-opencode` and `--with-claude` flags ARE implemented in `init.go` (lines 41-42).

For each skipped test:

1. Remove the `t.Skip()` call
2. Run the test locally
3. If it passes, keep it
4. If it fails, fix the test to match current behavior (the init command's API may have changed since the tests were written)
5. If the test is fundamentally invalid (tests something that no longer exists), remove it with a comment explaining why

**Files to Modify:**

- `cmd/maestro-cli/cmd/commands_test.go`

**Acceptance Criteria:**

- [ ] Zero `t.Skip()` calls remain in `commands_test.go`
- [ ] All tests in the file pass when run with `go test ./...` from `cmd/maestro-cli/`
- [ ] No test is deleted without a clear comment in the commit explaining why

<!-- TASK:END -->

<!-- TASK:BEGIN id=T007 -->

### T007: Remove Duplicate Dashboard Test File

**Metadata:**

- **Label:** fix
- **Size:** XS
- **Assignee:** general
- **Dependencies:** None

**Description:**
Delete `src/stores/dashboard.test.ts` (47 lines, 3 tests). Keep `src/stores/dashboard.store.test.ts` (400 lines, comprehensive). The smaller file is an older version that was superseded. Verify the comprehensive file covers all scenarios from the smaller file before deleting.

**Files to Modify:**

- `src/stores/dashboard.test.ts` (delete)

**Acceptance Criteria:**

- [ ] `src/stores/dashboard.test.ts` no longer exists
- [ ] `src/stores/dashboard.store.test.ts` still exists and passes: `pnpm run test:run`
- [ ] The 3 test cases from the deleted file are covered by the remaining file

<!-- TASK:END -->

<!-- TASK:BEGIN id=T008 -->

### T008: Delete Orphan Spec Directories (020-030)

**Metadata:**

- **Label:** fix
- **Size:** XS
- **Assignee:** general
- **Dependencies:** None

**Description:**
Delete the 11 orphan spec directories that are test/duplicate data with no corresponding state files:

- `.maestro/specs/020-we-need-build-kanban-board-our-tauri-ui/`
- `.maestro/specs/021-we-need-build-kanban-board-our-tauri-ui/`
- `.maestro/specs/022-need-build-kanban-board-tauri-ui/`
- `.maestro/specs/023-kanban-board-ui/`
- `.maestro/specs/024-quick-brown-fox-jumps-lazy-dog/`
- `.maestro/specs/025-add-user-authentication/`
- `.maestro/specs/026-kanban-board-ui/`
- `.maestro/specs/027-amazing-kanban-board/`
- `.maestro/specs/028-customize-maestro-flow-planning-side/`
- `.maestro/specs/029-customize-maestro-flow-planning-side/`
- `.maestro/specs/030-brand-new-feature-does-something-cool/`

Verify none have state files before deleting.

**Files to Modify:**

- `.maestro/specs/020-*` through `.maestro/specs/030-*` (delete 11 directories)

**Acceptance Criteria:**

- [ ] All 11 directories listed above are deleted
- [ ] No state files existed for any of these directories (verified before delete)
- [ ] Remaining spec directories (001-019, 031-033) are untouched
- [ ] `/maestro.list` output no longer shows these orphan entries

<!-- TASK:END -->

<!-- TASK:BEGIN id=T009 -->

### T009: Update README with Prerequisites and Full Command Table

**Metadata:**

- **Label:** backend
- **Size:** S
- **Assignee:** general
- **Dependencies:** T005

**Description:**
Update `README.md` with three changes:

1. **Add Prerequisites section** after the "How It Works" section listing all system requirements: `bd` (with actual install link), `jq`, `python3`, `git`, and a supported AI agent (Claude Code or OpenCode). Include install commands for macOS (brew) and Linux (apt).

2. **Update command table** to include all 14 commands. Add the 3 missing entries:
   - `/maestro.list` -- Show feature dashboard with pipeline stage, progress, and next actions
   - `/maestro.research.list` -- List all research artifacts with status
   - `/maestro.research.search` -- Search existing research by keyword

3. **Add link to QUICKSTART.md** in the installation section after Step 4.

**Files to Modify:**

- `README.md`

**Acceptance Criteria:**

- [ ] Prerequisites section lists `bd`, `jq`, `python3`, `git`, and AI agent requirement
- [ ] `bd` install guidance points to `https://github.com/anomalyco/beads` (not placeholder ellipsis)
- [ ] Command table lists exactly 14 commands
- [ ] Link to `QUICKSTART.md` is present in the installation section
- [ ] No broken markdown links

<!-- TASK:END -->

<!-- TASK:BEGIN id=T010 -->

### T010: Expand CI Workflow with TypeScript, Rust, and Shell Jobs

**Metadata:**

- **Label:** backend
- **Size:** S
- **Assignee:** general
- **Dependencies:** T006, T007

**Description:**
Expand `.github/workflows/ci.yml` from 1 job to 4 parallel jobs:

1. **go-test** (existing) -- `go test`, `go build`, `go vet` in `cmd/maestro-cli/`
2. **typescript-test** (new) -- `pnpm install`, `pnpm run build` (includes tsc), `pnpm run test:run`
3. **rust-test** (new) -- install Rust toolchain, `cargo check`, `cargo test` in `src-tauri/`
4. **shell-test** (new) -- run `bash .maestro/scripts/test/test-list-features.sh`, `bash .maestro/scripts/test/validate-plan-test.sh`, `bash .maestro/scripts/test/create-tasks-test.sh`

New jobs 2-4 must use `continue-on-error: true` (non-blocking). Job 1 (Go) remains blocking.

Dependencies: T006 (Go tests un-skipped) and T007 (duplicate test file removed) must be done first so the test suites are clean.

**Files to Modify:**

- `.github/workflows/ci.yml`

**Acceptance Criteria:**

- [ ] CI workflow has 4 jobs: `go-test`, `typescript-test`, `rust-test`, `shell-test`
- [ ] All 4 jobs run in parallel (no `needs:` dependencies between them)
- [ ] `typescript-test` runs `pnpm install`, `pnpm run build`, `pnpm run test:run`
- [ ] `rust-test` runs `cargo check` and `cargo test` in `src-tauri/`
- [ ] `shell-test` runs the 3 shell test scripts
- [ ] Jobs 2-4 have `continue-on-error: true`
- [ ] Go job remains blocking (no continue-on-error)

<!-- TASK:END -->

<!-- TASK:BEGIN id=T011 -->

### T011: Create Quickstart Tutorial

**Metadata:**

- **Label:** backend
- **Size:** S
- **Assignee:** general
- **Dependencies:** T009

**Description:**
Create `QUICKSTART.md` at the repo root. Walk a new user through the complete pipeline on a trivial example feature ("add a greeting message"). The tutorial covers:

1. **Install** -- how to get the maestro CLI and bd
2. **Init** -- `maestro init` in a fresh project
3. **Specify** -- `/maestro.specify "add a greeting message"` with expected output
4. **Clarify** -- `/maestro.clarify` resolving sample markers
5. **Plan** -- `/maestro.plan` generating the implementation plan
6. **Tasks** -- `/maestro.tasks` creating bd issues

Each step shows the command, expected output (abbreviated), and what to verify before proceeding. Total estimated time: under 10 minutes.

The tutorial stops at tasks. A note at the end explains that `/maestro.implement` requires a live AI agent session.

**Files to Modify:**

- `QUICKSTART.md` (create new)

**Acceptance Criteria:**

- [ ] `QUICKSTART.md` exists at repo root
- [ ] Tutorial covers 6 stages: install, init, specify, clarify, plan, tasks
- [ ] Each step includes the exact command to run
- [ ] Each step includes abbreviated expected output
- [ ] Tutorial explicitly states it stops before implement/review
- [ ] Uses a concrete, trivial example feature (not abstract placeholders)

<!-- TASK:END -->

---

## 6. Task Sizing Guidance

All tasks are XS or S. No task exceeds the 6-hour S ceiling.

| Task                             | Size | Estimated Effort |
| -------------------------------- | ---- | ---------------- |
| T001: Fix JSON bug               | XS   | 30 min           |
| T002: Add research stage         | XS   | 30 min           |
| T003: Multi-stack compile gate   | S    | 3 hours          |
| T004: Doctor dependency checks   | S    | 2 hours          |
| T005: Fix bd install guidance    | XS   | 15 min           |
| T006: Resolve skipped Go tests   | S    | 3 hours          |
| T007: Remove duplicate test file | XS   | 15 min           |
| T008: Delete orphan specs        | XS   | 15 min           |
| T009: Update README              | S    | 2 hours          |
| T010: Expand CI workflow         | S    | 3 hours          |
| T011: Create quickstart tutorial | S    | 4 hours          |

---

## 7. Testing Strategy

### 7.1 Unit Tests

- **T001 (JSON fix):** Pipe output of `parse-plan-tasks.sh` through `jq .` to validate JSON
- **T002 (list-features):** Run existing `test-list-features.sh` + add a test case for `research` stage
- **T003 (compile gate):** Test with single-stack config, multi-stack config, backward-compatible config, and invalid stack
- **T004 (doctor):** Existing `TestDoctorOnInitializedProject` test; add new test verifying dependency check output
- **T006 (Go tests):** Un-skipped tests serve as their own verification

### 7.2 Integration Tests

- **T010 (CI):** Push to a branch and verify all 4 CI jobs appear and execute
- **T003 + T010:** Verify the compile gate runs in CI with the correct stack configuration

### 7.3 End-to-End Tests

- **T011 (quickstart):** Manually walk through the tutorial on a fresh directory to verify all steps work

### 7.4 Test Data

- Existing test fixtures in `.maestro/scripts/test/fixtures/` are sufficient
- T002 may need a new fixture for the `research` stage in `test-list-features.sh`

---

## 8. Risks and Mitigations

| Risk                                                           | Likelihood | Impact | Mitigation                                                                  |
| -------------------------------------------------------------- | ---------- | ------ | --------------------------------------------------------------------------- |
| CI expansion exposes broken tests in TS/Rust/Shell             | High       | Medium | New jobs use `continue-on-error: true`; fix failures in follow-up           |
| Multi-stack compile gate breaks existing single-stack users    | Low        | High   | Backward-compatible: falls back to `stack` key when `stacks` list is absent |
| Un-skipping Go tests reveals init command bugs                 | Medium     | Medium | Fix tests to match current behavior; some may need updating                 |
| Orphan spec cleanup deletes something useful                   | Low        | Low    | Verified: all 11 dirs are test/duplicate data with no state files           |
| Quickstart tutorial goes stale as commands evolve              | Medium     | Low    | Link tutorial to specific version; note "last verified" date                |
| Custom awk YAML parser in compile-gate.sh fails on list syntax | Medium     | Medium | Add a simple list parser; test with `stacks: [go, node]` format             |

---

## 9. Open Questions

- None -- all questions were resolved during clarification.
