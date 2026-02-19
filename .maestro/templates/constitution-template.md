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

| Date   | Change                       | Author   |
| ------ | ---------------------------- | -------- |
| {DATE} | Initial constitution created | {AUTHOR} |
