---
description: >
  Interactive Q&A to resolve [NEEDS CLARIFICATION] markers in the current specification.
  Reads the spec, presents questions, incorporates answers, and updates the spec.
argument-hint: [feature-id] (optional, defaults to most recent)
---

# maestro.clarify

Resolve uncertainties in the feature specification.

## Step 1: Find the Specification

If `$ARGUMENTS` contains a feature ID, use it to find the spec:

- Look for `.maestro/specs/{feature-id}/spec.md`

Otherwise, find the most recent feature:

- List directories in `.maestro/specs/` sorted by name (highest number first)
- Use the most recent one

If no spec is found, tell the user to run `/maestro.specify` first and stop.

## Step 2: Check for Clarification Markers

Read the spec file and scan for `[NEEDS CLARIFICATION: ...]` markers.

If no markers are found:

- Tell the user: "No clarification markers found. The spec is ready for planning."
- Suggest: "Run `/maestro.plan` to generate the implementation plan."
- Stop here.

If markers are found, extract them into a list.

## Step 3: Present Questions

For each clarification marker, present the question to the user:

```
## Clarification 1 of N

**From the spec:**
> {surrounding context from the spec}

**Question:**
{the specific question from the marker}

Please provide your answer:
```

Wait for the user's response before proceeding to the next question.

## Step 4: Proactive Gap Detection

After all explicit markers are resolved, scan the spec for implicit gaps:

1. **Undefined edge cases**: What happens when X fails? What if the list is empty?
2. **Missing actors**: Who triggers this action? Who is notified?
3. **Ambiguous quantities**: "Multiple" — how many? "Fast" — how fast?
4. **Unstated assumptions**: Does this require authentication? What timezone?

Present any new questions found:

```
## Additional Questions

While reviewing the spec, I identified some implicit gaps:

1. {question}
2. {question}

Would you like to address these now? (yes/no/skip)
```

## Step 5: Update the Specification

For each answered question:

1. Find the corresponding `[NEEDS CLARIFICATION: ...]` marker
2. Replace it with the user's answer, formatted appropriately
3. If the answer affects other sections (e.g., adds a new user story), update those too

Write the updated spec back to the same file.

## Step 6: Update State

Update `.maestro/state/{feature_id}.json`:

- Set `stage` to `clarify`
- Update `clarification_count` to remaining markers (should be 0)
- Add history entry: `{"stage": "clarify", "timestamp": "...", "action": "resolved N markers"}`

## Step 7: Report and Next Steps

Show the user:

1. Summary of changes made
2. Number of markers resolved
3. If any markers remain (user skipped), list them
4. Suggest: "Run `/maestro.plan` to generate the implementation plan."

---

**Remember:** Clarification is about removing ambiguity, not adding implementation details. Keep answers focused on WHAT and WHY, not HOW.
