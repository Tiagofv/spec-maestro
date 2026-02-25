# Implementation Plan: Plan-Based Agent Assignment for Task Implementation

**Feature ID:** 012-lets-change-the-way-we-select-the-agent-to-impleme
**Spec:** .maestro/specs/012-lets-change-the-way-we-select-the-agent-to-impleme/spec.md
**Created:** 2026-02-19
**Status:** Draft

---

## 1. Architecture Overview

### 1.1 High-Level Design

This feature shifts agent selection from a **runtime concern** (label-based routing in `maestro.implement`) to a **plan-time concern** (assignee set during `maestro.plan`). The change touches three command files that form the maestro orchestration pipeline:

```
maestro.plan  →  maestro.tasks  →  maestro.implement
(assigns agent)   (creates bd issues)   (reads assignee, spawns agent)
```

**Before:** `maestro.implement` reads `config.yaml → agent_routing[label]` to choose the agent at spawn time.
**After:** `maestro.plan` assigns an agent per task using a file-pattern table. `maestro.tasks` passes the assignee through to bd issues. `maestro.implement` reads the assignee directly from the task.

### 1.2 Component Interactions

1. **`maestro.plan.md`** — Contains a static file-pattern-to-agent mapping table. When generating tasks in the plan, the planner matches each task's target files against this table and records the agent as the task's assignee. If a task touches files matching different agents, it is split into separate tasks.

2. **`maestro.tasks.md`** — Reads the assignee from the plan output and passes it to `bd create` when creating issues. No longer reads `agent_routing` from `config.yaml`.

3. **`maestro.implement.md`** — Reads the assignee from the task's bd data (`bd show {task_id} --json → assignee`). No longer consults `config.yaml → agent_routing`. Falls back to `general` if no assignee is set. Labels are still used for routing to the correct handler (impl vs review vs PM-validation) but no longer determine the agent type.

4. **`config.yaml`** — The `agent_routing` section remains in the file but is no longer read by any command. It becomes documentation/legacy. No file modification needed.

### 1.3 Key Design Decisions

| Decision                                      | Options Considered                                      | Chosen                            | Rationale                                                                                                                                                 |
| --------------------------------------------- | ------------------------------------------------------- | --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Where to define file-pattern-to-agent mapping | config.yaml, separate file, plan.md                     | Static table in `maestro.plan.md` | User specified: "defined in maestro.plan.md command. Every plan must have its assigned agent." Makes the mapping visible alongside planning instructions. |
| When agent is assigned                        | Runtime (implement time), Plan time, Task creation time | Plan time                         | User specified: "agent = task assignee." Setting during planning means the plan output shows agent assignments for review before task creation.           |
| Multi-pattern task handling                   | First match wins, majority wins, label fallback         | Split into separate tasks         | User specified. Each agent handles only its specialized files.                                                                                            |
| Relationship to label-based routing           | Override, complement, replace                           | Replace entirely                  | User specified. Single mechanism for agent selection. Labels still determine handler type (impl/review/PM).                                               |
| Review/PM-validation agent assignment         | Always general, same as impl, assignable in plan        | Assignable in plan                | User specified. Full control over all task types.                                                                                                         |
| Agent name validation                         | Config time, runtime, both                              | Runtime only                      | Simpler. Invalid names fall back to `general` with warning.                                                                                               |
| Backward compatibility                        | Require migration, default fallback, refuse             | Default to `general`              | Existing plans without assignees continue to work.                                                                                                        |

---

## 2. Component Design

### 2.1 New Components

_None._ This feature modifies existing command files only.

### 2.2 Modified Components

#### Component: `maestro.plan.md`

- **Current:** Generates a plan with phases, components, and tasks. Does not assign agents to tasks. Has no file-pattern-to-agent mapping.
- **Change:**
  1. Add a **File-Pattern-to-Agent Mapping Table** section near the top (after Step 1, before the plan generation rules). This table maps glob-style file patterns to agent identifiers.
  2. Add instructions in **Step 5 (Generate the Plan)** telling the planner to: (a) match each task's target files against the mapping table, (b) record the matched agent as the task's assignee in the plan output, (c) split tasks that touch files matching different agents.
  3. Update the **plan template** to include an `Assignee` column in the task table.
- **Risk:** Medium — The planner's behavior changes significantly. Task splitting could produce unexpected results for complex cross-cutting tasks.

#### Component: `maestro.tasks.md`

- **Current:** Reads `agent_routing[label]` from `config.yaml` (Step 5) to determine the assignee for each task. Passes assignee to `bd create`.
- **Change:**
  1. **Step 5 (Map Sizes and Assignees):** Stop reading `agent_routing` from `config.yaml`. Instead, read the assignee directly from the plan's task table (the `Assignee` column added above). If the plan doesn't specify an assignee, default to `general`.
  2. Update the task table format in Step 6 to reflect that assignee comes from the plan, not config.
- **Risk:** Low — The assignee field already exists in the `bd create` command. We're just changing where the value comes from.

#### Component: `maestro.implement.md`

- **Current:** Step 3 routes by label to determine handler type AND agent. Step 4d uses `subagent_type="{assignee from task}"` which already reads the assignee.
- **Change:**
  1. **Step 3 (Route by Label):** Clarify that labels determine the **handler type** (implementation, review, or PM-validation) but NOT the agent. Remove any reference to `config.yaml → agent_routing`.
  2. **Step 4d (Spawn implementation agent):** Already uses `subagent_type="{assignee from task}"`. Add a fallback: if assignee is empty/null, use `general`. Add a warning log if the assignee is set but doesn't match a known agent type.
  3. **Step 5 (Execute Review Task):** Already spawns via `/maestro.review` which reads the assignee. No change needed here.
  4. **Step 6 (Execute PM Validation):** Already spawns via `/maestro.pm-validate`. No change needed here.
  5. **Rules section:** Update rule 3 ("Route by label") to clarify labels determine handler type, not agent. Add a new rule about agent assignment coming from the task's assignee field.
  6. **Add an agent fallback rule:** If the task's assignee is empty or doesn't match any available `subagent_type`, fall back to `general` and log a warning.
- **Risk:** Low — The `subagent_type="{assignee from task}"` pattern is already in place. The changes are clarification and fallback logic.

#### Component: `plan-template.md`

- **Current:** Task table in Phase sections has no `Assignee` column. The format is free-form task lists.
- **Change:** Add an `Assignee` column to the task sizing guidance section (Section 6) to document that every task should have an assignee. Add a note that the assignee comes from the file-pattern mapping in `maestro.plan.md`.
- **Risk:** Low — Template change only affects future plans.

---

## 3. Data Model

### 3.1 New Entities

_None._

### 3.2 Modified Entities

#### Entity: Plan Task Table (in plan.md output)

- **Current fields:** #, ID, Title, Label, Size, Minutes, Assignee, Blocked By
- **New fields:** No new fields — `Assignee` already exists but was populated from `config.yaml`. Now populated from the file-pattern mapping.
- **Migration notes:** Existing plans without assignee values will work because `maestro.implement` defaults to `general`.

### 3.3 Data Flow

```
maestro.plan.md (file-pattern table)
       │
       ▼
Plan output (each task has Assignee column)
       │
       ▼
maestro.tasks.md reads Assignee from plan
       │
       ▼
bd create --assignee={agent} (stored in bd task)
       │
       ▼
maestro.implement reads bd show → assignee
       │
       ▼
Task(subagent_type="{assignee}")
```

---

## 4. API Contracts

_No API endpoints are modified. All changes are to markdown command files read by Claude Code._

---

## 5. Implementation Phases

### Phase 1: Add File-Pattern Mapping Table to `maestro.plan.md`

- **Goal:** Define the agent mapping table and update planning instructions to use it
- **Tasks:**
  - Add a "File-Pattern-to-Agent Mapping" section to `maestro.plan.md` with a default table mapping `*` to `general`
  - Update Step 5 instructions to tell the planner to match task files against the mapping and assign agents
  - Add task-splitting instructions for tasks touching files matching different agent patterns
- **Deliverable:** `maestro.plan.md` contains the mapping table and updated planning instructions. Running `/maestro.plan` on any spec produces a plan with agent assignments per task.

### Phase 2: Update `plan-template.md` to Include Assignee

- **Goal:** Ensure the plan template documents agent assignment
- **Tasks:**
  - Add `Assignee` column documentation to the task table format in `plan-template.md`
  - Add a note explaining that assignee comes from the file-pattern mapping
- **Deliverable:** Plan template shows the expected format for agent-assigned tasks.

### Phase 3: Update `maestro.tasks.md` to Read Assignee from Plan

- **Goal:** Stop reading `agent_routing` from config.yaml; read assignee from the plan instead
- **Tasks:**
  - Modify Step 5 to read assignee from the plan's task table instead of `config.yaml → agent_routing`
  - Add fallback: if no assignee in plan, default to `general`
  - Update Step 6 task table to reflect the new assignee source
- **Deliverable:** `maestro.tasks.md` creates bd tasks with assignees sourced from the plan.
- **Dependencies:** Phase 1 (plan must output assignees first)

### Phase 4: Update `maestro.implement.md` to Clarify Agent Selection

- **Goal:** Remove references to `config.yaml → agent_routing`; clarify labels determine handler type only
- **Tasks:**
  - Update Step 3 to clarify labels route to handler type (impl/review/PM), not agent
  - Add fallback logic in Step 4d: if assignee is empty → `general`; if assignee is invalid → `general` with warning
  - Update Rules section: clarify rule 3, add new rule about agent assignment from task assignee
- **Deliverable:** `maestro.implement.md` no longer references `agent_routing`. Agent selection is purely from task assignee.
- **Dependencies:** Phase 3 (tasks must have assignees)

### Phase 5: Review and Validation

- **Goal:** Verify all changes are consistent and backward compatible
- **Tasks:**
  - Review all 4 modified files for consistency
  - Verify backward compatibility: a plan without assignees should still work with `general` default
  - Verify the constitution is not violated (Section 5: "Changes to agent routing configuration" is out of scope for AI agents — but this feature was explicitly requested by the user)
- **Deliverable:** All changes reviewed and validated.
- **Dependencies:** Phases 1-4

---

## 6. Task Sizing Guidance

All tasks follow the sizing guidelines from the plan template:

| Size   | Time Range                  | Status   |
| ------ | --------------------------- | -------- |
| **XS** | 0-120 minutes (0-2 hours)   | Accepted |
| **S**  | 121-360 minutes (2-6 hours) | Accepted |

All tasks in this feature are XS or S — they involve editing markdown command files, not writing application code.

---

## 7. Testing Strategy

### 7.1 Unit Tests

_Not applicable — this feature modifies markdown command files, not code._

### 7.2 Integration Tests

- **End-to-end flow test:** Run `/maestro.plan` on a test spec, verify the output plan contains agent assignments per task. Then run `/maestro.tasks` and verify bd issues have the correct assignees.
- **Backward compatibility test:** Run `/maestro.implement` on a feature with pre-existing tasks that have no assignee field. Verify it defaults to `general` without errors.

### 7.3 End-to-End Tests

Manual verification:

1. Create a test spec with files spanning `.go` and `.ts` patterns
2. Run `/maestro.plan` — verify tasks are split by file type and assigned correct agents
3. Run `/maestro.tasks` — verify bd issues have the correct assignees
4. Run `/maestro.implement` — verify sub-agents are spawned with the correct `subagent_type`

### 7.4 Test Data

No test fixtures needed. Testing uses the existing maestro command pipeline.

---

## 8. Risks and Mitigations

| Risk                                                                    | Likelihood | Impact | Mitigation                                                                                                                                     |
| ----------------------------------------------------------------------- | ---------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Task splitting produces too many small tasks                            | Medium     | Low    | Only split when files genuinely match different agent patterns. Document splitting rules clearly.                                              |
| Existing workflows break due to removed `agent_routing` dependency      | Low        | Medium | Backward compatibility: missing assignee defaults to `general`. `agent_routing` section stays in config.yaml (just ignored).                   |
| Planner doesn't follow the file-pattern matching instructions correctly | Medium     | Medium | Clear, structured instructions with examples in `maestro.plan.md`. The mapping table is simple glob-to-agent.                                  |
| Constitution Section 5 flags "changes to agent routing configuration"   | Low        | High   | This is a user-requested feature. The constitution's out-of-scope rule applies to AI agents acting autonomously, not to user-directed changes. |

---

## 9. Open Questions

None — all clarifications were resolved in `/maestro.clarify`.
