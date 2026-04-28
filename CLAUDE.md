# CLAUDE.md

Project instructions for Claude Code working on the spec-maestro repo.

## Forbidden bd Commands

Never run any of these from a maestro command, helper script, or sub-agent
prompt — they are destructive and can silently lose prior features' issues
when the workspace already has data:

- `bd init --force` — deprecated alias for `--reinit-local`; bypasses the
  local data-safety guard.
- `bd init --reinit-local` — re-initializes the local `.beads/`, can lose
  prior features' issues if the prefix changes.
- `bd init --discard-remote` — authorizes discarding the configured remote's
  Dolt history; the most destructive option.

**Use `bd-preflight.sh` for setup and recovery.** It uses `bd bootstrap`
(non-destructive) and refuses to proceed on prefix drift, surfacing a named
recovery path instead of attempting destructive recovery.

- Entry point: `.maestro/scripts/bd-preflight.sh`
- Recovery runbook: `.maestro/templates/migration-runbook-template.md`
