---
description: >
  Initialize Maestro in the current project. Creates .maestro/ directory structure,
  generates config.yaml, creates constitution from template, and registers commands
  with AI agents (.claude/commands/, .opencode/commands/).
argument-hint: [--force to overwrite existing config]
---

# maestro.init

Initialize Maestro for this project.

## Step 1: Check Existing Installation

Check if `.maestro/config.yaml` already exists:

- If it exists and `$ARGUMENTS` does NOT contain `--force`:
  - Tell the user: "Maestro is already initialized. Use `/maestro.init --force` to reinitialize."
  - Stop here.
- If it exists and `$ARGUMENTS` contains `--force`:
  - Warn the user that config will be overwritten
  - Proceed with initialization

## Step 2: Create Directory Structure

Create the following directories:

```
.maestro/
├── commands/       # Slash commands (*.md)
├── templates/      # Spec, plan, review templates
├── scripts/        # Shell scripts
├── skills/         # SKILL.md files
├── cookbook/        # Decision tables that evolve
├── reference/      # Conventions and patterns
├── specs/          # Feature specifications (created by /maestro.specify)
└── state/          # Pipeline state JSON files
```

## Step 3: Generate config.yaml

If `.maestro/config.yaml` doesn't exist (or --force was used), create it with the default schema:

```yaml
# Maestro Configuration
# Edit this file to customize behavior for your project

project:
  name: "<project-name>" # Replace with actual project name
  description: ""
  base_branch: main

agent_routing:
  backend: general
  frontend: general
  test: general
  fix: general
  refactor: general
  review: general
  pm-validation: general

compile_gate:
  go: "go build ./... && go vet ./..."
  node: "npm run build && npm run lint"
  python: "python -m py_compile **/*.py && ruff check ."
  stack: go # Change to match your project

size_mapping:
  XS: 120
  S: 360
  M: 720
  L: 1200

review_sizing:
  XS: 120
  S: 120
  M: 360
  L: 360
```

Detect the project name from:

1. `package.json` name field (Node projects)
2. `go.mod` module name (Go projects)
3. Current directory name (fallback)

## Step 4: Create Constitution

If `.maestro/constitution.md` doesn't exist, create it from the template:

Read `.maestro/templates/constitution-template.md` and write to `.maestro/constitution.md`.

The constitution defines the project's architectural principles, code standards, and review requirements. It should be edited by the team to reflect their specific standards.

## Step 5: Register Commands and Skills

Run the init script to register commands and skills with AI agents:

```bash
bash .maestro/scripts/init.sh .
```

This registers:

**Commands** — copies all `.maestro/commands/maestro.*.md` files to:

- `.claude/commands/` (for Claude Code)
- `.opencode/commands/` (for OpenCode)

**Skills** — copies each `.maestro/skills/<name>/SKILL.md` to:

- `.claude/skills/maestro-<name>/SKILL.md`
- `.opencode/skills/maestro-<name>/SKILL.md`

Skills are prefixed with `maestro-` to avoid collisions with agent-native skills.

## Step 6: Report Results

Tell the user:

1. What was created:
   - Directory structure
   - config.yaml (with detected project name)
   - constitution.md (from template)
   - Registered commands (12 slash commands)
   - Registered skills (constitution, review, pm-validation)

2. Next steps:
   - Edit `.maestro/config.yaml` to set the correct stack and agent routing
   - Edit `.maestro/constitution.md` to define project standards
   - Run `/maestro.specify <feature description>` to start a new feature
