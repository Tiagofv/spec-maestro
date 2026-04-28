# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**

- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

---

## Rebuilding Maestro CLI

The maestro CLI (`cmd/maestro-cli/maestro`) is a Go binary. Here's when you need to rebuild:

### ✅ Rebuild Required

Run `make build` or `go build -o maestro ./cmd/maestro-cli` when you change:

- **Go source files** (`.go` in `cmd/`, `pkg/`, `internal/`)
- **Go module dependencies** (`go.mod`, `go.sum`)
- **Embedded assets** (if code uses `//go:embed`)

### ❌ No Rebuild Needed

The CLI reads these files at runtime - changes take effect immediately:

- **Command definitions** (`.maestro/commands/*.md`)
- **Scripts** (`.maestro/scripts/*.sh`)
- **Templates** (`.maestro/templates/*.md`)
- **Configuration** (`.maestro/config.yaml`)
- **Documentation** (README, USAGE, etc.)
- **Inventory script** (`.maestro/scripts/list-agents.sh`) — bash script discovering harness agents at plan time; edits take effect immediately, no Go rebuild.

### Quick Check

```bash
# Did you modify .go files?
git diff --name-only | grep '\.go$'

# If yes → rebuild required
make build

# If only .md, .sh, .yaml → no rebuild needed
```
