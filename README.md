# Maestro

A spec-driven development kit delivered as slash commands and skills for AI coding agents. No binary, no runtime — just markdown files that turn your agent into a disciplined engineer.

Maestro gives AI agents (Claude Code, OpenCode, Cursor, Copilot) a structured pipeline:

```
specify → clarify → research → plan → tasks → implement → review → pm-validate → analyze
```

Each stage produces an artifact that feeds the next. The agent never skips ahead.

## How It Works

Maestro is a `.maestro/` directory you drop into any project. It contains slash commands (`.md` files) that AI agents execute as workflows. When you type `/maestro.specify add user authentication`, the agent reads the command file and follows the steps — reading templates, creating specs, checking prerequisites — without any custom runtime.

This follows the [spec-kit](https://github.com/github/spec-kit) pattern: slash commands as the interface, markdown as the implementation.

## Prerequisites

- [bd](https://github.com/anomalyco/beads) (beads) CLI on PATH — for issue tracking and task management
- An AI coding agent that supports slash commands:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — commands in `.claude/commands/`, skills in `.claude/skills/`
  - [OpenCode](https://opencode.ai) — commands in `.opencode/commands/`, skills in `.opencode/skills/`

## Installation

### 1. Copy `.maestro/` into your project

```bash
# From a project that already has maestro:
cp -r /path/to/agent-maestro/.maestro /path/to/your-project/.maestro
```

Or clone this repo and copy:

```bash
git clone <this-repo> /tmp/agent-maestro
cp -r /tmp/agent-maestro/.maestro /path/to/your-project/.maestro
```

### 2. Register commands and skills

Run the init command through your agent:

```
/maestro.init
```

Or run the script directly:

```bash
bash .maestro/scripts/init.sh .
```

This does three things:

1. **Creates the directory structure** — specs, state, memory
2. **Registers commands** — copies `maestro.*.md` files to `.claude/commands/` and `.opencode/commands/`
3. **Registers skills** — copies each skill to `.claude/skills/maestro-<name>/` and `.opencode/skills/maestro-<name>/`

After init, your project looks like this:

```
your-project/
├── .maestro/              # Source of truth (commands, templates, scripts, skills)
├── .claude/
│   ├── commands/          # maestro.*.md (copied by init)
│   └── skills/            # maestro-review/, maestro-constitution/, etc. (copied by init)
├── .opencode/
│   ├── commands/          # maestro.*.md (copied by init)
│   └── skills/            # maestro-review/, maestro-constitution/, etc. (copied by init)
└── ...
```

### 3. Configure

Edit `.maestro/config.yaml`:

```yaml
project:
  name: "your-project"
  base_branch: main

compile_gate:
  stack: node # or: go, python

agent_routing:
  backend: general
  frontend: general
  review: general
```

### 4. Write your constitution

Edit `.maestro/constitution.md` to define your project's rules — architectural boundaries, code standards, forbidden patterns. Every command reads this file before acting.

## How agents discover maestro

Both Claude Code and OpenCode support slash commands and skills, but each looks in its own directory:

| Resource | Claude Code                                   | OpenCode                           |
| -------- | --------------------------------------------- | ---------------------------------- |
| Commands | `.claude/commands/`                           | `.opencode/commands/`              |
| Skills   | `.claude/skills/<name>/SKILL.md`              | `.opencode/skills/<name>/SKILL.md` |
| Scripts  | N/A — invoked via `bash .maestro/scripts/...` | Same — invoked via bash            |

The `init.sh` script copies from `.maestro/` (the source of truth) into the agent-specific directories. If you edit a command or skill in `.maestro/`, re-run init to propagate.

**Scripts** live only in `.maestro/scripts/` and are invoked by commands via `bash .maestro/scripts/compile-gate.sh`. Both agents can run bash, so no registration is needed.

**Skills** are prefixed with `maestro-` when copied (e.g., `.maestro/skills/review/` becomes `.claude/skills/maestro-review/`) to avoid collisions with any agent-native skills you may have.

## Commands

| Command                          | What it does                                                              |
| -------------------------------- | ------------------------------------------------------------------------- |
| `/maestro.init`                  | Initialize maestro in the project                                         |
| `/maestro.specify <description>` | Generate a feature spec from plain language                               |
| `/maestro.clarify`               | Resolve `[NEEDS CLARIFICATION]` markers in the spec                       |
| `/maestro.research`              | Run pre-planning research and produce readiness artifacts                 |
| `/maestro.plan`                  | Generate an implementation plan from the spec                             |
| `/maestro.tasks`                 | Break the plan into bd issues with dependencies                           |
| `/maestro.implement`             | Implement all tasks — loops through ready tasks, reviews, and PM validate |
| `/maestro.review <task-id>`      | Code review with risk-based routing                                       |
| `/maestro.pm-validate`           | Final validation gate — regression scan + acceptance criteria             |
| `/maestro.commit`                | Layer-separated atomic commits                                            |
| `/maestro.analyze`               | Post-epic learning — metrics, patterns, improvement proposals             |

### Pipeline flow

```
/maestro.specify "add user authentication"
    └── .maestro/specs/001-add-user-authentication/spec.md

/maestro.clarify
    └── resolves [NEEDS CLARIFICATION] markers in spec.md

/maestro.research
    └── .maestro/specs/001-add-user-authentication/research/*.md

/maestro.plan
    └── .maestro/specs/001-add-user-authentication/plan.md

/maestro.tasks
    └── bd epic + implementation tasks + review tasks + PM validation task

/maestro.implement
    └── loops: bd ready → implement task → /maestro.review → repeat
    └── when all tasks done → /maestro.pm-validate → /maestro.analyze
```

## Directory Structure

```
.maestro/
├── commands/           # Slash commands (maestro.*.md) — source of truth
│   ├── maestro.init.md
│   ├── maestro.specify.md
│   ├── maestro.clarify.md
│   ├── maestro.research.md
│   ├── maestro.plan.md
│   ├── maestro.tasks.md
│   ├── maestro.implement.md
│   ├── maestro.review.md
│   ├── maestro.pm-validate.md
│   ├── maestro.commit.md
│   └── maestro.analyze.md
├── templates/          # Templates for specs, plans, reviews, research
│   ├── spec-template.md
│   ├── plan-template.md
│   ├── review-template.md
│   ├── research-template.md
│   └── constitution-template.md
├── skills/             # SKILL.md files — source of truth (copied to agent dirs by init)
│   ├── constitution/SKILL.md
│   ├── review/SKILL.md
│   └── pm-validation/SKILL.md
├── scripts/            # Shell utilities (invoked by commands via bash)
│   ├── init.sh              # Register commands and skills with agents
│   ├── create-feature.sh    # Create numbered feature dir + branch
│   ├── check-prerequisites.sh  # Verify pipeline stage completion
│   ├── compile-gate.sh      # Run build+lint for the configured stack
│   └── bd-helpers.sh        # bd CLI wrapper functions
├── cookbook/            # Decision tables and patterns
│   ├── review-routing.md
│   └── post-epic-analysis.md
├── reference/
│   └── conventions.md       # Global review conventions
├── config.yaml         # Project configuration
├── constitution.md     # Project rules (generated from template)
├── specs/              # Feature specifications (created by /maestro.specify)
├── state/              # Pipeline state JSON files
└── memory/             # Agent memory (learnings across sessions)
```

## Key Concepts

### Constitution

The constitution (`.maestro/constitution.md`) defines the rules every agent must follow: architectural boundaries, code standards, testing requirements, forbidden patterns. Every command reads it. Every review checks against it.

### Compile Gate

After implementation, the compile gate runs your project's build and lint commands. Configured in `config.yaml` under `compile_gate.stack`. The agent cannot mark a task as done until the gate passes.

### Review Routing

Reviews are classified by risk level (HIGH/MEDIUM/LOW) based on what files changed. Business logic and data access files get thorough reviews. Markdown and config changes can be fast-tracked. See `.maestro/cookbook/review-routing.md`.

### Agent Routing

The `agent_routing` config maps task types to agent identifiers. By default everything routes to `general`, but you can route `frontend` tasks to a React-specialized agent, `review` tasks to a code-reviewer, etc.

## Extending

### Adding a new command

1. Create `.maestro/commands/maestro.your-command.md`
2. Add the frontmatter (`description`, `argument-hint`)
3. Write the steps
4. Run `bash .maestro/scripts/init.sh .` to register it

### Adding a new skill

1. Create `.maestro/skills/your-skill/SKILL.md` with `name` and `description` in frontmatter
2. Run `bash .maestro/scripts/init.sh .` to copy it to agent directories

### Customizing templates

Edit files in `.maestro/templates/`. Commands use these as starting points when generating specs, plans, and reviews.

### Re-syncing after edits

If you edit any command or skill in `.maestro/`, re-run init to propagate changes:

```bash
bash .maestro/scripts/init.sh .
```

## License

MIT
