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

| Task Type      | Relevant Sections                                      |
| -------------- | ------------------------------------------------------ |
| Specification  | Architecture Principles, Domain-Specific Rules         |
| Planning       | All sections                                           |
| Implementation | Code Standards, Layer Separation, Dependency Rules     |
| Review         | Review Requirements, Error Handling, Testing Standards |

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
- Meet testing standards

**During review:**

- Use the review checklist from the constitution
- Check layer boundary violations
- Verify error handling compliance
- Confirm testing standards are met

## Enforcement Examples

### Layer Boundary Check

If constitution says "Domain never imports Infrastructure":

- Flag `import "myproject/infrastructure/db"` in a domain file as CRITICAL
- Suggest moving the dependency to a higher layer

### Error Handling Check

If constitution says "All errors must be wrapped with context":

- Flag bare `return err` as MINOR
- Suggest `return fmt.Errorf("doing X: %w", err)`

### Testing Standards Check

If constitution says "Coverage target: 80%":

- Check coverage report before approving
- Flag untested edge cases

### Security Check

If constitution says "PII must be encrypted at rest":

- Flag plain-text PII fields as CRITICAL
- Check database column encryption

## Escalation

If you encounter a situation where:

1. The constitution doesn't cover the case → Note it in the review/implementation as "constitutional gap" and proceed with best judgment
2. The task conflicts with the constitution → Flag it as BLOCKED and explain the conflict
3. You're unsure about interpretation → Default to the stricter reading
