# Feature: Maestro CLI - Native Binary Distribution

**Spec ID:** 002-create-an-npm-cli-package-for-maestro-that-provide
**Author:** Maestro System
**Created:** 2025-02-19
**Last Updated:** 2025-02-19
**Status:** Review

---

## 1. Problem Statement

Currently, maestro requires manual setup and configuration for each project. Users must:

- Copy command files manually into their projects
- Manually update skills and commands when improvements are released
- Have no standardized way to validate project setup
- Lack a unified installation experience across different operating systems

This creates friction for new users and makes it difficult to keep maestro installations up-to-date across multiple projects. Teams need a consistent, cross-platform way to initialize, maintain, and validate their maestro configurations.

---

## 2. Proposed Solution

Create `maestro`, a native CLI binary that provides a command-line interface for managing maestro projects. The CLI will be distributed as a single executable that can be installed via package managers or direct download, providing standardized commands for project initialization, updates, and health checks.

The CLI follows patterns established by successful tools like kubectl, docker, and terraform, providing:

- Single binary distribution with no runtime dependencies
- Simple, memorable commands (`maestro init`, `maestro update`, `maestro doctor`)
- Cross-platform support (macOS, Linux, Windows)
- Automatic version management and update notifications
- Integration with existing `.maestro` directory structure

---

## 3. User Stories

### Story 1: Initialize New Project

**As a** developer starting a new project,
**I want** to run a single command to set up maestro,
**so that** I can immediately start using maestro commands without manual configuration.

**Acceptance Criteria:**

- [ ] Running `maestro init` creates the `.maestro/` directory structure in the current project
- [ ] The command downloads and extracts all necessary templates, skills, and commands from GitHub releases on first use
- [ ] The command generates a `AGENTS.md` file with quick reference for available commands
- [ ] The command confirms successful initialization with a summary of what was created
- [ ] Running `maestro init` in an existing project offers to overwrite, backup, or cancel
- [ ] `maestro init` does NOT initialize a git repository - users should do this manually if needed
- [ ] Running `maestro init` outside a typical project directory (e.g., home folder) shows a warning but allows the user to proceed

### Story 2: Update Existing Installation

**As a** developer with an existing maestro project,
**I want** to update my commands and skills to the latest versions,
**so that** I can benefit from improvements without manually downloading files.

**Acceptance Criteria:**

- [ ] Running `maestro update` checks the current CLI version against the latest release
- [ ] The command downloads and installs the latest CLI version if available
- [ ] The command updates project-specific bundled resources (templates, skills, commands) to their latest versions
- [ ] Custom user modifications in `.maestro/` are preserved during updates
- [ ] The command shows a summary of what was updated
- [ ] `maestro update` updates all bundled resources at once (no selective update support in initial version)
- [ ] When custom modifications are detected, the CLI prompts the user for action
- [ ] Network failures show a clear error message with troubleshooting guidance

### Story 3: Validate Project Setup

**As a** developer troubleshooting a maestro project,
**I want** to verify that my project is correctly configured,
**so that** I can identify and fix setup issues quickly.

**Acceptance Criteria:**

- [ ] Running `maestro doctor` validates the presence of required `.maestro/` directory structure
- [ ] The command checks that all required files exist (config.yaml, templates/, skills/, commands/)
- [ ] The command verifies that the project has necessary prerequisites (git, compatible shell)
- [ ] The command reports any missing or corrupted files with specific error messages
- [ ] The command provides actionable remediation steps for each issue found
- [ ] Exit code is 0 when all checks pass, non-zero when issues are found

### Story 4: Cross-Platform Installation

**As a** developer on macOS/Linux/Windows,
**I want** to install and use maestro without runtime dependencies or platform-specific workarounds,
**so that** my team can use consistent tooling regardless of operating system.

**Acceptance Criteria:**

- [ ] The CLI binary runs on macOS (Intel and Apple Silicon), Linux (x64 and ARM64), and Windows
- [ ] All CLI commands work identically across platforms
- [ ] File paths are handled correctly on Windows (backslashes) and Unix (forward slashes)
- [ ] The CLI detects the operating system and adjusts behavior as needed
- [ ] The CLI is optimized for macOS and Linux; Windows support is secondary
- [ ] The CLI is distributed via both Homebrew (`brew install maestro`) and direct download from GitHub releases

### Story 5: Check Version

**As a** developer,
**I want** to check which version of maestro is installed,
**so that** I can verify I have the latest version or report issues with version info.

**Acceptance Criteria:**

- [ ] Running `maestro --version` displays the installed CLI version
- [ ] Running `maestro version` displays the installed CLI version
- [ ] The version output includes CLI version, build date, and platform for debugging
- [ ] The command checks if a newer version is available and notifies the user

### Story 6: Remove Maestro from Project

**As a** developer,
**I want** to remove maestro configuration from a project,
**so that** I can clean up projects that no longer use maestro.

**Acceptance Criteria:**

- [ ] Running `maestro remove` or `maestro uninstall` removes the `.maestro/` directory
- [ ] The command asks for confirmation before deleting files
- [ ] The command shows what was removed after completion
- [ ] The command fails gracefully if `.maestro/` directory doesn't exist

### Story 7: Install CLI via Package Manager

**As a** developer,
**I want** to install the maestro CLI using my system's package manager,
**so that** I can easily install, update, and manage the tool like other CLI utilities.

**Acceptance Criteria:**

- [ ] Homebrew is the supported package manager (macOS and Linux)
- [ ] The package manager installation puts the binary in the system PATH
- [ ] Updates are available through the same package manager
- [ ] The installation process shows clear success/failure messages

---

## 4. Success Criteria

The feature is considered complete when:

1. Users can install maestro via package manager or direct download and successfully use commands
2. `maestro init` creates a fully functional `.maestro/` directory in any project
3. `maestro update` updates bundled resources while preserving custom user modifications
4. `maestro doctor` identifies common setup issues and provides clear remediation guidance
5. All commands work consistently across macOS, Linux, and Windows
6. Version checking displays current version and availability of updates
7. Error messages are clear, actionable, and include troubleshooting suggestions
8. The single binary runs without requiring any runtime dependencies

---

## 5. Scope

### 5.1 In Scope

- Native CLI binary with no runtime dependencies
- `maestro init` command for project initialization
- `maestro update` command for updating CLI and bundled resources
- `maestro doctor` command for project health validation
- Cross-platform support (macOS, Linux, Windows)
- Version checking and update notifications
- Error handling with actionable messages
- Integration with existing `.maestro` configuration structure
- Distribution via package managers and direct download

### 5.2 Out of Scope

- GUI or web-based interface (CLI only)
- Automatic background updates
- Migration from existing manual maestro installations
- Hosting or server-side functionality
- npm/yarn/pnpm package distribution

### 5.3 Deferred

- Plugin system for third-party commands
- Team/collaboration features
- Analytics or telemetry collection
- Configuration profiles for different project types
- Self-updating binary (like rustup)

---

## 6. Dependencies

- Git (for projects using version control features)
- Existing `.maestro/` directory structure conventions
- Package manager or download mechanism for installation
- Minimum OS versions: macOS 11 (Big Sur)+, Ubuntu 20.04+, Windows 10+

---

## 7. Open Questions

**Resolved:**

- ✅ Distribution: Both Homebrew and GitHub releases
- ✅ Package managers: Homebrew only (macOS and Linux)
- ✅ Minimum OS versions: macOS 11+, Ubuntu 20.04+, Windows 10+
- ✅ Asset distribution: Download on first use (not embedded)

**No remaining open questions.**

---

## 8. Risks

- **Network Dependency**: Assets are downloaded on first use, requiring internet connectivity. Mitigation: Cache assets locally and provide clear error messages for offline scenarios.
- **Platform Differences**: Path handling and shell differences may cause Windows-specific bugs. Mitigation: Comprehensive cross-platform testing.
- **Distribution Complexity**: Managing multiple package managers and release channels adds overhead. Mitigation: Use GoReleaser or similar tool for automation.
- **Update Mechanism**: Self-updating binaries can be complex and may trigger security warnings. Mitigation: Clear documentation on manual update process.

---

## Changelog

| Date       | Change                                        | Author         |
| ---------- | --------------------------------------------- | -------------- |
| 2025-02-19 | Initial spec created                          | Maestro System |
| 2025-02-19 | Clarified 10 questions, added 2 user stories  | Maestro System |
| 2025-02-19 | Refactored for Go/native binary distribution  | Maestro System |
| 2025-02-19 | Clarified distribution and platform questions | Maestro System |
