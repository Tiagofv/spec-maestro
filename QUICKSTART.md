# Maestro Quickstart

> Complete this tutorial in ~10 minutes. You'll walk through the full maestro pipeline on a real (tiny) feature: **"add a greeting to the homepage"**.

## What You'll Build

By the end, you'll have:

- A structured feature spec (`spec.md`) with clarified requirements
- A technical implementation plan (`plan.md`)
- A set of bd issues (epic + tasks) ready to implement

## Prerequisites

- `bd` (beads) CLI installed and on PATH — [github.com/anomalyco/beads](https://github.com/anomalyco/beads)
- An AI coding agent that supports slash commands:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — recommended
  - [OpenCode](https://opencode.ai) — also supported

---

## Step 1: Install

### maestro

Maestro is not a binary — it's a `.maestro/` directory you add to your project.

**Option A: Clone and copy**

```bash
git clone https://github.com/anomalyco/agent-maestro /tmp/agent-maestro
cp -r /tmp/agent-maestro/.maestro /path/to/your-project/.maestro
```

**Option B: If you're working inside this repo**

The `.maestro/` directory is already present. Skip to Step 2.

### bd (beads)

Follow the install instructions at [github.com/anomalyco/beads](https://github.com/anomalyco/beads), then run:

```bash
bd onboard
```

**Verify:**

```
$ bd --version
bd version 0.x.x

$ ls .maestro/
commands/  config.yaml  constitution.md  scripts/  skills/  specs/  state/  templates/
```

Both commands should succeed without errors before continuing.

---

## Step 2: Initialize Your Project

Run the init command in your AI agent session:

```
/maestro.init
```

**What happens:**

The agent reads `.maestro/commands/maestro.init.md` and executes the workflow:

1. Creates the directory structure under `.maestro/`
2. Generates `.maestro/config.yaml` with detected project name
3. Creates `.maestro/constitution.md` from the template
4. Runs `bash .maestro/scripts/init.sh .` to register all commands with your agent

**Expected output:**

```
Maestro initialized successfully.

Created:
  ✓ .maestro/config.yaml (project: my-app, stack: node)
  ✓ .maestro/constitution.md
  ✓ .maestro/specs/ (empty)
  ✓ .maestro/state/ (empty)

Registered 12 slash commands → .claude/commands/
Registered 3 skills → .claude/skills/

Next steps:
  1. Edit .maestro/config.yaml to set compile_gate.stack
  2. Edit .maestro/constitution.md to define your project standards
  3. Run /maestro.specify <feature description> to start a new feature
```

**Verify:**

```bash
ls .claude/commands/ | grep maestro
# Should list: maestro.specify.md, maestro.clarify.md, maestro.plan.md, maestro.tasks.md, ...

cat .maestro/config.yaml | grep stack
# Should show:  stack: node  (or go, python — adjust to match your project)
```

Edit `.maestro/config.yaml` to set `compile_gate.stack` to match your project (`node`, `go`, or `python`) before proceeding.

---

## Step 3: Specify the Feature

Run the specify command with the feature description:

```
/maestro.specify "add a greeting to the homepage"
```

**What happens:**

1. The agent reads the constitution and spec template
2. Runs `bash .maestro/scripts/create-feature.sh "add a greeting to the homepage"` to create a numbered directory and git branch
3. Generates a structured `spec.md` with user stories, success criteria, scope, and clarification markers
4. Writes the spec to `.maestro/specs/001-add-a-greeting-to-the-homepage/spec.md`
5. Creates state at `.maestro/state/001-add-a-greeting-to-the-homepage.json`

**Expected output:**

```
Feature spec created.

  Branch:    feat/001-add-a-greeting-to-the-homepage
  Spec:      .maestro/specs/001-add-a-greeting-to-the-homepage/spec.md
  Stories:   2 user stories defined
  Markers:   2 [NEEDS CLARIFICATION] markers found

The spec has 2 clarification markers. Run /maestro.clarify to resolve
them before planning.
```

**Abbreviated spec content:**

```markdown
# Feature: Add a Greeting to the Homepage

## 3. User Stories

### Story 1: Visitor sees greeting
As a visitor, I want to see a personalized greeting on the homepage,
so that the page feels welcoming when I arrive.

Acceptance Criteria:
- [ ] A greeting message is visible on the homepage without scrolling
- [ ] [NEEDS CLARIFICATION: Should the greeting use the visitor's name,
      or is it a generic message like "Welcome"?]

### Story 2: Greeting updates by time of day
As a visitor, I want the greeting to reflect the time of day,
so that the page feels contextually relevant.

Acceptance Criteria:
- [ ] [NEEDS CLARIFICATION: Is a time-based greeting (Good morning /
      Good afternoon / Good evening) in scope, or is a static greeting sufficient?]
```

**Verify:**

```bash
cat .maestro/specs/001-add-a-greeting-to-the-homepage/spec.md | grep "NEEDS CLARIFICATION"
# Should print 2 lines with clarification markers

cat .maestro/state/001-add-a-greeting-to-the-homepage.json | grep stage
# Should show:  "stage": "specify"
```

---

## Step 4: Clarify

Run the clarify command to resolve the markers interactively:

```
/maestro.clarify
```

**What happens:**

The agent finds the most recent spec, scans for `[NEEDS CLARIFICATION]` markers, and presents each as a question. You answer each one, and the agent updates the spec in place.

**Expected interaction:**

```
## Clarification 1 of 2

From the spec:
> A greeting message is visible on the homepage without scrolling

Question:
Should the greeting use the visitor's name, or is it a generic message like "Welcome"?

Please provide your answer:
```

> **Your answer:** Use a generic greeting — "Welcome to our site." We don't have user authentication yet.

```
## Clarification 2 of 2

From the spec:
> The greeting reflects the time of day

Question:
Is a time-based greeting (Good morning / Good afternoon / Good evening)
in scope, or is a static greeting sufficient?

Please provide your answer:
```

> **Your answer:** Static greeting only. Time-based is a nice future enhancement.

**Expected output after both answers:**

```
Clarification complete.

  Resolved: 2 markers
  Remaining: 0

Spec updated: .maestro/specs/001-add-a-greeting-to-the-homepage/spec.md

Run /maestro.plan to generate the implementation plan.
```

**Verify:**

```bash
grep "NEEDS CLARIFICATION" .maestro/specs/001-add-a-greeting-to-the-homepage/spec.md
# Should return nothing — all markers resolved

cat .maestro/state/001-add-a-greeting-to-the-homepage.json | grep stage
# Should show:  "stage": "clarify"
```

---

## Step 5: Plan

Run the plan command to generate the implementation plan:

```
/maestro.plan
```

**What happens:**

1. The agent checks prerequisites (spec exists, no unresolved markers)
2. Reads the clarified spec, constitution, and plan template
3. Generates a technical plan with architecture decisions, component breakdown, phases, and task markers
4. Writes the plan to `.maestro/specs/001-add-a-greeting-to-the-homepage/plan.md`

> **Note:** If you haven't run `/maestro.research`, the agent will ask you to acknowledge proceeding without research. Type exactly: `I acknowledge proceeding without complete research`

**Expected output:**

```
Implementation plan generated.

  Plan: .maestro/specs/001-add-a-greeting-to-the-homepage/plan.md
  Phases: 2
  New components: 1 (GreetingBanner)
  Modified components: 1 (HomePage)
  Tasks: 3
  Key risks: None identified

Review the plan, then run /maestro.tasks to break it into bd issues.
```

**Abbreviated plan content:**

```markdown
# Implementation Plan: Add a Greeting to the Homepage

## Phase 1: Component

### Tasks

<!-- TASK:BEGIN id=T001 -->
### T001: Create GreetingBanner component
**Metadata:**
- **Label:** ui
- **Size:** XS
- **Assignee:** general
- **Dependencies:** None
**Files:**
- `src/components/GreetingBanner.tsx`
- `src/components/GreetingBanner.test.tsx`
<!-- TASK:END -->

## Phase 2: Integration

<!-- TASK:BEGIN id=T002 -->
### T002: Integrate GreetingBanner into HomePage
**Metadata:**
- **Label:** ui
- **Size:** XS
- **Assignee:** general
- **Dependencies:** T001
**Files:**
- `src/pages/HomePage.tsx`
<!-- TASK:END -->
```

**Verify:**

```bash
ls .maestro/specs/001-add-a-greeting-to-the-homepage/
# Should show: plan.md  spec.md

grep "TASK:BEGIN" .maestro/specs/001-add-a-greeting-to-the-homepage/plan.md
# Should print one line per task (e.g., 3 lines for T001, T002, T003)

cat .maestro/state/001-add-a-greeting-to-the-homepage.json | grep stage
# Should show:  "stage": "plan"
```

---

## Step 6: Create Tasks

Run the tasks command to create the bd epic and issues:

```
/maestro.tasks
```

**What happens:**

1. Parses all `<!-- TASK:BEGIN -->` markers from the plan
2. Validates each task (ID format, size, assignee)
3. Creates a bd epic for the feature
4. Creates one implementation task per marker
5. Auto-generates a paired review task for each implementation task
6. Creates a final PM-VAL task blocked by all review tasks
7. Wires all dependencies

**Expected output:**

```
Tasks created.

  Epic:  001-add-a-greeting-to-the-homepage (epic ID: abc123)

  | #  | ID     | Title                            | Label         | Size | Assignee |
  |----|--------|----------------------------------|---------------|------|----------|
  | 1  | T001   | Create GreetingBanner component  | ui            | XS   | general  |
  | 2  | R001   | Review: T001                     | review        | XS   | general  |
  | 3  | T002   | Integrate GreetingBanner         | ui            | XS   | general  |
  | 4  | R002   | Review: T002                     | review        | XS   | general  |
  | 5  | PM-VAL | PM-VAL: Greeting Validation      | pm-validation | XS   | general  |

  Dependencies wired: R001 ← T001, R002 ← T002, PM-VAL ← R001, R002

Run /maestro.implement to begin automated implementation.
```

**Verify:**

```bash
bd show abc123 --children
# Should list the epic with all tasks

bd ready
# Should show T001 as the first available task (no blockers)

cat .maestro/state/001-add-a-greeting-to-the-homepage.json | grep stage
# Should show:  "stage": "tasks"
```

---

## What's Next

This tutorial covers the **planning half** of the maestro pipeline. The next stage is `/maestro.implement`, which requires a live AI agent session.

When you run `/maestro.implement`, your agent will:

1. Call `bd ready` to find the first available task
2. Read the task description and implement the code changes
3. Run the compile gate (`npm run build && npm run lint` or equivalent)
4. Run `/maestro.review <task-id>` for a risk-classified code review
5. Mark the task complete and loop to the next ready task
6. When all tasks are done, run `/maestro.pm-validate` to verify acceptance criteria
7. Run `/maestro.analyze` to capture learnings for future epics

The implement/review cycle is designed to run autonomously — you can let the agent work through the full task list and check back when it's done.

**See [README.md](README.md) for full documentation**, including:

- All available commands
- Constitution and compile gate configuration
- Agent routing for specialized agents
- How to extend maestro with new commands and skills
