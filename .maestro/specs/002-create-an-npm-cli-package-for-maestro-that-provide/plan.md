# Implementation Plan: Maestro CLI - Native Binary Distribution

**Feature ID:** 002-create-an-npm-cli-package-for-maestro-that-provide
**Spec:** .maestro/specs/002-create-an-npm-cli-package-for-maestro-that-provide/spec.md
**Created:** 2025-02-19
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

The Maestro CLI is a standalone Go binary that manages maestro projects. It follows a command-based architecture with clear separation of concerns:

```
Maestro CLI Binary
├── Commands Layer
│   ├── init      - Initialize new maestro project
│   ├── update    - Update CLI and project resources
│   ├── doctor    - Validate project setup
│   ├── version   - Check CLI version
│   └── remove    - Remove maestro from project
├── Services Layer
│   ├── ProjectService    - Project initialization/management
│   ├── UpdateService     - CLI and asset updates
│   ├── ValidationService - Project health checks
│   └── GitHubService     - GitHub API/release management
└── Infrastructure Layer
    ├── FileSystem    - Cross-platform file operations
    ├── HTTPClient    - GitHub API and asset downloads
    ├── CacheManager  - Local asset caching
    └── ConfigLoader  - Configuration parsing
```

### 1.2 Component Interactions

**Initialization Flow:**

1. User runs `maestro init`
2. CLI checks if `.maestro/` exists in current directory
3. If exists, prompts for overwrite/backup/cancel
4. Downloads assets from GitHub releases (if not cached)
5. Extracts assets to `.maestro/` directory
6. Generates `AGENTS.md` file
7. Shows success summary

**Update Flow:**

1. User runs `maestro update`
2. CLI queries GitHub API for latest release
3. Compares current version with latest
4. Downloads latest assets bundle from GitHub
5. Detects custom modifications in `.maestro/`
6. Prompts user for action on modified files
7. Applies updates while preserving custom changes

**Validation Flow:**

1. User runs `maestro doctor`
2. CLI checks `.maestro/` directory structure
3. Verifies required files are present
4. Checks file integrity
5. Reports issues with remediation steps
6. Returns appropriate exit code

### 1.3 Key Design Decisions

| Decision             | Options Considered                         | Chosen                         | Rationale                                                      |
| -------------------- | ------------------------------------------ | ------------------------------ | -------------------------------------------------------------- |
| Language             | Go, Rust, Node.js                          | Go                             | Native binary, cross-compilation, standard for CLI tools       |
| Asset Distribution   | Embedded, Download on first use            | Download on first use          | Keeps binary small, allows independent asset updates           |
| Update Mechanism     | Self-updating binary, Package manager only | Package manager + notification | Simpler, avoids security concerns with self-modifying binaries |
| Cross-Platform Paths | Use `/` everywhere, Platform-specific      | Platform-specific with helpers | Windows uses backslashes                                       |
| Configuration Format | YAML, JSON, TOML                           | YAML                           | Matches existing `.maestro/config.yaml` format                 |
| Caching Strategy     | No cache, Cache everything                 | Cache everything               | Assets are versioned and rarely change                         |

---

## 2. Component Design

### 2.1 New Components

#### Component: cmd/root.go

- **Purpose:** Entry point and command routing using Cobra framework
- **Location:** `cmd/maestro-cli/cmd/root.go`
- **Dependencies:** spf13/cobra
- **Dependents:** All subcommand modules (init, update, doctor, version, remove)

#### Component: cmd/init.go

- **Purpose:** Implements `maestro init` command
- **Location:** `cmd/maestro-cli/cmd/init.go`
- **Dependencies:** pkg/github, pkg/fs, pkg/config
- **Dependents:** None

#### Component: cmd/update.go

- **Purpose:** Implements `maestro update` command
- **Location:** `cmd/maestro-cli/cmd/update.go`
- **Dependencies:** pkg/github, pkg/fs, pkg/config
- **Dependents:** None

#### Component: cmd/doctor.go

- **Purpose:** Implements `maestro doctor` command
- **Location:** `cmd/maestro-cli/cmd/doctor.go`
- **Dependencies:** pkg/fs, pkg/config
- **Dependents:** None

#### Component: cmd/version.go

- **Purpose:** Implements `maestro version` command
- **Location:** `cmd/maestro-cli/cmd/version.go`
- **Dependencies:** pkg/github (for version check)
- **Dependents:** None

#### Component: cmd/remove.go

- **Purpose:** Implements `maestro remove` command
- **Location:** `cmd/maestro-cli/cmd/remove.go`
- **Dependencies:** pkg/fs
- **Dependents:** None

#### Component: pkg/github/client.go

- **Purpose:** GitHub API client for fetching releases and assets
- **Location:** `cmd/maestro-cli/pkg/github/client.go`
- **Dependencies:** net/http
- **Dependents:** cmd/init, cmd/update, cmd/version

#### Component: pkg/fs/manager.go

- **Purpose:** File system operations with cross-platform path handling
- **Location:** `cmd/maestro-cli/pkg/fs/manager.go`
- **Dependencies:** os, filepath
- **Dependents:** cmd/init, cmd/update, cmd/doctor, cmd/remove

#### Component: pkg/config/parser.go

- **Purpose:** Parse and validate `.maestro/config.yaml`
- **Location:** `cmd/maestro-cli/pkg/config/parser.go`
- **Dependencies:** gopkg.in/yaml.v3
- **Dependents:** cmd/init, cmd/update, cmd/doctor

#### Component: pkg/assets/downloader.go

- **Purpose:** Download and extract asset bundles from GitHub releases
- **Location:** `cmd/maestro-cli/pkg/assets/downloader.go`
- **Dependencies:** pkg/github, pkg/fs
- **Dependents:** cmd/init, cmd/update

#### Component: internal/version/version.go

- **Purpose:** Version information injected at build time
- **Location:** `cmd/maestro-cli/internal/version/version.go`
- **Dependencies:** None
- **Dependents:** cmd/root, cmd/version

### 2.2 Modified Components

#### Component: .maestro/config.yaml (Schema Addition)

- **Current:** Basic configuration structure
- **Change:** Add `cli_version` field to track which CLI version initialized the project
- **Risk:** Low - backward compatible addition

#### Component: AGENTS.md Template

- **Current:** Static template in `.maestro/templates/`
- **Change:** Generate dynamically during `maestro init` with platform-specific paths
- **Risk:** Low - only affects new projects

---

## 3. Data Model

### 3.1 New Entities

#### Entity: Release

```go
type Release struct {
    Version     string    `json:"tag_name"`
    PublishedAt time.Time `json:"published_at"`
    Assets      []Asset   `json:"assets"`
    Body        string    `json:"body"`
}
```

#### Entity: Asset

```go
type Asset struct {
    Name        string `json:"name"`
    DownloadURL string `json:"browser_download_url"`
    Size        int64  `json:"size"`
}
```

#### Entity: ProjectConfig

```go
type ProjectConfig struct {
    CLIVersion    string            `yaml:"cli_version"`
    InitializedAt time.Time         `yaml:"initialized_at"`
    Components    []string          `yaml:"components"`
    Custom        map[string]string `yaml:"custom,omitempty"`
}
```

#### Entity: Platform

```go
type Platform struct {
    OS   string // darwin, linux, windows
    Arch string // amd64, arm64
}
```

### 3.2 Data Flow

**Asset Download Flow:**

1. CLI determines current platform (OS/Arch)
2. Queries GitHub API for latest release
3. Finds matching asset for current platform
4. Downloads asset to temp directory
5. Verifies checksum (if available)
6. Extracts to `.maestro/` directory
7. Cleans up temp files

**Config Update Flow:**

1. Read existing `.maestro/config.yaml`
2. Parse into ProjectConfig struct
3. Update `cli_version` field
4. Preserve all custom fields
5. Write back to config file

---

## 4. API Contracts

### 4.1 GitHub Releases API

#### GET /repos/{owner}/{repo}/releases/latest

- **Purpose:** Fetch latest release information
- **Input:** None (authenticated requests have higher rate limits)
- **Output:** Release JSON
- **Errors:** 404 (no releases), 403 (rate limited)

#### GET /repos/{owner}/{repo}/releases/tags/{tag}

- **Purpose:** Fetch specific release by version tag
- **Input:** Version tag (e.g., "v1.2.3")
- **Output:** Release JSON
- **Errors:** 404 (tag not found)

### 4.2 GitHub Asset Download

#### GET {asset.browser_download_url}

- **Purpose:** Download asset tarball/zip
- **Input:** None
- **Output:** Binary asset data
- **Errors:** 404 (asset not found), network errors

---

## 5. Implementation Phases

### Phase 1: Project Setup and Core Infrastructure

- **Goal:** Set up Go project structure, CI/CD pipeline, and basic CLI framework
- **Tasks:**
  - Initialize Go module: `go mod init github.com/spec-maestro/maestro-cli`
  - Set up project structure (cmd/, pkg/, internal/)
  - Add Cobra CLI framework dependency
  - Implement version package with ldflags injection
  - Create basic root command with --version support
  - Set up GitHub Actions workflow for cross-platform builds
  - Configure GoReleaser for automated releases
- **Deliverable:** Working `maestro --version` command that displays version info

### Phase 2: GitHub Integration and Asset Management

- **Goal:** Implement GitHub API client and asset downloading
- **Dependencies:** Phase 1
- **Tasks:**
  - Implement GitHub client with rate limiting and caching
  - Create asset downloader with progress indicators
  - Implement platform detection (OS/Arch)
  - Add asset extraction logic (tar.gz, zip)
  - Create local asset cache in `~/.cache/maestro/`
  - Implement checksum verification
- **Deliverable:** `maestro init` command that downloads and extracts assets

### Phase 3: Core Commands Implementation

- **Goal:** Implement all CLI commands
- **Dependencies:** Phase 2
- **Tasks:**
  - Implement `maestro init` with overwrite/backup/cancel prompts
  - Implement `maestro update` with version checking
  - Implement `maestro doctor` with health checks
  - Implement `maestro remove` with confirmation
  - Add AGENTS.md generation
  - Implement config.yaml parsing and updates
- **Deliverable:** All commands working locally

### Phase 4: Cross-Platform and Distribution

- **Goal:** Ensure cross-platform compatibility and distribution setup
- **Dependencies:** Phase 3
- **Tasks:**
  - Test on macOS (Intel and ARM64)
  - Test on Linux (Ubuntu 20.04+, various distros)
  - Test on Windows 10+
  - Set up Homebrew tap repository
  - Configure GoReleaser for Homebrew publishing
  - Create installation documentation
  - Add shell completion scripts (bash, zsh, fish)
- **Deliverable:** Binary installable via `brew install maestro` and GitHub releases

### Phase 5: Testing and Documentation

- **Goal:** Comprehensive testing and user documentation
- **Dependencies:** Phase 4
- **Tasks:**
  - Write unit tests for all packages (target: 80% coverage)
  - Create integration tests for command flows
  - Add E2E tests with temporary directories
  - Write user documentation (README, USAGE)
  - Create troubleshooting guide
  - Add CONTRIBUTING.md for CLI development
- **Deliverable:** Test suite passing, documentation complete

---

## 6. Testing Strategy

### 6.1 Unit Tests

- **pkg/github:** Mock GitHub API responses, test rate limiting handling
- **pkg/fs:** Cross-platform file operations, path handling
- **pkg/config:** YAML parsing and validation
- **pkg/assets:** Download and extraction logic
- **internal/version:** Version string formatting

**Coverage Target:** 80% overall

### 6.2 Integration Tests

- **Init command:** Full initialization flow with temp directories
- **Update command:** Version checking and asset updates
- **Doctor command:** Validation with various project states
- **End-to-end workflows:** Init to Doctor to Update cycle

**Test Locations:**

- `pkg/*/*_test.go` - Package integration tests
- `cmd/maestro/*_test.go` - Command integration tests
- `test/e2e/` - End-to-end test scenarios

### 6.3 End-to-End Tests

- Fresh install on macOS, Linux, Windows
- Homebrew installation flow
- Direct download installation flow
- Full workflow: init to validate to update to remove
- Network failure scenarios
- Permission error handling

### 6.4 Test Data

- **Mock GitHub responses:** `test/fixtures/github/releases.json`
- **Sample assets:** `test/fixtures/assets/minimal.tar.gz`
- **Test configurations:** `test/fixtures/configs/valid.yaml`, `test/fixtures/configs/invalid.yaml`
- **Project templates:** `test/fixtures/projects/` with various states

---

## 7. Risks and Mitigations

| Risk                                   | Likelihood | Impact | Mitigation                                                                     |
| -------------------------------------- | ---------- | ------ | ------------------------------------------------------------------------------ |
| GitHub API rate limiting               | Medium     | High   | Cache responses, implement backoff/retry, allow GitHub token for higher limits |
| Network failures during asset download | Medium     | Medium | Clear error messages, retry logic, offline mode detection                      |
| Cross-platform path issues             | Medium     | Medium | Comprehensive testing on Windows, use path/filepath package consistently       |
| Large binary size                      | Low        | Low    | Download assets on demand, compress assets, optimize build flags               |
| Breaking changes in asset format       | Low        | High   | Version assets independently, migration paths for old projects                 |
| Permission denied errors               | Medium     | Medium | Clear error messages, suggest sudo alternatives, document permissions          |
| Cache corruption                       | Low        | Medium | Cache validation, automatic cache clearing on errors                           |
| Windows-specific bugs                  | Medium     | Medium | CI testing on Windows, community feedback loop                                 |

---

## 8. Open Questions

- Should we support GitHub Enterprise Server for private deployments?
- Do we need to support air-gapped environments (no internet)?
- Should we implement a config file for CLI preferences?
- What is the retention policy for cached assets?
- Should we collect anonymous usage statistics?

---

## 9. File Structure

```
maestro-cli/
├── cmd/
│   └── maestro/
│       └── main.go              # Entry point
├── pkg/
│   ├── github/
│   │   ├── client.go            # GitHub API client
│   │   └── client_test.go
│   ├── fs/
│   │   ├── manager.go           # File system operations
│   │   └── manager_test.go
│   ├── config/
│   │   ├── parser.go            # Config parser
│   │   └── parser_test.go
│   └── assets/
│       ├── downloader.go        # Asset downloader
│       └── downloader_test.go
├── internal/
│   ├── version/
│   │   └── version.go           # Version info
│   └── cmd/
│       ├── root.go              # Root command
│       ├── init.go              # Init command
│       ├── update.go            # Update command
│       ├── doctor.go            # Doctor command
│       ├── version.go           # Version command
│       └── remove.go            # Remove command
├── test/
│   ├── fixtures/
│   │   ├── github/
│   │   ├── assets/
│   │   ├── configs/
│   │   └── projects/
│   └── e2e/
│       └── workflows_test.go
├── scripts/
│   └── build.sh                 # Build scripts
├── .goreleaser.yaml             # GoReleaser config
├── go.mod
├── go.sum
├── Makefile
└── README.md
```

---

## 10. Dependencies

**Core:**

- `github.com/spf13/cobra` - CLI framework
- `github.com/spf13/viper` - Configuration management
- `gopkg.in/yaml.v3` - YAML parsing
- `github.com/fatih/color` - Colored output
- `github.com/briandowns/spinner` - Progress indicators

**Testing:**

- `github.com/stretchr/testify` - Test assertions
- `github.com/h2non/gock` - HTTP mocking

**Build:**

- GoReleaser - Release automation

---

## Changelog

| Date       | Change               | Author         |
| ---------- | -------------------- | -------------- |
| 2025-02-19 | Initial plan created | Maestro System |
