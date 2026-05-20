---
description: >
  Fork an existing feature spec into a new, independent spec.
  Carries over problem context, research references, and dependencies
  from the source while creating fresh user stories and success criteria
  for the new feature.
argument-hint: <description> or <source-feature-id> <description>
---

# maestro.fork

Fork a feature spec for: **$ARGUMENTS**

## Prerequisites

Before starting, verify the project has been initialized:

1. Confirm `.maestro/` directory exists in the project root
2. Confirm `.maestro/templates/spec-template.md` exists
3. Confirm `.maestro/state/` directory exists and contains at least one state file
4. If any is missing, tell the user to run project initialization first and stop

## Step 0: Read Constitution

Before proceeding, read `.maestro/constitution.md` if it exists.

The constitution informs:

- Domain constraints that must appear in the forked spec
- Security requirements that may need clarification markers
- Architecture patterns that affect scope decisions

If the constitution doesn't exist, proceed without it but suggest the user run `/maestro.init` first.

## Step 1: Parse Arguments

Parse `$ARGUMENTS` to determine the source feature and new description.

**Two valid invocation forms:**

1. **Auto-detect source:** `$ARGUMENTS` is only a description (no leading feature ID pattern)
   - Example: `/maestro.fork "vendor notification emails"`
   - Source feature will be resolved from the active git branch in Step 2

2. **Explicit source:** `$ARGUMENTS` starts with a feature ID followed by a description
   - Example: `/maestro.fork 037-lets-add-new-command-named-maestro-fork "vendor notification emails"`
   - The first token matching the pattern `NNN-slug` (three-digit number followed by a hyphen and slug) is the source feature ID
   - Everything after the source ID is the new feature description

**Detection logic:**

1. Check if the first token in `$ARGUMENTS` matches the pattern `^[0-9]{3}-[a-z0-9-]+$`
2. If it matches: treat it as `<source-feature-id>` and the rest as `<description>`
3. If it does not match: treat the entire `$ARGUMENTS` as `<description>` (auto-detect mode)

Store the parsed values:
- `new_description` — the description for the new feature
- `explicit_source_id` — the source feature ID if explicitly provided, or null

## Step 2: Resolve Source Feature

Determine which feature to fork from.

### 2a: Auto-Detect from Git Branch

If no explicit source was provided in Step 1:

1. Run `git branch --show-current` to get the active branch name
2. List all state files in `.maestro/state/` (excluding the `research/` subdirectory)
3. For each state file, read the `branch` field and compare it to the current branch
4. If a match is found: use that state file's `feature_id` as the source

**If no match is found:**

Display this error and stop:

```
Error: Cannot auto-detect source feature.

You are on branch '{current_branch}', which does not match any known feature.

To fork from a specific feature, provide its ID explicitly:
  /maestro.fork <source-feature-id> "description of new feature"

To see available features:
  /maestro.list
```

### 2b: Validate Explicit Source

If an explicit source was provided in Step 1:

1. Check that `.maestro/state/{explicit_source_id}.json` exists
2. If it does not exist, display an error and stop:

```
Error: Feature '{explicit_source_id}' not found.

No state file exists at .maestro/state/{explicit_source_id}.json

To see available features:
  /maestro.list
```

3. If it exists, use `explicit_source_id` as the source feature ID

Store the resolved values:
- `source_feature_id` — the resolved source feature ID
- `source_state` — the parsed contents of the source state file

## Step 3: Read and Validate Source Spec

1. Read the source state file: `.maestro/state/{source_feature_id}.json`
2. Get the `spec_path` from the state file
3. Read the source spec file at `{spec_path}`

### 3a: Extract Source Content

Parse the source spec and extract these sections:

- **Problem Statement** — the content under `## 1. Problem Statement`
- **Research Section** — the content under `## 6. Research`, including linked research items
- **Dependencies Section** — the content under `## 7. Dependencies`
- **In Scope Items** — the items listed under `### 5.1 In Scope`
- **Feature Title** — the title from the first heading `# Feature: {title}`
- **Changelog Table** — the markdown table under `## Changelog`

### 3b: Check for Minimal Content

If the source spec's problem statement is empty or contains only template placeholders (e.g., `{One to three paragraphs...}`), display a warning:

```
Warning: Source spec '{source_feature_id}' has minimal content.
The problem statement appears to be empty or still contains template placeholders.
Proceeding with fork, but the inherited context may be limited.
```

Proceed with the fork regardless — do not stop.

## Step 4: Create New Feature Scaffold

Run the helper script to create the feature directory and git branch:

```bash
bash .maestro/scripts/create-feature.sh "$new_description"
```

The script outputs JSON with the created paths. Parse it to get:

- `feature_id` — the NNN-slug identifier (e.g., `038-vendor-notification-emails`)
- `spec_dir` — the full path to the spec directory
- `branch` — the git branch name
- `worktree_name` — the human-readable worktree directory name
- `worktree_path` — the relative path where the worktree will be created

If the script fails, show the error and stop.

## Step 5: Read the Spec Template

Read the template from `.maestro/templates/spec-template.md`.

## Step 6: Generate Forked Specification

Fill in the spec template for the new feature, applying these carry-over rules:

### 6.1: Header Metadata

```markdown
# Feature: {new feature title derived from new_description}

**Spec ID:** {feature_id}
**Author:** {current user}
**Created:** {today's date}
**Last Updated:** {today's date}
**Status:** Draft
**Forked from:** {source_feature_id} — {source_feature_title}
```

The `Forked from` line is a new metadata field not in the standard template. Add it after `Status`.

### 6.2: Problem Statement (Carried Over + New)

The problem statement has two parts:

1. **Primary problem** — Generated from `new_description`. This is the main problem statement for the new feature, written from the user's perspective.
2. **Background Context** — The source spec's problem statement, clearly marked as inherited context.

Format:

```markdown
## 1. Problem Statement

{New problem statement generated from new_description — 1-3 paragraphs describing the new feature's problem from the user's perspective}

### Background Context

> *Inherited from {source_feature_id} — {source_feature_title}:*
>
> {Source spec's problem statement, quoted as a blockquote}

This fork addresses a related but distinct concern identified during the specification of {source_feature_title}.
```

### 6.3: Proposed Solution

Generate a fresh proposed solution based on `new_description`. Do NOT copy from source.

### 6.4: User Stories (Fresh — NOT Carried Over)

Generate fresh user stories based on `new_description` following the same rules as `/maestro.specify`:

- Use "As a [role], I want [action], so that [benefit]" format
- Each story must be testable
- Include `[NEEDS CLARIFICATION: ...]` markers for ambiguities
- At least 2 user stories

Do NOT copy user stories from the source spec.

### 6.5: Success Criteria (Fresh — NOT Carried Over)

Generate fresh success criteria based on `new_description`:

- Each criterion must be verifiable without reading code
- Use measurable language
- At least 2 success criteria

Do NOT copy success criteria from the source spec.

### 6.6: Scope

**In Scope:** Generate fresh in-scope items based on `new_description`.

**Out of Scope:** Pre-populate with the source spec's in-scope items as a starting point. These represent capabilities that belong to the source feature and are explicitly excluded from this fork. Format them as:

```markdown
### 5.2 Out of Scope

- {Source in-scope item 1} *(covered by {source_feature_id})*
- {Source in-scope item 2} *(covered by {source_feature_id})*
- {Additional out-of-scope items specific to this feature}
```

**Deferred:** Generate fresh deferred items if applicable, or leave as "None identified."

### 6.7: Research Section (Carried Over)

Copy the research section from the source spec:

```markdown
## 6. Research

### Linked Research Items

{Copy linked research items from source spec}

### Research Summary

Inherited from {source_feature_id}. {Source research summary}

{Add any additional research context specific to this fork if apparent from the description}
```

If the source has no research items, write "No research inherited from source. None conducted yet for this feature."

### 6.8: Dependencies Section (Carried Over)

Copy the dependencies from the source spec as a starting point:

```markdown
## 7. Dependencies

*Starting dependencies inherited from {source_feature_id}:*

{Source dependencies list}

{Add any additional dependencies specific to this fork}
```

If the source has no dependencies, write "None inherited. None identified for this feature."

### 6.9: Open Questions

Generate fresh open questions based on `new_description`. Include at least 1 `[NEEDS CLARIFICATION: ...]` marker.

### 6.10: Risks

Generate fresh risks based on `new_description`, or write "None identified — to be explored during clarification."

### 6.11: Changelog

```markdown
## Changelog

| Date       | Change                                        | Author   |
| ---------- | --------------------------------------------- | -------- |
| {today}    | Initial spec created (forked from {source_feature_id}) | {author} |
```

## Step 7: Write the Spec File

Write the completed specification to `{spec_dir}/spec.md` (where `{spec_dir}` is from the script output in Step 4).

## Step 8: Validate

After writing the spec, do a self-check:

- [ ] No technology or implementation details mentioned
- [ ] At least 2 user stories defined
- [ ] At least 2 success criteria defined
- [ ] At least 1 `[NEEDS CLARIFICATION]` marker present
- [ ] Out of scope section includes source's in-scope items
- [ ] "Forked from" metadata is present in the header
- [ ] Background Context section is present with source problem statement
- [ ] Every user story is independently testable

If any check fails, revise the spec before proceeding.

## Step 9: Create Fork State File

Create the state file at `.maestro/state/{feature_id}.json`:

```json
{
  "feature_id": "{feature_id}",
  "created_at": "{ISO timestamp}",
  "updated_at": "{ISO timestamp}",
  "stage": "specify",
  "spec_path": "{spec_dir}/spec.md",
  "branch": "{branch}",
  "worktree_name": "{worktree_name}",
  "worktree_path": "{worktree_path}",
  "worktree_branch": "{branch}",
  "worktree_created": false,
  "forked_from": "{source_feature_id}",
  "clarification_count": 0,
  "user_stories": 0,
  "research_ids": [],
  "history": [{ "stage": "specify", "timestamp": "{ISO}", "action": "created (forked from {source_feature_id})" }]
}
```

Where:

- `{feature_id}`, `{spec_dir}`, `{branch}`, `{worktree_name}`, `{worktree_path}` come from Step 4 scaffold output
- `forked_from` is the `source_feature_id` resolved in Step 2
- `clarification_count` is the number of `[NEEDS CLARIFICATION]` markers in the generated spec
- `user_stories` is the number of user stories in the generated spec
- `research_ids` is an array of research IDs inherited from the source (if any)

## Step 10: Update Source State File

Read the source state file at `.maestro/state/{source_feature_id}.json` and update it:

1. If the `forks` field exists, append `{feature_id}` to the array
2. If the `forks` field does not exist, create it as `["feature_id"]`
3. Update `updated_at` to the current ISO timestamp
4. Append to the `history` array: `{ "stage": "{current_stage}", "timestamp": "{ISO}", "action": "forked to {feature_id}" }`
5. Write the updated state file back

## Step 11: Update Source Spec Changelog

Append a new row to the source spec's changelog table:

1. Read the source spec at `{source_state.spec_path}`
2. Find the `## Changelog` section and its markdown table
3. Append a new row:

```
| {today's date} | Forked to {feature_id} | {author} |
```

4. Write the updated source spec back

**Important:** Only the changelog table is modified in the source spec. No other content is changed.

## Step 12: Report and Suggest Next Steps

Show the user:

1. A summary of what was created:
   - Source feature: {source_feature_id} — {source_feature_title}
   - New feature ID: {feature_id}
   - Branch name: {branch}
   - Worktree name: {worktree_name} (will be created at {worktree_path} during /maestro.implement)
   - Spec file path: {spec_dir}/spec.md
   - Number of user stories generated
   - Number of clarification markers found
   - Sections carried over: problem context, research, dependencies
   - Sections generated fresh: user stories, success criteria, proposed solution

2. Suggest the next command:
   - If there are `[NEEDS CLARIFICATION]` markers: "Run `/maestro.clarify` to resolve the {N} clarification markers before planning."
   - If the spec is clean (no markers): "Run `/maestro.plan` to break this spec into implementation tasks."

---

**Remember:** A forked spec is an independent feature from the moment of creation. It maintains a lightweight reference back to its origin for traceability, but has no runtime dependency on the source spec. Get the fork's scope right and everything downstream improves.
