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
- [ ] No narrowed implementations (multi-entity to single-entity)
- [ ] No removed imports that served existing code
- [ ] No deleted method implementations

### How to Check

1. Look at the `-` (removed) lines in the diff
2. For each removed line with logic, ask: "Does the task require this removal?"
3. If not required -> CRITICAL with cause "feature-regression"

### Example

```diff
- case Notification:
-   return handleNotification(ctx, event)
+ case AuditLog:
+   return handleAuditLog(ctx, event)
```

If the task was "Add audit logging", the notification case should NOT be removed. This is a feature regression.

## Convention Injection

### Convention Application

When reviewing, apply conventions in this order:

1. **Local conventions** (from project CLAUDE.md `## Review Conventions` section) — highest priority
2. **Global conventions** (from `.maestro/reference/conventions.md`) — base layer
3. **Language idioms** (standard patterns for the language)

### Verdict Rules

- **PASS**: No issues at all. The code is correct, follows conventions, and doesn't regress.
- **MINOR**: Has issues that don't block merge (style, naming, optimization suggestions)
- **CRITICAL**: Must be fixed before merge (regression, security, data integrity, broken logic)

### Issue Ordering

When reporting issues:

1. CRITICAL issues first (ordered by: feature-regression > security > data-loss > logic)
2. MINOR issues second (ordered by: error-handling > style > naming)

### False Positives to Avoid

Don't flag these as issues:

- Imports that look unused but are used via side effects
- Code that looks "dead" but is called via reflection/interface
- Style choices that are consistent with existing codebase (even if not your preference)
- Test utilities/helpers that serve other tests

### Things to Always Catch

Always flag these regardless of context:

- Hardcoded credentials, API keys, or secrets
- SQL injection vectors (string concatenation in queries)
- Infinite loops without exit conditions
- Race conditions in concurrent code
- PII logged in plain text
