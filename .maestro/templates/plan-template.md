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

---

## 6. Testing Strategy

### 6.1 Unit Tests

- {test category 1}
- {test category 2}

### 6.2 Integration Tests

- {test category 1}

### 6.3 End-to-End Tests

{What E2E tests will be written, if any}

### 6.4 Test Data

{What test data/fixtures are needed}

---

## 7. Risks and Mitigations

| Risk   | Likelihood | Impact  | Mitigation   |
| ------ | ---------- | ------- | ------------ |
| {risk} | {L/M/H}    | {L/M/H} | {mitigation} |

---

## 8. Open Questions

- {question 1}
- {question 2}
