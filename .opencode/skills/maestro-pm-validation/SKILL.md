---
name: pm-validation
description: Final feature validation skill for checking regressions, acceptance criteria, implementation evidence, and scope discipline.
---

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

Acceptance criteria are written in EARS (When/While/If…then/Where/shall), so each criterion
is a literal, atomic assertion — validate them **1:1**. Read each criterion as `<condition> →
<system> shall <response>` and cite the code (and test) that makes that exact response happen.
Pay special attention to `If …, then …` (unwanted-behavior) criteria: a happy path that works
while its failure/edge criterion is unhandled is GAPS_FOUND, not COMPLETE.

#### EARS Criterion Validation Checklist

Each EARS shape points to a *specific kind* of evidence. Map every criterion 1:1 to
**file:line of code AND a test** that exercises it:

| EARS shape | Criterion form | Evidence to find |
| --- | --- | --- |
| Ubiquitous | `The … shall …` | the code path that **always** enforces it (no guard) + a test |
| Event-driven | `When … shall …` | the **trigger handler** + the observable **response** it produces + a test |
| State-driven | `While … shall …` | the **guarded/conditional path** active only in that state + a test |
| Optional | `Where … shall …` | the **feature-flag/config gate** that enables it + a test |
| Unwanted behavior | `If … then … shall …` | the **error/edge handler** AND a test that **exercises** that failure |

Emphasis:

- Cite each criterion **1:1** — one criterion, one `file:line` (plus its test). A criterion
  with no cited code or no cited test is not satisfied.
- An `If …, then …` criterion with **no matching error-handling code AND test** is
  **GAPS_FOUND**, even if the happy path is fully implemented and tested. A green happy
  path never covers for an unhandled failure path.

### Scope Discipline

The validator checks that the implementation matches the spec — no more, no less:

- Missing scope -> GAPS_FOUND
- Extra scope (gold plating) -> Note it, but not a failure
- Deviated scope (did something different) -> GAPS_FOUND with explanation

## Validation Workflow

1. **Regression scan** (git diff analysis)
2. **Requirements mapping** (spec -> code)
3. **Evidence collection** (specific citations)
4. **Verdict determination** (COMPLETE/GAPS_FOUND/REGRESSION/BLOCKED)
5. **Follow-up generation** (fix tasks for gaps)

## Escalation Rules

| Verdict    | Round 1      | Round 2      | Round 3           | Round 4+             |
| ---------- | ------------ | ------------ | ----------------- | -------------------- |
| GAPS_FOUND | Create fixes | Create fixes | ESCALATE to human | N/A                  |
| REGRESSION | Create fixes | Create fixes | Create fixes      | Continue until fixed |

Regressions have no round limit because they represent broken functionality that must be restored.
