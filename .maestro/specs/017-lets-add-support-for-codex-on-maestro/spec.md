# Feature: Codex CLI Support in Maestro

**Spec ID:** 017-lets-add-support-for-codex-on-maestro
**Author:** Maestro
**Created:** 2026-02-20
**Last Updated:** 2026-02-20
**Status:** Draft

---

## 1. Problem Statement

Maestro users who work with the Codex CLI cannot use it through the same path they use for other supported CLIs. They must switch tools or workflows, which adds friction and breaks consistency across teams.

The immediate need is simple: Codex CLI should be available with the same baseline behavior users already expect from existing CLI integrations.

---

## 2. Proposed Solution

Add Codex CLI as a selectable option in Maestro workflows with parity-level behavior: users can select it in Maestro CLI, run work with it, and receive clear feedback if it is unavailable.

This release focuses on core usability and trust, not expanded governance or analytics.

Codex selection is expected to happen through the Maestro CLI. Outside direct selection, Codex capability is exposed through the same commands and skills concept used by existing supported CLI profiles.

---

## 3. User Stories

### Story 1: Select Codex for Workflows

**As a** Maestro user,
**I want** to select Codex CLI when running Maestro workflows,
**so that** I can use Codex without changing my normal process.

**Acceptance Criteria:**

- [ ] The user can choose Codex through the same user-facing workflow used for other supported CLIs.
- [ ] A workflow started with Codex clearly shows that Codex CLI is the active selection.
- [ ] If Codex is not available to the user, Maestro shows a clear action-oriented message instead of failing silently.

### Story 2: Safe and Understandable Failure Handling

**As a** Maestro user,
**I want** clear feedback when Codex requests fail,
**so that** I can recover quickly and continue my task.

**Acceptance Criteria:**

- [ ] When a Codex request fails, Maestro shows a user-readable error message with a suggested next action.
- [ ] Error output and logs do not expose credentials or sensitive values.
- [ ] No special fallback mode is required for this release beyond clear failure messaging.

### Story 3: Basic Usage Visibility

**As a** team lead,
**I want** Codex selection to be visible in normal run history,
**so that** I can confirm which CLI integration was used for a run.

**Acceptance Criteria:**

- [ ] Codex selection and selection changes are captured in user-visible run history.
- [ ] State transitions related to Codex-enabled runs are recorded in a reviewable way.
- [ ] Workspace role-based controls are not part of this feature scope.

---

## 4. Success Criteria

The feature is considered complete when:

1. A user can complete an end-to-end Maestro workflow with Codex CLI selected and confirmed as the active integration.
2. In failed Codex scenarios, users receive actionable error guidance and can retry or choose another path within the same session.
3. No credentials or sensitive tokens appear in user-visible errors, run output, or workflow logs.
4. Users can verify Codex selection events and state transitions for Codex-enabled runs through normal Maestro history views.

---

## 5. Scope

### 5.1 In Scope

- Make Codex CLI available as a user-selectable option in Maestro workflows.
- Provide clear user feedback for Codex availability, selection, and failure scenarios.
- Reflect Codex usage in existing run history and workflow state tracking.
- Treat Codex as enabled when the project includes Codex commands and skills profile content.

### 5.2 Out of Scope

- Adding support for non-Codex CLI integrations.
- Redesigning the overall CLI selection experience beyond Codex parity.
- Creating new authentication or authorization systems.
- Introducing workspace-level controls for enabling or restricting Codex.

### 5.3 Deferred

- Advanced analytics for Codex performance or usage cost.
- Organization-wide CLI routing policy automation.
- Special handling for Codex access revocation during in-progress runs.

---

## 6. Dependencies

- Existing Maestro CLI selection and workflow execution capabilities.
- Existing run history and state tracking surfaces used by teams for review.
- Codex commands and skills profile content in the project as the availability signal for Codex support.

---

## 7. Open Questions

- None at this stage. Codex is considered available when the project includes Codex commands and skills profile content, with no workspace-level toggle.

---

## 8. Risks

- User confusion if Codex appears selectable but Codex commands and skills are not present in the project context.
- Increased support burden if failure messages are not specific enough to guide recovery.
- Policy conflicts across teams if Codex enablement boundaries are not clarified early.

---

## Changelog

| Date       | Change                                        | Author  |
| ---------- | --------------------------------------------- | ------- |
| 2026-02-20 | Initial spec created                          | Maestro |
| 2026-02-20 | Refined to MVP parity scope for Codex support | Maestro |
| 2026-02-20 | Resolved clarification markers                | Maestro |
| 2026-02-20 | Corrected scope to Codex CLI (not model)      | Maestro |
