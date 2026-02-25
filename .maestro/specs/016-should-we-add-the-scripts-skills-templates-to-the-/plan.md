# Implementation Plan: Include Starter Assets in `maestro init`

**Feature ID:** 016-should-we-add-the-scripts-skills-templates-to-the-
**Spec:** .maestro/specs/016-should-we-add-the-scripts-skills-templates-to-the-/spec.md
**Created:** 2026-02-20
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

The feature extends CLI initialization so starter asset groups (`scripts`, `skills`, `templates`) are treated as required baseline content and are installed by default, including non-interactive runs. The existing init flow remains the entry point; it will call a dedicated installer flow that:

1. Resolves required asset groups and source locations
2. Detects conflicts and applies one global conflict decision
3. Downloads required asset groups
4. Performs an all-or-nothing install for required groups (rollback on failure)
5. Emits clear user-facing status without exposing secrets

This fits the constitution by keeping presentation concerns in command handlers and install logic in package-level services.

### 1.2 Component Interactions

1. `cmd/init.go` gathers user context (interactive/non-interactive), selects default required groups, and invokes installation orchestration.
2. `pkg/agents` (or new install package) performs conflict detection and applies one global action.
3. `pkg/github` fetches remote content with existing fallback behavior.
4. Installer stages writes and commits only when all required groups are ready; otherwise restores pre-install state.
5. `cmd/init.go` prints final result summary and error guidance.

### 1.3 Key Design Decisions

| Decision                                            | Options Considered                                         | Chosen                       | Rationale                                                 |
| --------------------------------------------------- | ---------------------------------------------------------- | ---------------------------- | --------------------------------------------------------- |
| Required default groups                             | Keep optional defaults vs require scripts/skills/templates | Require all three by default | Matches clarified spec and consistency goal               |
| Conflict resolution scope                           | Per-directory vs single global action                      | Single global action         | Matches clarified behavior and reduces prompt noise       |
| Failure handling for required groups                | Partial success vs fail fast with rollback                 | Fail fast with rollback      | Matches success criteria: no partial required-asset state |
| Non-interactive behavior                            | Require flags vs default install                           | Default install              | Matches clarified non-interactive requirement             |
| User messaging severity for skipped optional groups | Info vs warning vs error                                   | Warning                      | Matches clarified user-visible severity                   |

---

## 2. Component Design

### 2.1 New Components

#### Component: RequiredAssetPolicy

- **Purpose:** Define required starter asset groups and default installation rules.
- **Location:** `cmd/maestro-cli/pkg/agents/policy.go`
- **Dependencies:** `pkg/agents/detect.go`
- **Dependents:** `cmd/init.go`, `cmd/update.go`

#### Component: AtomicAssetInstaller

- **Purpose:** Execute staged install + rollback for required groups.
- **Location:** `cmd/maestro-cli/pkg/agents/installer.go`
- **Dependencies:** `pkg/agents/writer.go`, `pkg/github/contents.go`, filesystem package(s)
- **Dependents:** `cmd/init.go`

### 2.2 Modified Components

#### Component: init command flow

- **Current:** Initializes `.maestro`, supports selected agent dirs, allows partial outcomes on remote failures.
- **Change:** Enforce required starter asset baseline, default installation in non-interactive mode, fail-fast required retrieval, global conflict action, and all-or-nothing write outcome.
- **Risk:** High - central onboarding path; regressions affect first-run experience.

#### Component: agent directory fetch flow

- **Current:** Fetches selected directories by ref with fallback.
- **Change:** Support required group retrieval semantics and clearer error typing for fail-fast decisions.
- **Risk:** Medium - network and source-shape edge cases.

#### Component: conflict prompt behavior

- **Current:** Supports conflict prompting, reusable in init/update flows.
- **Change:** Guarantee one global action across all required conflicting directories and consistent messaging.
- **Risk:** Medium - user data protection and expectation alignment.

#### Component: command documentation

- **Current:** Describes init behavior and optional auth guidance.
- **Change:** Document required default groups, non-interactive defaults, and rollback/failure semantics.
- **Risk:** Low - documentation drift risk only.

---

## 3. Data Model

### 3.1 New Entities

#### Entity: InstallTransaction (in-memory)

```
InstallTransaction:
  required_groups: [scripts, skills, templates]
  staged_paths: list[path]
  backups_created: list[path]
  conflict_action: overwrite | backup | cancel
  status: pending | committed | rolled_back
```

### 3.2 Modified Entities

#### Entity: InitResult (command output contract)

- **Current fields:** success/failure by returned error and console output.
- **New fields:** explicit installed groups list, skipped groups list, rollback occurred flag (output-level concept).
- **Migration notes:** No persisted schema changes.

### 3.3 Data Flow

Input (init context) -> required group resolution -> conflict detection -> fetch all required groups -> stage writes -> commit or rollback -> summarized output.

---

## 4. API Contracts

### 4.1 New Endpoints/Methods

No external API surface changes. This feature modifies CLI command behavior and internal package interfaces only.

### 4.2 Modified Endpoints

No HTTP/RPC endpoints are modified.

---

## 5. Implementation Phases

### Phase 1: Policy and Selection Rules

- **Goal:** Encode required default groups and non-interactive defaults.
- **Tasks:**
  - Add required asset policy in `cmd/maestro-cli/pkg/agents/policy.go` - Assignee: general
  - Integrate policy into `cmd/maestro-cli/cmd/init.go` selection path - Assignee: general
  - Align update behavior in `cmd/maestro-cli/cmd/update.go` where needed - Assignee: general
- **Deliverable:** Init selection behavior matches spec defaults in unit tests.

### Phase 2: Atomic Installation and Rollback

- **Goal:** Guarantee no partial required-asset state on failure.
- **Dependencies:** Phase 1
- **Tasks:**
  - Add transactional installer in `cmd/maestro-cli/pkg/agents/installer.go` - Assignee: general
  - Reuse/extend backup and writer helpers in `cmd/maestro-cli/pkg/agents/writer.go` - Assignee: general
  - Wire init flow to staged commit/rollback in `cmd/maestro-cli/cmd/init.go` - Assignee: general
- **Deliverable:** Failure scenarios leave required groups unchanged or fully rolled back.

### Phase 3: Conflict and Error UX

- **Goal:** Enforce one global conflict action and actionable fail-fast messages.
- **Dependencies:** Phase 2
- **Tasks:**
  - Normalize global conflict handling in `cmd/maestro-cli/cmd/update.go` and `cmd/maestro-cli/cmd/init.go` - Assignee: general
  - Ensure warning severity for optional-group skip cases in command output paths - Assignee: general
  - Tighten error context mapping in `cmd/maestro-cli/pkg/github/client.go` and `cmd/maestro-cli/pkg/github/contents.go` - Assignee: general
- **Deliverable:** Clear, consistent messages validated by command-level tests.

### Phase 4: Verification and Documentation

- **Goal:** Lock behavior with tests and docs.
- **Dependencies:** Phase 3
- **Tasks:**
  - Extend command tests in `cmd/maestro-cli/cmd/commands_test.go` and `cmd/maestro-cli/cmd/init_test.go` - Assignee: general
  - Add/extend fetch-path tests in `cmd/maestro-cli/pkg/github/contents_test.go` - Assignee: general
  - Update docs in `cmd/maestro-cli/USAGE.md`, `cmd/maestro-cli/README.md`, `cmd/maestro-cli/TROUBLESHOOTING.md` - Assignee: general
- **Deliverable:** Passing test suite and updated user documentation.

---

## 6. Task Sizing Guidance

Keep all implementation tasks XS/S by splitting by file and operation:

- `policy.go` creation and tests as one S task
- installer transaction logic and tests as one S task
- init wiring and messaging as one S task
- update/conflict alignment as one XS/S task
- docs updates as one XS task

---

## 7. Testing Strategy

### 7.1 Unit Tests

- Required policy tests for default/non-interactive behavior.
- Transactional installer tests for commit and rollback paths.
- Conflict decision tests for one global action across multiple directories.

### 7.2 Integration Tests

- Command integration tests for init with required groups present/absent.
- Remote fetch failure tests validating fail-fast required behavior.

### 7.3 End-to-End Tests

- Initialize a clean temp project and verify required baseline directories exist.
- Simulate required-group failure and verify no partial required-asset state remains.

### 7.4 Test Data

- Temp directories with pre-existing `scripts`, `skills`, and `templates` content.
- Mocked remote responses for success, not found, and rate-limit/fallback paths.

---

## 8. Risks and Mitigations

| Risk                                                    | Likelihood | Impact | Mitigation                                                             |
| ------------------------------------------------------- | ---------- | ------ | ---------------------------------------------------------------------- |
| Rollback logic leaves residual files on edge failures   | M          | H      | Use staged writes, explicit cleanup checks, and rollback-focused tests |
| Existing users surprised by stricter fail-fast behavior | M          | M      | Clear CLI output, migration notes in docs, and explicit warnings       |
| Regression in `init` due to central flow changes        | M          | H      | Add command-level tests for happy path and conflict/error paths        |
| Remote source structure drift breaks required retrieval | M          | M      | Preserve fallback retrieval path and add source-shape contract tests   |

---

## 9. Open Questions

- None at planning time; all current spec clarifications are resolved.
