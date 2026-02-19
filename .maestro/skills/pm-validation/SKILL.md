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
