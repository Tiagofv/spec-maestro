# Implementation Plan: Agent Config Directory Copying During Init

**Feature ID:** 011-maestro-cli-needs-to-copy-opencode-and-claude-can-
**Spec:** .maestro/specs/011-maestro-cli-needs-to-copy-opencode-and-claude-can-/spec.md
**Created:** 2026-02-19
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

The feature extends the existing CLI init/update pipeline with a new "agent config" stage. After the `.maestro/` directory is set up, the CLI optionally fetches `.opencode/` and `.claude/` directories from the GitHub repository's default branch using the GitHub Contents API, then writes them to the project root.

```
User runs `maestro init`
  │
  ├─ [existing] Fetch release → extract .maestro/
  │
  ├─ [NEW] Prompt: "Which agent configs?" (.opencode / .claude)
  │         (skipped if --with-opencode / --with-claude flags provided)
  │
  ├─ [NEW] For each selected dir:
  │         ├─ Check if dir exists → conflict prompt (overwrite/backup/cancel)
  │         ├─ Fetch directory tree from GitHub Contents API
  │         └─ Write files to project root
  │
  └─ [existing] Write config.yaml, AGENTS.md
```

### 1.2 Component Interactions

```
cmd/init.go ──┬──> pkg/github/client.go (FetchLatestRelease — existing)
              │
              ├──> pkg/github/contents.go (FetchTree, DownloadBlob — NEW)
              │         │
              │         └──> GitHub Contents/Trees API
              │
              ├──> pkg/agents/prompt.go (PromptAgentConfigs — NEW)
              │
              └──> pkg/agents/writer.go (WriteAgentDir — NEW)

cmd/update.go ──> pkg/agents/detect.go (DetectInstalledAgents — NEW)
              └──> same fetch/write pipeline as init

cmd/doctor.go ──> pkg/agents/detect.go (DetectInstalledAgents — NEW)
```

### 1.3 Key Design Decisions

| Decision                            | Options Considered                                                          | Chosen                | Rationale                                                                                                                                                                                                |
| ----------------------------------- | --------------------------------------------------------------------------- | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| How to fetch agent dirs from GitHub | A) Bundle in release assets B) Use GitHub Contents API C) Use Git Trees API | C) Git Trees API      | Trees API fetches an entire directory recursively in a single request, avoiding per-file API calls. Contents API is limited to 1000 files and requires recursive calls. Trees API is the most efficient. |
| Where to put agent config logic     | A) Inline in cmd/init.go B) New `pkg/agents/` package                       | B) New package        | Constitution requires layer separation. Agent config logic is domain/application-level, not presentation-level. Keeps init.go focused on orchestration.                                                  |
| Conflict handling approach          | A) Per-directory prompts B) Single prompt matching .maestro/ pattern        | B) Single prompt      | Per spec clarification — consistent UX with existing .maestro/ conflict handling.                                                                                                                        |
| Detection of installed agents       | A) Track in config.yaml B) Detect by directory presence                     | B) Directory presence | Per spec clarification — simpler, no state to drift.                                                                                                                                                     |

---

## 2. Component Design

### 2.1 New Components

#### Component: GitHub Trees/Blob Fetcher

- **Purpose:** Fetch a directory tree and file blobs from a GitHub repository
- **Location:** `cmd/maestro-cli/pkg/github/contents.go`
- **Dependencies:** `pkg/github/client.go` (shares the `Client` struct and HTTP plumbing)
- **Dependents:** `cmd/init.go`, `cmd/update.go`

Methods to add on the existing `Client` struct:

- `FetchTree(path string, ref string, recursive bool) (*Tree, error)` — calls `GET /repos/{owner}/{repo}/git/trees/{tree_sha}?recursive=1`
- `FetchRef(ref string) (string, error)` — resolves a branch/tag to a commit SHA, then to a tree SHA
- `DownloadBlob(sha string) ([]byte, error)` — calls `GET /repos/{owner}/{repo}/git/blobs/{sha}` to fetch file content (base64-encoded)

#### Component: Agent Config Prompt

- **Purpose:** Interactive prompt asking the user which agent config directories to install
- **Location:** `cmd/maestro-cli/pkg/agents/prompt.go`
- **Dependencies:** Standard `bufio`, `os` (stdin)
- **Dependents:** `cmd/init.go`, `cmd/update.go`

Functions:

- `PromptAgentSelection(available []string) ([]string, error)` — displays interactive multi-select, returns selected directory names
- `PromptConflictResolution(conflicting []string) (ConflictAction, error)` — overwrite/backup/cancel prompt for existing dirs

#### Component: Agent Config Detector

- **Purpose:** Detect which agent config directories are present on disk
- **Location:** `cmd/maestro-cli/pkg/agents/detect.go`
- **Dependencies:** Standard `os`
- **Dependents:** `cmd/init.go`, `cmd/update.go`, `cmd/doctor.go`

Functions:

- `DetectInstalled(projectRoot string) []string` — returns list of agent config dir names found on disk
- `KnownAgentDirs() []string` — returns `[".opencode", ".claude"]` (single source of truth for known dirs)

#### Component: Agent Config Writer

- **Purpose:** Write fetched agent config files to the project directory, with conflict handling
- **Location:** `cmd/maestro-cli/pkg/agents/writer.go`
- **Dependencies:** `pkg/github/contents.go`, standard `os`
- **Dependents:** `cmd/init.go`, `cmd/update.go`

Functions:

- `WriteAgentDir(tree *github.Tree, blobs map[string][]byte, targetDir string) error` — writes the directory tree to disk
- `BackupDir(dirPath string) (string, error)` — creates a timestamped backup

### 2.2 Modified Components

#### Component: cmd/init.go

- **Current:** Downloads release assets, extracts `.maestro/`, writes config and AGENTS.md
- **Change:** After `.maestro/` setup, add agent config selection prompt (or read flags), fetch selected directories from GitHub, handle conflicts, write to project root. Add `--with-opencode` and `--with-claude` boolean flags to `initCmd`.
- **Risk:** Medium — this is the main entry point; changes must not break the existing `.maestro/` init flow

#### Component: cmd/update.go

- **Current:** Fetches latest release, re-downloads `.maestro/` assets
- **Change:** After `.maestro/` update, detect installed agent config dirs, update them. Offer to install any not-yet-installed agent config dirs.
- **Risk:** Medium — same concerns as init; must not break existing update flow

#### Component: cmd/doctor.go

- **Current:** Validates `.maestro/` directory structure (config.yaml, scripts/, specs/, state/)
- **Change:** Add agent config directory checks as warnings (not errors). Report which are present and which are missing.
- **Risk:** Low — additive checks only, no change to existing validation logic

#### Component: pkg/github/client.go

- **Current:** Defines `Client`, `Release`, `Asset` types and release-fetching methods
- **Change:** No structural changes to existing code. The `Client` struct gains new methods via `contents.go` in the same package. May need to export the `httpClient` field or add a helper method for authenticated GET requests.
- **Risk:** Low — existing methods untouched; new methods added in a separate file

---

## 3. Data Model

### 3.1 New Entities

#### Entity: TreeResponse (in pkg/github/contents.go)

```
TreeResponse {
  SHA       string
  URL       string
  Tree      []TreeEntry
  Truncated bool
}

TreeEntry {
  Path string          // e.g. "commands/maestro-plan.md"
  Mode string          // e.g. "100644"
  Type string          // "blob" or "tree"
  SHA  string
  Size int             // only for blobs
  URL  string
}
```

#### Entity: ConflictAction (in pkg/agents/prompt.go)

```
ConflictAction enum {
  Overwrite
  Backup
  Cancel
}
```

### 3.2 Modified Entities

#### Entity: ProjectConfig (in pkg/config/parser.go)

- **Current fields:** CLIVersion, InitializedAt, Project (Name, Description, BaseBranch), Custom
- **New fields:** None — per spec, installed agents are detected by directory presence, not tracked in config
- **Migration notes:** No migration needed

### 3.3 Data Flow

1. User runs `maestro init --with-claude`
2. Init command parses flags → determines `.claude/` requested
3. Checks if `.claude/` exists on disk → if yes, conflict prompt
4. GitHub client resolves `HEAD` ref → fetches tree for `.claude/` path recursively
5. For each blob in tree, fetches content via blob API
6. Writer creates directory structure and writes files to `.claude/` in project root

---

## 4. API Contracts

### 4.1 New CLI Flags

#### `maestro init --with-opencode`

- **Purpose:** Include `.opencode/` directory during init, skip interactive prompt
- **Type:** Boolean flag, default `false`
- **Behavior:** When set, fetches and installs `.opencode/` without prompting

#### `maestro init --with-claude`

- **Purpose:** Include `.claude/` directory during init, skip interactive prompt
- **Type:** Boolean flag, default `false`
- **Behavior:** When set, fetches and installs `.claude/` without prompting

### 4.2 GitHub API Endpoints Used (External)

#### GET /repos/{owner}/{repo}/git/ref/heads/{branch}

- **Purpose:** Resolve branch to commit SHA
- **Input:** Branch name (default: `main`)
- **Output:** `{ ref, object: { sha, type, url } }`
- **Errors:** 404 if branch not found, 403 if rate limited

#### GET /repos/{owner}/{repo}/git/trees/{tree_sha}?recursive=1

- **Purpose:** Fetch full directory tree recursively
- **Input:** Tree SHA from commit
- **Output:** `{ sha, url, tree: [...entries], truncated }`
- **Errors:** 404, 403, 409 if empty repo

#### GET /repos/{owner}/{repo}/git/blobs/{sha}

- **Purpose:** Fetch individual file content
- **Input:** Blob SHA
- **Output:** `{ sha, size, content (base64), encoding }`
- **Errors:** 404, 403

### 4.3 Modified CLI Commands

#### `maestro doctor`

- **Current behavior:** Reports pass/fail for `.maestro/` structure
- **New behavior:** Additionally reports agent config directory status as warnings
- **Breaking:** No — additive output only

#### `maestro update`

- **Current behavior:** Updates `.maestro/` from latest release
- **New behavior:** Also updates installed agent config dirs; offers to install missing ones
- **Breaking:** No — existing update behavior unchanged; new behavior is additive

---

## 5. Implementation Phases

### Phase 1: GitHub Trees/Blob API Client

- **Goal:** Enable fetching directory contents from a GitHub repository
- **Tasks:**
  - Create `cmd/maestro-cli/pkg/github/contents.go` with `FetchRef`, `FetchTree`, `DownloadBlob` methods
  - Create `cmd/maestro-cli/pkg/github/contents_test.go` with table-driven tests using mock HTTP responses
  - Refactor `client.go` to expose an internal `doGet(url) (*http.Response, error)` helper for reuse
- **Deliverable:** A `Client` that can fetch any directory tree from the maestro GitHub repo and download individual file blobs

### Phase 2: Agent Config Package (detect, prompt, write)

- **Goal:** Core agent config logic — detection, prompting, and writing
- **Tasks:**
  - Create `cmd/maestro-cli/pkg/agents/detect.go` with `KnownAgentDirs()` and `DetectInstalled()`
  - Create `cmd/maestro-cli/pkg/agents/prompt.go` with `PromptAgentSelection()` and `PromptConflictResolution()`
  - Create `cmd/maestro-cli/pkg/agents/writer.go` with `WriteAgentDir()` and `BackupDir()`
  - Create tests: `detect_test.go`, `prompt_test.go` (stdin mocking), `writer_test.go` (temp dir)
- **Deliverable:** A reusable `agents` package that can detect, prompt, and write agent config directories

### Phase 3: Wire Into Init Command

- **Goal:** `maestro init` supports agent config directory installation
- **Dependencies:** Phase 1, Phase 2
- **Tasks:**
  - Add `--with-opencode` and `--with-claude` flags to `initCmd` in `cmd/init.go`
  - Add agent selection logic after `.maestro/` setup: check flags → if none, show prompt → fetch and write selected dirs
  - Add conflict handling for existing agent config directories
  - Add error handling: if GitHub fetch fails, fail init with clear error message
  - Add tests in `cmd/commands_test.go` for the new flag combinations
- **Deliverable:** `maestro init` fully supports interactive and flag-based agent config installation

### Phase 4: Wire Into Update and Doctor Commands

- **Goal:** `maestro update` refreshes agent configs; `maestro doctor` reports their status
- **Dependencies:** Phase 2, Phase 3
- **Tasks:**
  - Modify `cmd/update.go`: detect installed agent dirs → fetch and overwrite from latest; prompt to install missing dirs
  - Modify `cmd/doctor.go`: add agent config directory checks as warnings
  - Add tests for update and doctor agent config behavior
- **Deliverable:** Full lifecycle support — init, update, and doctor all handle agent config directories

---

## 6. Task Sizing Guidance

All tasks in this plan are XS or S sized:

| Phase   | Task Count | Estimated Total |
| ------- | ---------- | --------------- |
| Phase 1 | 3 tasks    | ~3-4 hours (S)  |
| Phase 2 | 4 tasks    | ~4-5 hours (S)  |
| Phase 3 | 5 tasks    | ~4-5 hours (S)  |
| Phase 4 | 3 tasks    | ~3-4 hours (S)  |

**Total estimate:** ~14-18 hours across 15 tasks

---

## 7. Testing Strategy

### 7.1 Unit Tests

- `pkg/github/contents_test.go` — Table-driven tests for FetchRef, FetchTree, DownloadBlob using httptest mock server. Test cases: success, 404, 403 rate limit, empty tree, truncated tree
- `pkg/agents/detect_test.go` — Table-driven tests with temp directories: no dirs exist, one exists, both exist
- `pkg/agents/prompt_test.go` — Tests with mocked stdin: select one, select both, select none, conflict resolution (overwrite, backup, cancel)
- `pkg/agents/writer_test.go` — Tests with temp directories: write new dir, backup existing dir, verify file permissions

### 7.2 Integration Tests

- `cmd/commands_test.go` — Test init with --with-opencode flag against a mock GitHub server
- `cmd/commands_test.go` — Test update detects and refreshes agent dirs
- `cmd/commands_test.go` — Test doctor reports missing agent dirs as warnings

### 7.3 End-to-End Tests

- `test/e2e/e2e_test.go` — Extend existing E2E tests to cover:
  - `maestro init --with-claude` creates `.claude/` directory
  - `maestro init` followed by `maestro update` refreshes agent dirs
  - `maestro doctor` shows agent config warnings

### 7.4 Test Data

- Mock GitHub API responses (JSON fixtures for tree, blob, ref endpoints)
- Sample `.opencode/` and `.claude/` directory structures for writer tests
- Temp directories created via `t.TempDir()` for all filesystem tests

---

## 8. Risks and Mitigations

| Risk                                                                     | Likelihood | Impact | Mitigation                                                                                                           |
| ------------------------------------------------------------------------ | ---------- | ------ | -------------------------------------------------------------------------------------------------------------------- |
| GitHub API rate limiting blocks init for unauthenticated users           | Medium     | High   | Document `GITHUB_TOKEN` requirement clearly in CLI output; fail with helpful error message mentioning token setup    |
| Trees API returns truncated result for large directories                 | Low        | Medium | Check `truncated` field in response; fall back to recursive Contents API calls if truncated                          |
| Network failure during multi-file blob download leaves partial directory | Medium     | Medium | Write to a temp directory first, then atomically rename to target path; clean up temp on failure                     |
| Existing user customizations lost during update                          | Medium     | Medium | Per spec, this is out of scope — but the backup mechanism provides a safety net; clearly warn before overwrite       |
| Breaking existing init flow with new prompt                              | Low        | High   | New prompt is added _after_ existing `.maestro/` setup; existing behavior is untouched; flags bypass prompt entirely |

---

## 9. Open Questions

- None — all spec clarifications were resolved and architectural decisions are clear.
