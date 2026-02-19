# Maestro Phase 0 — Commands-First Spec-Driven Development Kit

## Metadata

- **Acronym:** MST
- **Feature Number:** 001
- **External Ref:** None
- **Priority:** P1
- **Epic Title:** MST-001: Maestro Phase 0 Commands-First Development Kit

## Summary

Build Maestro Phase 0 — a spec-driven development kit delivered as slash commands and skills for AI coding agents. This is a greenfield implementation of a structured pipeline: constitution → specify → clarify → plan → tasks → implement → review → validate, with automated orchestration, learning loops, and layer-separated commits.

The product is markdown command files that AI agents follow, with supporting shell scripts, templates, skills, and configuration. All artifacts live in `.maestro/` and get registered to agent command directories (`.claude/commands/` and `.opencode/commands/`) via the init command.

## Technical Approach

1. **Foundation first** — Create the scaffolding infrastructure (config schema, init command, shell scripts) that all other commands depend on
2. **Spec pipeline** — Build the specify→clarify→plan flow that captures and refines requirements
3. **Execution pipeline** — Build tasks→implement→review→pm-validate flow that executes the plan
4. **Orchestration layer** — Build orchestrate, commit, and analyze commands that automate the full workflow
5. **Supporting artifacts** — Skills, cookbook, and reference files that inject patterns and conventions

All commands use the existing PoC patterns (YAML frontmatter, $ARGUMENTS, step-by-step instructions). Shell scripts use `set -euo pipefail` and output JSON for AI consumption. Templates are 100% generic with no domain-specific content.

## Tasks

### 1. MST-001-001: Create config.yaml schema and foundation `[backend]` `[S]`

**Assignee:** general

## Overview

Define the config.yaml schema that all commands depend on, and create the state directory structure.

## Context

The config file is the central configuration for Maestro, defining agent routing, compile gates, size mappings, and project metadata. Every command reads this file to determine how to route work and run quality gates.

## Implementation Details

Create the config.yaml file with the following sections:

**Files:**

- `.maestro/config.yaml` - Main configuration file with complete schema
- `.maestro/state/.gitkeep` - State directory for tracking pipeline progress

## Code Examples

```yaml
# .maestro/config.yaml
# Maestro Configuration — Edit this file to customize behavior

# Project metadata
project:
  name: "my-project"
  description: "Project description"
  # Base branch for PR comparisons and diff analysis
  base_branch: main

# Agent routing — maps task labels to agent identifiers
# Agents are spawned via Task() with subagent_type set to these values
agent_routing:
  backend: general # Go/Python/backend implementation
  frontend: general # React/TypeScript/frontend implementation
  test: general # Test writing
  fix: general # Fix tasks from reviews
  refactor: general # Code improvement
  review: general # Code review
  pm-validation: general # PM feature validation

# Compile gate — stack-specific build+lint commands
# Maestro reads the 'stack' field and runs the corresponding command
compile_gate:
  go: "go build ./... && go vet ./..."
  node: "npm run build && npm run lint"
  python: "python -m py_compile **/*.py && ruff check ."
  # The stack to use for this project (must match a key above)
  stack: go

# Size mapping — converts T-shirt sizes to minutes for bd estimates
size_mapping:
  XS: 120 # 2 hours
  S: 360 # 6 hours
  M: 720 # 12 hours
  L: 1200 # 20 hours

# Review sizing — review tasks get smaller estimates
review_sizing:
  XS: 120 # XS impl -> XS review
  S: 120 # S impl -> XS review
  M: 360 # M impl -> S review
  L: 360 # L impl -> S review
```

## Acceptance Criteria

- [ ] config.yaml exists with all required sections
- [ ] Schema includes: project, agent_routing, compile_gate, size_mapping, review_sizing
- [ ] All values are generic (no project-specific content)
- [ ] State directory exists with .gitkeep
- [ ] YAML is valid and parseable

---

### 2. Review: MST-001-001 `[review]` `[XS]`

**Assignee:** general

> Blocked by: Task 1

## Overview

Review the config.yaml schema and state directory structure.

## Task Reference

- **Reviews:** Task 1 - Create config.yaml schema and foundation

## Files to Review

- `.maestro/config.yaml`
- `.maestro/state/.gitkeep`

## Review Focus

- [ ] All configuration sections present per requirements
- [ ] Schema is self-documenting with comments
- [ ] No domain-specific content (generic template)
- [ ] YAML syntax is valid

## Acceptance Criteria

- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 3. MST-001-002: Create shell script helpers `[backend]` `[M]`

**Assignee:** general

> Blocked by: Task 1

## Overview

Create the shell script infrastructure that commands depend on: prerequisites checker, compile gate runner, and bd helper functions.

## Context

Commands delegate to shell scripts for deterministic operations like checking pipeline state, running build/lint, and interacting with bd. Scripts must be defensive (set -euo pipefail), output JSON for AI parsing, and handle errors gracefully.

## Implementation Details

**Files:**

- `.maestro/scripts/check-prerequisites.sh` - Validate pipeline state before running commands
- `.maestro/scripts/compile-gate.sh` - Run stack-specific build+lint from config
- `.maestro/scripts/bd-helpers.sh` - Wrapper functions for common bd operations
- `.maestro/scripts/init.sh` - Setup script called by /maestro.init

Enhance existing:

- `.maestro/scripts/create-feature.sh` - Already exists (PoC), may need minor polish

## Code Examples

```bash
# check-prerequisites.sh
#!/usr/bin/env bash
# Check that required pipeline stages are complete before proceeding
# Usage: check-prerequisites.sh <stage>
# Stages: clarify (needs spec), plan (needs spec), tasks (needs plan), implement (needs tasks)
# Outputs JSON: {"ok":true} or {"ok":false,"error":"...","suggestion":"..."}

set -euo pipefail

STAGE="${1:?Usage: check-prerequisites.sh <stage>}"
FEATURE_DIR="${2:-.maestro/specs/$(ls -1 .maestro/specs 2>/dev/null | tail -1)}"

check_file_exists() {
  local file="$1"
  local name="$2"
  if [[ ! -f "$file" ]]; then
    echo "{\"ok\":false,\"error\":\"$name not found\",\"suggestion\":\"Run the previous pipeline stage first\"}"
    exit 1
  fi
}

case "$STAGE" in
  clarify|plan)
    check_file_exists "$FEATURE_DIR/spec.md" "Specification"
    ;;
  tasks)
    check_file_exists "$FEATURE_DIR/plan.md" "Implementation plan"
    ;;
  implement|review|pm-validate)
    # Check bd has tasks for this feature
    if ! command -v bd &>/dev/null; then
      echo "{\"ok\":false,\"error\":\"bd CLI not found\",\"suggestion\":\"Install bd: go install github.com/...\"}"
      exit 1
    fi
    ;;
  *)
    echo "{\"ok\":false,\"error\":\"Unknown stage: $STAGE\",\"suggestion\":\"Valid stages: clarify, plan, tasks, implement\"}"
    exit 1
    ;;
esac

echo "{\"ok\":true}"
```

```bash
# compile-gate.sh
#!/usr/bin/env bash
# Run compile gate based on stack from config.yaml
# Usage: compile-gate.sh [worktree-path]
# Exit 0 = pass, exit 1 = fail

set -euo pipefail

WORKTREE="${1:-.}"
CONFIG=".maestro/config.yaml"

echo "=== Compile Gate: $WORKTREE ===" >&2

cd "$WORKTREE" || { echo "FAIL: Cannot cd to $WORKTREE" >&2; exit 1; }

# Parse stack from config
if [[ ! -f "$CONFIG" ]]; then
  echo "FAIL: Config not found at $CONFIG" >&2
  exit 1
fi

# Extract stack value (simple grep, avoid yq dependency)
STACK=$(grep -E "^\s+stack:" "$CONFIG" | head -1 | sed 's/.*stack:\s*//' | tr -d '"' | tr -d "'")

if [[ -z "$STACK" ]]; then
  echo "FAIL: No stack defined in config.yaml" >&2
  exit 1
fi

# Get command for this stack
CMD=$(grep -A1 "^compile_gate:" "$CONFIG" | grep -E "^\s+$STACK:" | sed "s/.*$STACK:\s*//" | tr -d '"')

if [[ -z "$CMD" ]]; then
  echo "FAIL: No compile_gate command for stack: $STACK" >&2
  exit 1
fi

echo "Running: $CMD" >&2
if eval "$CMD" 2>&1; then
  echo "=== Compile gate PASSED ===" >&2
  exit 0
else
  echo "=== Compile gate FAILED ===" >&2
  echo "Fix the errors above and re-run." >&2
  exit 1
fi
```

```bash
# bd-helpers.sh
#!/usr/bin/env bash
# Helper functions for bd operations
# Source this file: source .maestro/scripts/bd-helpers.sh

# Check if bd is available
bd_check() {
  if ! command -v bd &>/dev/null; then
    echo "{\"error\":\"bd CLI not found\"}" >&2
    return 1
  fi
  return 0
}

# Create epic and return ID
# Usage: bd_create_epic "Title" "Description"
bd_create_epic() {
  local title="$1"
  local desc="${2:-}"
  bd create --title="$title" --type=epic --priority=2 ${desc:+--description="$desc"} --json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4
}

# Create task under epic
# Usage: bd_create_task "Title" "Description" "label" estimate_minutes epic_id assignee
bd_create_task() {
  local title="$1"
  local desc="$2"
  local label="$3"
  local estimate="$4"
  local epic_id="$5"
  local assignee="${6:-general}"

  bd create \
    --title="$title" \
    --type=task \
    --priority=2 \
    --labels="$label" \
    --estimate="$estimate" \
    --assignee="$assignee" \
    --description="$desc" \
    --parent="$epic_id" \
    --json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4
}

# Add dependency between tasks
# Usage: bd_add_dep dependent_id blocker_id
bd_add_dep() {
  local dependent="$1"
  local blocker="$2"
  bd dep add "$dependent" "$blocker" 2>/dev/null || true
}

# Get ready tasks as JSON
bd_ready_json() {
  bd ready --json 2>/dev/null || echo "[]"
}

# Close task with structured reason
# Usage: bd_close task_id "VERDICT | key: value"
bd_close() {
  local task_id="$1"
  local reason="$2"
  bd close "$task_id" --reason "$reason" 2>/dev/null
}
```

```bash
# init.sh
#!/usr/bin/env bash
# Initialize Maestro in a project
# Called by /maestro.init command
# Creates directory structure and registers commands

set -euo pipefail

PROJECT_ROOT="${1:-.}"
MAESTRO_DIR="$PROJECT_ROOT/.maestro"

echo "=== Initializing Maestro ===" >&2

# Create directory structure
mkdir -p "$MAESTRO_DIR"/{commands,templates,scripts,skills,cookbook,reference,specs,state}

# Copy commands to agent directories
for agent_dir in ".claude/commands" ".opencode/commands"; do
  target="$PROJECT_ROOT/$agent_dir"
  mkdir -p "$target"

  # Copy all maestro.*.md commands
  for cmd in "$MAESTRO_DIR/commands"/maestro.*.md; do
    if [[ -f "$cmd" ]]; then
      cp "$cmd" "$target/" 2>/dev/null || true
      echo "Registered: $(basename "$cmd") -> $agent_dir" >&2
    fi
  done
done

echo "=== Maestro initialized ===" >&2
echo "{\"ok\":true,\"maestro_dir\":\"$MAESTRO_DIR\"}"
```

## Acceptance Criteria

- [ ] All scripts use `set -euo pipefail`
- [ ] Scripts output JSON for AI parsing
- [ ] check-prerequisites.sh validates pipeline state correctly
- [ ] compile-gate.sh reads stack from config.yaml
- [ ] bd-helpers.sh provides reusable functions
- [ ] init.sh creates directory structure and registers commands
- [ ] All scripts are executable (`chmod +x`)

---

### 4. Review: MST-001-002 `[review]` `[XS]`

**Assignee:** general

> Blocked by: Task 3

## Overview

Review the shell script infrastructure for correctness and defensive programming.

## Task Reference

- **Reviews:** Task 3 - Create shell script helpers

## Files to Review

- `.maestro/scripts/check-prerequisites.sh`
- `.maestro/scripts/compile-gate.sh`
- `.maestro/scripts/bd-helpers.sh`
- `.maestro/scripts/init.sh`

## Review Focus

- [ ] All scripts use `set -euo pipefail`
- [ ] Error handling is defensive
- [ ] JSON output is valid and parseable
- [ ] No hardcoded paths or project-specific content
- [ ] Scripts handle edge cases (missing files, missing config)

## Acceptance Criteria

- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 5. MST-001-003: Create /maestro.init command `[backend]` `[S]`

**Assignee:** general

> Blocked by: Task 3

## Overview

Create the initialization command that scaffolds the .maestro directory structure, creates the constitution from template, and registers commands with AI agents.

## Context

This is the entry point for new projects. It creates all directories, generates config.yaml if missing, creates a constitution from template, and copies commands to .claude/commands/ and .opencode/commands/.

## Implementation Details

**Files:**

- `.maestro/commands/maestro.init.md` - The init command

## Code Examples

```markdown
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
├── commands/ # Slash commands (\*.md)
├── templates/ # Spec, plan, review templates
├── scripts/ # Shell scripts
├── skills/ # SKILL.md files
├── cookbook/ # Decision tables that evolve
├── reference/ # Conventions and patterns
├── specs/ # Feature specifications (created by /maestro.specify)
└── state/ # Pipeline state JSON files

````

## Step 3: Generate config.yaml

If `.maestro/config.yaml` doesn't exist (or --force was used), create it with the default schema:

```yaml
# Maestro Configuration
# Edit this file to customize behavior for your project

project:
  name: "<project-name>"  # Replace with actual project name
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
  stack: go  # Change to match your project

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
````

Detect the project name from:

1. `package.json` name field (Node projects)
2. `go.mod` module name (Go projects)
3. Current directory name (fallback)

## Step 4: Create Constitution

If `.maestro/constitution.md` doesn't exist, create it from the template:

Read `.maestro/templates/constitution-template.md` and write to `.maestro/constitution.md`.

The constitution defines the project's architectural principles, code standards, and review requirements. It should be edited by the team to reflect their specific standards.

## Step 5: Register Commands

Run the init script to copy commands to agent directories:

```bash
bash .maestro/scripts/init.sh .
```

This copies all `.maestro/commands/maestro.*.md` files to:

- `.claude/commands/` (for Claude Code)
- `.opencode/commands/` (for OpenCode)

## Step 6: Report Results

Tell the user:

1. What was created:
   - Directory structure
   - config.yaml (with detected project name)
   - constitution.md (from template)
   - Registered commands

2. Next steps:
   - Edit `.maestro/config.yaml` to set the correct stack and agent routing
   - Edit `.maestro/constitution.md` to define project standards
   - Run `/maestro.specify <feature description>` to start a new feature

````

## Acceptance Criteria
- [ ] Command creates full directory structure
- [ ] config.yaml is generated with project name detection
- [ ] Constitution is created from template
- [ ] Commands are registered to .claude/commands/ and .opencode/commands/
- [ ] Idempotent (--force flag for reinitialization)
- [ ] Clear next steps provided to user

---

### 6. Review: MST-001-003 `[review]` `[XS]`

**Assignee:** general
> Blocked by: Task 5

## Overview
Review the /maestro.init command for completeness and correctness.

## Task Reference
- **Reviews:** Task 5 - Create /maestro.init command

## Files to Review
- `.maestro/commands/maestro.init.md`

## Review Focus
- [ ] All steps from requirements are implemented
- [ ] Directory structure matches spec
- [ ] Project name detection is reasonable
- [ ] Command registration works for both Claude and OpenCode
- [ ] Idempotency handled correctly

## Acceptance Criteria
- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 7. MST-001-004: Create constitution template `[backend]` `[S]`

**Assignee:** general
> Blocked by: Task 1

## Overview
Create the constitution template that defines architectural principles, code standards, and review requirements for a project.

## Context
The constitution is the foundational document that all other Maestro artifacts reference. It establishes the rules that specs, plans, implementations, and reviews must follow. The template must be 100% generic with placeholder sections for domain-specific content.

## Implementation Details

**Files:**
- `.maestro/templates/constitution-template.md` - Generic constitution template

## Code Examples

```markdown
# Project Constitution

**Project:** {PROJECT_NAME}
**Created:** {DATE}
**Last Updated:** {DATE}

---

## 1. Architecture Principles

### 1.1 Core Architecture
{Describe the high-level architecture: monolith, microservices, modular monolith, etc.}

### 1.2 Layer Separation
{Define architectural layers and their responsibilities. Examples:}
- **Domain Layer** — Business logic, entities, value objects
- **Application Layer** — Use cases, commands, queries
- **Infrastructure Layer** — Database, external services, messaging
- **Presentation Layer** — API, UI, CLI

### 1.3 Dependency Rules
{Define which layers can depend on which. Example: Domain never imports Infrastructure}

### 1.4 Communication Patterns
{Define how components communicate: sync API calls, async events, etc.}

---

## 2. Code Standards

### 2.1 Language-Specific Standards
{Reference language style guides or define custom rules}

### 2.2 Naming Conventions
{Define naming rules for files, functions, variables, packages, etc.}

### 2.3 Error Handling
{Define error handling patterns: wrapping, sentinel errors, error types, etc.}

### 2.4 Testing Standards
{Define testing requirements: coverage targets, test types, naming conventions}

---

## 3. Review Requirements

### 3.1 Required Reviews
{Define what requires code review: all code, only production code, etc.}

### 3.2 Review Checklist
{Common items reviewers must check}
- [ ] No hardcoded secrets or credentials
- [ ] Error handling is complete
- [ ] Tests cover happy path and edge cases
- [ ] No breaking changes to public APIs
- [ ] Performance implications considered

### 3.3 Approval Requirements
{Define who can approve: any team member, senior engineer, specific owners}

---

## 4. Domain-Specific Rules

### 4.1 Business Logic Constraints
{Define domain-specific constraints. Examples:}
- Money must never be represented as floating point
- User actions must be audit logged
- PII must be encrypted at rest

### 4.2 Integration Patterns
{Define patterns for external service integration}

### 4.3 Security Requirements
{Define security requirements specific to the domain}

---

## 5. Out of Scope for AI Agents

{List things AI agents should NOT do without human approval}
- Database migrations that drop columns/tables
- Changes to authentication/authorization logic
- Modifications to critical business logic
- Deletion of production data
- Changes to encryption keys or secrets

---

## 6. Reference Files

{List important reference files in the codebase}
- `docs/architecture.md` — Detailed architecture documentation
- `docs/api.md` — API documentation
- `CLAUDE.md` — AI agent instructions

---

## Changelog

| Date | Change | Author |
|------|--------|--------|
| {DATE} | Initial constitution created | {AUTHOR} |
````

## Acceptance Criteria

- [ ] Template is 100% generic (no domain-specific content)
- [ ] All required sections present: Architecture, Code Standards, Review Requirements, Domain-Specific
- [ ] Placeholder syntax is clear and consistent ({PLACEHOLDER})
- [ ] Includes "Out of Scope for AI" section
- [ ] Includes changelog section
- [ ] Self-documenting with examples in placeholders

---

### 8. Review: MST-001-004 `[review]` `[XS]`

**Assignee:** general

> Blocked by: Task 7

## Overview

Review the constitution template for completeness and genericity.

## Task Reference

- **Reviews:** Task 7 - Create constitution template

## Files to Review

- `.maestro/templates/constitution-template.md`

## Review Focus

- [ ] Template is domain-agnostic
- [ ] All RFC-002 required sections present
- [ ] Placeholder syntax is consistent
- [ ] Examples are generic (not Go/Python/etc specific)
- [ ] AI "out of scope" section is comprehensive

## Acceptance Criteria

- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 9. MST-001-005: Polish /maestro.specify command `[backend]` `[S]`

**Assignee:** general

> Blocked by: Task 5

## Overview

Polish the existing PoC /maestro.specify command to add state tracking, idempotency, and better integration with the pipeline.

## Context

The PoC exists at `.maestro/commands/maestro.specify.md` and works well. This task adds: state.json tracking, idempotency (offer refine if spec exists), constitution reading, and better next-step guidance.

## Implementation Details

**Files:**

- `.maestro/commands/maestro.specify.md` - Enhance existing command

Enhancements needed:

1. Read constitution before generating spec
2. Write state.json after creating spec
3. Add idempotency check (offer refine mode if spec exists)
4. Better integration with /maestro.clarify next step

## Code Examples

Add these sections to the existing command:

````markdown
## Step 0: Read Constitution (NEW)

Before generating the spec, read `.maestro/constitution.md` if it exists.

The constitution informs:

- Domain constraints that must appear in success criteria
- Security requirements that may need clarification markers
- Architecture patterns that affect scope decisions

If the constitution doesn't exist, proceed without it but suggest the user run `/maestro.init` first.

## Step 1b: Check for Existing Spec (NEW - after Step 1)

After creating the feature scaffold, check if `{spec_dir}/spec.md` already exists:

- If it exists, offer two options:
  1. **Refine**: Read the existing spec and enhance it based on the new description
  2. **Replace**: Archive the old spec and create a fresh one

- If the user doesn't specify, default to **Refine** mode

In Refine mode:

- Read the existing spec
- Incorporate the new description as additional context
- Preserve existing clarification markers
- Add new sections as needed

## Step 5b: Update State (NEW - after Step 5)

Create or update the state file at `.maestro/state/{feature_id}.json`:

```json
{
  "feature_id": "{feature_id}",
  "created_at": "{ISO timestamp}",
  "updated_at": "{ISO timestamp}",
  "stage": "specify",
  "spec_path": "{spec_dir}/spec.md",
  "branch": "{branch}",
  "clarification_count": {number of [NEEDS CLARIFICATION] markers},
  "user_stories": {number of user stories},
  "history": [
    {"stage": "specify", "timestamp": "{ISO}", "action": "created"}
  ]
}
```
````

````

## Acceptance Criteria
- [ ] Command reads constitution if available
- [ ] State JSON is created/updated after spec generation
- [ ] Idempotency: offers refine vs replace for existing specs
- [ ] Preserves all existing PoC functionality
- [ ] Next step guidance includes /maestro.clarify when markers present

---

### 10. Review: MST-001-005 `[review]` `[XS]`

**Assignee:** general
> Blocked by: Task 9

## Overview
Review the polished /maestro.specify command.

## Task Reference
- **Reviews:** Task 9 - Polish /maestro.specify command

## Files to Review
- `.maestro/commands/maestro.specify.md`

## Review Focus
- [ ] Constitution integration works correctly
- [ ] State JSON schema is complete
- [ ] Idempotency logic is clear
- [ ] No regression to existing PoC functionality
- [ ] Step numbers and flow are logical

## Acceptance Criteria
- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 11. MST-001-006: Create /maestro.clarify command `[backend]` `[S]`

**Assignee:** general
> Blocked by: Task 9

## Overview
Create the clarify command that resolves [NEEDS CLARIFICATION] markers through interactive Q&A.

## Context
After /maestro.specify generates a spec with uncertainty markers, /maestro.clarify presents questions to the user, collects answers, and incorporates them into the spec. This is optional — if no markers exist, it suggests skipping to /maestro.plan.

## Implementation Details

**Files:**
- `.maestro/commands/maestro.clarify.md` - Interactive clarification command

## Code Examples

```markdown
---
description: >
  Interactive Q&A to resolve [NEEDS CLARIFICATION] markers in the current specification.
  Reads the spec, presents questions, incorporates answers, and updates the spec.
argument-hint: [feature-id] (optional, defaults to most recent)
---

# maestro.clarify

Resolve uncertainties in the feature specification.

## Step 1: Find the Specification

If `$ARGUMENTS` contains a feature ID, use it to find the spec:
- Look for `.maestro/specs/{feature-id}/spec.md`

Otherwise, find the most recent feature:
- List directories in `.maestro/specs/` sorted by name (highest number first)
- Use the most recent one

If no spec is found, tell the user to run `/maestro.specify` first and stop.

## Step 2: Check for Clarification Markers

Read the spec file and scan for `[NEEDS CLARIFICATION: ...]` markers.

If no markers are found:
- Tell the user: "No clarification markers found. The spec is ready for planning."
- Suggest: "Run `/maestro.plan` to generate the implementation plan."
- Stop here.

If markers are found, extract them into a list.

## Step 3: Present Questions

For each clarification marker, present the question to the user:

````

## Clarification 1 of N

**From the spec:**

> {surrounding context from the spec}

**Question:**
{the specific question from the marker}

Please provide your answer:

```

Wait for the user's response before proceeding to the next question.

## Step 4: Proactive Gap Detection

After all explicit markers are resolved, scan the spec for implicit gaps:

1. **Undefined edge cases**: What happens when X fails? What if the list is empty?
2. **Missing actors**: Who triggers this action? Who is notified?
3. **Ambiguous quantities**: "Multiple" — how many? "Fast" — how fast?
4. **Unstated assumptions**: Does this require authentication? What timezone?

Present any new questions found:

```

## Additional Questions

While reviewing the spec, I identified some implicit gaps:

1. {question}
2. {question}

Would you like to address these now? (yes/no/skip)

```

## Step 5: Update the Specification

For each answered question:
1. Find the corresponding `[NEEDS CLARIFICATION: ...]` marker
2. Replace it with the user's answer, formatted appropriately
3. If the answer affects other sections (e.g., adds a new user story), update those too

Write the updated spec back to the same file.

## Step 6: Update State

Update `.maestro/state/{feature_id}.json`:
- Set `stage` to `clarify`
- Update `clarification_count` to remaining markers (should be 0)
- Add history entry: `{"stage": "clarify", "timestamp": "...", "action": "resolved N markers"}`

## Step 7: Report and Next Steps

Show the user:
1. Summary of changes made
2. Number of markers resolved
3. If any markers remain (user skipped), list them
4. Suggest: "Run `/maestro.plan` to generate the implementation plan."

---

**Remember:** Clarification is about removing ambiguity, not adding implementation details. Keep answers focused on WHAT and WHY, not HOW.
```

## Acceptance Criteria

- [ ] Command finds spec by feature-id or most recent
- [ ] Gracefully handles case with no markers (suggests /maestro.plan)
- [ ] Presents questions interactively
- [ ] Proactively identifies implicit gaps
- [ ] Updates spec file with answers
- [ ] Updates state.json
- [ ] Clear next step guidance

---

### 12. Review: MST-001-006 `[review]` `[XS]`

**Assignee:** general

> Blocked by: Task 11

## Overview

Review the /maestro.clarify command.

## Task Reference

- **Reviews:** Task 11 - Create /maestro.clarify command

## Files to Review

- `.maestro/commands/maestro.clarify.md`

## Review Focus

- [ ] Interactive flow is clear and usable
- [ ] Proactive gap detection is reasonable
- [ ] State updates are atomic
- [ ] Edge cases handled (no markers, user skips questions)
- [ ] No implementation details creep into clarification

## Acceptance Criteria

- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 13. MST-001-007: Create plan template and /maestro.plan command `[backend]` `[M]`

**Assignee:** general

> Blocked by: Task 11

## Overview

Create the plan template and /maestro.plan command that generates a technical implementation plan from the specification.

## Context

The plan bridges the gap between the WHAT (spec) and the HOW (implementation). It defines architecture, component design, data model, API contracts, implementation phases, and testing strategy. It should be detailed enough to generate tasks from.

## Implementation Details

**Files:**

- `.maestro/templates/plan-template.md` - Technical plan template
- `.maestro/commands/maestro.plan.md` - Plan generation command

## Code Examples

```markdown
# Implementation Plan: {FEATURE_TITLE}

**Feature ID:** {FEATURE_ID}
**Spec:** {SPEC_PATH}
**Created:** {DATE}
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

{Describe how this feature fits into the existing architecture. Include a simple diagram if helpful.}

### 1.2 Component Interactions

{Show how components will interact. Consider sequence diagrams for complex flows.}

### 1.3 Key Design Decisions

{List important architectural decisions and their rationale.}

| Decision   | Options Considered | Chosen   | Rationale |
| ---------- | ------------------ | -------- | --------- |
| {decision} | {options}          | {chosen} | {why}     |

---

## 2. Component Design

### 2.1 New Components

{For each new component to be created:}

#### Component: {Name}

- **Purpose:** {one sentence}
- **Location:** {file path}
- **Dependencies:** {what it depends on}
- **Dependents:** {what will depend on it}

### 2.2 Modified Components

{For each existing component to be modified:}

#### Component: {Name}

- **Current:** {what it does now}
- **Change:** {what will change}
- **Risk:** {Low/Medium/High — potential for regression}

---

## 3. Data Model

### 3.1 New Entities

{For each new entity/table:}

#### Entity: {Name}
```

{Schema definition — language agnostic}

```

### 3.2 Modified Entities
{For each existing entity to be modified:}

#### Entity: {Name}
- **Current fields:** {list}
- **New fields:** {list}
- **Migration notes:** {any special migration considerations}

### 3.3 Data Flow
{Describe how data flows through the system}

---

## 4. API Contracts

### 4.1 New Endpoints/Methods
{For each new API endpoint or method:}

#### {METHOD} {path}
- **Purpose:** {one sentence}
- **Input:** {request schema}
- **Output:** {response schema}
- **Errors:** {possible error responses}

### 4.2 Modified Endpoints
{For existing endpoints being modified:}

#### {METHOD} {path}
- **Current behavior:** {what it does}
- **New behavior:** {what changes}
- **Breaking:** {Yes/No}

---

## 5. Implementation Phases

### Phase 1: {Name}
- **Goal:** {what this phase achieves}
- **Tasks:**
  - {task 1}
  - {task 2}
- **Deliverable:** {what can be demonstrated/tested}

### Phase 2: {Name}
- **Goal:** {what this phase achieves}
- **Dependencies:** {what must be done first}
- **Tasks:**
  - {task 1}
  - {task 2}
- **Deliverable:** {what can be demonstrated/tested}

{Continue for all phases}

---

## 6. Testing Strategy

### 6.1 Unit Tests
{What unit tests will be written}
- {test category 1}
- {test category 2}

### 6.2 Integration Tests
{What integration tests will be written}
- {test category 1}

### 6.3 End-to-End Tests
{What E2E tests will be written, if any}

### 6.4 Test Data
{What test data/fixtures are needed}

---

## 7. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| {risk} | {L/M/H} | {L/M/H} | {mitigation} |

---

## 8. Open Questions

{Any questions that arose during planning that need answers before implementation}
- {question 1}
- {question 2}
```

````markdown
---
description: >
  Generate a technical implementation plan from the feature specification.
  Creates architecture, component design, data model, API contracts, phases, and testing strategy.
argument-hint: [feature-id] (optional, defaults to most recent)
---

# maestro.plan

Generate an implementation plan for the feature.

## Step 1: Prerequisites Check

Run the prerequisite check:

```bash
bash .maestro/scripts/check-prerequisites.sh plan
```
````

If it fails, show the error and suggestion, then stop.

## Step 2: Find the Specification

If `$ARGUMENTS` contains a feature ID, use it. Otherwise, find the most recent feature in `.maestro/specs/`.

Read:

- The spec file: `.maestro/specs/{feature_id}/spec.md`
- The constitution: `.maestro/constitution.md` (if exists)
- The state: `.maestro/state/{feature_id}.json`

## Step 3: Validate Spec Readiness

Check for unresolved `[NEEDS CLARIFICATION]` markers:

- If found, warn the user and suggest running `/maestro.clarify` first
- Offer to proceed anyway with assumptions noted

## Step 4: Read the Plan Template

Read `.maestro/templates/plan-template.md`.

## Step 5: Generate the Plan

Fill in the template based on the spec and constitution.

**Rules for plan generation:**

1. **Architecture must be justified** — Every design decision should trace back to a requirement in the spec
2. **Be specific about files** — List actual file paths, not generic "create a service"
3. **Identify risks early** — Especially regression risks in modified components
4. **Phases should be deliverable** — Each phase produces something testable
5. **Testing is not optional** — Every component needs a testing strategy

If the spec is too vague to make architectural decisions, add items to "Open Questions" section and flag them.

## Step 6: Create Supporting Artifacts

If the plan includes:

- **API contracts** — Create `.maestro/specs/{feature_id}/contracts/` directory with contract files
- **Data model** — Create `.maestro/specs/{feature_id}/data-model.md` with detailed schema

## Step 7: Write the Plan

Write the completed plan to `.maestro/specs/{feature_id}/plan.md`.

## Step 8: Update State

Update `.maestro/state/{feature_id}.json`:

- Set `stage` to `plan`
- Add `plan_path` field
- Add `phases` count
- Add `components_new` and `components_modified` counts
- Add history entry

## Step 9: Report and Next Steps

Show the user:

1. Summary of the plan:
   - Number of phases
   - New components to create
   - Existing components to modify
   - Key risks identified
2. Any open questions that need resolution
3. Suggest: "Review the plan, then run `/maestro.tasks` to break it into bd issues."

---

**Remember:** The plan is a technical blueprint. It should be detailed enough that a developer unfamiliar with the feature could implement it correctly.

````

## Acceptance Criteria
- [ ] Plan template covers all RFC-002 sections
- [ ] Template is generic (no domain-specific content)
- [ ] Command reads spec and constitution
- [ ] Command validates spec has no unresolved markers (with override)
- [ ] Command creates contracts/ and data-model.md when relevant
- [ ] State JSON is updated
- [ ] Clear summary and next steps

---

### 14. Review: MST-001-007 `[review]` `[S]`

**Assignee:** general
> Blocked by: Task 13

## Overview
Review the plan template and /maestro.plan command.

## Task Reference
- **Reviews:** Task 13 - Create plan template and /maestro.plan command

## Files to Review
- `.maestro/templates/plan-template.md`
- `.maestro/commands/maestro.plan.md`

## Review Focus
- [ ] Template covers all required sections
- [ ] Template is domain-agnostic
- [ ] Command flow is logical
- [ ] State updates include all relevant fields
- [ ] Contracts and data-model creation is conditional

## Acceptance Criteria
- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 15. MST-001-008: Create /maestro.tasks command `[backend]` `[M]`

**Assignee:** general
> Blocked by: Task 13

## Overview
Create the tasks command that breaks the implementation plan into bd issues with proper dependencies, assignees, and estimates.

## Context
This command reads the plan and creates an epic with child tasks in bd. It handles idempotency (abort if tasks exist), assignee routing via config.yaml, size→minutes conversion, paired review tasks, PM validation gating, and offers dry-run mode.

## Implementation Details

**Files:**
- `.maestro/commands/maestro.tasks.md` - Task creation command

## Code Examples

```markdown
---
description: >
  Break the implementation plan into bd issues with dependencies.
  Creates an epic with implementation tasks, review tasks, and PM validation.
argument-hint: [feature-id] [--dry-run]
---

# maestro.tasks

Create bd issues from the implementation plan.

## Step 1: Prerequisites Check

Run the prerequisite check:
```bash
bash .maestro/scripts/check-prerequisites.sh tasks
````

If it fails, show the error and suggestion, then stop.

## Step 2: Find the Plan

If `$ARGUMENTS` contains a feature ID, use it. Otherwise, find the most recent feature.

Read:

- The plan: `.maestro/specs/{feature_id}/plan.md`
- The config: `.maestro/config.yaml`
- The state: `.maestro/state/{feature_id}.json`

## Step 3: Idempotency Check

Check if tasks already exist for this feature:

- If state.json has `epic_id` field → tasks exist
- Warn the user: "Tasks already exist for this feature (epic: {epic_id})"
- Show current task status: `bd show {epic_id} --children`
- Offer options:
  1. **Abort**: Stop and preserve existing tasks (default)
  2. **Regenerate**: Archive existing epic and create fresh tasks
- If user doesn't explicitly choose Regenerate, abort.

## Step 4: Parse the Plan

Extract from the plan:

1. **Feature title** — from the header
2. **Phases** — each implementation phase
3. **Components** — new and modified components
4. **Tests** — from testing strategy

Create a task list with:

- Title (imperative verb + what)
- Description (detailed implementation guidance)
- Size estimate (XS/S/M/L based on complexity)
- Label (backend/frontend/test based on type)
- Dependencies (which tasks must complete first)

## Step 5: Map Sizes and Assignees

Read from `.maestro/config.yaml`:

For each task:

1. Convert size to minutes using `size_mapping`
2. Determine assignee using `agent_routing[label]`
3. Determine review assignee using `agent_routing.review`
4. Calculate review size using `review_sizing`

## Step 6: Generate Task Table

Build a table of all tasks:

| #   | ID   | Title        | Label   | Size | Minutes | Assignee | Blocked By |
| --- | ---- | ------------ | ------- | ---- | ------- | -------- | ---------- |
| 1   | T001 | {title}      | backend | S    | 360     | {agent}  | —          |
| 2   | R001 | Review: T001 | review  | XS   | 120     | {agent}  | T001       |
| ... |

Include:

- Implementation tasks paired with review tasks
- Final PM-VAL task blocked by ALL review tasks

## Step 7: Dry Run Mode

If `$ARGUMENTS` contains `--dry-run`:

- Show the task table
- Show what commands would be executed
- Do NOT create any tasks
- Stop here

## Step 8: Create Epic

```bash
source .maestro/scripts/bd-helpers.sh
EPIC_ID=$(bd_create_epic "{feature_id}: {feature_title}" "{plan summary}")
```

Store the epic ID for later.

## Step 9: Create Tasks

For each task in the table:

```bash
TASK_ID=$(bd_create_task \
  "{task_title}" \
  "{task_description}" \
  "{label}" \
  {estimate_minutes} \
  "$EPIC_ID" \
  "{assignee}")
```

Store task IDs for dependency wiring.

## Step 10: Wire Dependencies

For each task with dependencies:

```bash
bd_add_dep "{dependent_task_id}" "{blocker_task_id}"
```

## Step 11: Update State

Update `.maestro/state/{feature_id}.json`:

- Add `epic_id` field
- Add `task_count` field
- Set `stage` to `tasks`
- Add history entry

## Step 12: Report Results

Show the user:

1. Epic created with ID
2. Task table with all created tasks
3. Dependency tree visualization (use `bd dep tree {epic_id}`)
4. Suggest: "Run `/maestro.orchestrate` to begin automated implementation, or `/maestro.implement T001` to implement a specific task."

---

**Task ID format:** `{feature_acronym}-{feature_number}-{task_number}` (e.g., MST-001-001)

**Review task pairing:** Every implementation task (backend/frontend/test) gets a paired review task blocked by it.

**PM Validation:** The final task, blocked by ALL review tasks, validates the entire feature.

````

## Acceptance Criteria
- [ ] Command reads plan and config correctly
- [ ] Idempotency check prevents duplicate task creation
- [ ] Tasks have correct sizes, assignees, and estimates from config
- [ ] Review tasks are paired with implementation tasks
- [ ] PM-VAL task is blocked by all reviews
- [ ] Dry-run mode shows plan without creating tasks
- [ ] Dependencies are wired correctly
- [ ] State JSON updated with epic_id

---

### 16. Review: MST-001-008 `[review]` `[S]`

**Assignee:** general
> Blocked by: Task 15

## Overview
Review the /maestro.tasks command.

## Task Reference
- **Reviews:** Task 15 - Create /maestro.tasks command

## Files to Review
- `.maestro/commands/maestro.tasks.md`

## Review Focus
- [ ] Idempotency logic is correct (abort vs regenerate)
- [ ] Config reading for sizes/assignees is accurate
- [ ] Review task pairing is consistent
- [ ] PM-VAL dependency calculation is correct
- [ ] Dry-run mode is useful
- [ ] bd commands are correctly structured

## Acceptance Criteria
- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 17. MST-001-009: Create /maestro.implement command `[backend]` `[M]`

**Assignee:** general
> Blocked by: Task 15

## Overview
Create the implement command that executes a single task via a spawned sub-agent with compile gate enforcement.

## Context
This command reads a task from bd, spawns a sub-agent based on the task's assignee field, provides ADDITIVE preservation instructions, and enforces compile gate passing before completion. The sub-agent reports results in a structured format.

## Implementation Details

**Files:**
- `.maestro/commands/maestro.implement.md` - Single task implementation command

## Code Examples

```markdown
---
description: >
  Implement a single task by spawning a specialized sub-agent.
  Reads task details from bd, routes to agent by assignee, enforces compile gate.
argument-hint: <task-id>
---

# maestro.implement

Implement task: **$ARGUMENTS**

## Step 1: Validate Task ID

`$ARGUMENTS` must contain a task ID. If empty:
- List ready tasks: `bd ready`
- Ask the user which task to implement
- Stop until they provide a task ID

## Step 2: Read Task Details

```bash
bd show $ARGUMENTS --json
````

Extract:

- `id` — task identifier
- `title` — task title
- `description` — full task description (includes files, code examples, acceptance criteria)
- `assignee` — agent to spawn
- `labels` — task type (backend, frontend, test, fix)
- `status` — should be "ready" or "in_progress"

If task is not ready (has blocking dependencies):

- Show blocking tasks: `bd blocked $ARGUMENTS`
- Tell user which tasks must complete first
- Stop

## Step 3: Mark Task In Progress

```bash
bd update $ARGUMENTS --status in_progress
```

## Step 4: Read Context Files

Read files mentioned in the task description. This gives the sub-agent context.

Also read:

- `.maestro/constitution.md` — for architectural constraints
- Project CLAUDE.md, AGENTS.md or README — for project-specific patterns

## Step 5: Spawn Implementation Agent

Spawn a sub-agent with the assignee type from the task:

```
Task(
  subagent_type="{assignee from task}",
  description="Implement: {task_title}",
  prompt="Implement the following task:

  Task ID: {task_id}
  Title: {task_title}

  ## Description
  {full task description from bd show}

  ## Files to Modify
  {files list from task description}

  ## Acceptance Criteria
  {criteria from task description}

  ## Constitution Constraints
  {relevant sections from constitution}

  ## Instructions
  1. Read the referenced files
  2. Implement the changes following any code examples provided
  3. CRITICAL — PRESERVE EXISTING FUNCTIONALITY:
     - Before modifying any file, read it fully and understand ALL existing
       features, handlers, switch cases, and registered routes/topics
     - Your task is ADDITIVE: add new code without removing or breaking
       existing code paths
     - If a file handles multiple entities/features, keep ALL of them intact
     - If you need to refactor a shared file, ensure every pre-existing
       behavior still works after your changes
     - When in doubt, ADD a new case/handler rather than replacing an
       existing one
  4. After implementing, you MUST run the compile gate:
     bash .maestro/scripts/compile-gate.sh
  5. If the compile gate fails, fix the errors and re-run until it passes
  6. Do NOT report your work as complete until the gate passes
  7. Ensure all acceptance criteria are met

  ## Output Format
  When complete, report using this exact format:
  DONE | files: {comma-separated list} | pattern: {pattern used} | ref: {reference file if any}

  If you cannot complete the task, report:
  BLOCKED | reason: {why} | needs: {what is needed}"
)
```

## Step 6: Parse Sub-Agent Result

Wait for the sub-agent to complete and parse the result:

**If DONE:**

- Extract files, pattern, ref
- Proceed to Step 7

**If BLOCKED:**

- Show the user why and what's needed
- Do NOT close the task
- Stop

## Step 7: Close Task

```bash
bd close $ARGUMENTS --reason "{sub-agent result}"
```

## Step 8: Report and Next Steps

Show the user:

1. Task completed: {task_id} - {title}
2. Files modified: {list}
3. Pattern used: {pattern}
4. Next ready tasks: `bd ready`
5. Suggest: "Run `/maestro.review {paired_review_id}` to review this task, or `/maestro.orchestrate` for automated workflow."

---

**Compile gate is mandatory.** The sub-agent must run the compile gate and fix any failures before reporting DONE. This is non-negotiable.

**ADDITIVE implementation.** Existing functionality must be preserved. This prevents regressions where an agent implements a new feature but breaks existing ones.

````

## Acceptance Criteria
- [ ] Command validates task ID is provided
- [ ] Task details read from bd correctly
- [ ] Task marked in_progress before work starts
- [ ] Sub-agent spawned with correct type from assignee field
- [ ] ADDITIVE preservation instruction is prominent
- [ ] Compile gate instruction is mandatory
- [ ] Structured output format is clear
- [ ] Task closed with structured reason
- [ ] BLOCKED case handled (task stays open)

---

### 18. Review: MST-001-009 `[review]` `[S]`

**Assignee:** general
> Blocked by: Task 17

## Overview
Review the /maestro.implement command.

## Task Reference
- **Reviews:** Task 17 - Create /maestro.implement command

## Files to Review
- `.maestro/commands/maestro.implement.md`

## Review Focus
- [ ] Agent routing uses assignee field correctly
- [ ] ADDITIVE instruction is clear and prominent
- [ ] Compile gate is mandatory (not optional)
- [ ] Structured output format is parseable
- [ ] BLOCKED handling doesn't close the task
- [ ] Constitution is injected into sub-agent

## Acceptance Criteria
- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 19. MST-001-010: Create review template and /maestro.review command `[backend]` `[M]`

**Assignee:** general
> Blocked by: Task 17

## Overview
Create the review template (JSON schema) and /maestro.review command that performs risk-based code review with convention injection.

## Context
This command routes reviews by risk level (HIGH/MEDIUM/LOW), injects global and local conventions, performs feature regression checks FIRST, and handles CRITICAL findings by creating fix tasks. It uses the cookbook/review-routing.md to classify files.

## Implementation Details

**Files:**
- `.maestro/templates/review-template.md` - JSON output schema for reviews
- `.maestro/commands/maestro.review.md` - Code review command
- `.maestro/cookbook/review-routing.md` - Risk classification table
- `.maestro/reference/conventions.md` - Global review conventions

## Code Examples

```markdown
# Review Output Schema

Reviews must output JSON in this exact format:

```json
{
  "verdict": "PASS | MINOR | CRITICAL",
  "issues": [
    {
      "severity": "CRITICAL | MINOR",
      "file": "path/to/file",
      "line": 42,
      "cause": "feature-regression | nil-pointer | wrong-error | missing-impl | etc",
      "description": "One sentence describing the issue"
    }
  ],
  "summary": "One sentence overall assessment"
}
````

## Verdict Definitions

- **PASS**: No issues found. Code is ready to merge.
- **MINOR**: Style, naming, or optimization suggestions. Does not block merge.
- **CRITICAL**: Must be fixed before merge. Includes: feature regression, security issues, data loss, incorrect logic.

## Cause Categories

| Cause              | Description                                         |
| ------------------ | --------------------------------------------------- |
| feature-regression | Removed existing functionality not required by task |
| nil-pointer        | Dereferencing potentially nil value                 |
| wrong-error        | Incorrect error comparison or handling              |
| missing-impl       | Required functionality not implemented              |
| missing-field      | Required field not included                         |
| security           | Security vulnerability                              |
| data-loss          | Potential data loss or corruption                   |
| breaking-change    | Unintended API breaking change                      |

## Issue Priority

When multiple issues exist:

1. List CRITICAL issues first
2. Within CRITICAL, list feature-regression first
3. Then list MINOR issues

````

```markdown
---
description: >
  Perform code review on a completed implementation task.
  Routes by risk level, injects conventions, checks for feature regression first.
argument-hint: <review-task-id>
---

# maestro.review

Review task: **$ARGUMENTS**

## Step 1: Read Review Task

```bash
bd show $ARGUMENTS --json
````

Extract:

- `id` — review task ID
- `title` — should start with "Review:"
- `description` — contains reference to implementation task
- `assignee` — reviewer agent

Find the implementation task ID from the description (the task this reviews).

## Step 2: Get Implementation Details

Read the implementation task to find what files were modified:

```bash
bd show {implementation_task_id} --json
```

Extract the close_reason to get the file list:

```
DONE | files: x.go,y.go | pattern: consumer | ref: z.go
```

## Step 3: Risk Classification

Read `.maestro/cookbook/review-routing.md` and classify each file:

- **HIGH RISK**: Always review (business logic, handlers, data access)
- **MEDIUM RISK**: Review if >50 lines changed
- **LOW RISK**: Skip review (generated, structs, mappings)

If ALL files are LOW RISK:

- Close the review task: `bd close $ARGUMENTS --reason "SKIPPED | risk: low | files: {list}"`
- Report to user and stop

Otherwise, proceed with review.

## Step 4: Load Conventions

Read conventions to inject into the reviewer:

1. **Global conventions**: `.maestro/reference/conventions.md`
2. **Local conventions**: Check for `## Review Conventions` section in project's CLAUDE.md

Local conventions take precedence over global ones.

## Step 5: Spawn Reviewer

```
Task(
  subagent_type="{assignee from task}",
  description="Review: {implementation_task_title}",
  prompt="You are reviewing code changes for: {task_title}

  ## Conventions to Apply

  ### Global Conventions
  {content from .maestro/reference/conventions.md}

  ### Local Conventions
  {content from CLAUDE.md ## Review Conventions if exists}

  Local conventions take precedence over global ones.

  ## Files to Review
  {file list with full paths}

  ## FEATURE REGRESSION CHECK (DO THIS FIRST)

  For every modified file, use `git diff HEAD~1 -- {file}` to detect REMOVED functionality:
  - Deleted switch cases, event handlers, or consumer registrations
  - Removed function calls, route registrations, or feature branches
  - Replaced a multi-entity handler with a single-entity one
  - Dropped imports that were serving existing features

  If ANY existing functionality was removed that is NOT explicitly required by the task description, flag it as CRITICAL with cause \"feature-regression\".

  Feature regressions are the #1 priority check. A passing review means nothing if it broke something else.

  ## Code Quality Review

  After the regression check, review for:
  - Error handling correctness
  - Edge case coverage
  - Security vulnerabilities
  - Performance issues
  - Code style (per conventions)

  ## Output

  Return ONLY valid JSON. No markdown, no preamble, no explanation.

  {review template JSON schema}
  "
)
```

## Step 6: Parse Review Result

Parse the JSON output from the reviewer.

**If PASS:**

```bash
bd close $ARGUMENTS --reason "PASS | files: {list} | layer: {layer}"
```

**If MINOR:**

```bash
bd close $ARGUMENTS --reason "MINOR | files: {list} | note: {summary}"
```

**If CRITICAL:**
Do NOT close the review task yet. Proceed to Step 7.

## Step 7: Handle CRITICAL Issues

For each CRITICAL issue:

1. Create a fix task:

```bash
bd create \
  --title="Fix: {issue description}" \
  --parent={implementation_task_id} \
  --labels=fix \
  --description="CRITICAL from review {review_id}:

  File: {file}
  Line: {line}
  Cause: {cause}
  Description: {description}

  ## Instructions
  Fix this issue while maintaining all existing functionality.
  After fixing, run compile gate: bash .maestro/scripts/compile-gate.sh"
```

2. Implement the fix:

```
/maestro.implement {fix_task_id}
```

3. Re-run the review (go back to Step 5)

**Fix-Review Loop:** Continue until review returns PASS or MINOR.

## Step 8: Report Results

Show the user:

1. Review verdict: {PASS/MINOR/CRITICAL}
2. Issues found (if any)
3. Fix tasks created (if any)
4. Next ready tasks
5. If all reviews complete, suggest `/maestro.pm-validate`

---

**Feature regression check is non-negotiable.** It happens FIRST, before any other review activity. This was learned from production incidents where agents implemented new features but broke existing ones.

````

## Acceptance Criteria
- [ ] Review template defines JSON schema clearly
- [ ] Command reads implementation task details
- [ ] Risk classification uses cookbook/review-routing.md
- [ ] LOW risk files are skipped (task closed as SKIPPED)
- [ ] Conventions injected from global and local sources
- [ ] Feature regression check is FIRST and prominent
- [ ] CRITICAL issues create fix tasks
- [ ] Fix-review loop continues until PASS/MINOR
- [ ] Structured close reasons for all outcomes

---

### 20. Review: MST-001-010 `[review]` `[S]`

**Assignee:** general
> Blocked by: Task 19

## Overview
Review the review template and /maestro.review command.

## Task Reference
- **Reviews:** Task 19 - Create review template and /maestro.review command

## Files to Review
- `.maestro/templates/review-template.md`
- `.maestro/commands/maestro.review.md`
- `.maestro/cookbook/review-routing.md`
- `.maestro/reference/conventions.md`

## Review Focus
- [ ] JSON schema is valid and complete
- [ ] Risk routing logic matches requirements
- [ ] Conventions injection works for both global and local
- [ ] Feature regression check is FIRST
- [ ] Fix task creation is correct
- [ ] Fix-review loop is bounded (avoids infinite loops)
- [ ] All close reason formats are consistent

## Acceptance Criteria
- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 21. MST-001-011: Create /maestro.pm-validate command `[backend]` `[M]`

**Assignee:** general
> Blocked by: Task 19

## Overview
Create the PM validation command that performs regression scan first, then requirements validation, with structured output and escalation handling.

## Context
This is the final gate before a feature is considered complete. It runs a regression scan FIRST (git diff for removed functionality), then validates all requirements are met. It has 3-round escalation for GAPS_FOUND and no round limit for REGRESSION.

## Implementation Details

**Files:**
- `.maestro/commands/maestro.pm-validate.md` - PM validation command
- `.maestro/skills/pm-validation/SKILL.md` - PM validation skill

## Code Examples

```markdown
---
description: >
  Final validation gate for feature completion.
  Performs regression scan FIRST, then requirements validation.
  Escalates after 3 rounds of GAPS_FOUND. No limit for REGRESSION.
argument-hint: [feature-id]
---

# maestro.pm-validate

Validate feature completion.

## Step 1: Find the Feature

If `$ARGUMENTS` contains a feature ID, use it. Otherwise, find the most recent feature.

Read:
- The spec: `.maestro/specs/{feature_id}/spec.md`
- The state: `.maestro/state/{feature_id}.json`
- The config: `.maestro/config.yaml`

Get the epic ID from state.json and verify all review tasks are complete:
```bash
bd show {epic_id} --children --json
````

If any review tasks are still open, tell the user and stop.

## Step 2: Check Validation Round

Read the validation round from state.json (default: 1).

If round > 3 and verdict was GAPS_FOUND:

- Output: "PM validation failed after 3 rounds. Human intervention required."
- Stop

If verdict was REGRESSION:

- No round limit — regressions must be fixed

## Step 3: Spawn PM Validator

```
Task(
  subagent_type="pm-feature-validator",
  description="Validate: {feature_title}",
  prompt="Validate the feature: {feature_title}

  ## Spec
  {full spec content}

  ## Implementation Summary
  {list of tasks completed with close reasons}

  ## PHASE 1: REGRESSION SCAN (DO THIS FIRST)

  Run `git diff {base_branch}...HEAD` to get ALL files modified during this feature.

  For each modified file, scan the diff for REMOVED functionality:
  - Deleted switch cases, event handlers, or consumer registrations
  - Removed function definitions or method implementations
  - Dropped route/topic registrations
  - Narrowed logic (e.g., multi-entity handler replaced with single-entity)

  For each removal found, check whether ANY task in the epic explicitly required it.
  If a removal is not justified by any task description, it is a regression.

  If regressions are found, set verdict to REGRESSION regardless of whether the new
  feature's acceptance criteria are met. Regressions take priority over everything else.

  ## PHASE 2: REQUIREMENTS VALIDATION

  Check all acceptance criteria from the spec:

  {acceptance criteria from spec}

  For each criterion:
  1. Find evidence in the implemented code
  2. Verify the implementation matches the requirement
  3. Note any gaps or partial implementations

  ## OUTPUT

  Return ONLY this JSON. No markdown, no preamble:

  {
    \"verdict\": \"COMPLETE | GAPS_FOUND | BLOCKED | REGRESSION\",
    \"regressions\": [
      {
        \"file\": \"path/to/file\",
        \"removed\": \"What was removed\",
        \"impact\": \"Which existing feature this breaks\",
        \"justified\": false
      }
    ],
    \"requirements\": [
      {
        \"id\": \"REQ-1\",
        \"description\": \"Requirement text\",
        \"status\": \"MET | PARTIAL | NOT_MET | BLOCKED\",
        \"evidence\": \"What satisfies or is missing\",
        \"files\": [\"path/to/file\"]
      }
    ],
    \"follow_up_tasks\": [
      {
        \"title\": \"Task title\",
        \"description\": \"What needs to be done\",
        \"priority\": \"HIGH | MEDIUM | LOW\"
      }
    ],
    \"summary\": \"One sentence overall assessment\"
  }"
)
```

## Step 4: Handle Validator Response

Parse the JSON output.

**If REGRESSION (highest priority):**

```bash
bd close {pm_val_task_id} --reason "REGRESSION | files: {list} | impact: {feature}"
```

For each regression:

- Create a high-priority fix task to restore the functionality
- These fixes have no round limit — must be resolved

Create a new pm-validation task blocked by the fix tasks.

**If COMPLETE:**

```bash
bd close {pm_val_task_id} --reason "COMPLETE | requirements: {met}/{total} | regressions: 0"
```

Update state.json: set `stage` to `complete`.

**If GAPS_FOUND (round 1-2):**

```bash
bd close {pm_val_task_id} --reason "GAPS_FOUND | requirements: {met}/{total} | gaps: {list}"
```

Create fix tasks from follow_up_tasks array.
Increment validation round in state.json.
Create new pm-validation task for next round.

**If GAPS_FOUND (round 3):**
Output: "PM validation failed after 3 rounds. Human intervention required."
Close the task and stop orchestration.

**If BLOCKED:**
Show what's blocking and stop.

## Step 5: Report Results

Show the user:

1. Validation verdict
2. Regressions found (if any) — with impact
3. Requirements status (met/partial/not_met)
4. Follow-up tasks created (if any)
5. Current validation round

If COMPLETE:

- Congratulate! Feature is done.
- Suggest: "Run `/maestro.analyze` for post-epic learning."

---

**Regression scan is mandatory and happens FIRST.** A feature that meets all requirements but breaks existing functionality is NOT complete.

````

```markdown
# PM Validation Skill

Specialized skill for final feature validation.

## Purpose

The PM validator ensures:
1. No existing functionality was regressed
2. All acceptance criteria from the spec are met
3. Implementation matches the "what" without diverging into scope creep

## Core Principles

### Regression Takes Priority

If ANY existing functionality was removed without explicit justification, the verdict is REGRESSION. This overrides everything else. A feature that works perfectly but breaks something else is a failure.

### Evidence-Based Validation

Every requirement check must cite specific evidence:
- File paths where implementation exists
- Code that satisfies the criterion
- Tests that verify the behavior

"It should work" is not evidence. "Line 42 of handler.go calls SendNotification()" is evidence.

### Scope Discipline

The validator checks that the implementation matches the spec — no more, no less:
- Missing scope → GAPS_FOUND
- Extra scope (gold plating) → Note it, but not a failure
- Deviated scope (did something different) → GAPS_FOUND with explanation

## Validation Workflow

1. **Regression scan** (git diff analysis)
2. **Requirements mapping** (spec → code)
3. **Evidence collection** (specific citations)
4. **Verdict determination** (COMPLETE/GAPS_FOUND/REGRESSION/BLOCKED)
5. **Follow-up generation** (fix tasks for gaps)

## Escalation Rules

| Verdict | Round 1 | Round 2 | Round 3 | Round 4+ |
|---------|---------|---------|---------|----------|
| GAPS_FOUND | Create fixes | Create fixes | ESCALATE to human | N/A |
| REGRESSION | Create fixes | Create fixes | Create fixes | Continue until fixed |

Regressions have no round limit because they represent broken functionality that must be restored.
````

## Acceptance Criteria

- [ ] Regression scan happens FIRST
- [ ] All spec requirements are validated with evidence
- [ ] Verdicts match requirements: COMPLETE/GAPS_FOUND/BLOCKED/REGRESSION
- [ ] 3-round escalation for GAPS_FOUND
- [ ] No round limit for REGRESSION
- [ ] Fix tasks created for gaps and regressions
- [ ] State JSON updated correctly
- [ ] Skill file provides clear guidance

---

### 22. Review: MST-001-011 `[review]` `[S]`

**Assignee:** general

> Blocked by: Task 21

## Overview

Review the /maestro.pm-validate command and skill.

## Task Reference

- **Reviews:** Task 21 - Create /maestro.pm-validate command

## Files to Review

- `.maestro/commands/maestro.pm-validate.md`
- `.maestro/skills/pm-validation/SKILL.md`

## Review Focus

- [ ] Regression scan is FIRST and comprehensive
- [ ] Round counting logic is correct
- [ ] Escalation at round 3 for GAPS_FOUND
- [ ] No round limit for REGRESSION
- [ ] JSON output schema matches review template
- [ ] State updates are atomic
- [ ] Skill provides actionable guidance

## Acceptance Criteria

- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 23. MST-001-012: Create /maestro.orchestrate command `[backend]` `[M]`

**Assignee:** general

> Blocked by: Task 21

## Overview

Create the orchestrate command that automates the full implementation loop: get ready tasks, assess parallelism, route by label, spawn sub-agents, track progress, and trigger post-epic analysis.

## Context

This is the main automation driver. It never implements directly — always spawns sub-agents. It can run up to 3 tasks in parallel when they're independent. It routes by label (implement/review/pm-validate) and continues until all tasks are closed.

## Implementation Details

**Files:**

- `.maestro/commands/maestro.orchestrate.md` - Orchestration command

## Code Examples

````markdown
---
description: >
  Automated orchestration loop for executing features.
  Gets ready tasks, routes by label, spawns sub-agents, tracks progress.
  Never implements directly — always delegates.
argument-hint: [feature-id]
---

# maestro.orchestrate

Orchestrate feature implementation.

## Step 1: Find the Feature

If `$ARGUMENTS` contains a feature ID, use it. Otherwise, find the most recent feature.

Read the state: `.maestro/state/{feature_id}.json`
Get the epic ID.

## Step 2: Get Ready Tasks

```bash
bd ready --json
```
````

Parse the ready tasks for this epic.

**If no tasks are ready:**

- Check blocked tasks: `bd blocked`
- If all tasks are closed → Go to Step 7 (Post-Epic Analysis)
- If tasks are blocked → Show what's blocking and wait

**If 1 task is ready:**

- Proceed to Step 3 with that task

**If 2+ tasks are ready:**

- Assess parallelism (Step 2b)

## Step 2b: Assess Parallelism

Check if ready tasks can be executed in parallel.

**Independence criteria (ALL must be true for a pair):**

- Tasks target different directories/modules
- No shared file paths in task descriptions
- No dependency relationship between them
- Both are implementation tasks (not reviews)

**Parallel execution rules:**

- Maximum 3 concurrent sub-agents
- Same-directory tasks run sequentially
- Reviews run after their implementation completes
- PM-validation runs after all reviews complete

**Example parallel scenarios:**

- Implementation tasks in different modules → Parallel
- Implementation + its review → Sequential
- Two reviews for independent implementations → Parallel

## Step 3: Route by Label

For each ready task, determine the handler:

| Label                                  | Handler                        |
| -------------------------------------- | ------------------------------ |
| backend, frontend, test, fix, refactor | `/maestro.implement {task_id}` |
| review                                 | `/maestro.review {task_id}`    |
| pm-validation                          | `/maestro.pm-validate`         |

## Step 4: Execute Tasks

**Sequential execution (1 task or dependent tasks):**

```
/maestro.implement {task_id}
```

Wait for completion, then continue.

**Parallel execution (independent tasks):**
Spawn multiple sub-agents in ONE message using Task() calls:

```
Task(description="Implement T001", prompt="...")
Task(description="Implement T003", prompt="...")
```

Process results as they return.

## Step 5: Track Progress

After each task completes, show progress:

```bash
bd stats
```

Display:

- Tasks completed / total
- Current stage (implementing / reviewing / validating)
- Estimated time remaining (based on remaining estimates)

## Step 6: Continue Loop

Go back to Step 2.

The loop continues until:

- All tasks are closed → Go to Step 7
- Human intervention required (3 rounds of GAPS_FOUND)
- Unresolvable blocker found

## Step 7: Post-Epic Analysis

When all tasks are closed:

```
/maestro.analyze {feature_id}
```

This triggers the learning loop that:

1. Collects metrics from close reasons
2. Computes patterns and bug rates
3. Proposes improvements
4. Presents for human approval

## Step 8: Report Completion

Show the user:

1. Feature completed: {feature_title}
2. Total tasks: {count}
3. Implementation time: {duration}
4. Reviews: {passed} / {total}
5. Fix tasks created: {count}
6. Regressions found: {count}

Suggest next steps:

- Create PR
- Deploy to staging
- Start next feature

---

## Orchestrator Rules

1. **Never implement directly** — ALL tasks are executed by spawning agents
2. **Parallel when possible** — Execute independent tasks across modules in parallel
3. **Route by label** — Check task label to determine handler
4. **Compile gate is mandatory** — Delegated to sub-agents
5. **Fix tasks need reviews** — Create implementation + review pair for CRITICAL findings
6. **Structured close reasons** — Every task close uses the standard format

````

## Acceptance Criteria
- [ ] Gets ready tasks from bd
- [ ] Parallelism assessment works correctly
- [ ] Routes by label to correct handler
- [ ] Never implements directly (always spawns)
- [ ] Progress tracking is visible
- [ ] Loop continues until all tasks closed
- [ ] Post-epic analysis triggered at end
- [ ] Clear completion report

---

### 24. Review: MST-001-012 `[review]` `[S]`

**Assignee:** general
> Blocked by: Task 23

## Overview
Review the /maestro.orchestrate command.

## Task Reference
- **Reviews:** Task 23 - Create /maestro.orchestrate command

## Files to Review
- `.maestro/commands/maestro.orchestrate.md`

## Review Focus
- [ ] Ready task fetching is correct
- [ ] Parallelism criteria are sound
- [ ] Label routing is complete (all labels covered)
- [ ] "Never implement directly" rule is enforced
- [ ] Loop termination conditions are clear
- [ ] Post-epic trigger is correct
- [ ] Progress tracking is useful

## Acceptance Criteria
- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 25. MST-001-013: Create /maestro.commit command `[backend]` `[S]`

**Assignee:** general
> Blocked by: Task 3

## Overview
Create the commit command that performs layer-separated atomic commits from staged changes.

## Context
This command groups staged changes by architectural layer, proposes a commit plan with inner→outer ordering, waits for user confirmation, and executes the commits. It never stages additional files and never pushes.

## Implementation Details

**Files:**
- `.maestro/commands/maestro.commit.md` - Layer-separated commit command

## Code Examples

```markdown
---
description: >
  Create layer-separated atomic commits from staged changes.
  Groups by architectural layer, proposes plan, waits for confirmation.
  Never stages additional files. Never pushes.
argument-hint: [--auto to skip confirmation]
---

# maestro.commit

Create layer-separated commits.

## Step 1: Check Staged Changes

```bash
git diff --cached --name-only
````

If no staged changes:

- Tell the user: "No staged changes. Stage files with `git add` first."
- Stop

## Step 2: Classify Files by Layer

Read the constitution (`.maestro/constitution.md`) to understand the project's layer structure.

If no constitution, use default layers:

1. **data** — Database migrations, schemas, models
2. **domain** — Business logic, entities, value objects
3. **application** — Use cases, commands, queries
4. **infrastructure** — External services, repositories, messaging
5. **presentation** — API, UI, handlers, controllers
6. **test** — Test files
7. **config** — Configuration files

Classify each staged file into a layer based on:

- File path patterns
- Directory names
- File extensions

## Step 3: Determine Commit Order

Order commits from innermost to outermost layer:

1. data (migrations first — they're prerequisites)
2. domain (pure business logic)
3. application (orchestrates domain)
4. infrastructure (depends on domain/application)
5. presentation (depends on everything)
6. test (tests the above)
7. config (configuration changes)

This ensures each commit is independently deployable and dependencies are satisfied.

## Step 4: Generate Commit Messages

For each layer with changes, draft a commit message:

```
{emoji} {layer}: {summary}

{optional body with details}
```

Layer emojis:

- 📊 data
- 🏛️ domain
- ⚙️ application
- 🔧 infrastructure
- 🎨 presentation
- ✅ test
- 🔧 config

Message rules:

- Imperative mood ("Add X" not "Added X")
- First line ≤ 72 characters
- Focus on WHY, not WHAT (the diff shows WHAT)

## Step 5: Present Commit Plan

Show the proposed commits:

```
## Commit Plan

1. 📊 data: Add vendor_status column to vendors table
   - migrations/20240115_add_vendor_status.sql

2. 🏛️ domain: Add VendorStatus enum and validation
   - internal/domain/vendor/status.go

3. ⚙️ application: Add UpdateVendorStatus command
   - internal/app/commands/update_vendor_status.go

4. 🔧 infrastructure: Implement status update in repository
   - internal/infra/repo/vendor_repo.go

5. ✅ test: Add vendor status tests
   - internal/domain/vendor/status_test.go
   - internal/app/commands/update_vendor_status_test.go

Execute this plan? [y/N/edit]
```

## Step 6: Wait for Confirmation

If `$ARGUMENTS` contains `--auto`:

- Skip confirmation, proceed to Step 7

Otherwise:

- Wait for user input
- **y/yes**: Proceed to Step 7
- **n/no**: Abort
- **edit**: Let user modify the plan (change messages, reorder, combine)

## Step 7: Execute Commits

For each commit in order:

```bash
# Unstage all first
git reset HEAD

# Stage only files for this commit
git add {files for this layer}

# Commit with message
git commit -m "{commit message}"
```

After each commit, verify it succeeded.

## Step 8: Report Results

Show the user:

1. Commits created: {count}
2. Files committed: {total}
3. Branch: {current branch}
4. Last commit: {SHA}

Remind:

- "Run `git push` to push to remote when ready."
- "Commits are NOT pushed automatically."

---

## Rules

1. **Never stage additional files** — Only work with what's already staged
2. **Never push** — User decides when to push
3. **Wait for confirmation** — Unless --auto flag
4. **Inner→outer order** — Dependencies satisfied in each commit
5. **Each commit is atomic** — Single layer, single purpose

````

## Acceptance Criteria
- [ ] Only works with staged changes (never stages new files)
- [ ] Classifies files by architectural layer
- [ ] Orders commits inner→outer (data→presentation)
- [ ] Generates meaningful commit messages
- [ ] Shows plan and waits for confirmation (unless --auto)
- [ ] Never pushes automatically
- [ ] Each commit is atomic (one layer)

---

### 26. Review: MST-001-013 `[review]` `[XS]`

**Assignee:** general
> Blocked by: Task 25

## Overview
Review the /maestro.commit command.

## Task Reference
- **Reviews:** Task 25 - Create /maestro.commit command

## Files to Review
- `.maestro/commands/maestro.commit.md`

## Review Focus
- [ ] Layer classification is reasonable
- [ ] Commit order is correct (inner→outer)
- [ ] Confirmation flow is clear
- [ ] "Never stage" and "never push" rules are explicit
- [ ] Commit message format is consistent
- [ ] --auto flag works correctly

## Acceptance Criteria
- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 27. MST-001-014: Create /maestro.analyze command `[backend]` `[M]`

**Assignee:** general
> Blocked by: Task 23

## Overview
Create the analyze command that performs post-epic learning: collects metrics, computes patterns, generates improvement proposals, and presents for human approval.

## Context
This is the learning loop that makes Maestro better over time. It collects data from structured close reasons, computes bug rates and patterns, proposes changes to existing artifacts (risk tables, conventions) and new artifacts (commands, skills, agents), with minimum thresholds to avoid noise.

## Implementation Details

**Files:**
- `.maestro/commands/maestro.analyze.md` - Post-epic analysis command
- `.maestro/cookbook/post-epic-analysis.md` - Analysis workflow

## Code Examples

```markdown
---
description: >
  Post-epic learning: collect metrics, compute patterns, generate improvement proposals.
  Presents proposals for human approval. Never auto-applies.
argument-hint: [feature-id]
---

# maestro.analyze

Analyze the completed epic and propose improvements.

## Step 1: Collect Data

Find the epic and gather all closed tasks:

```bash
bd list --all --parent {epic_id} --json --limit 0
````

Group tasks by label:

- Implementation tasks (backend, frontend, test)
- Review tasks (review)
- Fix tasks (fix)
- PM validation tasks (pm-validation)

## Step 2: Parse Close Reasons

For each task, parse the `close_reason` field:

```
"VERDICT | key: value | key: value"
```

Extract structured data:

- `verdict` — PASS, MINOR, CRITICAL, FIXED, DONE, SKIPPED, etc.
- `files` — which files were touched
- `layer` — architectural layer
- `cause` — bug category
- `pattern` — implementation pattern
- `ref` — reference file used

Build a dataset for analysis.

## Step 3: Compute Metrics

### Review Metrics

- Count by verdict: PASS / MINOR / CRITICAL / SKIPPED
- Calculate skip rate: SKIPPED / total reviews
- Group CRITICAL by layer → bug rate per layer
- Count FALSE_POSITIVE on fix tasks → review accuracy

### Fix Chain Metrics

- Group by cause → cause distribution
- Count total fix chains (fix → review → fix cycles)
- Identify repeat causes (same cause 3+ times)

### Implementation Metrics

- Group by pattern → pattern frequency
- Group by ref → most-used reference files
- Cross-reference: which patterns had fix chains?

### Regression Metrics

- Count regressions detected by reviewer
- Count regressions detected by PM validator
- Track which layer caught it first
- Identify fragile files (multiple regressions)

## Step 4: Generate Proposals

Based on the metrics, generate improvement proposals:

### A. Existing Artifact Changes

**Risk Reclassification** (threshold: 5+ data points):

- Layer with 0% bug rate → propose demotion to LOW
- Layer with >30% bug rate → confirm HIGH

**Convention Updates** (threshold: 2+ bugs from same cause):

- Propose new convention entry in `reference/conventions.md`

**Checklist Updates** (threshold: 2+ preventable bugs):

- Propose checklist item in orchestrator prompt

### B. New Artifact Proposals

**New Commands** (threshold: 3+ repetitions of same workflow):

- Include: detection evidence, skeleton file, expected savings
- Example: `/fix-chain` for automating fix-review-close

**New Skills** (threshold: 5+ implementations with same pattern):

- Include: detection evidence, SKILL.md skeleton, reference file
- Example: `consumer-scaffold` for repeated handler creation

**New Agents** (threshold: 10+ spawns with same context OR 1+ false positive from missing context):

- Include: detection evidence, what it wraps, what it auto-injects
- Example: specialized reviewer with domain conventions baked in

## Step 5: Present for Approval

For each proposal, show:

```
## Proposal {N}: {Type}

### What Changes
{file path + diff or skeleton}

### Why
{data that motivated it — task IDs, counts, percentages}

### Expected Impact
{estimated savings or quality improvement}

### Approve?
[yes/no/skip]
```

Human approves/rejects each independently. Never auto-apply.

## Step 6: Apply Approved Changes

For approved proposals:

- Edit existing files (add convention entries, update risk tables)
- Create new files (commands, skills, agents)
- Update documentation

## Step 7: Report Summary

Show the user:

1. Epic analyzed: {feature_id}
2. Tasks reviewed: {count}
3. Metrics computed:
   - Review pass rate: {X}%
   - Bug rate: {Y} per 100 tasks
   - Top causes: {list}
4. Proposals generated: {count}
5. Proposals approved: {count}
6. Changes applied: {list}

---

## Minimum Thresholds

These thresholds prevent noise from small sample sizes:

| Proposal Type         | Minimum Data Points                  |
| --------------------- | ------------------------------------ |
| Risk reclassification | 5+ reviews of that layer             |
| New convention entry  | 2+ bugs from same cause              |
| Checklist item        | 2+ preventable bugs                  |
| New command           | 3+ repetitions of workflow           |
| New skill             | 5+ implementations with same pattern |
| New agent             | 10+ spawns OR 1+ false positive      |

Proposals that don't meet thresholds are noted but not presented.

````

## Acceptance Criteria
- [ ] Collects data from all epic tasks
- [ ] Parses structured close reasons correctly
- [ ] Computes all metric categories
- [ ] Generates proposals with evidence
- [ ] Respects minimum thresholds
- [ ] Presents each proposal independently
- [ ] Never auto-applies (requires human approval)
- [ ] Applies approved changes correctly

---

### 28. Review: MST-001-014 `[review]` `[S]`

**Assignee:** general
> Blocked by: Task 27

## Overview
Review the /maestro.analyze command.

## Task Reference
- **Reviews:** Task 27 - Create /maestro.analyze command

## Files to Review
- `.maestro/commands/maestro.analyze.md`
- `.maestro/cookbook/post-epic-analysis.md`

## Review Focus
- [ ] Data collection is comprehensive
- [ ] Close reason parsing handles all formats
- [ ] Metrics computation is correct
- [ ] Proposal generation uses correct thresholds
- [ ] Human approval is mandatory
- [ ] Change application is safe
- [ ] Thresholds prevent noise

## Acceptance Criteria
- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 29. MST-001-015: Create constitution skill `[backend]` `[S]`

**Assignee:** general
> Blocked by: Task 7

## Overview
Create the constitution enforcement skill that helps agents understand and apply constitutional constraints.

## Context
The constitution skill is loaded by agents when they need to understand project constraints. It provides guidance on how to read and apply the constitution in different contexts (specification, planning, implementation, review).

## Implementation Details

**Files:**
- `.maestro/skills/constitution/SKILL.md` - Constitution enforcement skill

## Code Examples

```markdown
---
name: constitution
description: >
  Constitution enforcement skill for understanding and applying
  project constraints during specification, planning, implementation, and review.
---

# Constitution Skill

The constitution defines the rules that govern all work in this project. Load this skill when you need to understand or enforce these rules.

## When to Load This Skill

- `/maestro.specify` — Ensure spec respects architectural boundaries
- `/maestro.plan` — Ensure design follows constitutional patterns
- `/maestro.implement` — Ensure code follows standards and layer rules
- `/maestro.review` — Check that implementation respects constraints

## How to Use the Constitution

### 1. Read the Constitution

The constitution is at `.maestro/constitution.md`. Read it fully before starting work.

### 2. Extract Relevant Sections

Based on your task, focus on:

| Task Type | Relevant Sections |
|-----------|-------------------|
| Specification | Architecture Principles, Domain-Specific Rules |
| Planning | All sections |
| Implementation | Code Standards, Layer Separation, Dependency Rules |
| Review | Review Requirements, Error Handling, Testing Standards |

### 3. Apply Constraints

**During specification:**
- Ensure features align with architectural principles
- Flag anything that violates domain constraints
- Note security requirements that need consideration

**During planning:**
- Design within the allowed layer dependencies
- Follow the communication patterns defined
- Apply error handling and testing standards

**During implementation:**
- Follow code standards for the language
- Respect layer boundaries (no forbidden imports)
- Apply error handling patterns
- Write tests as required

**During review:**
- Check that implementation matches constitutional rules
- Verify layer boundaries are respected
- Ensure required reviews/approvals are obtained
- Check for "out of scope" items that shouldn't have been done

## Common Constitutional Checks

### Layer Boundary Check
1. Read the dependency rules section
2. For each import/dependency in the code, verify it's allowed
3. Flag imports that cross forbidden boundaries

### Error Handling Check
1. Read the error handling section
2. Verify errors are wrapped with context
3. Verify error comparison uses correct methods
4. Verify errors bubble up correctly

### Testing Standards Check
1. Read the testing standards section
2. Verify coverage requirements are met
3. Verify test naming conventions
4. Verify happy path and edge cases are covered

### Security Check
1. Read the security requirements section
2. Verify no hardcoded secrets
3. Verify PII handling
4. Verify authentication/authorization

## Example: Checking a Go File

```go
// Check 1: Is this package allowed to import that package?
import "internal/infrastructure/repo" // <- From domain layer?

// Read constitution:
// "Domain layer must not import Infrastructure layer"
// This is a CRITICAL violation.

// Check 2: Error handling
if err != nil {
    return err  // <- No context added
}
// Read constitution:
// "Error wrapping should add context at layer boundaries"
// This is a MINOR issue.
````

## Escalation

If you find a situation not covered by the constitution:

1. Flag it as an open question
2. Suggest the constitution be updated
3. Proceed with best judgment but note the assumption

The constitution evolves. If you encounter gaps, they should be filled.

````

## Acceptance Criteria
- [ ] Skill explains when to load it
- [ ] Clear guidance for each task type
- [ ] Common checks are actionable
- [ ] Example shows practical application
- [ ] Escalation path for gaps is defined
- [ ] Language-agnostic (not Go-specific)

---

### 30. Review: MST-001-015 `[review]` `[XS]`

**Assignee:** general
> Blocked by: Task 29

## Overview
Review the constitution skill.

## Task Reference
- **Reviews:** Task 29 - Create constitution skill

## Files to Review
- `.maestro/skills/constitution/SKILL.md`

## Review Focus
- [ ] Skill is actionable and practical
- [ ] Coverage of all task types
- [ ] Examples are language-agnostic
- [ ] Escalation path is clear
- [ ] Not too verbose (agents can load it)

## Acceptance Criteria
- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 31. MST-001-016: Create review skill `[backend]` `[S]`

**Assignee:** general
> Blocked by: Task 19

## Overview
Create the review skill that provides code review patterns and convention injection guidance.

## Context
The review skill is loaded by reviewer agents. It provides the review framework, feature regression detection checklist, convention injection patterns, and structured output guidance.

## Implementation Details

**Files:**
- `.maestro/skills/review/SKILL.md` - Code review skill

## Code Examples

```markdown
---
name: review
description: >
  Code review skill providing patterns, conventions, and structured output.
  Loaded by reviewer agents during /maestro.review.
---

# Review Skill

This skill guides code reviewers through structured, convention-aware review.

## Review Priority Order

1. **Feature Regression** (CRITICAL) — Did existing functionality get removed?
2. **Security Issues** (CRITICAL) — Authentication, authorization, data exposure
3. **Data Integrity** (CRITICAL) — Data loss, corruption, incorrect persistence
4. **Error Handling** (CRITICAL/MINOR) — Nil checks, error wrapping, recovery
5. **Logic Correctness** (CRITICAL/MINOR) — Does it do what it's supposed to?
6. **Code Quality** (MINOR) — Style, naming, structure, comments

## Feature Regression Detection

This is the #1 priority. Before reviewing anything else, check for removed functionality.

### Detection Checklist

For each modified file, run `git diff HEAD~1 -- {file}` and check:

- [ ] No deleted `case` branches in switch statements
- [ ] No removed handler/consumer registrations
- [ ] No dropped function calls that served existing features
- [ ] No narrowed implementations (multi-entity → single-entity)
- [ ] No removed imports that served existing code
- [ ] No deleted method implementations

### How to Check

1. Look at the `-` (removed) lines in the diff
2. For each removed line with logic, ask: "Does the task require this removal?"
3. If not required → CRITICAL with cause "feature-regression"

### Example

```diff
- case Notification:
-   return handleNotification(ctx, event)
+ case AuditLog:
+   return handleAuditLog(ctx, event)
````

If the task was "Add audit logging", the notification case should NOT be removed. This is a feature regression.

## Convention Injection

Before reviewing, load conventions:

1. **Global**: `.maestro/reference/conventions.md`
2. **Local**: Project's CLAUDE.md `## Review Conventions` section

Local conventions take precedence.

### Convention Application

For each convention:

1. Check if it applies to the files being reviewed
2. Verify compliance
3. Flag violations appropriately (CRITICAL or MINOR based on convention severity)

## Structured Output

Always output JSON in this format:

```json
{
  "verdict": "PASS | MINOR | CRITICAL",
  "issues": [
    {
      "severity": "CRITICAL | MINOR",
      "file": "path/to/file",
      "line": 42,
      "cause": "feature-regression | nil-pointer | ...",
      "description": "One sentence"
    }
  ],
  "summary": "One sentence overall"
}
```

### Verdict Rules

- **PASS**: Zero issues
- **MINOR**: Only MINOR issues (stylistic, optimization suggestions)
- **CRITICAL**: Any CRITICAL issue (must block merge)

### Issue Ordering

1. CRITICAL issues first
2. Within CRITICAL, feature-regression first
3. Then MINOR issues

## Risk-Based Review Depth

Read `.maestro/cookbook/review-routing.md` for risk classification.

| Risk   | Review Depth                                    |
| ------ | ----------------------------------------------- |
| HIGH   | Full review: security, logic, edge cases, tests |
| MEDIUM | Standard review: logic, obvious issues          |
| LOW    | Skip review (compile gate only)                 |

## Common Pitfalls

### False Positives to Avoid

- Import "collisions" that are actually different packages
- "Missing" error handling that's handled at a higher layer
- Style issues in generated code
- Comments in languages where they're not conventional

### Things to Always Catch

- Nil pointer dereferences
- Incorrect error comparison (`==` vs `errors.Is`)
- Hardcoded credentials
- SQL injection vectors
- Race conditions in concurrent code

````

## Acceptance Criteria
- [ ] Priority order is clear
- [ ] Feature regression checklist is comprehensive
- [ ] Convention injection is explained
- [ ] Structured output format is defined
- [ ] Risk-based depth is explained
- [ ] Common pitfalls are noted
- [ ] Language-agnostic

---

### 32. Review: MST-001-016 `[review]` `[XS]`

**Assignee:** general
> Blocked by: Task 31

## Overview
Review the review skill.

## Task Reference
- **Reviews:** Task 31 - Create review skill

## Files to Review
- `.maestro/skills/review/SKILL.md`

## Review Focus
- [ ] Priority order is sensible
- [ ] Regression checklist is actionable
- [ ] Convention injection is clear
- [ ] Output format is consistent with review template
- [ ] Risk-based routing is referenced correctly

## Acceptance Criteria
- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 33. MST-001-017: Polish existing spec template `[backend]` `[XS]`

**Assignee:** general
> Blocked by: Task 7

## Overview
Polish the existing spec template to ensure it's complete and consistent with other templates.

## Context
The PoC spec template exists at `.maestro/templates/spec-template.md`. This task ensures it's polished and consistent with the constitution template and plan template styles.

## Implementation Details

**Files:**
- `.maestro/templates/spec-template.md` - Polish existing template

Enhancements:
1. Add status field options
2. Ensure placeholder syntax is consistent with other templates
3. Add changelog section
4. Ensure all sections from RFC-002 are present

## Acceptance Criteria
- [ ] Template uses consistent placeholder syntax ({PLACEHOLDER})
- [ ] All RFC-002 sections present
- [ ] Status field has clear options
- [ ] Template is self-documenting
- [ ] Consistent style with constitution and plan templates

---

### 34. Review: MST-001-017 `[review]` `[XS]`

**Assignee:** general
> Blocked by: Task 33

## Overview
Review the polished spec template.

## Task Reference
- **Reviews:** Task 33 - Polish existing spec template

## Files to Review
- `.maestro/templates/spec-template.md`

## Review Focus
- [ ] Placeholder syntax is consistent
- [ ] All required sections present
- [ ] Style matches other templates
- [ ] Self-documenting with examples

## Acceptance Criteria
- [ ] Review completed with PASS or MINOR issues only
- [ ] CRITICAL issues create fix tasks

---

### 35. PM-VAL: Maestro Phase 0 Development Kit `[pm-validation]` `[S]`

**Assignee:** general
> Blocked by: Task 2, Task 4, Task 6, Task 8, Task 10, Task 12, Task 14, Task 16, Task 18, Task 20, Task 22, Task 24, Task 26, Task 28, Task 30, Task 32, Task 34

## Overview
Final validation that Maestro Phase 0 meets all RFC-002 requirements.

## Feature Reference
- **Epic:** MST-001
- **Plan:** `plans/maestro-phase0.md`

## Tasks to Validate

**Foundation:**
- Task 1: config.yaml schema
- Task 3: Shell script helpers
- Task 5: /maestro.init command
- Task 7: Constitution template

**Spec Pipeline:**
- Task 9: /maestro.specify command (polished)
- Task 11: /maestro.clarify command
- Task 13: /maestro.plan command + template

**Execution Pipeline:**
- Task 15: /maestro.tasks command
- Task 17: /maestro.implement command
- Task 19: /maestro.review command + template + cookbook
- Task 21: /maestro.pm-validate command

**Orchestration:**
- Task 23: /maestro.orchestrate command
- Task 25: /maestro.commit command
- Task 27: /maestro.analyze command

**Skills:**
- Task 29: Constitution skill
- Task 31: Review skill
- Task 33: Spec template polish

## Validation Checklist

### Commands (11 total)
- [ ] /maestro.init — scaffolds .maestro/, creates constitution, registers commands
- [ ] /maestro.specify — generates spec, creates branch/dir, marks uncertainties
- [ ] /maestro.clarify — interactive Q&A for clarification markers
- [ ] /maestro.plan — generates implementation plan from spec
- [ ] /maestro.tasks — creates bd epic with tasks, reviews, PM-VAL
- [ ] /maestro.implement — spawns sub-agent with compile gate
- [ ] /maestro.review — risk-based review with conventions
- [ ] /maestro.pm-validate — regression scan first, requirements check
- [ ] /maestro.orchestrate — automated loop with parallelism
- [ ] /maestro.commit — layer-separated atomic commits
- [ ] /maestro.analyze — post-epic learning with proposals

### Supporting Files
- [ ] config.yaml — agent routing, compile gate, size mapping
- [ ] Scripts — init.sh, create-feature.sh, check-prerequisites.sh, compile-gate.sh, bd-helpers.sh
- [ ] Templates — constitution, spec, plan, review
- [ ] Skills — constitution, review, pm-validation
- [ ] Cookbook — review-routing.md, post-epic-analysis.md
- [ ] Reference — conventions.md

### Quality Gates
- [ ] Commands work in both Claude Code and OpenCode
- [ ] Shell scripts are defensive (set -euo pipefail)
- [ ] Templates are 100% generic
- [ ] State JSON is updated atomically

## On Failure
Create fix tasks for any gaps found.

---

## Dependencies

```mermaid
graph TD
    T1[Task 1: Config] --> T2[Review 1]
    T1 --> T3[Task 3: Scripts]
    T3 --> T4[Review 3]
    T3 --> T5[Task 5: Init]
    T5 --> T6[Review 5]
    T1 --> T7[Task 7: Constitution]
    T7 --> T8[Review 7]
    T5 --> T9[Task 9: Specify]
    T9 --> T10[Review 9]
    T9 --> T11[Task 11: Clarify]
    T11 --> T12[Review 11]
    T11 --> T13[Task 13: Plan]
    T13 --> T14[Review 13]
    T13 --> T15[Task 15: Tasks]
    T15 --> T16[Review 15]
    T15 --> T17[Task 17: Implement]
    T17 --> T18[Review 17]
    T17 --> T19[Task 19: Review Cmd]
    T19 --> T20[Review 19]
    T19 --> T21[Task 21: PM-Val]
    T21 --> T22[Review 21]
    T21 --> T23[Task 23: Orchestrate]
    T23 --> T24[Review 23]
    T3 --> T25[Task 25: Commit]
    T25 --> T26[Review 25]
    T23 --> T27[Task 27: Analyze]
    T27 --> T28[Review 27]
    T7 --> T29[Task 29: Constitution Skill]
    T29 --> T30[Review 29]
    T19 --> T31[Task 31: Review Skill]
    T31 --> T32[Review 31]
    T7 --> T33[Task 33: Spec Template]
    T33 --> T34[Review 33]

    T2 --> T35[PM-VAL]
    T4 --> T35
    T6 --> T35
    T8 --> T35
    T10 --> T35
    T12 --> T35
    T14 --> T35
    T16 --> T35
    T18 --> T35
    T20 --> T35
    T22 --> T35
    T24 --> T35
    T26 --> T35
    T28 --> T35
    T30 --> T35
    T32 --> T35
    T34 --> T35
````

## Risks

- **Circular dependencies**: Commands reference each other; ensure documentation is clear
- **Template genericity**: Must resist temptation to add domain-specific content
- **bd CLI dependency**: All commands assume bd is installed and configured
- **State file consistency**: Multiple commands modify state; ensure atomic updates
