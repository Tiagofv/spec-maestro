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

| Decision   | Options Considered | Chosen   | Rationale |
| ---------- | ------------------ | -------- | --------- |
| {decision} | {options}          | {chosen} | {why}     |

---

## 2. Component Design

### 2.1 New Components

#### Component: {Name}

- **Purpose:** {one sentence}
- **Location:** {file path}
- **Dependencies:** {what it depends on}
- **Dependents:** {what will depend on it}

### 2.2 Modified Components

#### Component: {Name}

- **Current:** {what it does now}
- **Change:** {what will change}
- **Risk:** {Low/Medium/High — potential for regression}

---

## 3. Data Model

### 3.1 New Entities

#### Entity: {Name}

```
{Schema definition — language agnostic}
```

### 3.2 Modified Entities

#### Entity: {Name}

- **Current fields:** {list}
- **New fields:** {list}
- **Migration notes:** {any special migration considerations}

### 3.3 Data Flow

{Describe how data flows through the system}

---

## 4. API Contracts

### 4.1 New Endpoints/Methods

#### {METHOD} {path}

- **Purpose:** {one sentence}
- **Input:** {request schema}
- **Output:** {response schema}
- **Errors:** {possible error responses}

### 4.2 Modified Endpoints

#### {METHOD} {path}

- **Current behavior:** {what it does}
- **New behavior:** {what changes}
- **Breaking:** {Yes/No}

---

## 5. Implementation Phases

### Phase 1: {Name}

- **Goal:** {what this phase achieves}
- **Tasks:**
  - {task 1} — Assignee: {agent}
  - {task 2} — Assignee: {agent}
- **Deliverable:** {what can be demonstrated/tested}

### Phase 2: {Name}

- **Goal:** {what this phase achieves}
- **Dependencies:** {what must be done first}
- **Tasks:**
  - {task 1} — Assignee: {agent}
  - {task 2} — Assignee: {agent}
- **Deliverable:** {what can be demonstrated/tested}

---

## 6. Task Sizing Guidance

When breaking down implementation into tasks, ensure all tasks are **XS** or **S** size only. **M** and **L** tasks must be split before they can be assigned.

### 6.1 Size Definitions

| Size   | Time Range                   | Status                   |
| ------ | ---------------------------- | ------------------------ |
| **XS** | 0-120 minutes (0-2 hours)    | ✅ Accepted              |
| **S**  | 121-360 minutes (2-6 hours)  | ✅ Accepted              |
| **M**  | 361-720 minutes (6-12 hours) | ❌ REJECTED - must split |
| **L**  | 721+ minutes (12+ hours)     | ❌ REJECTED - must split |

**Agent Assignment:** Every task must have an assignee (agent name). The assignee is determined by matching the task's target files against the file-pattern-to-agent mapping table in `maestro.plan.md`. If no pattern matches, the assignee defaults to `general`.

### 6.2 Complexity Indicators

Use these keywords and weights to estimate task size:

**High Complexity (25-30 points):**

- `refactor`, `architecture`, `redesign`, `migrate`, `rewrite`

**Medium Complexity (10-20 points):**

- `implement` (20), `create` (15), `build` (15), `design` (15), `integrate` (15), `configure` (10), `setup` (10)

**Low Complexity (2-5 points):**

- `fix` (5), `update` (5), `add` (5), `remove` (5), `rename` (3), `typo` (2), `docs` (3), `documentation` (3)

Estimated minutes are computed from complexity score (approximately `score * 3`, bounded to 15-1440 minutes).

### 6.3 Splitting Strategies for Oversized Tasks

When a task exceeds S size (360 min), apply these splitting strategies:

**Split by File:**

- If a task modifies multiple files, create separate tasks per file
- Example: Instead of "Update auth middleware and user service", create two tasks

**Split by Operation:**

- Separate high-complexity operations into individual tasks
- Example: "Refactor database layer and migrate user data" → two separate tasks

**Split Setup from Implementation:**

- Create one task for setup/configuration
- Create another for actual implementation
- Example: "Setup Redis and implement caching" → separate into two tasks

**Split by 'And' Clauses:**

- If a task description contains "and" joining multiple actions, split it
- Example: "Add login form and implement password reset" → two separate tasks

### 6.4 Ambiguity Indicators (Scope Creep Signals)

These words and patterns signal vague scope - replace with specific, countable deliverables:

- `etc`, `etc.`
- `various`
- `multiple`
- `several`
- `...`
- `and more`
- `and others`
- `including but not limited`
- `some`, `many`, `few`

**Action:** When you see these terms, ask: "What exactly?" Replace with specific counts or lists.

---

## 7. Testing Strategy

### 7.1 Unit Tests

- {test category 1}
- {test category 2}

### 7.2 Integration Tests

- {test category 1}

### 7.3 End-to-End Tests

{What E2E tests will be written, if any}

### 7.4 Test Data

{What test data/fixtures are needed}

---

## 8. Risks and Mitigations

| Risk   | Likelihood | Impact  | Mitigation   |
| ------ | ---------- | ------- | ------------ |
| {risk} | {L/M/H}    | {L/M/H} | {mitigation} |

---

## 9. Open Questions

- {question 1}
- {question 2}
