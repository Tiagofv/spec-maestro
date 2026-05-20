# Maestro

A spec-driven development kit delivered as slash commands and skills for AI coding agents. The runtime is your agent (Claude Code, OpenCode, Codex) reading markdown — the only binary is a small Go CLI (`maestro`) that installs and refreshes the markdown into your project.

Maestro gives AI agents a structured pipeline:

```
specify → clarify → research → plan → tasks → implement → analyze
                                                  └── inline review + pm-validate
```

Each stage produces an artifact that feeds the next. The agent never skips ahead.

## How It Works

Maestro is a `.maestro/` directory you drop into any project, plus per-harness mirrors (`.claude/`, `.opencode/`, `.codex/`). It contains slash commands (`.md` files) that AI agents execute as workflows. When you type `/maestro.specify add user authentication`, the agent reads the command file and follows the steps — reading templates, creating specs, checking prerequisites — without any custom runtime.

This follows the [spec-kit](https://github.com/github/spec-kit) pattern: slash commands as the interface, markdown as the implementation. The `maestro` Go CLI exists only to install, update, and doctor those markdown files — the actual workflow logic lives entirely in the `.md` files your agent reads.

## Prerequisites

- [bd](https://github.com/steveyegge/beads) (beads) CLI — issue tracking and task management
  - macOS: `brew install anomalyco/tap/beads`
  - Linux: download from https://github.com/steveyegge/beads/releases
- `jq` — JSON processing (used by shell scripts)
  - macOS: `brew install jq`
  - Linux: `apt-get install jq`
- `python3` — used by the research readiness gate
  - macOS: `brew install python3`
  - Linux: `apt-get install python3`
- `git` — version control
- An AI coding agent that supports slash commands:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
  - [OpenCode](https://opencode.ai)
  - [Codex](https://github.com/openai/codex) (optional — gets `.codex/commands/` and `.codex/skills/` mirrored alongside the others)

## Installation

### 1. Install the `maestro` CLI

The CLI ships pre-built resources embedded in the binary, so installation is a single build step.

```bash
git clone https://github.com/Tiagofv/spec-maestro /tmp/spec-maestro
cd /tmp/spec-maestro/cmd/maestro-cli
make download TAG=v0.0.24            # builds + sudo-installs to /usr/local/bin/maestro
maestro --version                     # confirm
```

Or if you have the repo already, `make upgrade` builds from the local source instead.

### 2. Initialize your project

From the root of any project:

```bash
maestro init                  # installs .maestro/ and prompts for harness mirrors
maestro init --with-claude    # also installs .claude/commands/ and .claude/skills/
maestro init --with-opencode  # also installs .opencode/commands/ and .opencode/skills/
maestro init --with-codex     # also installs .codex/commands/ and .codex/skills/
```

This installs the markdown commands and skills from the embedded resources into the harness directories your agent reads. After init, your project looks like this:

```
your-project/
├── .maestro/              # Source of truth (commands, templates, scripts, skills)
├── .claude/
│   ├── commands/          # maestro.*.md
│   └── skills/            # maestro-review/, maestro-constitution/, etc. (with --with-claude)
├── .opencode/
│   ├── commands/          # maestro.*.md
│   └── skills/            # maestro-review/, maestro-constitution/, etc. (with --with-opencode)
├── .codex/
│   ├── commands/          # maestro.*.md
│   └── skills/            # maestro-review/, maestro-constitution/, etc. (with --with-codex)
└── ...
```

### 3. Keep it fresh

Run `maestro update` periodically — it checks for a newer release and refreshes `.maestro/` assets when there is one. (Note: when the installed binary already matches the latest tag, `update` is a no-op. To force-refresh assets from the current binary, re-run `maestro init` and choose `o` to overwrite, or copy the files manually from this repo.)

`maestro doctor` validates a project's setup (required tools, directory structure, command files in sync).

### 4. Configure

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

### 5. Write your constitution

Edit `.maestro/constitution.md` to define your project's rules — architectural boundaries, code standards, forbidden patterns. Every command reads this file before acting.

### 6. Follow the quickstart

See [QUICKSTART.md](./QUICKSTART.md) for a step-by-step walkthrough.

## How agents discover maestro

Claude Code, OpenCode, and Codex all support slash commands but each looks in its own directory:

| Resource | Claude Code                                   | OpenCode                           | Codex                              |
| -------- | --------------------------------------------- | ---------------------------------- | ---------------------------------- |
| Commands | `.claude/commands/`                           | `.opencode/commands/`              | `.codex/commands/`                 |
| Skills   | `.claude/skills/<name>/SKILL.md`              | `.opencode/skills/<name>/SKILL.md` | `.codex/skills/<name>/SKILL.md`    |
| Scripts  | N/A — invoked via `bash .maestro/scripts/...` | Same — invoked via bash            | Same — invoked via bash            |

The `maestro` CLI copies the embedded resources into the harness-specific directories on `init` (and on `update` when a new release lands). If you edit a command or skill directly in `.maestro/`, re-run `maestro init` (and choose `o` to overwrite) to propagate to the harness mirrors.

**Scripts** live only in `.maestro/scripts/` and are invoked by commands via `bash .maestro/scripts/compile-gate.sh`. All harnesses can run bash, so no registration is needed.

**Skills** are prefixed with `maestro-` when copied (e.g., `.maestro/skills/review/` becomes `.codex/skills/maestro-review/`) to avoid collisions with any agent-native skills you may have.

## Commands

| Command                          | What it does                                                                       |
| -------------------------------- | ---------------------------------------------------------------------------------- |
| `/maestro.init`                  | Initialize maestro in the project (also runnable as `maestro init` from CLI)       |
| `/maestro.specify <description>` | Generate a feature spec from plain language                                        |
| `/maestro.clarify`               | Resolve `[NEEDS CLARIFICATION]` markers in the spec                                |
| `/maestro.research`              | Run pre-planning research and produce readiness artifacts                          |
| `/maestro.research.list`         | List all research artifacts with status                                            |
| `/maestro.research.search`       | Search existing research by keyword or tag                                         |
| `/maestro.plan`                  | Generate an implementation plan from the spec                                      |
| `/maestro.tasks`                 | Break the plan into bd issues with dependencies                                    |
| `/maestro.implement`             | Loop through ready tasks — implement, inline review (assignee subagent + review skill), then PM-validate when all tasks are done |
| `/maestro.pm-validate`           | Final validation gate — regression scan + acceptance criteria                      |
| `/maestro.commit`                | Layer-separated atomic commits                                                     |
| `/maestro.analyze`               | Post-epic learning — metrics, patterns, improvement proposals                      |
| `/maestro.list [--all]`          | Feature dashboard. Default shows active features only; `--all` includes completed and cancelled |
| `/maestro.fork <feature>`        | Branch a new feature off an existing one, copying spec/plan/research               |
| `/maestro.respond`               | Answer PR review comments with learning memory; replies in threads + records findings |

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
    └── loops: bd ready → implement task → inline review (assignee subagent + review skill) → repeat
    └── when all tasks done → /maestro.pm-validate → /maestro.analyze
```

## Directory Structure

This repo:

```
spec-maestro/
├── .maestro/              # Canonical source for commands, scripts, skills, templates
├── .claude/commands/      # Mirror — Claude Code harness
├── .opencode/commands/    # Mirror — OpenCode harness
└── cmd/maestro-cli/       # Go CLI (the `maestro` binary)
    └── pkg/embedded/resources/   # Auto-regenerated copy of all the above (gitignored)
```

A project that has run `maestro init`:

```
your-project/
├── .maestro/
│   ├── commands/           # Slash commands — maestro.*.md source of truth
│   │   ├── maestro.init.md
│   │   ├── maestro.specify.md
│   │   ├── maestro.clarify.md
│   │   ├── maestro.research.md
│   │   ├── maestro.research.list.md
│   │   ├── maestro.research.search.md
│   │   ├── maestro.plan.md
│   │   ├── maestro.tasks.md
│   │   ├── maestro.implement.md
│   │   ├── maestro.pm-validate.md
│   │   ├── maestro.commit.md
│   │   ├── maestro.analyze.md
│   │   ├── maestro.list.md
│   │   ├── maestro.fork.md
│   │   └── maestro.respond.md
│   ├── templates/          # Spec / plan / review / research / constitution templates
│   ├── skills/             # SKILL.md files — review, constitution, pm-validation
│   ├── scripts/            # Shell utilities invoked by commands via bash
│   │   ├── init.sh                 # Legacy registration (CLI's `maestro init` is preferred)
│   │   ├── create-feature.sh       # Create numbered feature dir + branch
│   │   ├── check-prerequisites.sh  # Verify pipeline stage completion
│   │   ├── compile-gate.sh         # Run build+lint for the configured stack
│   │   ├── list-features.sh        # Backs /maestro.list
│   │   ├── list-agents.sh          # Backs auto-selection in /maestro.plan
│   │   ├── bd-helpers.sh / bd-preflight.sh   # bd CLI wrappers
│   │   └── ...
│   ├── cookbook/           # Decision tables and patterns
│   ├── reference/          # Global review conventions
│   ├── agents/             # Project-local agent definitions (optional)
│   ├── config.yaml         # Project configuration
│   ├── constitution.md     # Project rules (generated from template)
│   ├── specs/              # Feature specifications (created by /maestro.specify)
│   └── state/              # Pipeline state JSON files
├── .claude/commands/       # Harness mirrors (copied by `maestro init`)
├── .opencode/commands/
└── .codex/                 # Optional Codex mirror: commands/ and skills/
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

### Auto-Selection of Agents

When `/maestro.plan` runs, it discovers the harness's actual agent inventory by invoking `bash .maestro/scripts/list-agents.sh --harness=auto`. The script walks per-runtime directories (Claude Code: `.claude/agents/`, `~/.claude/agents/`, `.claude/skills/`; OpenCode: `.opencode/agents/`, `~/.config/opencode/agents/`; Codex: `.codex/agents/`, `.codex/skills/`, plus legacy `.agents/skills/`) and emits a normalized JSON inventory. The plan then scores each task against the inventory by file pattern + intent + harness and picks the best-fit assignee — falling back to `general` with a `[no-match: <reason>]` annotation when no specialized agent matches.

Plan output now includes annotations on every `Assignee:` line: `[harness: <name>]`, `[no-match: <reason>]`, `[tie-broken]`, `[review-fallback]`, or `[divergence: ...]`. These make the selection rationale visible. The legacy `agent_routing` block in `config.yaml` remains for backwards compatibility but is no longer consulted.

## Extending

### Adding a new command

1. Create `.maestro/commands/maestro.your-command.md`
2. Add the frontmatter (`description`, `argument-hint`)
3. Write the steps
4. Mirror it to `.claude/commands/`, `.opencode/commands/`, and (if you use Codex) `.codex/commands/`. The three mirrors are plain copies of `.maestro/commands/` — keep them identical
5. From `cmd/maestro-cli/`, run `make generate` so the embedded resources used by `maestro init` reflect the new command

### Adding a new skill

1. Create `.maestro/skills/your-skill/SKILL.md` with `name` and `description` in frontmatter
2. Run `maestro init` (and choose `o` to overwrite) in any consumer project to copy it into the harness skill directories

### Customizing templates

Edit files in `.maestro/templates/`. Commands use these as starting points when generating specs, plans, and reviews.

### Re-syncing after edits

If you edit any command or skill in this repo's `.maestro/`, copy it to the harness mirrors (`.claude/`, `.opencode/`, `.codex/`) and run `make generate` from `cmd/maestro-cli/`. In a downstream project, re-run `maestro init` and choose overwrite to pull the latest embedded resources from your installed binary.

## License

MIT
