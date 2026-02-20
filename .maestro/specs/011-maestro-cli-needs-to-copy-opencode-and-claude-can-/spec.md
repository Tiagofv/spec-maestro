# Feature: Agent Config Directory Copying During Init

**Spec ID:** 011-maestro-cli-needs-to-copy-opencode-and-claude-can-
**Author:** User
**Created:** 2026-02-19
**Last Updated:** 2026-02-19
**Status:** Draft

---

## 1. Problem Statement

When a user runs `maestro init` in a target project, only the `.maestro/` directory is set up. However, the maestro framework also ships agent configuration directories (`.opencode/` and `.claude/`) that contain slash commands and skills needed by AI coding agents (OpenCode and Claude Code respectively).

Today, users must manually copy these directories into their projects or are unaware they exist. This creates a fragmented setup experience — the project gets `.maestro/` but not the agent-specific configuration that makes the commands and skills actually available in those tools.

Users need a way to opt into copying `.opencode/` and `.claude/` during `maestro init`, either interactively or via command-line flags.

---

## 2. Proposed Solution

Extend the `maestro init` command to offer copying of `.opencode/` and `.claude/` directories into the target project. The user should be able to:

- Be prompted interactively during init about which agent config directories to install
- Skip the prompt entirely and specify their choices via flags
- Choose all, some, or none of the agent config directories

The directories are fetched directly from the GitHub repository at runtime (not bundled in release assets), ensuring the user always gets the latest version.

---

## 3. User Stories

### Story 1: Interactive Agent Config Setup

**As a** developer initializing maestro in a project,
**I want** to be asked which agent configuration directories to install,
**so that** I only get the config files relevant to the AI tools I use.

**Acceptance Criteria:**

- [ ] Running `maestro init` displays a prompt asking which agent config directories to copy (`.opencode/`, `.claude/`)
- [ ] The user can select one, both, or neither
- [ ] Selected directories are copied into the project root
- [ ] Skipping the prompt (pressing Enter with no selection) installs neither directory — the default is opt-in (none selected)

### Story 2: Flag-Based Agent Config Setup

**As a** developer scripting project setup or running init non-interactively,
**I want** to specify which agent config directories to install via command-line flags,
**so that** I can automate the setup without interactive prompts.

**Acceptance Criteria:**

- [ ] A `--with-opencode` flag includes the `.opencode/` directory during init
- [ ] A `--with-claude` flag includes the `.claude/` directory during init
- [ ] When either flag is provided, the interactive prompt for agent config is skipped
- [ ] Flags can be combined (e.g., `--with-opencode --with-claude` for both)

### Story 3: Existing Directory Conflict Handling

**As a** developer re-initializing maestro in a project that already has agent config directories,
**I want** to be warned about existing `.opencode/` or `.claude/` directories,
**so that** I don't accidentally overwrite my customizations.

**Acceptance Criteria:**

- [ ] If any selected agent config directories already exist, the user is warned
- [ ] The conflict handling matches the existing `.maestro/` pattern: a single prompt covering all conflicting agent config directories with overwrite / backup / cancel options
- [ ] Backup creates a timestamped copy (consistent with existing `.maestro/` backup behavior)

### Story 4: Update Includes Agent Config Directories

**As a** developer running `maestro update`,
**I want** the update to also refresh my agent config directories if I previously installed them,
**so that** I get the latest commands and skills for my AI tools.

**Acceptance Criteria:**

- [ ] `maestro update` detects which agent config directories are present in the project (by checking directory existence on disk)
- [ ] Present directories are updated alongside `.maestro/`
- [ ] `maestro update` also offers to install agent config directories that aren't currently present in the project

### Story 5: Fetch Failure Handling

**As a** developer running `maestro init` or `maestro update`,
**I want** clear error feedback when agent config directories cannot be fetched,
**so that** I know to resolve connectivity issues before retrying.

**Acceptance Criteria:**

- [ ] If the GitHub repository is unreachable when fetching agent config directories, init fails with a clear error message
- [ ] The error message indicates which directory fetch failed and suggests checking network/GitHub access

---

## 4. Success Criteria

The feature is considered complete when:

1. Running `maestro init` prompts the user about `.opencode/` and `.claude/` installation (defaulting to none selected) and copies selected directories correctly
2. Running `maestro init --with-opencode --with-claude` copies both directories without prompting
3. Running `maestro doctor` reports missing agent config directories as warnings (not errors, since they are optional)
4. Existing agent config directories are not silently overwritten during init or update
5. Agent config directories are fetched from GitHub at runtime, always getting the latest version

---

## 5. Scope

### 5.1 In Scope

- Interactive prompt during `maestro init` for agent config directory selection (opt-in, none by default)
- `--with-opencode` and `--with-claude` flags for non-interactive init
- Conflict detection and resolution matching the existing `.maestro/` overwrite/backup/cancel pattern
- Fetching `.opencode/` and `.claude/` directly from the GitHub repository at runtime
- Extending `maestro update` to refresh installed agent config directories and offer new ones
- Extending `maestro doctor` to report agent config directory status as warnings

### 5.2 Out of Scope

- Merging user customizations with upstream changes during update (full overwrite or skip only)
- Supporting additional agent config directories beyond `.opencode/` and `.claude/`
- Modifying the content of `.opencode/` or `.claude/` directories themselves
- Per-file conflict resolution within agent config directories
- Bundling agent config directories in release assets
- A `--with-all-agents` convenience flag
- Tracking installed agent directories in `config.yaml` (detection is by directory presence on disk)

### 5.3 Deferred

- Smart merge strategy that preserves user customizations while applying upstream updates
- Plugin system for registering additional agent config directories
- Config option in `.maestro/config.yaml` to remember agent config preferences for future updates

---

## 6. Dependencies

- The `.opencode/` and `.claude/` directories must be accessible in the GitHub repository for runtime fetching
- GitHub API access is required (subject to rate limits; `GITHUB_TOKEN` env var recommended)

---

## 7. Open Questions

None — all clarifications resolved.

---

## 8. Risks

- If the agent config directories evolve independently from `.maestro/`, version drift between them could cause compatibility issues.
- Users may customize files within `.opencode/` or `.claude/` and lose changes during update if no merge strategy exists.
- Adding interactive prompts to init increases the surface area for non-interactive/CI environments to break if flags are not used.
- Fetching from GitHub at runtime introduces a network dependency — init will fail if GitHub is unreachable (by design per clarification).

---

## Changelog

| Date       | Change                                             | Author |
| ---------- | -------------------------------------------------- | ------ |
| 2026-02-19 | Initial spec created                               | User   |
| 2026-02-19 | Resolved 6 clarification markers + 3 implicit gaps | User   |
