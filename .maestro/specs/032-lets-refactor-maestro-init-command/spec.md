# Feature: Embedded Init Resources (Offline-Capable Init)

**Spec ID:** 032-lets-refactor-maestro-init-command
**Author:** Maestro
**Created:** 2026-03-16
**Last Updated:** 2026-03-16 (clarified)

**Status:** Draft

---

## 1. Problem Statement

Today, when a user runs `maestro init`, the CLI must reach out to GitHub to download commands, scripts, templates, skills, cookbook entries, reference files, the constitution, and agent configuration directories. This means:

- **Initialization fails without internet access.** Users on restricted networks, in CI environments with limited egress, or traveling offline cannot set up a new project.
- **Initialization is slow and fragile.** Each init makes multiple sequential network requests. If GitHub is rate-limiting, down, or the user lacks a valid token, the process either fails entirely or falls back to downloading a full tarball — adding latency and unpredictability.
- **Version mismatch between CLI and resources.** The binary is built from a specific tagged release, but init fetches resources from the `main` branch at runtime. This means the CLI version and the resource versions can drift apart, causing subtle incompatibilities.

Users expect a CLI tool to work reliably at the version they installed, with the resources that match that version bundled inside the binary itself.

---

## 2. Proposed Solution

Bundle all init-time resources (commands, scripts, templates, skills, cookbook, reference, constitution, and agent config directories) directly inside the CLI binary at build time. When a user runs `maestro init`, the CLI extracts these bundled resources to the target project directory instead of fetching them from GitHub.

The resources included in the binary should correspond to the tagged release version, ensuring perfect version alignment between the CLI binary and the resources it installs.

---

## 3. User Stories

### Story 1: Offline Initialization

**As a** developer,
**I want** `maestro init` to work without an internet connection,
**so that** I can set up new projects on planes, restricted networks, or environments without GitHub access.

**Acceptance Criteria:**

- [ ] Running `maestro init` in a directory with no internet connection creates the `.maestro/` directory structure with all expected files
- [ ] The output of `maestro init` does not show any network-related errors or warnings when offline
- [ ] The resulting `.maestro/` directory contains the same set of files as today's online init (commands, scripts, templates, skills, cookbook, reference, constitution)

### Story 2: Version-Matched Resources

**As a** developer,
**I want** the resources installed by `maestro init` to match the version of the CLI binary I installed,
**so that** I never encounter incompatibilities between my CLI version and the project resources it sets up.

**Acceptance Criteria:**

- [ ] Running `maestro init` installs resources that correspond to the same tagged version as the CLI binary
- [ ] Running `maestro version` (or equivalent) displays the version, and the resources installed by init originate from that same version
- [ ] The init output displays the version of resources being installed, e.g., "Installing maestro v1.2.3 resources..."
- [ ] For development builds (not from a tagged release), the output shows a dev indicator such as "v0.0.0-dev" or a short commit hash

### Story 3: Agent Config Installation

**As a** developer,
**I want** to optionally install agent configuration directories (e.g., `.claude/`, `.opencode/`) from the bundled resources,
**so that** I can configure my preferred AI coding agent during init without needing network access.

**Acceptance Criteria:**

- [ ] The interactive prompt to select agent directories still appears during `maestro init`
- [ ] Selected agent directories are extracted from bundled resources, not fetched from GitHub
- [ ] Users can still skip agent directory installation by selecting none

### Story 4: Fast Initialization

**As a** developer,
**I want** `maestro init` to complete without waiting for network requests,
**so that** project setup is near-instantaneous regardless of network conditions.

**Acceptance Criteria:**

- [ ] `maestro init` completes in under 2 seconds on a standard machine (excluding user interaction time)
- [ ] No HTTP requests are made to GitHub during `maestro init`

### Story 5: Automated Release Pipeline

**As a** maintainer,
**I want** release binaries (with embedded resources) to be built and published automatically when I push a version tag,
**so that** I don't have to manually build platform-specific binaries for each release.

**Acceptance Criteria:**

- [ ] Pushing a semantic version tag (e.g., `v1.2.3`) triggers an automated build that produces binaries for all supported platforms
- [ ] The built binaries include the embedded init resources from the tagged commit
- [ ] The release binaries are published as GitHub release assets, downloadable by users

---

## 4. Success Criteria

The feature is considered complete when:

1. `maestro init` succeeds in a completely offline environment, producing the full `.maestro/` directory structure with all resource files
2. The resources installed by init are identical to those in the corresponding tagged release of the source repository
3. No HTTP requests to GitHub (or any external service) are made during the init process
4. The existing user-facing behavior is preserved: conflict prompts, agent directory selection, `AGENTS.md` generation, and `config.yaml` creation all work as before
5. The CLI binary size stays under 50MB total (current baseline should be measured before and after)

---

## 5. Scope

### 5.1 In Scope

- Bundling all init-time resources inside the CLI binary at build time
- Removing GitHub fetch logic from the init command path
- Ensuring bundled resources match the tagged release version
- Preserving all existing init behavior (conflict resolution, agent selection prompts, directory creation, config generation)
- Updating the build process to include resource bundling

### 5.2 Out of Scope

- Removing the GitHub client package entirely — it may still be used by other commands (e.g., `update`, self-update)
- Adding a "fetch latest from GitHub" flag to init — users should use `maestro update` for that
- Changing the `maestro update` command — update should continue to fetch from GitHub
- Modifying the resources themselves (commands, templates, skills, etc.) — only the delivery mechanism changes
- Changes to the release/tagging process beyond what is needed for resource bundling

### 5.3 Deferred

- A hybrid mode where init uses bundled resources but can optionally fetch newer versions from GitHub if available
- Bundling resources for the `maestro update` command as well
- Compression or deduplication of bundled resources to minimize binary size

---

## 6. Research

No prior research items linked. The exploration of the current init flow revealed:

- The init command currently makes 10+ sequential GitHub API calls (or a full tarball download as fallback)
- The same 6 directories are fetched twice during init (once in `initFromGitHub` and again in `installRequiredStarterAssets`) — this redundancy can be eliminated
- There are no existing embedded resources in the codebase

---

## 7. Dependencies

- The build/release process must be updated to bundle resources into the binary at build time
- The tagged release must include all resources that init needs to install
- There is no existing CI/CD pipeline for building release binaries — a new GitHub Actions workflow will be created as part of this feature to build and publish release binaries automatically on tag push

---

## 8. Open Questions

All questions have been resolved:

- **Network fallback:** No. `maestro init` will be purely offline — no network calls at all. Embedded resources only.
- **Release tagging:** Tags are already formalized with semantic versioning. The existing process is sufficient to ensure resources are snapshotted at each release.
- **GitHub escape hatch:** No `--from-github` flag will be provided. Users who want the latest resources can use `maestro update` instead.

---

## 9. Risks

- **Binary size growth**: Bundling all resource files will increase the CLI binary size. The impact should be measured and monitored.
- **Resource staleness**: Users who want the absolute latest resources between releases will need to wait for a new CLI release. This is intentional but may surprise users accustomed to always getting `main` branch content.
- **Build complexity**: The build process becomes more coupled to the resource files, meaning resource changes require a new binary release to take effect.

---

## Changelog

| Date       | Change                                 | Author  |
| ---------- | -------------------------------------- | ------- |
| 2026-03-16 | Clarified 6 markers, added CI/CD story | Maestro |
| 2026-03-16 | Initial spec created                   | Maestro |
