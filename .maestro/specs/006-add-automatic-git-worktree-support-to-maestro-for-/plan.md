# Implementation Plan: Add Automatic Git Worktree Support to Maestro

**Feature ID:** 006-add-automatic-git-worktree-support-to-maestro-for-
**Spec:** `.maestro/specs/006-add-automatic-git-worktree-support-to-maestro-for-/spec.md`
**Created:** 2026-02-19
**Status:** Draft

> **Note:** All implementations for this feature happen on the **main branch**. No feature branch or worktree is used for implementing worktree support itself.

---

## 1. Architecture Overview

### 1.1 High-Level Design

Worktree support is a shell-script and command-definition layer that wraps git's native worktree capabilities. It integrates into maestro's existing lifecycle pipeline without modifying the Tauri/Rust application code.

```
 maestro.specify          maestro.implement          maestro.review / commit
 ┌──────────────┐         ┌──────────────────┐       ┌───────────────────┐
 │ Select wt    │────────►│ Create worktree   │──────►│ Operate inside    │
 │ name + store │         │ + branch + symlink│       │ worktree context  │
 │ in state.json│         │ + detect existing │       │ (warn if in wt)   │
 └──────────────┘         └──────────────────┘       └───────────────────┘
        │                         │                           │
        ▼                         ▼                           ▼
 .maestro/state/          .worktrees/{name}/          git worktree list
 {feature}.json           ├── (full checkout)         git worktree remove
   worktree_name          ├── .maestro → symlink
   worktree_path          └── feat/{slug} branch

 maestro.implement (cleanup)
 ┌──────────────────────┐
 │ On completion:        │
 │ git worktree remove   │
 │ Update state.json     │
 └──────────────────────┘
```

### 1.2 Component Interactions

**Worktree Creation Flow (during `/maestro.implement`):**

1. Read `worktree_name` and `worktree_path` from state.json
2. Check if worktree already exists (`git worktree list`)
3. If not, run `git worktree add .worktrees/{name} -b feat/{slug}`
4. Symlink `.maestro/` into the worktree (if not version-controlled)
5. Update state.json with `worktree_created: true`
6. All sub-agent Task() calls include `workdir` pointing to the worktree

**Worktree Detection Flow (on any maestro command):**

1. Script checks `git rev-parse --show-toplevel` vs `git worktree list`
2. If CWD is inside a worktree (not the main repo), emit warning
3. Resolve main repo root for state/config reads
4. Continue operating in the worktree context

**Worktree Cleanup Flow (on feature completion):**

1. Verify all changes committed and pushed (PR opened)
2. Run `git worktree remove .worktrees/{name}`
3. Remove the branch if merged: `git branch -d feat/{slug}`
4. Update state.json: `worktree_created: false`

### 1.3 Key Design Decisions

| Decision                 | Options Considered                                      | Chosen                                              | Rationale                                                                                                |
| ------------------------ | ------------------------------------------------------- | --------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Worktree location        | Configurable path, `.worktrees/` in repo, external dir  | `.worktrees/` in repo root                          | Simple, discoverable, `.gitignore`-able. Spec mandates "relative to main repo root"                      |
| Branch convention        | `spec/{id}`, `feat/{slug}`, `wt/{name}`                 | `feat/{feature-slug}`                               | Per spec. Clear semantic meaning, matches common git conventions                                         |
| Symlink strategy         | Full `.maestro/` symlink, selective file symlinks, copy | Symlink entire `.maestro/` dir                      | Spec says ".maestro/ directory symlinked when not version-controlled". Single symlink = zero maintenance |
| Worktree creation timing | At specify, at plan, at implement                       | Name at specify, create at implement                | Per spec. Avoids creating worktrees that may never be implemented                                        |
| Detection mechanism      | Custom tracking file, git worktree list, both           | `git worktree list --porcelain`                     | Native git, always accurate, no custom state to sync                                                     |
| Cleanup policy           | Automatic on complete, manual only, ask user            | Automatic on feature complete, manual for abandoned | Spec: "user responsible for abandoned". Maestro cleans up on normal completion                           |

---

## 2. Component Design

### 2.1 New Components

#### Component: worktree-create.sh

- **Purpose:** Create a git worktree for a feature with proper branch, symlinks, and .gitignore setup
- **Location:** `.maestro/scripts/worktree-create.sh`
- **Dependencies:** git CLI (2.5+), state.json (for worktree_name, worktree_path)
- **Dependents:** `maestro.implement` command

**Interface:**

```bash
# Usage: worktree-create.sh <worktree-name> <branch-name> [base-branch]
# Output JSON: {"worktree_path":".worktrees/kanban-board","branch":"feat/kanban-board","created":true}
```

**Behavior:**

1. Validate git version >= 2.5
2. Create `.worktrees/` directory if not exists
3. Ensure `.worktrees/` is in `.gitignore`
4. Run `git worktree add .worktrees/{name} -b {branch} {base-branch}`
5. If `.maestro/` is not tracked by git, symlink it into worktree
6. Output JSON result

#### Component: worktree-list.sh

- **Purpose:** List all active worktrees with their associated features and status
- **Location:** `.maestro/scripts/worktree-list.sh`
- **Dependencies:** git CLI, state.json files
- **Dependents:** `maestro.implement` command, user CLI usage

**Interface:**

```bash
# Usage: worktree-list.sh [--json]
# Output: table or JSON of active worktrees
```

**Behavior:**

1. Run `git worktree list --porcelain`
2. For each worktree, cross-reference with `.maestro/state/*.json` to find feature association
3. Display: worktree path, branch, feature ID, stage

#### Component: worktree-cleanup.sh

- **Purpose:** Remove a worktree and optionally its branch after feature completion
- **Location:** `.maestro/scripts/worktree-cleanup.sh`
- **Dependencies:** git CLI, state.json
- **Dependents:** `maestro.implement` (on completion), user CLI usage

**Interface:**

```bash
# Usage: worktree-cleanup.sh <worktree-path> [--delete-branch]
# Output JSON: {"removed":true,"branch_deleted":false}
```

**Behavior:**

1. Verify no uncommitted changes in the worktree
2. Run `git worktree remove {path}`
3. If `--delete-branch` and branch is merged, run `git branch -d {branch}`
4. Run `git worktree prune` to clean up stale entries
5. Output JSON result

#### Component: worktree-detect.sh

- **Purpose:** Detect if CWD is inside a worktree, resolve main repo root, and emit warnings
- **Location:** `.maestro/scripts/worktree-detect.sh`
- **Dependencies:** git CLI
- **Dependents:** All maestro commands (sourced at the top)

**Interface:**

```bash
# Usage: source .maestro/scripts/worktree-detect.sh
# Sets: MAESTRO_MAIN_REPO, MAESTRO_IN_WORKTREE (true/false), MAESTRO_WORKTREE_FEATURE
```

**Behavior:**

1. Get current toplevel: `git rev-parse --show-toplevel`
2. Get main worktree: `git worktree list --porcelain | head` (first entry is always main)
3. If current != main, set `MAESTRO_IN_WORKTREE=true`
4. Emit warning: "You are inside worktree for feature: {feature_id}"
5. Resolve `MAESTRO_MAIN_REPO` to the main worktree path for state/config reads

### 2.2 Modified Components

#### Component: create-feature.sh

- **Current:** Creates spec directory and git branch (`spec/{feature-id}`), checks out branch
- **Change:** Add worktree name generation and storage. The script will:
  1. Generate a human-readable worktree name from the slug (reuse existing slug logic)
  2. Compute `worktree_path` as `.worktrees/{slug}/`
  3. Compute `branch` as `feat/{slug}` (changing from `spec/{feature-id}`)
  4. Include `worktree_name` and `worktree_path` in JSON output
  5. **Do NOT create the worktree** (deferred to implement)
  6. **Do NOT checkout or create the branch** (deferred to worktree creation)
- **Risk:** Medium — changes existing branch naming convention from `spec/{id}` to `feat/{slug}`. Existing features with `spec/` branches are unaffected but won't follow the new convention.

#### Component: maestro.specify.md

- **Current:** Calls `create-feature.sh`, writes spec, creates state.json with `branch` field
- **Change:**
  1. After Step 1, extract `worktree_name` and `worktree_path` from script JSON output
  2. In Step 5b, add `worktree_name` and `worktree_path` fields to state.json
  3. Update report to mention selected worktree name
- **Risk:** Low — additive changes to command definition

#### Component: maestro.implement.md

- **Current:** Finds feature, checks out branch, loops through tasks with sub-agents
- **Change:**
  1. In Step 1 (Find the Feature): read `worktree_name` and `worktree_path` from state
  2. After Step 1: call `worktree-create.sh` if worktree doesn't exist yet
  3. Replace `git checkout {branch}` with worktree-based workflow (no branch switching needed)
  4. In Step 4d (spawn agent): add worktree path context so sub-agents operate in the correct directory
  5. In Step 4d: update compile gate call to pass worktree path: `bash .maestro/scripts/compile-gate.sh {worktree_path}`
  6. In Step 9 (completion): call `worktree-cleanup.sh` to remove worktree
- **Risk:** High — this is the core orchestration command. Changes affect how all sub-agents receive their working directory context.

#### Component: maestro.review.md

- **Current:** Reads implementation task, spawns reviewer, uses `git diff HEAD~1`
- **Change:**
  1. Read worktree path from state.json
  2. Pass worktree path context to reviewer sub-agent
  3. Adjust `git diff` commands to work from worktree directory
- **Risk:** Medium — diff commands must be worktree-aware

#### Component: maestro.commit.md

- **Current:** Operates on staged changes in current directory
- **Change:**
  1. Source `worktree-detect.sh` to determine if running from a worktree
  2. If in worktree, warn user and show feature context
  3. Operate normally (git commands naturally work within the worktree)
- **Risk:** Low — git commands already work correctly inside worktrees

#### Component: maestro.tasks.md

- **Current:** Creates bd epic and tasks from plan
- **Change:**
  1. Read `worktree_path` from state.json
  2. Include worktree path in each task description so sub-agents know where to work
  3. Add a note to each task: "Work in worktree: {worktree_path}"
- **Risk:** Low — additive to task descriptions

#### Component: compile-gate.sh

- **Current:** Already accepts `[worktree-path]` argument and cds into it
- **Change:** When running from a worktree, resolve `.maestro/config.yaml` from the main repo (via symlink — already handled since `.maestro/` is symlinked)
- **Risk:** Low — already mostly worktree-aware

#### Component: check-prerequisites.sh

- **Current:** Validates stage ordering by checking state files
- **Change:** Source `worktree-detect.sh` to resolve main repo path for state file lookups when running from a worktree
- **Risk:** Low — path resolution change only

#### Component: .gitignore

- **Current:** Standard gitignore for Tauri/React project
- **Change:** Add `.worktrees/` entry to prevent worktree directories from being tracked
- **Risk:** Low — single line addition

---

## 3. Data Model

### 3.1 New Entities

#### Entity: Worktree State (fields added to feature state.json)

```json
{
  "worktree_name": "kanban-board",
  "worktree_path": ".worktrees/kanban-board",
  "worktree_created": false,
  "worktree_branch": "feat/kanban-board"
}
```

### 3.2 Modified Entities

#### Entity: Feature State JSON (`.maestro/state/{feature_id}.json`)

- **Current fields:** `feature_id`, `created_at`, `updated_at`, `stage`, `spec_path`, `branch`, `clarification_count`, `user_stories`, `history`
- **New fields:**
  - `worktree_name: string` — human-readable worktree directory name
  - `worktree_path: string` — relative path from repo root (e.g., `.worktrees/kanban-board`)
  - `worktree_created: boolean` — whether the worktree has been created on disk
  - `worktree_branch: string` — the `feat/{slug}` branch name used in the worktree
- **Migration notes:** Existing state files (001-007) don't have these fields. Scripts must handle their absence gracefully (default to `null`/`false`). No retroactive migration needed.

#### Entity: create-feature.sh JSON output

- **Current:** `{"feature_id":"...","spec_dir":"...","branch":"...","slug":"..."}`
- **New:** `{"feature_id":"...","spec_dir":"...","branch":"feat/{slug}","slug":"...","worktree_name":"{slug}","worktree_path":".worktrees/{slug}"}`

### 3.3 Data Flow

```
maestro.specify                     maestro.implement
     │                                     │
     ▼                                     ▼
create-feature.sh               worktree-create.sh
  outputs JSON with               reads state.json
  worktree_name/path              creates worktree
     │                            sets up symlinks
     ▼                                     │
state.json                                 ▼
  worktree_name: "kb"           .worktrees/kb/
  worktree_path: ".wt/kb"        ├── (full checkout)
  worktree_created: false         ├── .maestro → symlink
  worktree_branch: "feat/kb"     └── feat/kb branch
     │                                     │
     ▼                                     ▼
maestro.tasks                    Sub-agents work in
  includes wt path                .worktrees/kb/
  in task descriptions                     │
                                           ▼
                               maestro.implement (complete)
                                 calls worktree-cleanup.sh
                                 removes .worktrees/kb/
                                 updates state.json
```

---

## 4. API Contracts

### 4.1 New Script Interfaces

#### worktree-create.sh

- **Purpose:** Create a git worktree with symlinks for a feature
- **Input:** `<worktree-name> <branch-name> [base-branch]`
  - `worktree-name`: human-readable name (e.g., `kanban-board`)
  - `branch-name`: git branch name (e.g., `feat/kanban-board`)
  - `base-branch`: branch to fork from (default: `main` from config.yaml `project.base_branch`)
- **Output (stdout):** `{"worktree_path":".worktrees/kanban-board","branch":"feat/kanban-board","created":true}`
- **Errors (stderr + exit 1):**
  - Git version < 2.5
  - Worktree already exists at path
  - Branch already exists (not created by us)
  - Git not a repository

#### worktree-list.sh

- **Purpose:** List active worktrees with feature associations
- **Input:** `[--json]`
- **Output (stdout):**
  - Default: human-readable table
  - `--json`: `[{"path":".worktrees/kb","branch":"feat/kb","feature_id":"001-...","stage":"implement"}]`
- **Errors:** None (empty list is valid)

#### worktree-cleanup.sh

- **Purpose:** Remove a worktree and optionally its branch
- **Input:** `<worktree-path> [--delete-branch]`
- **Output (stdout):** `{"removed":true,"branch_deleted":false}`
- **Errors (stderr + exit 1):**
  - Worktree has uncommitted changes
  - Path doesn't exist
  - Not a valid worktree

#### worktree-detect.sh (sourced, not executed)

- **Purpose:** Set environment variables for worktree context
- **Input:** None (reads git state)
- **Output (env vars):**
  - `MAESTRO_MAIN_REPO`: absolute path to main worktree
  - `MAESTRO_IN_WORKTREE`: `true` or `false`
  - `MAESTRO_WORKTREE_FEATURE`: feature ID if in a worktree, empty otherwise
- **Side effects:** Prints warning to stderr if inside a worktree

### 4.2 Modified Script Interfaces

#### create-feature.sh

- **Current behavior:** Creates spec dir, creates/checks out `spec/{id}` branch, outputs JSON
- **New behavior:** Creates spec dir, computes `feat/{slug}` branch name (does NOT create branch), adds `worktree_name` and `worktree_path` to JSON output
- **Breaking:** Yes — branch name convention changes from `spec/{id}` to `feat/{slug}`. Branch is no longer created at specify time.

---

## 5. Implementation Phases

### Phase 1: Foundation Scripts

- **Goal:** Core worktree shell scripts that can be tested independently
- **Tasks:**
  - Create `worktree-detect.sh` with env var detection logic
  - Create `worktree-create.sh` with worktree + symlink setup
  - Create `worktree-list.sh` with feature association lookup
  - Create `worktree-cleanup.sh` with safe removal logic
  - Add `.worktrees/` to `.gitignore`
- **Deliverable:** Four shell scripts that pass manual testing: create a worktree, list it, detect it, clean it up

### Phase 2: Specify Integration

- **Goal:** `/maestro.specify` selects worktree name and stores it in state
- **Dependencies:** Phase 1 (worktree-detect.sh exists for sourcing)
- **Tasks:**
  - Modify `create-feature.sh` to output worktree fields and use `feat/{slug}` branch convention
  - Modify `maestro.specify.md` to extract and store worktree fields in state.json
  - Update state.json schema to include worktree fields
- **Deliverable:** Running `/maestro.specify` produces a state.json with `worktree_name`, `worktree_path`, and `worktree_branch` fields. No worktree is created yet.

### Phase 3: Implement Integration

- **Goal:** `/maestro.implement` creates worktrees and routes sub-agents to them
- **Dependencies:** Phase 2 (state.json has worktree fields)
- **Tasks:**
  - Modify `maestro.implement.md` Step 1 to read worktree state and create worktree if needed
  - Modify `maestro.implement.md` Step 4d to pass worktree path to sub-agents
  - Modify `maestro.implement.md` Step 9 to call `worktree-cleanup.sh` on completion
  - Update compile-gate.sh invocations to pass worktree path
- **Deliverable:** Running `/maestro.implement` creates a worktree, delegates work inside it, and cleans up on completion

### Phase 4: Task & Review Integration

- **Goal:** Tasks reference worktree paths; reviews operate within worktree context
- **Dependencies:** Phase 3 (implement creates worktrees)
- **Tasks:**
  - Modify `maestro.tasks.md` to include worktree path in task descriptions
  - Modify `maestro.review.md` to operate within worktree context for diffs
  - Modify `maestro.commit.md` to source `worktree-detect.sh` and warn when in worktree
  - Modify `check-prerequisites.sh` to resolve state files from main repo when in worktree
- **Deliverable:** Full pipeline works end-to-end in worktree context. Tasks mention worktree. Reviews diff correctly. Commits work from within worktrees.

### Phase 5: Agent Registration & Polish

- **Goal:** Updated commands propagated to agents, edge cases handled
- **Dependencies:** Phase 4 (all commands updated)
- **Tasks:**
  - Run `init.sh` to propagate updated commands to `.claude/commands/` and `.opencode/commands/`
  - Verify `compile-gate.sh` works correctly with symlinked `.maestro/`
  - Test edge case: running maestro commands from inside a worktree
  - Test edge case: specifying a feature when worktrees from other features exist
  - Add validation for git version >= 2.5 in `worktree-create.sh`
- **Deliverable:** All agents have updated commands. Edge cases are handled gracefully.

---

## 6. Testing Strategy

### 6.1 Unit Tests (Script-Level)

- **worktree-create.sh:**
  - Creates worktree at correct path
  - Creates branch with `feat/` prefix
  - Symlinks `.maestro/` when not version-controlled
  - Fails gracefully on git < 2.5
  - Handles existing worktree at path (idempotent or error)
  - Outputs valid JSON

- **worktree-list.sh:**
  - Lists worktrees with feature associations
  - Handles empty list (no worktrees)
  - JSON output is valid
  - Associates worktrees with state files correctly

- **worktree-cleanup.sh:**
  - Removes worktree directory
  - Refuses to remove with uncommitted changes
  - Optionally deletes merged branch
  - Handles already-removed worktree gracefully

- **worktree-detect.sh:**
  - Sets correct env vars when in main repo
  - Sets correct env vars when in worktree
  - Resolves main repo path correctly
  - Identifies feature from worktree branch name

- **create-feature.sh (modified):**
  - Outputs new fields: `worktree_name`, `worktree_path`
  - Uses `feat/` branch prefix
  - Does NOT create branch at specify time
  - Backward compatible: existing features without worktree fields work

### 6.2 Integration Tests

- **Full lifecycle:** specify -> plan -> tasks -> implement -> review -> complete
  - Verify worktree created during implement
  - Verify sub-agents work in worktree
  - Verify worktree cleaned up on completion
  - Verify state.json updated at each stage

- **Multiple worktrees:** Create two features, verify both have independent worktrees
  - Changes in one don't affect the other
  - Both can exist simultaneously

- **Symlink integrity:** Verify `.maestro/` symlink works
  - Config reads from worktree resolve correctly
  - State updates from worktree context write to main repo

### 6.3 End-to-End Tests

- **Developer workflow:** Full maestro pipeline from specify to completion using worktrees
- **Worktree detection:** Run maestro commands from inside a worktree and verify warnings + correct behavior
- **Cleanup:** Complete a feature and verify worktree is removed

### 6.4 Test Data

- **Test repository:** A git repo with `.maestro/` initialized and at least one existing feature (non-worktree) to verify backward compatibility
- **Edge cases:**
  - Empty repo (no commits)
  - Repo with dirty working tree
  - Repo with existing `.worktrees/` directory
  - State file without worktree fields (pre-existing features)

---

## 7. Risks and Mitigations

| Risk                                           | Likelihood | Impact | Mitigation                                                                                                           |
| ---------------------------------------------- | ---------- | ------ | -------------------------------------------------------------------------------------------------------------------- |
| Breaking existing `spec/` branch convention    | High       | Medium | Existing features keep their `spec/` branches. Only new features use `feat/` convention. Scripts handle both.        |
| Symlink `.maestro/` breaks when main dir moves | Low        | High   | Use relative symlinks. `worktree-detect.sh` resolves main repo path dynamically.                                     |
| Sub-agents ignore worktree path context        | Medium     | High   | Task descriptions explicitly state the worktree path. Compile gate validates correct directory.                      |
| Disk space from multiple worktrees             | Medium     | Low    | Git worktrees share the `.git` object store. Only working tree files are duplicated. `node_modules` is user-managed. |
| `git worktree list` output format changes      | Low        | Medium | Parse `--porcelain` format which is stable. Add version check.                                                       |
| Existing state files lack worktree fields      | High       | Low    | All scripts default to `null`/`false` when fields are absent. No retroactive migration.                              |
| Commands edited as markdown, not code          | Medium     | Medium | Each command change is minimal and additive. Test full pipeline after each phase.                                    |

---

## 8. Open Questions

- None. All questions were resolved during the clarification phase.

---

## 9. File Structure

```
.maestro/
├── scripts/
│   ├── create-feature.sh          # MODIFIED: add worktree fields, feat/ branch convention
│   ├── compile-gate.sh            # MODIFIED: minor — resolve config via symlink
│   ├── check-prerequisites.sh     # MODIFIED: source worktree-detect for path resolution
│   ├── worktree-create.sh         # NEW: create worktree + branch + symlinks
│   ├── worktree-list.sh           # NEW: list active worktrees with feature info
│   ├── worktree-cleanup.sh        # NEW: remove worktree safely
│   ├── worktree-detect.sh         # NEW: detect worktree context, set env vars
│   ├── bd-helpers.sh              # UNCHANGED
│   └── init.sh                    # UNCHANGED (re-run to propagate command changes)
├── commands/
│   ├── maestro.specify.md         # MODIFIED: store worktree name/path in state
│   ├── maestro.implement.md       # MODIFIED: create/use/cleanup worktrees
│   ├── maestro.review.md          # MODIFIED: worktree-aware diffs
│   ├── maestro.commit.md          # MODIFIED: worktree detection + warning
│   ├── maestro.tasks.md           # MODIFIED: include worktree path in task descriptions
│   ├── maestro.clarify.md         # UNCHANGED
│   ├── maestro.plan.md            # UNCHANGED
│   ├── maestro.init.md            # UNCHANGED
│   ├── maestro.analyze.md         # UNCHANGED
│   └── maestro.pm-validate.md     # UNCHANGED
├── state/
│   └── *.json                     # MODIFIED SCHEMA: new worktree_* fields
└── config.yaml                    # UNCHANGED

.worktrees/                        # NEW: created at runtime, gitignored
├── {feature-name}/                # One per active feature
│   ├── (full working tree)
│   └── .maestro → symlink

.gitignore                         # MODIFIED: add .worktrees/
```
