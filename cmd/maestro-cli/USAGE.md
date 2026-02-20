# Maestro CLI Usage Guide

## Commands

### maestro init

Initialize maestro in the current project directory.

```bash
maestro init
```

**What it does:**

- Checks if `.maestro/` already exists (prompts overwrite/backup/cancel)
- Downloads the latest maestro assets from GitHub releases
- Installs required starter assets: `.maestro/scripts`, `.maestro/skills`, `.maestro/templates`
- Creates the `.maestro/` directory structure (`specs/`, `state/`)
- Generates `AGENTS.md` with quick reference
- Updates `.maestro/config.yaml` with CLI version

**Options:**

- `--with-opencode` - install `.opencode/` during init (non-interactive)
- `--with-claude` - install `.claude/` during init (non-interactive)

`GITHUB_TOKEN` or `GH_TOKEN` are optional and only needed for higher GitHub API limits.

---

### maestro update

Update maestro to the latest version.

```bash
maestro update
```

**What it does:**

- Checks current version against latest GitHub release
- Downloads and extracts the latest assets to `.maestro/`
- Preserves custom modifications (does not wipe your changes)
- Updates `cli_version` in config.yaml

---

### maestro doctor

Validate your maestro project setup.

```bash
maestro doctor
```

**What it checks:**

- `.maestro/` directory exists
- `config.yaml` is present
- Required subdirectories: `scripts/`, `specs/`, `state/`

**Exit codes:**

- `0` — all checks passed
- `1` — one or more checks failed

---

### maestro remove

Remove maestro from the current project.

```bash
maestro remove [--force] [--backup]
```

**Flags:**

- `--force, -f` — skip confirmation prompt
- `--backup` — create a timestamped backup before removing

---

### maestro completion

Generate shell completion scripts.

```bash
maestro completion [bash|zsh|fish|powershell]
```

---

### maestro --version

Show the current version.

```bash
maestro --version
```
