---
description: >
  Answer PR review comments with learning memory. Fetches unresolved feedback,
  proposes fixes, applies with approval, replies in threads, and records findings
  to project memory for cross-repo convention learning.
argument-hint: [pr-number|pr-url]
---

# maestro.respond

Answer PR review comments and build memory from what reviewers flag.

## Input

Target PR: `$ARGUMENTS` (optional; if omitted, use the open PR for the checked-out branch)

## Goal

1. Fetch unresolved feedback first, newest first
2. Filter to actionable requests
3. Build a concrete fix plan
4. Propose exact code changes
5. Wait for approval before applying edits
6. Reply in the original review thread
7. Record findings to project memory (convention learning)

## Step 1: Resolve the Target PR

- If `$ARGUMENTS` is provided, use it as PR selector.
- If omitted, first check whether the currently checked-out branch has an open PR.

```bash
BRANCH=$(git branch --show-current)
gh pr list --state open --head "$BRANCH" --limit 1 --json number,url,title,headRefName
```

- If `BRANCH` is empty (detached HEAD), stop and ask the user for a PR number/URL.
- If the result is empty, stop and explain that no open PR exists for the local branch, and ask the user to pass a PR number/URL.
- If found, use that PR number as the selector.
- Read PR metadata first:

```bash
gh pr view ${ARGUMENTS:-} --json number,title,url,headRefName,baseRefName,author,isDraft
```

If no PR is found, stop and explain how to pass a PR number or URL.

## Step 2: Fetch Feedback (unresolved, newest first)

Always fetch in this order:
1. Reviews
2. Review-thread comments
3. PR conversation comments

Default prioritization must always be:
- unresolved review threads first
- then newest activity first

Use GraphQL for unresolved thread status and keep newest-first sorting:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
OWNER=${REPO%/*}
NAME=${REPO#*/}
PR=$(gh pr view ${ARGUMENTS:-} --json number -q .number)

# Reviews (newest first)
gh api "repos/$REPO/pulls/$PR/reviews?per_page=100" --jq 'sort_by(.submitted_at // .id) | reverse'

# Review threads (unresolved first, then newest)
gh api graphql -f owner="$OWNER" -f name="$NAME" -F pr="$PR" -f query='query($owner:String!, $name:String!, $pr:Int!) { repository(owner:$owner, name:$name) { pullRequest(number:$pr) { reviewThreads(first:100) { nodes { id isResolved isOutdated path line updatedAt comments(first:20) { nodes { id databaseId author { login } body createdAt url } } } } } } }' --jq '.data.repository.pullRequest.reviewThreads.nodes | sort_by(.updatedAt) | reverse | sort_by(.isResolved)'

# PR conversation comments (newest first)
gh api "repos/$REPO/issues/$PR/comments?sort=created&direction=desc&per_page=100"
```

Then summarize only recent and relevant items:
- prioritize unresolved threads and `CHANGES_REQUESTED` reviews
- include latest inline review comments from unresolved threads first
- include issue comments that request concrete changes
- ignore pure approvals, bots, and non-actionable chatter

**If no actionable comments exist, exit silently with no output.**

## Step 3: Build the Fix Plan

Create a concise, numbered plan with one item per actionable request:

```
Fix plan for PR #<number>:

1. <short request title>
   - Source: <review/comment + author>
   - Files: <path(s)>
   - Proposed change: <what to change and why>

2. ...
```

If feedback conflicts, call it out and propose the safest default.

## Step 4: Draft Suggested Fixes (do not apply yet)

For each plan item, inspect the referenced files and produce a concrete proposal:

- show targeted file references
- include a small diff-style snippet when possible
- explain why it addresses the reviewer concern

Use this response format:

```
Proposed fixes for approval:

[1] <title>
File: path/to/file.ext:line
Diff:
<diff snippet>
Rationale: <1-2 lines>

[2] ...

Approve changes? (all / list of ids / revise)
```

## Step 5: Approval Gate (mandatory)

Never edit files before explicit approval.

- `all` -> apply all proposed fixes
- `list of ids` -> apply only selected items
- `revise` -> update proposals and re-present

## Step 6: Apply Approved Fixes

After approval:

1. Apply only approved edits
2. Run targeted checks (tests/lint/typecheck) for touched areas
3. Report what changed and any remaining risks

If checks fail, fix them before finalizing, or report exactly what is still failing.

## Step 7: Respond in Thread (no new top-level comment)

After each approved fix is applied, reply on the originating review thread/comment.

- Never post a new standalone PR comment for thread-based requests.
- For review comments, reply to the exact thread:

```bash
gh api "repos/$REPO/pulls/$PR/comments/<comment_id>/replies" -f body="Addressed in <commit-or-diff-summary>."
```

- If feedback came from a PR conversation comment (not a review thread), keep it in the final summary and only post there when in-place reply is supported.
- Include what changed and where (file + short note) in each thread reply.

## Step 8: Record Finding (Memory Write-Back)

After each fix is applied, silently record the finding to build cross-repo convention memory.

### 8a: Classify the Finding

For each fix that was applied, determine:

- **Pattern category**: A short kebab-case name for what was wrong (e.g., `bare-error-return`, `missing-nil-check`, `wrong-handler-naming`, `missing-input-validation`)
- **Scope**: Infer from the current repo's language/framework:
  - Go project (has `go.mod`) → `go`
  - React/TypeScript project (has `package.json` with react) → `react`
  - Python project (has `requirements.txt` or `pyproject.toml`) → `python`
  - If the finding is language-agnostic (e.g., "never log PII") → `all`
  - If repo-specific → `repo:{repo-name}`
- **Reviewer**: Who flagged it
- **What was wrong**: One-line description
- **What the fix was**: One-line description of the change applied

### 8b: Check Existing Memory

Read the project memory index (MEMORY.md) and check:

1. Does a `convention_{pattern}.md` memory file already exist for this pattern?
   - If yes → this pattern is already a convention. Skip memory write. The system already learned this.
2. Does an `observation_{pattern}.md` memory file already exist?
   - If yes → append a new occurrence to the observation file. Update the occurrence count in MEMORY.md.
3. Neither exists?
   - Create a new `observation_{pattern}.md` file in project memory.
   - Add an entry to MEMORY.md under `## Observations (pending patterns)`.

### 8c: Observation Memory File Format

When creating a new observation:

```markdown
---
name: {Pattern name} (observation)
description: {One-line pattern description — 1 occurrence}
type: feedback
---
[scope: {inferred scope}]
[status: observation]

### Occurrences
- {repo}: {file}:{line} (reviewer: {name}, PR #{num}) — {what was wrong}

### Pattern
{Brief description of what the reviewer flagged}
```

When appending to an existing observation, add to the Occurrences list and update the description's occurrence count.

### 8d: Propose Convention Promotion

After recording the observation, ask the developer:

```
Pattern "{pattern-name}" has been seen {N} time(s) across {M} repo(s).
Inferred scope: {scope}

Promote to active convention? [yes / no / skip]
```

- Show the inferred scope for confirmation — the developer can override it.
- If **yes**: 
  1. Generate a draft convention with Do/Don't examples based on the accumulated evidence
  2. Show the draft for editing
  3. Delete the `observation_{pattern}.md` file
  4. Create `convention_{pattern}.md` with the approved content
  5. Update MEMORY.md: move from Observations to Conventions section
- If **no** or **skip**: observation remains as-is. May be asked again when new evidence appears.

### 8e: Convention Memory File Format

```markdown
---
name: {Convention name}
description: {One-line — used for MEMORY.md index and relevance matching}
type: feedback
---
[scope: {scope}]

{Convention rule — one or two sentences}
- Do: {correct example}
- Don't: {incorrect example}

**Why:** {Reason this matters}
**How to apply:** {When and where to apply this convention}

Evidence: {PR references with reviewer names}
Promoted: {date}
```

### 8f: MEMORY.md Sections

Ensure these sections exist in MEMORY.md (create if missing):

```markdown
## Conventions (learned from PR reviews)
- [{Convention name}](convention_{slug}.md) — [scope: {X}] {One-line rule}

## Observations (pending patterns)
- [{Pattern name}](observation_{slug}.md) — [scope: {X}] {N} occurrences across {M} repos
```

## Constraints

- Do not push
- Do not commit unless user asks
- Keep edits minimal and scoped to reviewer feedback
- Preserve unrelated local changes
- Prefer existing project patterns and conventions
- By default, process unresolved + newest feedback first
- Fetch reviews before comments
- Reply in existing review threads whenever possible; avoid new top-level comments
- Memory write-back is silent — the developer sees the fix flow, not the bookkeeping (except for promotion prompts)

## Output Expectations

Always provide:

1. Unresolved-first, newest-first actionable feedback summary
2. Numbered fix plan
3. Proposed diffs awaiting approval
4. Post-approval implementation report
5. Thread replies posted
6. Memory findings recorded (silent, unless promotion proposed)
