# Feature: Include Starter Assets in `maestro init`

**Spec ID:** 016-should-we-add-the-scripts-skills-templates-to-the-
**Author:** OpenCode
**Created:** 2026-02-20
**Last Updated:** 2026-02-20
**Status:** Draft

---

## 1. Problem Statement

Users initializing a project can receive core setup files but may still need manual steps to obtain starter scripts, skills, and templates. This creates inconsistent onboarding outcomes, especially for first-time users who expect a complete baseline after running one command.

The missing baseline increases setup time, causes confusion about what is required versus optional, and raises the chance of configuration drift across projects. Teams need predictable initialization so all contributors start from the same foundation.

---

## 2. Proposed Solution

Expand the initialization experience so users can receive a complete default baseline that includes scripts, skills, and templates at project setup time. The behavior should be predictable, clearly communicated, and safe when these directories already exist.

The goal is to reduce manual setup work while preserving user control over optional content and existing local changes.

---

## 3. User Stories

### Story 1: Default Complete Onboarding

**As a** developer starting a new project,
**I want** initialization to provide all core starter assets in one run,
**so that** I can begin using workflow commands immediately without extra manual setup.

**Acceptance Criteria:**

- [ ] After running initialization in a new project, starter scripts, skills, and templates are present and usable.
- [ ] The command output clearly confirms which asset groups were installed.
- [ ] If any required asset group cannot be retrieved, the user receives a clear, actionable message.

### Story 2: Safe Behavior with Existing Files

**As a** developer re-running initialization,
**I want** clear conflict behavior for existing starter assets,
**so that** I do not accidentally lose local customizations.

**Acceptance Criteria:**

- [ ] When existing starter asset directories are detected, the command provides explicit choices before modifying them.
- [ ] Choosing a non-destructive option leaves existing files unchanged.
- [ ] Conflicts are resolved with one global action that applies across all conflicting directories.

### Story 3: Team Consistency and Governance

**As a** team lead,
**I want** initialization outcomes to be consistent across contributors,
**so that** onboarding quality and project standards are repeatable.

**Acceptance Criteria:**

- [ ] Two users running initialization on clean checkouts get the same starter asset set by default.
- [ ] Initialization output avoids exposing credentials or tokens in logs or terminal text.
- [ ] Scripts, skills, and templates are all installed by default.

---

## 4. Success Criteria

The feature is considered complete when:

1. In a clean project, initialization produces a ready-to-use baseline including scripts, skills, and templates in one run.
2. At least 90% of initialization attempts in internal testing complete without requiring manual post-setup file copying.
3. Initialization messages are unambiguous and include recovery guidance for retrieval or conflict failures.
4. No secrets, access tokens, or credential-like values are shown in initialization output.
5. The required baseline for success measurement includes scripts, skills, and templates.
6. If any required asset group fails during initialization, the initialization result leaves no partial required-asset state.

---

## 5. Scope

### 5.1 In Scope

- Initialization behavior related to starter scripts, skills, and templates.
- User-facing messaging for what is installed, skipped, or blocked by conflicts.
- Conflict handling expectations when starter asset directories already exist.

### 5.2 Out of Scope

- Redesigning the content of scripts, skills, or templates themselves.
- Changes to unrelated commands outside initialization behavior.
- New authentication models or permission systems.

### 5.3 Deferred

- Per-team starter asset profiles or presets.
- Telemetry dashboards for long-term initialization quality trends.

---

## 6. Dependencies

- Existing project initialization flow and its baseline directory structure.
- Availability of the upstream starter asset source.
- Project constitution rules for safe output, input handling, and predictable state transitions.

---

## 7. Clarified Decisions

- `maestro init` installs all starter assets by default in non-interactive contexts.
- If remote retrieval fails for required asset groups, initialization fails.
- When optional asset groups are skipped, the user-facing message severity is warning.
- In automated/team environments, the individual developer running initialization is the primary actor for conflict decisions.

---

## 8. Risks

- Expanding default initialization content may surprise users who expect a minimal setup.
- Incorrect conflict handling could overwrite customized local files.
- Partial retrieval behavior could create inconsistent project baselines if not communicated clearly.

---

## Changelog

| Date       | Change                                             | Author   |
| ---------- | -------------------------------------------------- | -------- |
| 2026-02-20 | Initial spec created                               | OpenCode |
| 2026-02-20 | Resolved clarifications and added policy decisions | OpenCode |
