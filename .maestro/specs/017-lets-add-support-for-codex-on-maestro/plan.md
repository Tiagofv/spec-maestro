# Implementation Plan: Codex CLI Support in Maestro

**Feature ID:** 017-lets-add-support-for-codex-on-maestro
**Spec:** .maestro/specs/017-lets-add-support-for-codex-on-maestro/spec.md
**Created:** 2026-02-20
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

This feature extends the existing agent-directory integration pattern by adding `.codex/` as a first-class CLI profile alongside `.opencode/` and `.claude/`.

The design keeps the current architecture intact:

- Presentation layer: `maestro init`, `maestro update`, and `maestro doctor` commands surface Codex selection and status.
- Application/domain behavior: known agent directories list drives detection, prompts, conflict handling, and update flow.
- Infrastructure behavior: existing GitHub fetch + local writer pipeline installs `.codex/` content exactly like current profiles.

This directly satisfies the spec goals of Codex CLI parity, clear failure messaging, and run-time visibility through existing workflows.

### 1.2 Component Interactions

1. User runs `maestro init`.
2. Selection flow includes `.codex` in available agent directories.
3. Conflict resolution applies existing overwrite/backup/cancel behavior.
4. Fetch/install pipeline downloads `.codex` profile content and writes it to project root.
5. `maestro doctor` and `maestro update` discover `.codex` via shared known-dir registry and include it in warning/refresh/install paths.
6. `.maestro/scripts/init.sh` registers Maestro commands and skills to `.codex` when using slash-command flow.

### 1.3 Key Design Decisions

| Decision             | Options Considered                                                     | Chosen                                                  | Rationale                                                                            |
| -------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Codex representation | Treat Codex as model option; treat Codex as CLI profile directory      | CLI profile directory (`.codex/`)                       | Matches clarified requirement: Codex means Codex CLI, not model routing.             |
| Selection behavior   | New dedicated interaction; reuse existing agent selection flow         | Reuse existing `KnownAgentDirs` flow                    | Preserves current UX and minimizes regression risk while meeting parity requirement. |
| Content source       | Generate `.codex` dynamically; version `.codex` in repo/release assets | Version `.codex` profile content like existing profiles | Ensures deterministic init/update behavior and parity with `.opencode`/`.claude`.    |
| Failure handling     | Add special fallback modes; keep current actionable errors             | Keep current error path with clearer Codex wording      | Spec explicitly limits MVP to clear errors without fallback mode expansion.          |

---

## 2. Component Design

### 2.1 New Components

#### Component: Codex Agent Profile Content

- **Purpose:** Provide command and skill files for Codex CLI integration parity.
- **Location:** `.codex/commands/`, `.codex/skills/`
- **Dependencies:** `.maestro/commands/`, `.maestro/skills/` source artifacts
- **Dependents:** `cmd/maestro-cli/cmd/init.go`, `cmd/maestro-cli/cmd/update.go`, `.maestro/scripts/init.sh`

#### Component: Init Flag for Codex

- **Purpose:** Allow explicit non-interactive Codex installation during `maestro init`.
- **Location:** `cmd/maestro-cli/cmd/init.go`
- **Dependencies:** `cmd/maestro-cli/pkg/agents/detect.go`, `cmd/maestro-cli/pkg/agents/prompt.go`
- **Dependents:** CLI users and automation scripts

### 2.2 Modified Components

#### Component: Known Agent Directory Registry

- **Current:** Returns `.opencode` and `.claude` only.
- **Change:** Add `.codex` to the single source of truth used by init/update/doctor flows.
- **Risk:** Medium - affects multiple commands through shared behavior.
- **Location:** `cmd/maestro-cli/pkg/agents/detect.go`

#### Component: Agent Selection and Labels

- **Current:** Prompt descriptions cover OpenCode and Claude only.
- **Change:** Add Codex description and ensure prompt ordering remains stable.
- **Risk:** Low - isolated to prompt rendering and parsing behavior.
- **Location:** `cmd/maestro-cli/pkg/agents/prompt.go`

#### Component: Optional Agent Install Flags

- **Current:** Supports `--with-opencode` and `--with-claude`.
- **Change:** Add `--with-codex` and include in selection resolution logic.
- **Risk:** Medium - regression risk in non-interactive init scripts.
- **Location:** `cmd/maestro-cli/cmd/init.go`

#### Component: Update/Doctor Agent Discovery Paths

- **Current:** Refreshes/prompts/checks optional status for known dirs.
- **Change:** Codex included automatically via known-dir list; update user-facing messages if needed.
- **Risk:** Low - behavior is list-driven once registry changes.
- **Location:** `cmd/maestro-cli/cmd/update.go`, `cmd/maestro-cli/cmd/doctor.go`

#### Component: Shell-based Maestro Initialization Script

- **Current:** Registers commands/skills into `.claude` and `.opencode` only.
- **Change:** Register same artifacts into `.codex`.
- **Risk:** Medium - impacts bootstrap behavior for slash-command users.
- **Location:** `.maestro/scripts/init.sh`

#### Component: User Documentation

- **Current:** Docs explain `.claude` and `.opencode` setup only.
- **Change:** Add `.codex` parity to CLI usage and project docs.
- **Risk:** Low - documentation-only regression.
- **Location:** `README.md`, `cmd/maestro-cli/USAGE.md`, `.maestro/commands/maestro.init.md`

#### Component: Tests

- **Current:** Unit tests assert two known dirs and two selection options.
- **Change:** Extend test fixtures/assertions for `.codex` in init, prompt, detect, and update behavior.
- **Risk:** Medium - broad test updates required to prevent false positives.
- **Location:** `cmd/maestro-cli/cmd/init_test.go`, `cmd/maestro-cli/pkg/agents/prompt_test.go`, `cmd/maestro-cli/pkg/agents/policy_test.go`, `cmd/maestro-cli/cmd/commands_test.go`

---

## 3. Data Model

See detailed model in `.maestro/specs/017-lets-add-support-for-codex-on-maestro/data-model.md`.

### 3.1 New Entities

#### Entity: AgentProfileDirectory

```
AgentProfileDirectory {
  dir_name: string          // e.g., .opencode, .claude, .codex
  display_name: string      // e.g., OpenCode, Claude Code, Codex CLI
  description: string       // shown in selection prompts
  selectable_in_init: bool  // true for optional profiles
  detectable_in_doctor: bool
}
```

### 3.2 Modified Entities

#### Entity: KnownAgentDirs

- **Current fields:** list with two entries (`.opencode`, `.claude`)
- **New fields:** third entry (`.codex`)
- **Migration notes:** No persisted data migration; this is runtime list expansion.

### 3.3 Data Flow

Known profile directory names flow from shared registry to command selection, conflict detection, installation, and health checks. Prompt descriptions map mirrors this list for user-facing text. GitHub fetch/writer consumes selected directory names to materialize profile files in the project root.

---

## 4. API Contracts

Detailed CLI contracts are defined in `.maestro/specs/017-lets-add-support-for-codex-on-maestro/contracts/cli-agent-profile-contracts.md`.

### 4.1 New Endpoints/Methods

#### CLI Flag: `maestro init --with-codex`

- **Purpose:** Install `.codex/` profile in non-interactive init runs.
- **Input:** boolean flag
- **Output:** `.codex/` installed (or actionable conflict/error message)
- **Errors:** fetch failure, conflict resolution cancellation, write failure

### 4.2 Modified Endpoints

#### `maestro init`

- **Current behavior:** selection prompt and flags for `.opencode` / `.claude`
- **New behavior:** includes `.codex` in prompt and selection logic
- **Breaking:** No

#### `maestro update`

- **Current behavior:** refreshes installed known dirs; prompts for missing known dirs
- **New behavior:** `.codex` participates in refresh and missing-dir install flows
- **Breaking:** No

#### `maestro doctor`

- **Current behavior:** warning-only checks for optional known dirs
- **New behavior:** `.codex` appears in optional warning checks
- **Breaking:** No

---

## 5. Implementation Phases

### Phase 1: Registry and CLI Selection Parity

- **Goal:** Add Codex as a known optional profile in core CLI selection flows.
- **Tasks:**
  - Update known directory registry and prompt descriptions to include `.codex` (`cmd/maestro-cli/pkg/agents/detect.go`, `cmd/maestro-cli/pkg/agents/prompt.go`) — Assignee: general
  - Add `--with-codex` init flag and wire into selection logic (`cmd/maestro-cli/cmd/init.go`) — Assignee: general
  - Update usage/help text for new flag (`cmd/maestro-cli/USAGE.md`) — Assignee: general
- **Deliverable:** `maestro init` shows/selects Codex and supports non-interactive `--with-codex`.

### Phase 2: Profile Content and Bootstrap Registration

- **Goal:** Ensure Codex profile files exist and are registered like existing CLI profiles.
- **Dependencies:** Phase 1
- **Tasks:**
  - Create `.codex/commands/` and `.codex/skills/` with parity command/skill files — Assignee: general
  - Extend shell init registration loop to include `.codex` (`.maestro/scripts/init.sh`) — Assignee: general
  - Update Maestro init command docs to mention `.codex` targets (`.maestro/commands/maestro.init.md`) — Assignee: general
- **Deliverable:** Fresh init/setup can install/register Codex commands and skills using existing pipeline.

### Phase 3: Update/Doctor Coverage and Tests

- **Goal:** Validate no-regression behavior across update, doctor, and prompt/test surfaces.
- **Dependencies:** Phase 1, Phase 2
- **Tasks:**
  - Extend tests for known-dir count, prompt options, and init selection behavior (`cmd/maestro-cli/pkg/agents/prompt_test.go`, `cmd/maestro-cli/cmd/init_test.go`) — Assignee: general
  - Add/adjust update and doctor expectations for optional `.codex` detection (`cmd/maestro-cli/cmd/commands_test.go`) — Assignee: general
  - Add focused tests for known-dir detection including `.codex` (`cmd/maestro-cli/pkg/agents/detect_test.go` new file) — Assignee: general
  - Update project docs for profile parity (`README.md`) — Assignee: general
- **Deliverable:** Test suite validates Codex parity behavior across init/update/doctor with no regression for existing profiles.

---

## 6. Task Sizing Guidance

All implementation tasks for this feature should be split into XS/S chunks, with code and docs changes separated when possible to keep reviews focused and reversible.

---

## 7. Testing Strategy

### 7.1 Unit Tests

- Known-dir registry tests ensure `.codex` is present and detectable.
- Init selection tests cover `--with-codex`, mixed flags, and no-flag prompt flow.
- Prompt rendering/parsing tests validate `.codex` appears with stable selection indices.
- Conflict handling tests confirm no behavior change in overwrite/backup/cancel semantics.

### 7.2 Integration Tests

- `maestro init` in temp directory installs Codex profile when selected.
- `maestro update` refreshes installed `.codex` and offers install when missing.
- `maestro doctor` reports `.codex` as optional found/not found without failing health checks.

### 7.3 End-to-End Tests

- CLI E2E in `cmd/maestro-cli/test/e2e/e2e_test.go` adds a scenario for init/update lifecycle with Codex profile selected.

### 7.4 Test Data

- Fixture profile trees for `.codex` command and skill content.
- Mocked GitHub fetch responses containing `.codex` directory content.

---

## 8. Risks and Mitigations

| Risk                                                             | Likelihood | Impact | Mitigation                                                                                                  |
| ---------------------------------------------------------------- | ---------- | ------ | ----------------------------------------------------------------------------------------------------------- |
| `.codex` missing from release assets causes install failure      | M          | H      | Add pre-merge validation to confirm `.codex` exists in packaged assets and fetch tests cover path presence. |
| Prompt index regressions break scripted expectations             | M          | M      | Keep deterministic ordering from `KnownAgentDirs`; add tests that assert exact option ordering.             |
| Drift between `.codex` and existing command/skill profiles       | M          | M      | Add parity checklist in PR and compare command filenames across profile directories in CI/test script.      |
| User confusion between Codex CLI integration and model selection | M          | M      | Update CLI and README language to consistently use "Codex CLI" terminology.                                 |

---

## 9. Open Questions

- Should `.codex` profile artifacts be maintained manually or generated from `.maestro/commands` and `.maestro/skills` during release packaging?
- Should `maestro init` include `.codex` in default interactive suggestion text, or keep neutral multi-select with no defaults?
