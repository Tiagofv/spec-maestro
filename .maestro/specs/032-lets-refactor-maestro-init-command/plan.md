# Implementation Plan: Embedded Init Resources (Offline-Capable Init)

**Feature ID:** 032-lets-refactor-maestro-init-command
**Spec:** .maestro/specs/032-lets-refactor-maestro-init-command/spec.md
**Created:** 2026-03-16
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

The init command currently follows a network-first architecture: it resolves content from GitHub (via API tree walking, with archive fallback) and writes it to disk. This plan replaces that with an embedded-first architecture: all init-time resources are compiled into the binary at build time, and the init command extracts them directly from memory to disk.

The key architectural seam is the `AssetFetcher` function type already defined in `cmd/maestro-cli/pkg/agents/installer.go:10`:

```
type AssetFetcher func(dir string) (map[string][]byte, error)
```

Both init and update currently pass a GitHub-fetching closure as the `AssetFetcher`. This plan introduces an embedded-resource-fetching closure that reads from the binary's embedded filesystem. The update command continues to use the GitHub-fetching closure unchanged.

### 1.2 Component Interactions

```
Build Time:
  .maestro/ resources ──→ go:embed ──→ binary

Runtime (init):
  binary ──→ embedded FS ──→ AssetFetcher ──→ installer ──→ disk
                                                 ↓
                                          conflict handling
                                          (existing, unchanged)

Runtime (update — unchanged):
  binary ──→ GitHub client ──→ AssetFetcher ──→ installer ──→ disk
```

### 1.3 Key Design Decisions

| Decision                                             | Options Considered                                                                                                                                                                           | Chosen                                                         | Rationale                                                                                                                                                                                                                                                          |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Where to place embedded resources in the source tree | (A) Embed from `.maestro/` in repo root; (B) Copy resources to a dedicated `cmd/maestro-cli/embedded/` dir at build time; (C) Embed from repo root using relative path in go:embed directive | B — dedicated embedded dir populated by a build-time copy step | Go's `go:embed` cannot reference paths outside the module directory (`cmd/maestro-cli/`). The resources live at repo root (`.maestro/`, `.claude/`, `.opencode/`), so a build-time copy step is needed. This also keeps embedded content isolated and versionable. |
| How to populate the embedded dir                     | (A) Manual copy before build; (B) `go generate` script; (C) Makefile target                                                                                                                  | B — `go generate` script                                       | GoReleaser already runs `go generate ./...` in its `before.hooks`. A `go generate` directive that copies resources ensures the embedded dir is always fresh before compilation.                                                                                    |
| How to expose embedded content to init               | (A) New package with exported functions; (B) Direct embed in init.go; (C) New package returning `AssetFetcher`                                                                               | C — new package returning `AssetFetcher`                       | Aligns with the existing `AssetFetcher` interface. Init swaps one closure for another. Clean separation — the embedded package knows nothing about GitHub or init logic.                                                                                           |
| Remove or keep GitHub fetch in init                  | (A) Remove entirely; (B) Keep as fallback                                                                                                                                                    | A — remove entirely                                            | Per spec clarification: purely offline. No network fallback. Simpler code, no ambiguity.                                                                                                                                                                           |
| Version display                                      | (A) Separate version for resources; (B) Use CLI version                                                                                                                                      | B — use CLI version                                            | Resources are embedded at build time from the same tagged commit. The CLI version _is_ the resource version.                                                                                                                                                       |

---

## 2. Component Design

### 2.1 New Components

#### Component: embedded (package)

- **Purpose:** Provides access to init-time resources embedded in the binary
- **Location:** `cmd/maestro-cli/pkg/embedded/embedded.go`
- **Dependencies:** Go standard library (`embed`, `io/fs`, `path`)
- **Dependents:** `cmd/maestro-cli/cmd/init.go`

This package will:

1. Declare `//go:embed` directives for the resource directories
2. Export an `AssetFetcher` function compatible with `agents.AssetFetcher`
3. Export a `FetchFile` function for single-file retrieval (constitution.md)
4. Export a `ListAgentDirs` function returning available agent config directories

#### Component: generate-embedded (build script)

- **Purpose:** Copies resource directories from repo root into `cmd/maestro-cli/pkg/embedded/resources/` before compilation
- **Location:** `cmd/maestro-cli/pkg/embedded/generate.go` (contains `//go:generate` directive) and `cmd/maestro-cli/scripts/copy-resources.sh`
- **Dependencies:** Shell, filesystem
- **Dependents:** Build process (Makefile, GoReleaser)

#### Component: release workflow (GitHub Actions)

- **Purpose:** Automatically builds and publishes release binaries with embedded resources when a version tag is pushed
- **Location:** `.github/workflows/release.yml` (modify existing)
- **Dependencies:** GoReleaser, GitHub Actions
- **Dependents:** End users downloading release binaries

### 2.2 Modified Components

#### Component: init command

- **Current:** Fetches resources from GitHub via API calls and archive fallback. Uses `initFromGitHub()`, `installRequiredStarterAssets()`, `installRequiredStarterFiles()`, and `fetchAndInstallAgentDirs()` — all of which make network requests.
- **Change:** Replace all GitHub-fetching logic in the init path with calls to the embedded package. Remove `initFromGitHub()`. Replace the `AssetFetcher` closure in `installRequiredStarterAssets()` with `embedded.NewAssetFetcher()`. Replace `fetchFileWithRefFallback()` calls with `embedded.FetchFile()`. Replace `fetchAndInstallAgentDirs()` agent content fetch with `embedded.NewAssetFetcher()`. Remove the release-asset download path (lines 86-119 of init.go). Add version display line to init output.
- **Location:** `cmd/maestro-cli/cmd/init.go`
- **Risk:** Medium — this is the core behavioral change. Regression in conflict handling, agent selection, or directory creation is possible. Thorough testing of the full init flow is required.

#### Component: update command (shared functions)

- **Current:** Exports `fetchAndInstallAgentDirs`, `handleAgentConflicts`, `applyConflictAction`, `fetchAgentDirWithRefFallback` — used by both init and update.
- **Change:** `fetchAndInstallAgentDirs` and `fetchAgentDirWithRefFallback` will no longer be called from init. They remain for update. No code changes needed in update.go itself, but the init.go imports of these functions will change.
- **Location:** `cmd/maestro-cli/cmd/update.go`
- **Risk:** Low — update.go itself is not modified. Risk is only in verifying that removing init's dependency on these functions doesn't break update.

#### Component: Makefile

- **Current:** Builds with `go build -ldflags` for version injection. Does not run `go generate`.
- **Change:** Add a `generate` target that runs `go generate ./...` (which triggers the resource copy script). Update the `build` target to depend on `generate`.
- **Location:** `cmd/maestro-cli/Makefile`
- **Risk:** Low — additive change to existing build targets.

#### Component: GoReleaser config

- **Current:** Already runs `go generate ./...` in `before.hooks` and injects version via ldflags.
- **Change:** The `go generate` hook will now also trigger the resource copy. May need to adjust the working directory or add an explicit copy step if `go generate` runs from within `cmd/maestro-cli/` (which it does — GoReleaser uses `dir: cmd/maestro-cli`).
- **Location:** `cmd/maestro-cli/.goreleaser.yml`
- **Risk:** Low — the hook already exists; we're just adding work to what `go generate` does.

#### Component: CI workflow

- **Current:** Runs `go test`, `go build`, `go vet` on push/PR. Does not run `go generate`.
- **Change:** Add `go generate ./...` step before test/build/vet so that embedded resources are available during CI.
- **Location:** `.github/workflows/ci.yml`
- **Risk:** Low — additive step in CI pipeline.

---

## 3. Data Model

### 3.1 New Entities

No new data entities. This feature deals with file-system resources embedded in a binary, not persistent data.

### 3.2 Modified Entities

No entity modifications.

### 3.3 Data Flow

**Build time:**

1. `go generate` runs `copy-resources.sh`
2. Script copies `.maestro/commands/`, `.maestro/scripts/`, `.maestro/templates/`, `.maestro/skills/`, `.maestro/cookbook/`, `.maestro/reference/`, `.maestro/constitution.md`, `.claude/`, `.opencode/` from repo root into `cmd/maestro-cli/pkg/embedded/resources/`
3. `go build` compiles the binary with `//go:embed resources` directive, bundling all copied files

**Runtime (init):**

1. User runs `maestro init`
2. Init displays "Installing maestro {version} resources..."
3. Conflict check on `.maestro/` (unchanged)
4. `embedded.NewAssetFetcher()` reads directories from `embed.FS`
5. `agents.InstallRequiredAssets()` receives the embedded fetcher and writes to disk (unchanged transactional flow)
6. `embedded.FetchFile()` reads `constitution.md` from `embed.FS`
7. Empty dirs (`specs`, `state`, `research`, `memory`) created locally (unchanged)
8. `config.yaml` generated (unchanged)
9. `AGENTS.md` written from hardcoded string (unchanged)
10. Agent dir selection prompt (unchanged), content read from `embed.FS`

---

## 4. API Contracts

### 4.1 New Endpoints/Methods

No new HTTP endpoints. This feature modifies CLI behavior only.

#### New Go API: `embedded.NewAssetFetcher`

- **Purpose:** Returns an `agents.AssetFetcher` that reads from embedded resources
- **Signature:** `func NewAssetFetcher() agents.AssetFetcher`
- **Returns:** A closure `func(dir string) (map[string][]byte, error)` that walks the embedded FS under `dir` and returns file contents keyed by relative path
- **Errors:** Returns error if the requested directory does not exist in the embedded FS

#### New Go API: `embedded.FetchFile`

- **Purpose:** Reads a single file from the embedded resources
- **Signature:** `func FetchFile(path string) ([]byte, error)`
- **Returns:** File contents as bytes
- **Errors:** Returns error if file not found in embedded FS

#### New Go API: `embedded.ListAgentDirs`

- **Purpose:** Returns list of available agent config directories in the embedded resources
- **Signature:** `func ListAgentDirs() []string`
- **Returns:** Slice of directory names (e.g., `[".claude", ".opencode"]`)

### 4.2 Modified Endpoints

#### CLI: `maestro init` (behavioral change)

- **Current behavior:** Makes HTTP requests to GitHub, downloads resources, writes to disk
- **New behavior:** Reads resources from binary, writes to disk. Displays version string in output.
- **Breaking:** No — same user-facing behavior, same output files. The only visible change is the version display line and the absence of network activity.

---

## 5. Implementation Tasks

<!-- TASK:BEGIN id=T001 -->

### T001: Create the `copy-resources.sh` build script

**Metadata:**

- **Label:** build
- **Size:** XS
- **Assignee:** general
- **Dependencies:** None

**Description:**
Create a shell script at `cmd/maestro-cli/scripts/copy-resources.sh` that copies the 9 resource directories/files from the repo root into `cmd/maestro-cli/pkg/embedded/resources/`. The script must:

- Clear the target `resources/` directory before copying (to avoid stale files)
- Copy these 6 `.maestro/` subdirectories: `commands`, `scripts`, `templates`, `skills`, `cookbook`, `reference`
- Copy the standalone file `.maestro/constitution.md` into `resources/.maestro/constitution.md`
- Copy the `.claude/` directory (excluding any `.git` or `node_modules`)
- Copy the `.opencode/` directory (excluding `node_modules`, `bun.lock`)
- Preserve directory structure under `resources/`
- Exit with non-zero status on any copy failure
- Be idempotent (safe to run repeatedly)

**Files to Modify:**

- `cmd/maestro-cli/scripts/copy-resources.sh` (new)

**Acceptance Criteria:**

- [ ] Running the script from `cmd/maestro-cli/` copies all 9 resource sets into `pkg/embedded/resources/`
- [ ] Running the script twice produces identical output (idempotent)
- [ ] The script excludes `node_modules`, `.git`, and `bun.lock` from `.opencode/`
- [ ] The script exits non-zero if the source directories don't exist

<!-- TASK:END -->

<!-- TASK:BEGIN id=T002 -->

### T002: Create the `embedded` package with `go:embed` directives

**Metadata:**

- **Label:** core
- **Size:** S
- **Assignee:** general
- **Dependencies:** T001

**Description:**
Create a new Go package at `cmd/maestro-cli/pkg/embedded/` that embeds the `resources/` directory. The package must:

- Declare a `//go:embed resources` directive on an `embed.FS` variable
- Export `NewAssetFetcher() agents.AssetFetcher` — returns a closure that walks the embedded FS for a given directory prefix and returns `map[string][]byte` (relative path to content), matching the signature in `pkg/agents/installer.go:10`
- Export `FetchFile(path string) ([]byte, error)` — reads a single file from the embedded FS
- Export `ListAgentDirs() []string` — returns available agent config directory names (`.claude`, `.opencode`) by checking what exists in the embedded FS
- Handle the path mapping: callers use paths like `.maestro/commands` but the embedded FS has them under `resources/.maestro/commands`

Also create `cmd/maestro-cli/pkg/embedded/generate.go` containing:

```go
//go:generate bash ../../../scripts/copy-resources.sh
```

(Adjust relative path as needed to reach `cmd/maestro-cli/scripts/copy-resources.sh`)

**Files to Modify:**

- `cmd/maestro-cli/pkg/embedded/embedded.go` (new)
- `cmd/maestro-cli/pkg/embedded/generate.go` (new)
- `cmd/maestro-cli/pkg/embedded/resources/.gitkeep` (new — placeholder so git tracks the directory)

**Acceptance Criteria:**

- [ ] `NewAssetFetcher()` returns a function that, given `.maestro/commands`, returns a map with 14 entries (one per command file) with correct file contents
- [ ] `FetchFile(".maestro/constitution.md")` returns the constitution content
- [ ] `ListAgentDirs()` returns `[".claude", ".opencode"]`
- [ ] Requesting a non-existent directory from the `AssetFetcher` returns a descriptive error
- [ ] `go generate ./pkg/embedded/...` runs the copy script successfully

<!-- TASK:END -->

<!-- TASK:BEGIN id=T003 -->

### T003: Refactor `init.go` to use embedded resources instead of GitHub

**Metadata:**

- **Label:** core
- **Size:** S
- **Assignee:** general
- **Dependencies:** T002

**Description:**
Modify `cmd/maestro-cli/cmd/init.go` to replace all GitHub-fetching logic with the embedded package. Specifically:

- Remove the release-asset download path (lines 86-119 that call `client.FetchLatestRelease()` and `assets.DownloadAndExtract()`)
- Remove the `initFromGitHub()` function call (line 122-129) and the `initFromGitHub` function itself (lines 328-380)
- Replace the `AssetFetcher` closure in `installRequiredStarterAssets()` (line 224-226) with `embedded.NewAssetFetcher()`
- Replace `fetchFileWithRefFallback()` calls in `installRequiredStarterFiles()` with `embedded.FetchFile()`
- Replace the GitHub-based agent dir fetching in `fetchAndInstallAgentDirs()` call (line 181) with embedded-based fetching
- Remove the GitHub client initialization from `runInit` (the `ghclient.NewClient` call)
- Remove the `githubOwner` and `githubRepo` constants from init.go (they may still be needed in update.go — verify and move if needed)
- Remove the platform detection call (`fs.DetectPlatform()`) since there's no release asset to match
- Add a version display line at the start of init: `fmt.Printf("Installing maestro %s resources...\n", version.Version)`
- Preserve all existing behavior: conflict check, agent selection prompts, empty dir creation, config.yaml generation, AGENTS.md generation

**Files to Modify:**

- `cmd/maestro-cli/cmd/init.go`

**Acceptance Criteria:**

- [ ] `maestro init` in a clean directory creates the full `.maestro/` structure with all resource files
- [ ] `maestro init` makes zero HTTP requests (no GitHub client instantiation)
- [ ] The init output includes the version string (e.g., "Installing maestro dev resources...")
- [ ] Conflict handling (overwrite/backup/cancel) still works when `.maestro/` exists
- [ ] Agent directory selection prompt still appears and installs selected dirs
- [ ] `config.yaml` and `AGENTS.md` are still generated correctly
- [ ] The `initFromGitHub` function is removed

<!-- TASK:END -->

<!-- TASK:BEGIN id=T004 -->

### T004: Move shared constants to a common location if needed

**Metadata:**

- **Label:** refactor
- **Size:** XS
- **Assignee:** general
- **Dependencies:** T003

**Description:**
After T003 removes GitHub-related code from init.go, verify that `githubOwner` and `githubRepo` constants are still accessible to `update.go`. If they were defined in `init.go` and update.go references them:

- Move the constants to a shared location (e.g., a `cmd/maestro-cli/cmd/common.go` file or directly into `update.go`)
- Verify update command still compiles and functions correctly

If the constants are already in update.go or a shared file, this task is a no-op (mark complete immediately).

**Files to Modify:**

- `cmd/maestro-cli/cmd/init.go` (verify constants removed)
- `cmd/maestro-cli/cmd/update.go` (add constants if needed)

**Acceptance Criteria:**

- [ ] `go build ./...` succeeds with no errors in `cmd/maestro-cli/`
- [ ] `maestro update` still functions correctly (can resolve GitHub client with owner/repo)
- [ ] No duplicate constant definitions exist

<!-- TASK:END -->

<!-- TASK:BEGIN id=T005 -->

### T005: Update Makefile to run `go generate` before build

**Metadata:**

- **Label:** build
- **Size:** XS
- **Assignee:** general
- **Dependencies:** T002

**Description:**
Modify `cmd/maestro-cli/Makefile` to:

- Add a `generate` target that runs `go generate ./...`
- Update the `build` target to depend on `generate` (so resources are always fresh)
- Add the `cmd/maestro-cli/pkg/embedded/resources/` directory to `.gitignore` since it's generated at build time (should not be committed)

**Files to Modify:**

- `cmd/maestro-cli/Makefile`
- `cmd/maestro-cli/.gitignore` (create or modify)

**Acceptance Criteria:**

- [ ] Running `make build` from `cmd/maestro-cli/` first runs `go generate`, then builds the binary
- [ ] The `pkg/embedded/resources/` directory is listed in `.gitignore`
- [ ] Running `make build` produces a binary that contains embedded resources

<!-- TASK:END -->

<!-- TASK:BEGIN id=T006 -->

### T006: Update CI workflow to run `go generate` before tests

**Metadata:**

- **Label:** ci
- **Size:** XS
- **Assignee:** general
- **Dependencies:** T005

**Description:**
Modify `.github/workflows/ci.yml` to add a `go generate ./...` step before the existing `go test`, `go build`, and `go vet` steps. This ensures the embedded resources directory is populated during CI runs.

**Files to Modify:**

- `.github/workflows/ci.yml`

**Acceptance Criteria:**

- [ ] The CI workflow runs `go generate ./...` before test/build/vet
- [ ] CI builds succeed with the embedded resources present
- [ ] CI tests can exercise the embedded package

<!-- TASK:END -->

<!-- TASK:BEGIN id=T007 -->

### T007: Update release workflow for GoReleaser with embedded resources

**Metadata:**

- **Label:** ci
- **Size:** XS
- **Assignee:** general
- **Dependencies:** T005

**Description:**
Review and update `.github/workflows/release.yml` and `cmd/maestro-cli/.goreleaser.yml` to ensure:

- The `go generate ./...` hook in GoReleaser's `before.hooks` correctly populates embedded resources (it should, since the hook already exists — verify the working directory is correct)
- The matrix build job also runs `go generate` before `go build`
- The release workflow checks out the full repository (not shallow clone) so that resource files are available for the copy script
- Verify the `copy-resources.sh` script's relative paths work correctly from GoReleaser's working directory

**Files to Modify:**

- `.github/workflows/release.yml`
- `cmd/maestro-cli/.goreleaser.yml` (if adjustments needed)

**Acceptance Criteria:**

- [ ] GoReleaser's `before.hooks` triggers the resource copy via `go generate`
- [ ] The matrix build job includes a `go generate` step
- [ ] Release binaries built by CI contain embedded resources
- [ ] The workflow uses a full checkout (not shallow) to ensure resource files exist

<!-- TASK:END -->

<!-- TASK:BEGIN id=T008 -->

### T008: Write unit tests for the `embedded` package

**Metadata:**

- **Label:** test
- **Size:** S
- **Assignee:** general
- **Dependencies:** T002

**Description:**
Create table-driven unit tests for the `embedded` package at `cmd/maestro-cli/pkg/embedded/embedded_test.go`. Tests must cover:

- `NewAssetFetcher()` returns correct file count and contents for each of the 6 `.maestro/` subdirectories
- `NewAssetFetcher()` returns correct contents for `.claude/` and `.opencode/` agent dirs
- `NewAssetFetcher()` returns a descriptive error for non-existent directories
- `FetchFile()` returns correct content for `.maestro/constitution.md`
- `FetchFile()` returns error for non-existent files
- `ListAgentDirs()` returns expected agent directory names

Note: Tests require `go generate` to have been run first (resources must be present). Add a `TestMain` or build tag if needed, or document that `go generate ./...` must precede `go test`.

**Files to Modify:**

- `cmd/maestro-cli/pkg/embedded/embedded_test.go` (new)

**Acceptance Criteria:**

- [ ] All 6 `.maestro/` subdirectories return non-empty maps from `AssetFetcher`
- [ ] Agent dirs (`.claude`, `.opencode`) return non-empty maps from `AssetFetcher`
- [ ] Error cases return descriptive error messages (not bare "file not found")
- [ ] Tests pass with `go test ./pkg/embedded/...` (after `go generate`)
- [ ] Minimum 80% code coverage on the embedded package

<!-- TASK:END -->

<!-- TASK:BEGIN id=T009 -->

### T009: Write integration tests for `maestro init` with embedded resources

**Metadata:**

- **Label:** test
- **Size:** S
- **Assignee:** general
- **Dependencies:** T003

**Description:**
Create integration tests that exercise the full `maestro init` flow using the embedded resources. Tests should:

- Run `maestro init` in a temporary directory and verify the `.maestro/` structure is created with all expected files
- Verify that no network requests are made (mock or intercept HTTP if needed, or run in a network-isolated test)
- Verify the version string appears in the output
- Verify `config.yaml` and `AGENTS.md` are generated
- Verify empty dirs (`specs`, `state`, `research`, `memory`) are created
- Test the conflict flow: run init twice, verify overwrite/backup prompts work
- Test dev build version display (when version is "dev")

**Files to Modify:**

- `cmd/maestro-cli/cmd/init_test.go` (new or modify existing)

**Acceptance Criteria:**

- [ ] Init in a clean temp directory produces the full `.maestro/` structure
- [ ] All 6 resource directories contain the expected files
- [ ] `constitution.md` is present and non-empty
- [ ] `config.yaml` contains the CLI version
- [ ] `AGENTS.md` is present
- [ ] No HTTP client is instantiated during init
- [ ] Tests pass with `go test ./cmd/...` (after `go generate`)

<!-- TASK:END -->

<!-- TASK:BEGIN id=T010 -->

### T010: Measure and document binary size impact

**Metadata:**

- **Label:** docs
- **Size:** XS
- **Assignee:** general
- **Dependencies:** T003

**Description:**
Measure the binary size before and after embedding resources. Document the results:

- Build the binary without embedded resources (current main branch) and record size
- Build the binary with embedded resources and record size
- Calculate the delta
- Verify the total stays under 50MB (per spec requirement)
- Add a comment in the `embedded` package documenting the approximate size impact

**Files to Modify:**

- `cmd/maestro-cli/pkg/embedded/embedded.go` (add size documentation comment)

**Acceptance Criteria:**

- [ ] Binary size before and after is measured and documented
- [ ] Total binary size is under 50MB
- [ ] A comment in the embedded package notes the approximate resource size contribution

<!-- TASK:END -->

<!-- TASK:BEGIN id=T011 -->

### T011: Create GitHub Actions smoke test workflow for `maestro init`

**Metadata:**

- **Label:** ci
- **Size:** S
- **Assignee:** general
- **Dependencies:** T007

**Description:**
Create a new GitHub Actions workflow at `.github/workflows/smoke-test.yml` that validates the built binary can successfully initialize a project from scratch. This workflow should:

- Trigger on the release workflow completion (via `workflow_run`) and also be manually triggerable (`workflow_dispatch`)
- Run on a matrix of platforms: `ubuntu-latest`, `macos-latest` (and optionally `windows-latest`)
- Download the release binary for the matching platform from the GitHub release (using `gh` CLI or the GitHub API)
- Create a fresh empty directory
- Run `maestro init` (non-interactively, skipping agent selection prompts — use `--with-claude` flag or pipe input) in that directory
- Verify the following outputs exist and are non-empty:
  - `.maestro/commands/` (contains 14 files)
  - `.maestro/scripts/` (contains 16 files)
  - `.maestro/templates/` (contains 5 files)
  - `.maestro/skills/` (contains 3 subdirectories)
  - `.maestro/cookbook/` (contains 1 file)
  - `.maestro/reference/` (contains 1 file)
  - `.maestro/constitution.md`
  - `.maestro/config.yaml`
  - `AGENTS.md`
  - `.maestro/specs/` directory exists
  - `.maestro/state/` directory exists
- Verify `maestro version` outputs a valid version string (not empty, not "dev" for release builds)
- Verify the init output contains the version string (e.g., "Installing maestro v")
- Fail the workflow if any verification step fails

Additionally, add a CI-triggered variant that builds the binary from source (via `make build`) and runs the same smoke test — this runs on every PR and push to main, not just releases. This ensures the init flow is always tested even before a release.

**Files to Modify:**

- `.github/workflows/smoke-test.yml` (new)

**Acceptance Criteria:**

- [ ] Workflow triggers automatically after a release is published
- [ ] Workflow can be triggered manually via `workflow_dispatch`
- [ ] Smoke test runs on at least 2 platforms (Linux and macOS)
- [ ] The workflow downloads the correct platform-specific binary from the release
- [ ] `maestro init` runs successfully in a clean directory without network errors
- [ ] All expected `.maestro/` resource directories and files are verified to exist
- [ ] `maestro version` outputs the correct release version
- [ ] The CI-on-PR variant builds from source and runs the same verification steps
- [ ] Workflow fails with a clear error message if any verification step fails

<!-- TASK:END -->

---

## 6. Task Sizing Guidance

All tasks are sized XS or S. No M or L tasks present.

| Task | Size | Est. Time | Rationale                                                                |
| ---- | ---- | --------- | ------------------------------------------------------------------------ |
| T001 | XS   | ~45 min   | Simple shell script, well-defined inputs/outputs                         |
| T002 | S    | ~3 hours  | New package with embed directives, path mapping, 3 exported functions    |
| T003 | S    | ~4 hours  | Core refactor of init.go, removing GitHub logic, wiring embedded package |
| T004 | XS   | ~15 min   | Verify/move constants — may be a no-op                                   |
| T005 | XS   | ~30 min   | Add Makefile target and gitignore entry                                  |
| T006 | XS   | ~20 min   | Add one step to CI workflow                                              |
| T007 | XS   | ~30 min   | Verify/adjust release workflow paths                                     |
| T008 | S    | ~3 hours  | Table-driven tests for embedded package, 6+ test cases                   |
| T009 | S    | ~4 hours  | Integration tests for full init flow                                     |
| T010 | XS   | ~20 min   | Build twice, measure, document                                           |
| T011 | S    | ~3 hours  | New workflow with matrix builds, download logic, verification steps      |

---

## 7. Testing Strategy

### 7.1 Unit Tests

- **Embedded package** (T008): Table-driven tests for `NewAssetFetcher`, `FetchFile`, `ListAgentDirs` — covering happy paths, error cases, and all 8 resource directories
- **Path mapping**: Verify that caller-facing paths (`.maestro/commands`) correctly map to embedded paths (`resources/.maestro/commands`)
- **Edge cases**: Empty directories, files with special characters in names, binary content in scripts

### 7.2 Integration Tests

- **Full init flow** (T009): Run `maestro init` end-to-end in a temp directory, verify all outputs
- **Conflict handling**: Run init twice, verify overwrite produces correct results, backup creates timestamped copies
- **Agent selection**: Verify that selecting `.claude` and/or `.opencode` installs the correct files from embedded resources
- **No network**: Verify that the init command does not instantiate a GitHub client or make HTTP requests

### 7.3 End-to-End Tests

- **CI smoke test** (T011): GitHub Actions workflow that downloads the release binary on Linux and macOS, runs `maestro init` in a clean directory, and verifies all expected files are created. Also runs on every PR by building from source.
- **Offline verification**: Build the binary, disconnect network (or use network namespace), run `maestro init`, verify success
- **Version display**: Build with `VERSION=1.2.3`, verify init output shows "Installing maestro 1.2.3 resources..."
- **Dev build display**: Build with default version, verify init output shows "Installing maestro dev resources..."
- **Binary size gate**: Verify binary < 50MB after embedding

### 7.4 Test Data

- The embedded resources themselves serve as test data (they're compiled into the test binary via `go generate`)
- No additional fixtures needed — tests verify against the actual resources that will be shipped
- Temp directories for integration tests (cleaned up automatically via `t.TempDir()`)

---

## 8. Risks and Mitigations

| Risk                                                   | Likelihood | Impact | Mitigation                                                                                                                                                 |
| ------------------------------------------------------ | ---------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `go:embed` path resolution fails in GoReleaser context | Medium     | High   | T007 explicitly verifies GoReleaser paths. The `copy-resources.sh` script uses relative paths from a known anchor point. Test in CI before merging.        |
| Init regression — conflict handling breaks             | Low        | High   | T009 includes conflict-handling integration tests. The conflict logic itself (in `agents/installer.go`) is not modified — only the content source changes. |
| Binary size exceeds 50MB                               | Low        | Medium | T010 measures before merging. Current resources are ~40 text files (~200KB total). Even with embed overhead, well under 50MB.                              |
| `update` command breaks due to shared code removal     | Low        | High   | T004 explicitly verifies update still compiles and works. Update's code in `update.go` is not modified — only init's usage of shared functions changes.    |
| `.opencode/node_modules` accidentally embedded         | Medium     | Medium | T001's copy script explicitly excludes `node_modules`. T008 tests verify `.opencode` content doesn't include node_modules files.                           |
| Resource copy script fails on CI (path differences)    | Medium     | Medium | T006 and T007 verify CI runs. Script uses `$(dirname $0)` anchoring for reliable path resolution.                                                          |

---

## 9. Open Questions

None — all questions were resolved during the clarify phase. The plan is ready for task breakdown.
