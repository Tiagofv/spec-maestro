# Research Report: {FEATURE_TITLE}

**Feature ID:** {FEATURE_ID}
**Spec:** {SPEC_PATH}
**Created:** {DATE}
**Last Updated:** {DATE}
**Status:** Draft | Review | Ready

---

## 1. Research Scope and Execution Profile

### 1.1 Scope

- **Goal:** {What planning decision this research is intended to unlock}
- **In Scope:** {Bounded list of research questions}
- **Out of Scope:** {Explicitly deferred items for this round}

### 1.2 Fixed Agent Set and Parallelism

- **Agent Set:** Fixed for MVP (no project-level customization)
- **Default Parallel Agents:** `2`
- **Maximum Parallel Agents:** `5`
- **Agents Used:** {2-5}
- **Why this level of parallelism:** {One to two sentences}

### 1.3 Domain Coverage Checklist

- [ ] Technology options complete
- [ ] Pattern catalog complete
- [ ] Pitfall register complete
- [ ] Competitive analysis complete
- [ ] Synthesis complete

---

## 2. Technology Options

### 2.1 Evaluation Criteria

{List criteria used to evaluate options. Example: maturity, compatibility, operational complexity, licensing, cost.}

### 2.2 Options Matrix

| Option | Fit for Feature | Pros | Cons | Risks | Recommendation |
| ------ | --------------- | ---- | ---- | ----- | -------------- |
| {name} | {high/med/low}  | {..} | {..} | {..}  | {adopt/defer}  |

### 2.3 Findings

- {Key evidence-backed finding}

### 2.4 Recommendations

- {Recommendation with intended use}

### 2.5 Risks and Mitigations

- **Risk:** {Risk}
- **Mitigation:** {Mitigation}

### 2.6 References

- Internal: {path or doc}
- External: {url or source}

---

## 3. Pattern Catalog

### 3.1 Candidate Patterns

| Pattern | Source (Internal/External) | Applicability  | Trade-offs | Recommendation |
| ------- | -------------------------- | -------------- | ---------- | -------------- |
| {name}  | {source}                   | {high/med/low} | {..}       | {adopt/defer}  |

### 3.2 Findings

- {What reusable approach was identified and why it matters}

### 3.3 Recommendations

- {How this pattern should be used in planning}

### 3.4 Risks and Mitigations

- **Risk:** {Risk}
- **Mitigation:** {Mitigation}

### 3.5 References

- Internal: {path or doc}
- External: {url or source}

---

## 4. Pitfall Register

### 4.1 Known Pitfalls and Constraints

| Pitfall | Trigger | Impact  | Prevention | Mitigation |
| ------- | ------- | ------- | ---------- | ---------- |
| {name}  | {when}  | {L/M/H} | {how}      | {how}      |

### 4.2 Findings

- {Most likely failure mode and evidence}

### 4.3 Recommendations

- {Design or process guardrail to include in plan}

### 4.4 Risks and Mitigations

- **Risk:** {Residual risk}
- **Mitigation:** {Monitoring, fallback, or rollback}

### 4.5 References

- Internal: {path or doc}
- External: {url or source}

---

## 5. Competitive Analysis

Compare at least 3 external approaches and select a preferred direction.

### 5.1 External Approaches Compared

| Approach | What It Does Well | Weaknesses | Trade-offs | Relevance      |
| -------- | ----------------- | ---------- | ---------- | -------------- |
| {name}   | {..}              | {..}       | {..}       | {high/med/low} |

### 5.2 Preferred Direction

- **Preferred Approach:** {name}
- **Why Preferred:** {quality-first rationale}
- **What to Adopt Now:** {specific items}
- **What to Defer:** {specific items}

### 5.3 References

- External source 1: {url or citation}
- External source 2: {url or citation}
- External source 3: {url or citation}

---

## 6. Synthesis and Planning Readiness

### 6.1 Major Recommendations (Required Format)

For each major recommendation, include all fields below.

#### Recommendation {N}: {Title}

- **Decision:** {What should be done}
- **Rationale:** {Why this is the best choice now}
- **Alternatives:** {At least one alternative and why not chosen}
- **Confidence:** {high | medium | low}

### 6.2 Ambiguities and Classification

| Ambiguity | Classification (blocker/non-blocker) | Plan Impact | Owner       |
| --------- | ------------------------------------ | ----------- | ----------- |
| {item}    | {blocker/non-blocker}                | {impact}    | {name/role} |

### 6.3 Readiness Quality Minimums Checklist

- [ ] Every major recommendation includes Decision, Rationale, Alternatives, Confidence
- [ ] All fixed research domains are covered (Technology, Patterns, Pitfalls, Competitive)
- [ ] At least 3 external approaches are compared with trade-offs
- [ ] One preferred direction is named with adopt-now vs defer split
- [ ] Ambiguities are labeled blocker or non-blocker

### 6.4 Planning Readiness Verdict (Required)

- **Verdict:** `ready` | `not_ready` (choose exactly one)
- **Reasoning:** {One concise paragraph}

If verdict is `not_ready`, list missing minimum items explicitly:

- **Missing minimum items:**
  - {Missing item 1}
  - {Missing item 2}

### 6.5 Open Questions Carried to Planning

- {Question 1}
- {Question 2}

---

## Changelog

| Date   | Change                   | Author   |
| ------ | ------------------------ | -------- |
| {DATE} | Initial research created | {AUTHOR} |
