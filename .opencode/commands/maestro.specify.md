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

## Step 1: Create Feature Scaffold

Run the helper script to create the feature directory and git branch:

```bash
bash .maestro/scripts/create-feature.sh "$ARGUMENTS"
```

The script outputs JSON with the created paths. Parse it to get:

- `feature_id` — the NNN-slug identifier (e.g., `001-webhook-system`)
- `spec_dir` — the full path to the spec directory
- `branch` — the git branch name

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

## Step 2: Read the Spec Template

Read the template from `.maestro/templates/spec-template.md`.

## Step 3: Generate the Specification

Fill in the template based on the feature description provided in `$ARGUMENTS`.

**Rules for specification generation:**

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
  "spec_path": "{spec_dir}/spec.md",
  "branch": "{branch}",
  "clarification_count": 0,
  "user_stories": 0,
  "history": [{ "stage": "specify", "timestamp": "{ISO}", "action": "created" }]
}
```

Where:

- `{feature_id}`, `{spec_dir}`, and `{branch}` come from Step 1 scaffold output
- `clarification_count` is the number of `[NEEDS CLARIFICATION]` markers in the generated spec
- `user_stories` is the number of user stories in the generated spec
- If the state file already exists (refine mode), append to the `history` array with action `"refined"` and update `updated_at`

## Step 6: Report and Suggest Next Steps

Show the user:

1. A summary of what was created:
   - Branch name
   - Spec file path
   - Number of user stories
   - Number of clarification markers found

2. Suggest the next command:
   - If there are `[NEEDS CLARIFICATION]` markers: "Run `/maestro.clarify` to resolve the {N} clarification markers before planning."
   - If the spec is clean (no markers): "Run `/maestro.plan` to break this spec into implementation tasks."

---

**Remember:** The specification is the source of truth. Code is its expression. Get the spec right and everything downstream improves. Get it wrong and no amount of engineering fixes it.
