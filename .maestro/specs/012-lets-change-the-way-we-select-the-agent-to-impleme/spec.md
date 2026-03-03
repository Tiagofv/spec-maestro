# Feature: Plan-Based Agent Assignment for Task Implementation

**Spec ID:** 012-lets-change-the-way-we-select-the-agent-to-impleme
**Author:** System
**Created:** 2026-02-19
**Last Updated:** 2026-02-19
**Status:** Draft

---

## 1. Problem Statement

Currently, the agent selected to implement a task during `maestro.implement` is determined by a label-based routing table in `config.yaml`. This is coarse-grained — every backend task uses the same agent regardless of what files it touches. A task modifying Go files, Python files, or Rust files all get routed to the same `general` agent.

Projects often have specialized agents that are better suited for specific file types. For example, a Go payments project might have a `golang-expert-payments` agent that understands domain patterns far better than the generic agent. There is no way for project maintainers to express "when a task touches `.go` files, use this specialized agent" without manually overriding the assignee on every task after planning.

This means users either accept suboptimal agent selection or must manually intervene in the task creation process — defeating the purpose of automated orchestration.

---

## 2. Proposed Solution

Move agent selection from runtime label-based routing to **plan-time assignment**. The `maestro.plan.md` command will contain a static file-pattern-to-agent mapping table. When the planner generates tasks, it inspects the files each task will modify and assigns the appropriate agent as the task's assignee based on this table.

This means:

- Every task in the plan has an explicit agent assignee
- The agent is determined by the files the task touches, not its label
- If a task would touch files matching different agent patterns, the planner splits it into separate tasks — one per agent
- The `maestro.implement` command reads the assignee from each task and uses it as the `subagent_type` when spawning the sub-agent
- The existing label-based `agent_routing` section in `config.yaml` is replaced by this approach
- All task types (implementation, review, PM-validation) can have their agent assigned in the plan
- The default agent remains `general` for any task or file pattern without a specific mapping

---

## 3. User Stories

### Story 1: Configure File-Pattern-to-Agent Mapping

**As a** project maintainer,
**I want** to define a file-pattern-to-agent mapping table in the `maestro.plan.md` command,
**so that** the planner automatically assigns the right agent to each task based on the files involved.

**Acceptance Criteria:**

- [ ] The `maestro.plan.md` command contains a human-readable table mapping file patterns (glob-style) to agent names
- [ ] The default agent for all unmatched file patterns is `general`
- [ ] Multiple patterns can be defined, each mapping to a different agent
- [ ] The mapping is editable directly in the `.md` file without special tooling

### Story 2: Automatic Agent Assignment During Planning

**As a** user running `/maestro.plan`,
**I want** each generated task to have an agent assignee based on the files it will modify,
**so that** the implementation phase uses the correct specialized agent without manual intervention.

**Acceptance Criteria:**

- [ ] When the planner generates a task, it matches the task's target files against the configured patterns
- [ ] The matched agent is set as the task's assignee
- [ ] If no files match any pattern, the task is assigned to `general`
- [ ] The agent assignment is visible in the plan output for each task

### Story 3: Task Splitting for Mixed File Types

**As a** project maintainer,
**I want** the planner to split tasks that touch files matching different agent patterns into separate tasks,
**so that** each agent only handles files it is specialized for.

**Acceptance Criteria:**

- [ ] When a planned task involves files matching multiple different agent patterns (e.g., `.go` and `.ts`), it is split into separate tasks
- [ ] Each resulting sub-task is assigned to the appropriate agent
- [ ] Dependencies between the split tasks are set correctly (they may need to run sequentially if they share interfaces)
- [ ] The split is visible in the plan output with a note explaining why the task was divided

### Story 4: Agent Assignment for Review and Validation Tasks

**As a** project maintainer,
**I want** review and PM-validation tasks to also have their agent assignable in the plan,
**so that** I have full control over which agent performs each role in the workflow.

**Acceptance Criteria:**

- [ ] Review tasks can have an explicit agent assignee in the plan
- [ ] PM-validation tasks can have an explicit agent assignee in the plan
- [ ] If no agent is specified for a review or PM-validation task, it defaults to `general`

### Story 5: Graceful Fallback for Missing or Invalid Agents

**As a** user running `maestro.implement`,
**I want** the system to gracefully handle tasks with no assignee or an invalid agent name,
**so that** implementation doesn't fail due to missing assignments or misconfiguration.

**Acceptance Criteria:**

- [ ] Tasks with no assignee default to `general`
- [ ] If a task's assignee doesn't match any available sub-agent type, the system falls back to `general` with a warning
- [ ] Existing plans created before this feature (without agent assignees) continue to work using `general`
- [ ] Agent name validation happens at runtime only (not at config or plan time)

### Story 6: Remove Label-Based Agent Routing

**As a** project maintainer,
**I want** the label-based `agent_routing` section in `config.yaml` to be replaced by the plan-based assignment,
**so that** there is a single, clear mechanism for agent selection.

**Acceptance Criteria:**

- [ ] The `agent_routing` section in `config.yaml` is no longer consulted by `maestro.implement`
- [ ] The `maestro.implement` command reads the agent from the task's assignee field instead
- [ ] The routing decision is logged so the user can see which agent was selected and why
- [ ] Backward compatibility is maintained: if no assignee exists, the system defaults to `general` (not to the old label routing)

---

## 4. Success Criteria

The feature is considered complete when:

1. The `maestro.plan.md` command contains a file-pattern-to-agent mapping table that the planner uses to assign agents to tasks
2. Every task generated by the planner has an explicit agent assignee based on its target files
3. Tasks touching files of different agent specializations are split into separate tasks during planning
4. `maestro.implement` reads the task assignee and uses it as the `subagent_type` when spawning sub-agents
5. Existing plans without agent assignees continue to work, defaulting to `general`
6. The label-based `agent_routing` in `config.yaml` is no longer used for agent selection

---

## 5. Scope

### 5.1 In Scope

- Adding a file-pattern-to-agent mapping table to `maestro.plan.md`
- Updating the planner to assign agents per task based on file patterns
- Implementing task splitting when files match multiple agent patterns
- Modifying `maestro.implement` to read agent from task assignee instead of label routing
- Removing the dependency on `agent_routing` in `config.yaml`
- Backward compatibility for existing plans without assignees
- Runtime fallback to `general` for invalid or missing agent names

### 5.2 Out of Scope

- Validating agent names at configuration or plan time (runtime only)
- Supporting regex patterns (glob patterns are sufficient)
- Auto-detecting available agents in the environment
- Dynamically reading the mapping from `config.yaml` (the mapping is static in the `.md` file)
- Changing the `config.yaml` file structure (the `agent_routing` section can remain but will be ignored)

### 5.3 Deferred

- Agent validation at config/plan time (could be added in a future iteration)
- Per-task agent override via inline annotations in task descriptions
- Agent capability discovery (querying what agents are available in the environment)
- Removing the `agent_routing` section from `config.yaml` entirely (can be cleaned up later)

---

## 6. Dependencies

- The existing `maestro.plan.md` command and plan template
- The existing `maestro.implement` command and its sub-agent spawning logic
- Task descriptions must include file paths for pattern matching to work (this is already the case in the current plan template)
- The bd task system must support an assignee field

---

## 7. Open Questions

All clarification markers have been resolved.

---

## 8. Risks

- **Plan complexity increase** — The planner now has more responsibility (assigning agents, splitting tasks). This could make plan generation slower or produce unexpected splits. Mitigation: clear splitting rules and visible output.
- **Task proliferation from splitting** — Aggressive splitting could create many small tasks where one would suffice. Mitigation: only split when files match genuinely different agent patterns.
- **Stale mapping** — If the project adds new file types, the mapping in `maestro.plan.md` may not cover them. Mitigation: default fallback to `general` ensures nothing breaks.
- **Breaking change** — Removing label-based routing is a breaking change for any workflow that depends on the `agent_routing` config. Mitigation: backward compatibility through `general` default, and the `agent_routing` section remains in config (just ignored).

---

## Changelog

| Date       | Change                               | Author |
| ---------- | ------------------------------------ | ------ |
| 2026-02-19 | Initial spec created                 | System |
| 2026-02-19 | Resolved 5 markers + 3 implicit gaps | System |
