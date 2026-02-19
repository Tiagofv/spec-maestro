# Feature: Add Automatic Git Worktree Support to Maestro

**Spec ID:** 006-add-automatic-git-worktree-support-to-maestro-for-
**Author:** Maestro System
**Created:** 2026-02-19
**Last Updated:** 2026-02-19 (clarified)
**Status:** Clarified

---

## 1. Problem Statement

Currently, developers using maestro must switch between git branches when working on multiple features simultaneously. This creates several pain points:

1. **Context Loss**: Switching branches requires stashing or committing work-in-progress, disrupting the development flow
2. **Conflict Risk**: Running commands in the wrong branch can accidentally pollute feature work with unrelated changes
3. **Parallel Development Blockers**: Developers cannot work on independent features simultaneously without multiple repository clones
4. **Workspace Pollution**: Build artifacts, node_modules, and IDE configurations from one feature bleed into another when switching branches

These problems are especially acute for maestro users who often work on multiple features in quick succession. A developer working on feature A cannot easily review or test feature B without losing their current context.

---

## 2. Proposed Solution

Maestro should automatically create and manage isolated git worktrees for each feature. When a developer starts working on a feature, maestro will:

1. Create a dedicated worktree directory using git worktrees
2. Automatically set up the feature branch in that worktree
3. Maintain the constitution and shared resources via symlinks
4. Clean up worktrees when features are completed or abandoned

This allows developers to work on multiple features simultaneously without branch switching, with each feature having its own isolated workspace.

---

## 3. User Stories

### Story 1: Feature Isolation

**As a** developer working on multiple features,
**I want** each feature to have its own isolated workspace,
**so that** I can context-switch between features without stashing or losing work.

**Acceptance Criteria:**

- [ ] When I run `/maestro.implement`, a new worktree is created automatically using the name selected during `/maestro.specify`
- [ ] The worktree directory is isolated from other feature work
- [ ] I can see all active worktrees and their status
- [ ] Changes in one worktree do not affect other worktrees

### Story 2: Parallel Development

**As a** developer,
**I want** to work on multiple independent features simultaneously,
**so that** I can make progress on feature A while waiting for review on feature B.

**Acceptance Criteria:**

- [ ] I can have two or more features in active development at the same time
- [ ] Each feature has its own independent branch and workspace
- [ ] I can run tests/builds in one feature without affecting others
- [ ] There is no limit on the number of concurrent worktrees

### Story 3: Worktree Lifecycle Management

**As a** developer,
**I want** maestro to manage worktree creation, updates, and cleanup,
**so that** I don't have to manually run git worktree commands.

**Acceptance Criteria:**

- [ ] Worktrees are created automatically when running `/maestro.implement`
- [ ] Worktrees are updated when the parent branch changes
- [ ] Worktrees are cleaned up when a feature is completed or abandoned
- [ ] I can manually trigger worktree cleanup for completed features

### Story 4: Shared Resources

**As a** developer,
**I want** shared resources (constitution, templates) to be accessible in every worktree,
**so that** I don't duplicate files or lose access to maestro configuration.

**Acceptance Criteria:**

- [ ] The `.maestro/` directory is symlinked into every worktree (when not version-controlled)
- [ ] Changes to shared resources in `.maestro/` are reflected across all worktrees via symlinks
- [ ] Worktree-specific state is isolated per feature

### Story 5: Integration with Implementation

**As a** developer,
**I want** `/maestro.implement` to detect and use the appropriate worktree,
**so that** implementation happens in the correct isolated workspace.

**Acceptance Criteria:**

- [ ] `/maestro.implement` checks for existing worktrees before creating new ones
- [ ] Implementation tasks are executed in the correct worktree
- [ ] Each feature has exactly one worktree, defined during `/maestro.specify`; `/maestro.implement` uses the worktree already associated with the feature
- [ ] Worktree status is displayed during implementation
- [ ] All implementation tasks reference the worktree they must work on

---

## 4. Success Criteria

The feature is considered complete when:

1. Running `/maestro.specify` selects the worktree name for the new feature; `/maestro.implement` creates it
2. Multiple features can be developed simultaneously without branch switching
3. Worktrees are cleaned up automatically when features complete
4. The maestro constitution is accessible in all worktrees via symlinks
5. `/maestro.implement` detects existing worktrees and uses them appropriately
6. Developers can list and manage active worktrees through maestro commands
7. Worktrees sync with the parent branch on demand only (not automatically)

---

## 5. Scope

### 5.1 In Scope

- Worktree name selection during `/maestro.specify`; actual worktree creation during `/maestro.implement`
- Worktree directory structure under `.worktrees/{human-readable-name}/` relative to the main repo root
- Automatic branch creation following `feat/{feature-slug}` convention and tracking within worktrees
- Symlink setup for shared resources (`.maestro/` directory, only when not version-controlled)
- Worktree listing and status commands
- Worktree cleanup on feature completion
- Integration with `/maestro.implement` for worktree detection

### 5.2 Out of Scope

- Worktrees for non-maestro managed branches
- Complex merge conflict resolution workflows
- IDE-specific worktree configurations
- Remote worktrees on different machines (not supported)

### 5.3 Deferred

- Visual worktree management UI
- Worktree performance metrics and monitoring
- Automatic worktree archival after extended inactivity
- Integration with CI/CD pipelines for worktree-based testing

---

## 6. Dependencies

- Git worktree support (available in Git 2.5+)
- Existing maestro feature lifecycle management
- Current branch management in `/maestro.specify` and `/maestro.implement`

---

## 7. Open Questions

- **Remote branch deletion**: Maestro does not handle this; the user manages it. After a worktree's work is finished, a PR must be opened to the target branch.
- **Worktree naming**: Worktree directories use human-readable names rather than raw feature IDs.
- **Running from a worktree**: Maestro warns the user they are inside a worktree, shows which feature it belongs to, and continues operating in that context.
- **Abandoned feature cleanup**: Manual; the user is responsible for cleaning up abandoned worktrees.
- **Submodule support**: Not supported.

---

## 8. Risks

1. **Disk Space**: Multiple worktrees will increase disk usage significantly, especially for repositories with large dependencies
2. **Complexity**: Adding worktree management increases the complexity of maestro commands
3. **Git Version Compatibility**: Worktree features require Git 2.5+, which may not be available in all environments
4. **User Confusion**: Developers unfamiliar with git worktrees may be confused about where their work is happening

---

## Changelog

| Date       | Change                                             | Author         |
| ---------- | -------------------------------------------------- | -------------- |
| 2026-02-19 | Initial spec created                               | Maestro System |
| 2026-02-19 | Resolved 8 clarification markers + 4 implicit gaps | Maestro System |
