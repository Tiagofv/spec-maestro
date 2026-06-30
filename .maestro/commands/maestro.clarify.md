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

**Resolve the feature** — run the shared resolver (replaces the old inline inference):

```bash
bash .maestro/scripts/resolve-feature.sh "$ARGUMENTS"
```

It emits JSON `{feature_id, spec_dir, branch, source, conflict, conflict_with}` (empty
feature dirs are already excluded). Then act on the result:

- `conflict: true` — surface both candidates (`feature_id` from recent state vs
  `conflict_with` from the git branch) and ask the user which to use.
- `source: none` — no usable feature found. If this command CREATES a feature (specify),
  treat it as new and proceed to scaffold; otherwise ask the user for an explicit feature ID.
- otherwise — surface the resolved `feature_id` and its `source`, then proceed.

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
5. **Non-EARS / untestable acceptance criteria**: Any acceptance criterion not expressible
   in an EARS shape (When/While/If…then/Where, or "The <system> shall …") is ambiguous —
   rewrite it into EARS, or raise a clarification question if you'd be guessing.
6. **Missing unwanted-behavior paths**: For every `When <trigger>, … shall …` happy-path
   criterion, is there a matching `If <that trigger fails / bad input>, then … shall …`
   criterion? Missing failure/edge criteria are the most common gap EARS exposes — surface
   each one as a question.

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

After writing the updated spec, run the acceptance-criteria validator:

```bash
bash .maestro/scripts/validate-spec-format.sh {spec_dir}/spec.md
```

If it fails, a resolution landed as a non-EARS, unpaired, or vague criterion.
Report to the user **which resolved criterion is still malformed** (cite the
`spec validation failed:` line), then fix it — rewrite into an EARS shape, add
the missing `If …, then …` failure path, or remove the vague term — or re-ask
the question if you would be guessing. Re-run the validator and do not proceed
to Step 6 until it exits 0.

## Step 6: Update State

Only stamp the clarification count **after** the validator passes — every marker
resolution must land as a valid EARS criterion before finalizing. At this point
`remaining_markers` should be 0 **and** the spec is EARS-valid.

Update state via the helper — **never hand-write timestamps** (fabricated times corrupt
`/maestro.analyze`). The script stamps real UTC time and appends history:

```bash
bash .maestro/scripts/update-state.sh {feature_id} clarify "resolved {N} markers" \
  clarification_count={remaining_markers}
```

`{remaining_markers}` should be 0.

## Step 7: Report and Next Steps

Show the user:

1. Summary of changes made
2. Number of markers resolved
3. If any markers remain (user skipped), list them
4. Suggest: "Run `/maestro.plan` to generate the implementation plan."

---

**Remember:** Clarification is about removing ambiguity, not adding implementation details. Keep answers focused on WHAT and WHY, not HOW.
