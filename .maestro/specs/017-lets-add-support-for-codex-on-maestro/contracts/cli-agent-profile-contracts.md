# CLI Agent Profile Contracts: Codex

## 1. `maestro init` selection contract

- `KnownAgentDirs()` must include `.codex` as an optional profile.
- Interactive prompt must list `.codex` with user-readable description.
- Empty selection remains valid and installs no optional profile directories.

## 2. `maestro init --with-codex` contract

- `--with-codex` installs `.codex/` without requiring interactive selection.
- If `.codex/` exists, conflict resolution must follow existing overwrite/backup/cancel flow.
- On fetch/write errors, command returns actionable error with context; no credentials in output.

## 3. `maestro update` contract

- If `.codex/` is installed, update refreshes it with other installed profiles.
- If `.codex/` is missing, update can offer it in missing-profile selection flow.
- Existing behavior for `.opencode/` and `.claude/` must remain unchanged.

## 4. `maestro doctor` contract

- `.codex/` appears in optional profile checks.
- Missing `.codex/` is warning-only and does not fail doctor exit status.
- Installed `.codex/` reports as found (optional).
