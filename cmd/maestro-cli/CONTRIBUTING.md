# Contributing to Maestro CLI

## Development Setup

1. Clone the repository
2. Install Go 1.23+
3. Build: `cd cmd/maestro-cli && go build .`
4. Test: `go test ./...`

## Project Structure

```
cmd/maestro-cli/
├── cmd/           # CLI commands (Cobra)
├── pkg/
│   ├── assets/    # Download and extraction
│   ├── config/    # YAML config parsing
│   ├── fs/        # Platform detection
│   ├── github/    # GitHub API client
│   └── templates/ # AGENTS.md generation
├── internal/
│   └── version/   # Version info (ldflags)
└── homebrew/      # Homebrew formula
```

## Release Process

Releases are automated via GoReleaser when a tag is pushed:

```bash
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```
