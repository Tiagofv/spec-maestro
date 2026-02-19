# Post-Epic Analysis Workflow

This workflow runs after all tasks in an epic are closed. It collects metrics, identifies patterns, and proposes improvements.

## When to Run

Trigger `/maestro.analyze` when:

- `bd stats` shows 0 open tasks for the epic
- `/maestro.implement` reaches Step 8 (automatic trigger)
- Manual analysis of any completed epic

## Data Sources

All data comes from structured close reasons on bd tasks:

| Field   | Source              | Example                            |
| ------- | ------------------- | ---------------------------------- |
| verdict | Close reason prefix | PASS, MINOR, CRITICAL, DONE, FIXED |
| files   | `files:` key        | handler.go,repo.go                 |
| layer   | `layer:` key        | consumer, command                  |
| cause   | `cause:` key        | feature-regression, nil-pointer    |
| pattern | `pattern:` key      | consumer-handler, event-struct     |
| ref     | `ref:` key          | eventHandler.go                    |

## Analysis Pipeline

1. **Collect** — Gather all closed tasks with close reasons
2. **Parse** — Extract structured fields from pipe-delimited reasons
3. **Aggregate** — Group by layer, cause, pattern, verdict
4. **Compute** — Calculate rates, distributions, chains
5. **Propose** — Generate improvement proposals above threshold
6. **Present** — Show to human for approval
7. **Apply** — Implement approved changes

## Proposal Types

| Type                  | Threshold             | Target File                   |
| --------------------- | --------------------- | ----------------------------- |
| Risk reclassification | 5+ reviews            | cookbook/review-routing.md    |
| Convention update     | 2+ same-cause bugs    | reference/conventions.md      |
| Checklist item        | 2+ preventable bugs   | commands/maestro.implement.md |
| New command           | 3+ workflow repeats   | commands/                     |
| New skill             | 5+ same-pattern impls | skills/                       |
| New agent             | 10+ spawns            | config.yaml agent_routing     |

## Key Principle

**Never auto-apply.** All changes require human approval. The analyze command presents data and recommendations — the human decides what to adopt.
