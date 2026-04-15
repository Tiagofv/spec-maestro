---
description: >
  Grill-me interview to stress-test a feature specification. Reads the spec and codebase,
  then interviews the user relentlessly — one question at a time with recommended answers —
  walking each branch of the decision tree until shared understanding is reached.
  Also resolves [NEEDS CLARIFICATION] markers naturally during the interview.
argument-hint: [feature-id] (optional, defaults to most recent)
---

# maestro.clarify

Stress-test the feature specification through a structured interview.

## Step 1: Find the Specification

If `$ARGUMENTS` contains a feature ID, use it to find the spec:

- Look for `.maestro/specs/{feature-id}/spec.md`

Otherwise, find the most recent feature:

- List directories in `.maestro/specs/` sorted by name (highest number first)
- Use the most recent one

If no spec is found, tell the user to run `/maestro.specify` first and stop.

## Step 2: Build Context

Read the full spec file. Then explore the codebase for context:

1. Read any files referenced in the spec (dependencies, modified components)
2. Read `.maestro/constitution.md` if it exists (for architectural constraints)
3. If the spec references existing commands, services, or modules — read them
4. Note any `[NEEDS CLARIFICATION: ...]` markers in the spec — you will weave these into the interview naturally when their branch comes up

Build a mental decision tree from:

- Each user story and its acceptance criteria
- The scope boundaries (in scope vs out of scope)
- Dependencies on existing systems
- Risks and their mitigations
- Any gaps between what the spec says and what the codebase reveals

## Step 3: Conduct the Interview

Interview the user about every aspect of the spec, one question at a time.

**Core rules:**

1. **One question at a time** — never present a batch of questions. Ask one, wait for the answer, then ask the next.

2. **Provide a recommended answer** — for each question, state your recommendation based on what you learned from the spec and codebase. Format:

```
**Question:** {your question about a specific aspect of the spec}

**My recommendation:** {what you think the answer should be, and why}

Accept, override, or elaborate?
```

3. **Walk the decision tree in dependency order** — resolve foundational decisions before dependent ones. When a decision unlocks new branches, explore those before moving on.

4. **Be codebase-aware** — if a question can be answered by reading existing code, do so yourself. State what you found and your conclusion. The user can override if your finding is wrong or outdated. Do not ask the user questions the codebase already answers.

5. **Weave in existing markers** — when you reach a branch that corresponds to a `[NEEDS CLARIFICATION: ...]` marker in the spec, address it as part of the interview. Don't treat markers as a separate phase.

6. **Handle unanswerable questions** — if a question requires input from someone not in the conversation (a stakeholder, another team, etc.), note it and move on. These become new `[NEEDS CLARIFICATION: ...]` markers in the spec.

7. **Respect escape signals** — if the user says "skip", "skip this branch", "not relevant", or similar — move to the next branch without pushback. If the user says "wrap up", "done", "that's enough", or similar — proceed to Step 5 (wrap-up).

## Step 4: Update the Spec Incrementally

After each answered question:

1. Immediately update the spec file with the decision:
   - If it resolves a `[NEEDS CLARIFICATION: ...]` marker, replace the marker with the answer
   - If it adds a new requirement, add it to the appropriate user story or create a new one
   - If it narrows scope, update the scope section
   - If it reveals an edge case, add it to acceptance criteria
2. Write the updated spec back to the file — do not wait until the end of the session

This protects against session crashes or context window compaction. Every decision is persisted the moment it's made.

## Step 5: Declare Shared Understanding

When you believe all meaningful branches of the decision tree have been explored (or the user has requested wrap-up):

1. Summarize what was covered:
   - Decisions made (count)
   - New requirements added
   - Markers resolved
   - Branches skipped (if any)
   - New `[NEEDS CLARIFICATION]` markers added (for stakeholder questions)

2. Ask the user to confirm:

```
I believe we've reached shared understanding on this spec.

{summary above}

Confirm to finalize, or point me to anything I missed.
```

3. Wait for confirmation before proceeding to Step 6.

## Step 6: Update State

Update `.maestro/state/{feature_id}.json`:

- Set `stage` to `clarify`
- Update `clarification_count` to the number of remaining `[NEEDS CLARIFICATION]` markers
- Add history entry: `{"stage": "clarify", "timestamp": "...", "action": "grill-me session: resolved N questions, added M new markers"}`

## Step 7: Report and Next Steps

Show the user:

1. Session summary:
   - Questions asked
   - Decisions captured
   - Markers resolved
   - New markers added (if any)
   - Branches skipped (if any)
2. If any `[NEEDS CLARIFICATION]` markers remain (from stakeholder questions), list them
3. Suggest next step:
   - If markers remain: "Run `/maestro.clarify` again after resolving the {N} stakeholder questions."
   - If spec is clean: "Run `/maestro.plan` to generate the implementation plan."

---

**Remember:** You are the interviewer. Be relentless but respectful. Your job is to surface every assumption, edge case, and unstated dependency before a single line of code is written. Clarification is about removing ambiguity, not adding implementation details. Keep everything focused on WHAT and WHY, not HOW.
