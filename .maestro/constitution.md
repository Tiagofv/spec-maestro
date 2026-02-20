# Project Constitution

**Project:** agent-maestro
**Created:** 2024-02-19
**Last Updated:** 2024-02-19

---

## 1. Architecture Principles

### 1.1 Core Architecture

Modular monolith with clear separation between:

- Orchestrator: Workflow coordination
- Agents: Specialized task executors

### 1.2 Layer Separation

- **Domain Layer** — Business logic, entities, value objects
- **Application Layer** — Use cases, commands, queries
- **Infrastructure Layer** — Database, external services, messaging
- **Presentation Layer** — API, UI, CLI

### 1.3 Dependency Rules

- Domain never imports Infrastructure
- Application depends only on Domain
- Infrastructure implements interfaces defined in Domain
- Presentation depends on Application

### 1.4 Communication Patterns

- Sync: Direct function calls within layers
- Async: Event-driven between orchestrator and agents
- Patterns: Command pattern for task execution

---

## 2. Code Standards

### 2.1 Language-Specific Standards

**Python:**

- Follow PEP 8
- Use type hints
- Maximum line length: 100 characters
- Docstrings for all public methods

**Rust:**

- Follow rustfmt conventions
- Use clippy for linting
- Comprehensive error handling with Result types

### 2.2 Naming Conventions

- Files: snake_case.py
- Classes: PascalCase
- Functions/Methods: snake_case
- Constants: UPPER_SNAKE_CASE
- Private members: \_leading_underscore

### 2.3 Error Handling

- Wrap errors with context using fmt.Errorf or anyhow
- Never return bare errors
- Use custom error types for domain errors
- Always handle all error cases

### 2.4 Testing Standards

- Unit tests for all business logic
- Integration tests for external dependencies
- Minimum coverage: 80%
- Table-driven tests preferred
- Mock external dependencies

---

## 3. Review Requirements

### 3.1 Required Reviews

All code changes require review before merge.

### 3.2 Review Checklist

- [ ] No hardcoded secrets or credentials
- [ ] Error handling is complete
- [ ] Tests cover happy path and edge cases
- [ ] No breaking changes to public APIs
- [ ] Performance implications considered
- [ ] Constitutional compliance verified

### 3.3 Approval Requirements

- At least one approval from team member
- All CI checks must pass
- No unresolved review comments

---

## 4. Domain-Specific Rules

### 4.1 Business Logic Constraints

- All task IDs must be validated before processing
- State transitions must be logged
- Constitution rules take precedence over code patterns

### 4.2 Integration Patterns

- External API calls must have timeouts
- Retry logic with exponential backoff
- Circuit breaker for external dependencies

### 4.3 Security Requirements

- No credentials in logs
- Input validation on all boundaries
- Sanitize user inputs

---

## 5. Out of Scope for AI Agents

- Database migrations that drop columns/tables
- Changes to authentication/authorization logic
- Modifications to critical business logic
- Deletion of production data
- Changes to encryption keys or secrets
- Changes to agent routing configuration

---

## 6. Reference Files

- `.maestro/config.yaml` — Project configuration
- `.maestro/commands/` — Available maestro commands
- `AGENTS.md` — AI agent instructions
- `.maestro/templates/` — Templates for various artifacts

---

## Changelog

| Date       | Change                       | Author |
| ---------- | ---------------------------- | ------ |
| 2026-02-19 | Removed Planner from core architecture (feature 008) | Maestro |
| 2024-02-19 | Initial constitution created | System |
