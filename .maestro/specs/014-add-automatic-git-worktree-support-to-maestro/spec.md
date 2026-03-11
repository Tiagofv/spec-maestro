# Feature: Improve Git Worktree Behavior and Lifecycle Management

**Spec ID:** 014-add-automatic-git-worktree-support-to-maestro
**Author:** Maestro System
**Created:** 2026-02-19
**Last Updated:** 2026-02-19
**Status:** Draft

---

## 1. Problem Statement

Maestro's git worktree support (delivered in feature 006) is functional but exhibits several behaviors that confuse developers and waste resources:

1. **Stale worktrees accumulate**: Completed features (e.g., feature 008 is marked `complete` but its worktree still exists) leave behind worktree directories that are never automatically cleaned up. With each worktree consuming ~3.5GB of disk space, this quickly becomes expensive.

2. **Truncated, cryptic directory names**: Worktree directory names are derived by slugifying the full feature description and truncating at 50 characters. This produces names like `can-we-remove-the-planner-folder-i-believe-it-adds` and `maestro-cli-needs-to-copy-opencode-and-claude-can-` that are unreadable and offer no quick identification of the feature.

3. **`.maestro/` directory duplication**: When `.maestro/` is version-controlled (tracked by git), each worktree gets its own full copy of `.maestro/` rather than a symlink. This means state files, specs, and configuration inside a worktree can diverge from the main repository, leading to confusion about which copy is authoritative.

4. **No visibility into worktree health**: Developers have no easy way to see which worktrees are stale, how much disk space they consume, or whether they have uncommitted changes — information needed to decide what to clean up.

5. **Test artifacts left behind**: The worktree lifecycle test script (`test-worktree-lifecycle.sh`) can leave behind test worktrees (e.g., `test-unmerged`) that persist indefinitely.

These issues make the `.worktrees/` directory feel "weird" — it fills up silently, contains directories with inscrutable names, and has no self-maintenance behavior.

---

## 2. Proposed Solution

Improve the existing worktree system so that worktrees are easier to understand, cheaper to maintain, and self-cleaning. Specifically:

- Give worktrees short, meaningful names derived from the feature ID rather than the full description
- Automatically prompt for or perform worktree cleanup when a feature is marked complete
- Provide a dashboard-style status command that shows worktree health at a glance (size, staleness, uncommitted changes)
- Ensure the `.maestro/` directory inside worktrees stays in sync with the main repository, or clearly communicate which copy is authoritative
- Clean up test artifacts automatically after test runs

---

## 3. User Stories

### Story 1: Readable Worktree Names

**As a** developer navigating the `.worktrees/` directory,
**I want** each worktree to have a short, recognizable name,
**so that** I can quickly identify which feature a worktree belongs to without reading truncated descriptions.

**Acceptance Criteria:**

- [ ] Worktree directory names are short and identifiable (e.g., `014-worktree-fixes` rather than `add-automatic-git-worktree-support-to-maestro`)
- [ ] The feature ID prefix (e.g., `014`) is always present in the directory name
- [ ] Existing worktrees with long names continue to function (no breaking changes)
- [ ] [NEEDS CLARIFICATION: Should existing worktrees be renamed/migrated to the new naming scheme, or only new worktrees get short names?]

### Story 2: Automatic Cleanup on Feature Completion

**As a** developer completing a feature,
**I want** maestro to automatically clean up the worktree when the feature is marked complete,
**so that** stale worktrees do not accumulate and waste disk space.

**Acceptance Criteria:**

- [ ] When a feature transitions to `complete` status, the associated worktree is removed (after confirming no uncommitted changes)
- [ ] The developer is notified before cleanup occurs, with the option to skip it
- [ ] If the worktree has uncommitted changes, cleanup is blocked and the developer is warned
- [ ] The branch is optionally deleted if it has been merged
- [ ] [NEEDS CLARIFICATION: Should cleanup happen immediately upon status change, or should there be a grace period (e.g., 24 hours) to allow post-completion review?]

### Story 3: Worktree Health Dashboard

**As a** developer managing multiple features,
**I want** to see a summary of all worktrees including their size, staleness, and status,
**so that** I can make informed decisions about which worktrees to keep or remove.

**Acceptance Criteria:**

- [ ] A command shows all active worktrees with: feature name, branch, stage, disk size, and whether there are uncommitted changes
- [ ] Worktrees for completed features are flagged as "stale"
- [ ] The total disk usage of all worktrees is displayed
- [ ] [NEEDS CLARIFICATION: Should the health dashboard be a new standalone command, or an enhancement to the existing worktree-list output?]

### Story 4: Consistent `.maestro/` State Across Worktrees

**As a** developer working in a worktree,
**I want** the `.maestro/` directory to reflect the same state as the main repository,
**so that** I don't accidentally work with outdated specs, state files, or configuration.

**Acceptance Criteria:**

- [ ] The `.maestro/` directory inside a worktree does not silently diverge from the main repository's `.maestro/`
- [ ] When opening a worktree, the developer is informed if `.maestro/` content differs from the main branch
- [ ] There is a clear, documented policy on which `.maestro/` copy is authoritative (main repo)

---

## 4. Success Criteria

The feature is considered complete when:

1. New worktrees are created with short, feature-ID-prefixed directory names that are immediately recognizable
2. Completing a feature prompts the developer to clean up the associated worktree, and cleanup succeeds without manual git commands
3. A worktree status command shows disk usage, staleness, and uncommitted-change warnings for all active worktrees
4. Developers working in a worktree are warned if `.maestro/` content has diverged from the main branch
5. Test worktrees are cleaned up automatically after test scripts complete

---

## 5. Scope

### 5.1 In Scope

- Improved naming convention for worktree directories
- Automatic cleanup prompt/action on feature completion
- Enhanced worktree listing with health metrics (disk size, staleness, uncommitted changes)
- Detection and warning for diverged `.maestro/` content in worktrees
- Test artifact cleanup in worktree lifecycle tests

### 5.2 Out of Scope

- Rewriting the core worktree creation/removal logic (feature 006 scripts are stable)
- Automatic dependency installation in worktrees (e.g., running `pnpm install`)
- Shared `node_modules` or dependency deduplication across worktrees
- IDE integration for worktree switching
- Remote worktree management

### 5.3 Deferred

- Migration tool to rename existing worktrees to the new naming convention
- Scheduled background cleanup of stale worktrees (e.g., cron-based)
- Worktree disk usage limits or quotas

---

## 6. Dependencies

- Existing worktree scripts from feature 006 (`worktree-create.sh`, `worktree-cleanup.sh`, `worktree-list.sh`, `worktree-detect.sh`)
- Existing maestro state management (`.maestro/state/` files)
- Feature completion flow in maestro commands

---

## 7. Open Questions

- [NEEDS CLARIFICATION: Should the naming convention use `{NNN}-{short-slug}` (e.g., `014-worktree-fixes`) or just the feature ID `{NNN}` alone? How many characters should the slug portion be limited to?]
- [NEEDS CLARIFICATION: When `.maestro/` is version-controlled, should worktrees use a symlink override mechanism, or is a "divergence warning" sufficient?]
- [NEEDS CLARIFICATION: Should the cleanup-on-completion behavior be opt-in (developer must confirm) or opt-out (happens automatically unless developer declines)?]

---

## 8. Risks

1. **Breaking existing worktrees**: Changing the naming convention could break references in state files that store the current worktree path
2. **Automatic cleanup data loss**: If cleanup runs before a developer has pushed their branch, work could be lost. Safety checks (uncommitted change detection, unpushed commit detection) are critical.
3. **`.maestro/` sync complexity**: If `.maestro/` is tracked in git, worktrees will always get their own copy via git checkout. Overlaying a symlink on top of a tracked directory may cause git conflicts.

---

## Changelog

| Date       | Change               | Author         |
| ---------- | -------------------- | -------------- |
| 2026-02-19 | Initial spec created | Maestro System |
