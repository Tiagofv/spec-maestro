# Feature: {FEATURE_TITLE}

**Spec ID:** {FEATURE_ID}
**Author:** {AUTHOR}
**Created:** {DATE}
**Last Updated:** {DATE}
**Status:** Draft | Review | Approved | Superseded
**Repos:** <repo-a>, <repo-b>          <!-- replace with the comma-separated list of repo dirnames this feature touches; required at /maestro.specify time per spec §8.3 -->

---

<!--
SCALE TO THE FEATURE. This is a maximal checklist, not a required shape. For small
features, keep it tight: a couple of focused user stories beat ten padded ones, and
sections that don't apply (e.g. heavy Dependencies/Risks for a self-contained change)
should be a line or omitted rather than filled with boilerplate. Don't pad to look thorough.
-->

## 1. Problem Statement

{One to three paragraphs describing the problem from the user's perspective. What pain point exists? Why does it matter? Who is affected?}

---

## 2. Proposed Solution

{Describe the proposed approach at a high level. How does this feature solve the problem? What is the core idea? Keep this concise — implementation details belong in the plan, not the spec.}

---

## 3. User Stories

<!--
ACCEPTANCE CRITERIA USE EARS (Easy Approach to Requirements Syntax). Each criterion is
ONE atomic sentence in one of these five shapes — keyword order is fixed and the verb is
always "shall". This stays at the WHAT/WHY level: describe observable behavior, never HOW.

  Ubiquitous (always active):  The <system> shall <response>.
  Event-driven:                When <trigger>, the <system> shall <response>.
  State-driven:                While <state>, the <system> shall <response>.
  Unwanted behavior:           If <condition>, then the <system> shall <response>.
  Optional feature:            Where <feature is included>, the <system> shall <response>.
  Complex (combine):           While <state>, when <trigger>, the <system> shall <response>.

Rules: one trigger → one response per line (split "and also" into two criteria); pair every
`When …` happy path with an `If …, then …` for the failure/edge path; <system> is the
feature/component, not a class or table. A criterion you cannot phrase this way is ambiguous —
mark it [NEEDS CLARIFICATION: …] instead of guessing.
-->

### Story 1: {SHORT_NAME}

**As a** {ROLE},
**I want** {ACTION},
**so that** {BENEFIT}.

**Acceptance Criteria (EARS):**

- [ ] When {trigger}, the {system} shall {observable response}.
- [ ] If {error or edge condition}, then the {system} shall {response}.

### Story 2: {SHORT_NAME}

**As a** {ROLE},
**I want** {ACTION},
**so that** {BENEFIT}.

**Acceptance Criteria (EARS):**

- [ ] While {precondition holds}, the {system} shall {response}.
- [ ] The {system} shall {ubiquitous, always-active response}.
- [ ] [NEEDS CLARIFICATION: {Specific question about ambiguous acceptance criterion}]

{Add more stories as needed. Use [NEEDS CLARIFICATION: ...] markers on any criterion that cannot be written in an EARS shape without guessing.}

---

## 4. Success Criteria

The feature is considered complete when:

1. {Measurable, observable outcome}
2. {Measurable, observable outcome}
3. {Measurable, observable outcome}

---

## 5. Scope

### 5.1 In Scope

- {Capability that IS part of this feature}
- {Capability that IS part of this feature}

### 5.2 Out of Scope

- {Related capability that is explicitly excluded}
- {Future enhancement that should not be built now}

### 5.3 Deferred

- {Capability planned for a future iteration}
- {Enhancement that will be revisited after initial delivery}

---

## 6. Research

{Include research findings that inform this specification}

### Linked Research Items

- **{Research ID}** - {Brief description of findings}
  - Key insight: {What was learned}
  - Recommendation: {How this informs the spec}

### Research Summary

{Summary of how research findings influenced requirements, scope, or approach}

---

## 7. Dependencies

{List any existing features, services, or systems this feature depends on. If none, write "None identified."}

---

## 8. Open Questions

- [NEEDS CLARIFICATION: {Specific question about ambiguous requirement}]
- [NEEDS CLARIFICATION: {Specific question about edge case or boundary}]

---

## 8. Risks

{Known risks or concerns. If none obvious, write "None identified — to be explored during clarification."}

---

## Changelog

| Date   | Change               | Author   |
| ------ | -------------------- | -------- |
| {DATE} | Initial spec created | {AUTHOR} |
