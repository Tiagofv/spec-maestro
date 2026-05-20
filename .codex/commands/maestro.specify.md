---
description: >
  Generate a feature specification from a plain-language description.
  Creates a numbered spec directory, git branch, and structured spec.md
  following the Spec-Driven Development methodology.
argument-hint: <feature description in plain language>
---

# maestro.specify

Generate a feature specification for: **$ARGUMENTS**

## Prerequisites

Before starting, verify the project has been initialized:

1. Confirm `.maestro/` directory exists in the project root
2. Confirm `.maestro/templates/spec-template.md` exists
3. If either is missing, tell the user to run project initialization first and stop

## Step 0: Read Constitution

Before generating the spec, read `.maestro/constitution.md` if it exists.

The constitution informs:

- Domain constraints that must appear in success criteria
- Security requirements that may need clarification markers
- Architecture patterns that affect scope decisions

If the constitution doesn't exist, proceed without it but suggest the user run `/maestro.init` first.

## Step 0b: Parse Research References

Parse the feature description for research references:

**Research Reference Pattern:**

```
"(see research {research_id})"
"(research: {research_id})"
"ref: {research_id}"
```

Examples:

- `Implement OAuth (see research 20250311-oauth-patterns)`
- `Build caching layer (research: 20250312-cache-options)`
- `Database migration ref: 20250310-db-patterns`

**Extraction Logic:**

1. Search for patterns in $ARGUMENTS
2. Extract research_id from each match
3. Validate that research exists: `.maestro/state/research/{research_id}.json`
4. Store valid research_ids for context injection

## Step 0c: Find Existing Feature (for refine/update workflows)

If `$ARGUMENTS` contains an explicit feature ID (e.g., `070`, `070-improve-...`), use it directly. If the user is describing a new feature from scratch, skip to Step 1.

When re-specifying or refining an existing feature without an explicit ID, infer the active feature using the following rules.

**Resolving the feature ID (AI inference):**

1. If the user supplied an explicit feature ID or number (e.g., `070`, `070-improve-...`), use it directly.
2. Otherwise, infer from context using these signals in priority order:
   a. **Recent state activity**: List `.maestro/state/*.json` files, read their `updated_at` field, pick the most recently updated non-`complete` feature.
   b. **Current git branch**: Run `git branch --show-current`. If the branch matches `feat/NNN-...` or `NNN-...`, extract and use that feature ID.
   c. **Conversation context**: If the current conversation referenced a feature earlier, use that feature.
3. Surface the inferred feature ID to the user BEFORE taking any action:
   ```
   Inferred feature: 070-improve-maestro-tasks-command-speed (from: recent state activity)
   Proceeding… (reply with a different feature ID to override)
   ```
4. **On signal conflict** (e.g., state recency says 070 but branch says 069): Ask the user which to use.
5. **On no signals**: Treat as a new feature and proceed to Step 1.
6. **Exclude from inference**: Empty feature directories (spec.md missing or 0 bytes).

## Step 1: Create Feature Scaffold

Run the helper script to create the feature directory and git branch:

```bash
bash .maestro/scripts/create-feature.sh "$ARGUMENTS"
```

The script outputs JSON with the created paths. Parse it to get:

- `feature_id` — the NNN-slug identifier (e.g., `001-webhook-system`)
- `spec_dir` — the full path to the spec directory
- `branch` — the git branch name
- `worktree_name` — the human-readable worktree directory name
- `worktree_path` — the relative path where the worktree will be created (e.g., `.worktrees/my-feature`)

If the script fails, show the error and stop.

## Step 1b: Check for Existing Spec

After creating the feature scaffold, check if `{spec_dir}/spec.md` already exists:

- If it exists, offer two options:
  1. **Refine**: Read the existing spec and enhance it based on the new description
  2. **Replace**: Archive the old spec and create a fresh one

- If the user doesn't specify, default to **Refine** mode

In Refine mode:

- Read the existing spec
- Incorporate the new description as additional context
- Preserve existing clarification markers
- Add new sections as needed

## Step 1c: Load Research Context

If research references were found in Step 0b:

### 1c.1: Read Research Files

For each research_id found:

1. Read `.maestro/state/research/{research_id}.json`
2. Get the file_path from state
3. Read the research document from `.maestro/research/{research_id}.md`
4. Extract key findings for context

### 1c.2: Validate Research Relevance

Check that research is relevant to the feature:

- Research tags overlap with feature keywords
- Research query relates to feature description
- Research is not stale (>90 days old)

If stale, add warning but still include.

### 1c.3: Build Research Context

Compile research findings:

```markdown
## Research Context

### Linked Research Items

- **{research_id}** - {research_title}
  - Type: {source_type}
  - Key Finding: {summary}
  - Relevance: {High/Med/Low}

### Research Insights

{Key insights that inform this specification}

### Recommendations from Research

{Specific recommendations to consider}
```

This context will be injected into the spec generation.

## Step 2: Read the Spec Template

Read the template from `.maestro/templates/spec-template.md`.

## Step 2b: Determine the Repos Set

Determine which repos this feature touches and lock the value into `**Repos:**` before writing the spec. This field is required at specify-time and cannot be changed later (Decision 8.3).

**Inference (do this first):**

1. Read `$ARGUMENTS` and any problem-statement file paths mentioned for repo names or service names (e.g., `svc-accounts-receivable`, `alt-front-end`).
2. If none are found, default to the basename of the current `MAESTRO_BASE` directory (single-repo default).

**Confirmation:**

Present the inferred value to the user in one line:

> Repos this feature touches: **`<inferred value>`** — correct? (Add or remove names, or press Enter to accept.)

Wait for the user's response. Accept the corrected value if they provide one; otherwise use the inferred value.

**Examples of the final header line:**

- Single-repo: `**Repos:** spec-maestro`
- Multi-repo: `**Repos:** svc-accounts-receivable, alt-front-end`

Store the confirmed value as `repos_value` for use in Step 3.

## Step 3: Generate the Specification

Fill in the template based on the feature description provided in `$ARGUMENTS`.

**Rules for specification generation:**

0. **Write `repos_value` into the spec header**
   - Replace the `**Repos:**` placeholder in the template with the confirmed `repos_value` from Step 2b

1. **Focus on WHAT and WHY, never HOW**
   - Describe user-visible behavior
   - Describe the problem being solved
   - Do NOT mention technology, frameworks, libraries, or implementation patterns
   - Do NOT suggest database schemas, API designs, or architectural decisions

2. **Write concrete user stories**
   - Use "As a [role], I want [action], so that [benefit]" format
   - Each story must be testable — a QA engineer should be able to verify it
   - Avoid vague stories ("improve performance", "better UX")

3. **Mark uncertainty explicitly**
   - Use `[NEEDS CLARIFICATION: specific question]` for anything ambiguous
   - It is BETTER to mark something as needing clarification than to guess
   - At least 2-3 clarification markers are expected for any non-trivial feature

4. **Define success criteria as observable outcomes**
   - Each criterion must be verifiable without reading code
   - Use measurable language: "loads in under 2 seconds", "shows error message", "sends notification"

5. **Explicitly state what is out of scope**
   - Prevent scope creep by naming related things that are NOT included
   - Be specific: "OAuth integration is out of scope" not "advanced auth"

6. **Keep it concise**
   - The spec should be 1-3 pages, not a novel
   - If a section needs more than a paragraph, the feature may need splitting

## Step 4: Write the Spec File

Write the completed specification to `{spec_dir}/spec.md` (where `{spec_dir}` is from the script output in Step 1).

## Step 5: Validate

After writing the spec, do a self-check:

- [ ] No technology or implementation details mentioned
- [ ] At least 2 user stories defined
- [ ] At least 2 success criteria defined
- [ ] At least 1 `[NEEDS CLARIFICATION]` marker present
- [ ] Out of scope section is not empty
- [ ] Every user story is independently testable

If any check fails, revise the spec before proceeding.

## Step 5b: Update State

Create or update the state file at `.maestro/state/{feature_id}.json`:

```json
{
  "feature_id": "{feature_id}",
  "created_at": "{ISO timestamp}",
  "updated_at": "{ISO timestamp}",
  "stage": "specify",
  "repos": ["{repos_value}"],
  "worktrees": {},
  "spec_path": ".maestro/specs/{feature_id}/spec.md",
  "branch": "feat/{feature_slug}",
  "worktree_required": true,
  "worktree_created": false,
  "clarification_count": 0,
  "user_stories": 0,
  "research_ids": [],
  "history": [{ "stage": "specify", "timestamp": "{ISO}", "action": "created" }]
}
```

Where:

- `{feature_id}`, `{spec_dir}`, and `{branch}` come from Step 1 scaffold output
- `clarification_count` is the number of `[NEEDS CLARIFICATION]` markers in the generated spec
- `user_stories` is the number of user stories in the generated spec
- `research_ids` is an array of linked research IDs from Step 0b
- If the state file already exists (refine mode), append to the `history` array with action `"refined"` and update `updated_at`

### 5b.1: Link Research to Feature

For each research_id in `research_ids`:

```bash
.maestro/scripts/research-state.sh link {research_id} {feature_id}
```

This creates bidirectional linking:

- Feature state references research
- Research state references feature

## Step 6: Report and Suggest Next Steps

Show the user:

1. A summary of what was created:
   - Branch name
   - Worktree name: {worktree_name} (will be created at {worktree_path} during /maestro.implement)
   - Spec file path
   - Number of user stories
   - Number of clarification markers found

2. Suggest the next command:
   - If there are `[NEEDS CLARIFICATION]` markers: "Run `/maestro.clarify` to resolve the {N} clarification markers before planning."
   - If the spec is clean (no markers): "Run `/maestro.plan` to break this spec into implementation tasks."

---

**Remember:** The specification is the source of truth. Code is its expression. Get the spec right and everything downstream improves. Get it wrong and no amount of engineering fixes it.
