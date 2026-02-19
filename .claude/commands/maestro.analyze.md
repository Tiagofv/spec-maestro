---
description: >
  Post-epic learning: collect metrics, compute patterns, generate improvement proposals.
  Presents proposals for human approval. Never auto-applies.
argument-hint: [feature-id]
---

# maestro.analyze

Analyze the completed epic and propose improvements.

## Step 1: Collect Data

Find the epic and gather all closed tasks:

```bash
bd list --all --parent {epic_id} --json --limit 0
```

Group tasks by label:

- Implementation tasks (backend, frontend, test)
- Review tasks (review)
- Fix tasks (fix)
- PM validation tasks (pm-validation)

## Step 2: Parse Close Reasons

For each task, parse the `close_reason` field:

```
"VERDICT | key: value | key: value"
```

Extract structured data:

- `verdict` — PASS, MINOR, CRITICAL, FIXED, DONE, SKIPPED, etc.
- `files` — which files were touched
- `layer` — architectural layer
- `cause` — bug category
- `pattern` — implementation pattern
- `ref` — reference file used

Build a dataset for analysis.

## Step 3: Compute Metrics

### Review Metrics

- Count by verdict: PASS / MINOR / CRITICAL / SKIPPED
- Calculate skip rate: SKIPPED / total reviews
- Group CRITICAL by layer → bug rate per layer
- Count FALSE_POSITIVE on fix tasks → review accuracy

### Fix Chain Metrics

- Group by cause → cause distribution
- Count total fix chains (fix → review → fix cycles)
- Identify repeat causes (same cause 3+ times)

### Implementation Metrics

- Group by pattern → pattern frequency
- Group by ref → most-used reference files
- Cross-reference: which patterns had fix chains?

### Regression Metrics

- Count regressions detected by reviewer
- Count regressions detected by PM validator
- Track which layer caught it first
- Identify fragile files (multiple regressions)

## Step 4: Generate Proposals

Based on the metrics, generate improvement proposals:

### A. Existing Artifact Changes

**Risk Reclassification** (threshold: 5+ data points):

- Layer with 0% bug rate → propose demotion to LOW
- Layer with >30% bug rate → confirm HIGH

**Convention Updates** (threshold: 2+ bugs from same cause):

- Propose new convention entry in `reference/conventions.md`

**Checklist Updates** (threshold: 2+ preventable bugs):

- Propose checklist item in orchestrator prompt

### B. New Artifact Proposals

**New Commands** (threshold: 3+ repetitions of same workflow):

- Include: detection evidence, skeleton file, expected savings
- Example: `/fix-chain` for automating fix-review-close

**New Skills** (threshold: 5+ implementations with same pattern):

- Include: detection evidence, SKILL.md skeleton, reference file
- Example: `consumer-scaffold` for repeated handler creation

**New Agents** (threshold: 10+ spawns with same context OR 1+ false positive from missing context):

- Include: detection evidence, what it wraps, what it auto-injects
- Example: specialized reviewer with domain conventions baked in

## Step 5: Present for Approval

For each proposal, show:

```
## Proposal {N}: {Type}

### What Changes
{file path + diff or skeleton}

### Why
{data that motivated it — task IDs, counts, percentages}

### Expected Impact
{estimated savings or quality improvement}

### Approve?
[yes/no/skip]
```

Human approves/rejects each independently. Never auto-apply.

## Step 6: Apply Approved Changes

For approved proposals:

- Edit existing files (add convention entries, update risk tables)
- Create new files (commands, skills, agents)
- Update documentation

## Step 7: Report Summary

Show the user:

1. Epic analyzed: {feature_id}
2. Tasks reviewed: {count}
3. Metrics computed:
   - Review pass rate: {X}%
   - Bug rate: {Y} per 100 tasks
   - Top causes: {list}
4. Proposals generated: {count}
5. Proposals approved: {count}
6. Changes applied: {list}

---

## Minimum Thresholds

These thresholds prevent noise from small sample sizes:

| Proposal Type         | Minimum Data Points                  |
| --------------------- | ------------------------------------ |
| Risk reclassification | 5+ reviews of that layer             |
| New convention entry  | 2+ bugs from same cause              |
| Checklist item        | 2+ preventable bugs                  |
| New command           | 3+ repetitions of workflow           |
| New skill             | 5+ implementations with same pattern |
| New agent             | 10+ spawns OR 1+ false positive      |

Proposals that don't meet thresholds are noted but not presented.
