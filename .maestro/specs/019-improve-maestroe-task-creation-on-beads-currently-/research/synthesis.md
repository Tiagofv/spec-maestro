# Research Synthesis: Feature 019 - Improve Maestro Task Creation on Beads

**Research Date:** 2026-02-23  
**Synthesized By:** Maestro Research Agent  
**Status:** Complete - Ready for Planning

---

## 1. Executive Summary

This synthesis consolidates findings from four research artifacts investigating how to optimize Maestro task creation from ~10 minutes (current agent-based approach) to <30 seconds for 50+ tasks.

### Key Learnings

1. **Current bottleneck is architectural, not algorithmic**: The 10-minute duration comes from spawning an agent process for each task (50 tasks × ~12s = 600s), not from Beads CLI performance itself.

2. **Idempotency is solvable with simple composite keys**: Title + Parent Epic matching provides reliable duplicate detection without complex state management.

3. **Two-pass dependency linking is the pragmatic choice**: While single-pass is theoretically possible, two-pass (create all tasks first, then link dependencies) provides better error handling and matches industry patterns.

4. **JSON input format offers the best trade-off**: Structured, fast to parse, type-safe, and aligns with Beads CLI's native JSON output.

5. **20x speedup is achievable**: Script-based batch creation can reduce 50-task creation from ~600s to ~25-30s.

### Deferred Questions Resolved

| Question                         | Answer                        | Rationale                                                                   |
| -------------------------------- | ----------------------------- | --------------------------------------------------------------------------- |
| **Task identification strategy** | Title + Parent Epic composite | No state file needed; human-readable; aligns with existing Maestro patterns |
| **Input format**                 | JSON                          | Programmatic reliability; fast parsing; type-safe; Beads-native             |

---

## 2. Decision-Ready Recommendations

### Recommendation 1: Use Title + Parent Epic for Idempotency

**Decision:** Tasks are identified by their `title` within the context of a `parent epic`.

**Rationale:**

- Requires no additional state persistence between runs
- Uses existing Beads CLI capabilities (`bd list --parent`)
- Human-readable and debuggable
- Matches current Maestro task naming conventions (e.g., "TDP-001-037: Write component tests")
- No dependency on Beads schema extensions

**Alternatives Considered:**

| Approach                     | Pros                           | Cons                                                              | Why Rejected                                 |
| ---------------------------- | ------------------------------ | ----------------------------------------------------------------- | -------------------------------------------- |
| **Beads ID**                 | Guaranteed unique, fast lookup | Requires state file; IDs not human-readable; breaks if state lost | Adds complexity without proportional benefit |
| **External-ref field**       | Native Beads support           | Searchable but not directly queryable; requires format convention | Limited Beads support for filtering          |
| **Custom ID in description** | Full control over format       | Fragile; requires parsing; no query support                       | Too complex for the problem                  |

**Edge Cases & Mitigations:**

- Title changes break idempotency → Document that renames require manual cleanup
- Duplicate titles in plan → Reject plan with validation error before creation
- Whitespace/case sensitivity → Normalize before comparison (trim, case-insensitive)

**Confidence Level:** HIGH (90%) - Simple, proven pattern; well-understood trade-offs

---

### Recommendation 2: Use JSON as Input Format

**Decision:** Task plans are passed to the script as structured JSON.

**Rationale:**

- Native parsing support (jq, Python, etc.) - no custom parsers needed
- Type-safe with JSON Schema validation
- Fast parsing (no regex/scanning)
- Future-proof and extensible
- Bidirectional conversion with Beads CLI (which outputs JSON natively)

**Alternatives Considered:**

| Approach                     | Pros                              | Cons                                           | Why Rejected                              |
| ---------------------------- | --------------------------------- | ---------------------------------------------- | ----------------------------------------- |
| **YAML**                     | Human-readable, supports comments | Requires YAML parser; whitespace-sensitive     | Less standard for programmatic interfaces |
| **Markdown table (current)** | No conversion needed              | Complex parsing; fragile; limited structure    | Doesn't support rich metadata             |
| **Beads markdown format**    | Native Beads support              | Less structured; two-pass harder to coordinate | Doesn't solve the input problem           |

**Example Format:**

```json
{
  "feature_id": "019-improve-maestro-task-creation",
  "feature_title": "Improve Maestro Task Creation",
  "tasks": [
    {
      "number": 1,
      "title": "MST-019-001: Create task creation script",
      "description": "Implement...",
      "label": "backend",
      "size": "S",
      "estimate_minutes": 360,
      "assignee": "general",
      "dependencies": []
    }
  ]
}
```

**Confidence Level:** HIGH (95%) - Industry standard, no significant downsides

---

### Recommendation 3: Implement Two-Pass Dependency Linking

**Decision:** Create all tasks in Phase 1, then link dependencies in Phase 2.

**Rationale:**

- All task IDs are available before dependency linking begins
- Clear error boundaries (can fail at task creation or linking independently)
- Supports cycle detection before attempting links
- Matches patterns from Jira CLI and other mature tools
- Simpler than single-pass with forward references

**Alternatives Considered:**

| Approach                          | Pros                 | Cons                                                              | Why Rejected                     |
| --------------------------------- | -------------------- | ----------------------------------------------------------------- | -------------------------------- |
| **Single-pass with forward refs** | Potentially faster   | Requires placeholder IDs; complex error handling; race conditions | Too complex, marginal benefit    |
| **Create-on-demand**              | Minimal upfront work | Complex dependency resolution; partial failures hard to track     | Doesn't fit batch creation model |

**Confidence Level:** HIGH (85%) - Proven pattern, clear failure modes

---

### Recommendation 4: Script-Based Batch Creation Architecture

**Decision:** Replace per-task agent invocations with a single bash script that orchestrates all task creation.

**Rationale:**

- Eliminates agent spawning overhead (primary bottleneck)
- 20x speedup potential (600s → 25-30s for 50 tasks)
- Can use SQLite directly for fast idempotency checks
- Works with existing `bd` CLI - no Beads changes needed

**Confidence Level:** HIGH (90%) - Clear bottleneck identified; proven approach

---

## 3. Adopt-Now vs Defer Split

### Adopt-Now (MVP)

| Item                                    | Rationale                                    |
| --------------------------------------- | -------------------------------------------- |
| Title-based idempotency check           | Critical path; simple to implement           |
| JSON input parsing                      | Critical path; foundation for all other work |
| Two-pass dependency linking             | Critical path; required for correct behavior |
| Simple progress counter ([N/M])         | User experience; trivial to implement        |
| Error handling with `set -euo pipefail` | Quality; standard pattern                    |
| State file for resume capability        | Recovery from partial failures               |

### Defer to Future Iterations

| Item                                 | Rationale                               | Trigger for Implementation              |
| ------------------------------------ | --------------------------------------- | --------------------------------------- |
| Topological sort / cycle detection   | Nice to have; Beads may handle this     | Plans start having complex dependencies |
| Parallel wave detection              | Not needed for sequential creation      | Speed becomes bottleneck again          |
| External-ref based idempotency       | More robust but complex                 | Title-based proves insufficient         |
| Retry logic with exponential backoff | Beads is local SQLite; low failure rate | Actual timeout/failure observed         |
| File locking for concurrent access   | Low likelihood of collision             | Concurrent execution issues observed    |
| Progress bars (TTY detection)        | Cosmetic improvement                    | User feedback requests                  |
| Automatic cleanup on failure         | Recovery more valuable than rollback    | Partial failure becomes common          |

---

## 4. Planning Readiness Verdict

### **READY**

This feature is ready for planning. Both deferred questions have been answered with clear, implementable solutions.

### Missing Items (None)

No minimum items are missing. All critical decisions have been made:

- ✅ Task identification strategy: Title + Parent Epic
- ✅ Input format: JSON
- ✅ Dependency linking approach: Two-pass
- ✅ Architecture: Script-based batch creation

---

## 5. Open Questions for Planning

### Blockers (Must Resolve Before Implementation)

None identified.

### Non-Blockers (Can Iterate During Implementation)

| Question                                    | Impact | Suggested Approach                           |
| ------------------------------------------- | ------ | -------------------------------------------- |
| Exact JSON Schema definition                | Low    | Draft during implementation; finalize in PR  |
| Progress output format (JSON vs plain text) | Low    | Support both with `--json` flag              |
| State file format and location              | Low    | Extend existing `.maestro/state.json`        |
| Rate limiting delay value                   | Low    | Start with 100ms; tune based on testing      |
| Maximum tasks per batch                     | Low    | Document 100 as soft limit; test performance |

---

## 6. Major Recommendations Comparison

### Approach A: Script-Based Batch Creation (PREFERRED)

**Description:** Single bash script that reads JSON input, creates all tasks, then links dependencies.

**Trade-offs:**

- ✅ **Pros:** 20x faster; simple; no dependencies; works with existing tools
- ❌ **Cons:** Requires bash; sequential execution; two-pass complexity

**Evidence:**

- ClickUp API achieves ~10-30s for 50 tasks via bulk API
- Competitive analysis shows script-based approaches are standard
- Current bottleneck is agent spawning, not Beads performance

**Best For:** Development team workflow; current Maestro architecture

---

### Approach B: External Tool / Plugin

**Description:** Create a native binary or Python tool that wraps Beads operations.

**Trade-offs:**

- ✅ **Pros:** Faster execution; better error handling; cross-platform
- ❌ **Cons:** Additional build/maintenance burden; new dependency; overkill for the problem

**Evidence:**

- GitHub CLI (`gh`) is native Go; excellent but heavy-weight
- Jira CLI is feature-rich but requires separate installation

**Best For:** If we need to support multiple languages or platforms

---

### Approach C: Beads Native Bulk API

**Description:** Extend Beads CLI with bulk creation commands.

**Trade-offs:**

- ✅ **Pros:** Native support; fastest execution; best UX
- ❌ **Cons:** Requires upstream changes; longer timeline; adds to Beads scope

**Evidence:**

- Linear API supports GraphQL batch mutations
- ClickUp has true bulk endpoints
- Beads doesn't currently support this

**Best For:** Long-term; if this becomes a common pattern

---

### Comparison Matrix

| Criteria            | Script-Based (Preferred) | External Tool    | Beads Native                 |
| ------------------- | ------------------------ | ---------------- | ---------------------------- |
| Implementation Time | 1-2 days                 | 1-2 weeks        | 2-4 weeks                    |
| Speed (50 tasks)    | ~25-30s                  | ~20-25s          | ~10-15s                      |
| Maintenance Burden  | Low                      | Medium           | Low (if accepted upstream)   |
| Dependencies        | bash, jq                 | Language runtime | None (in Beads)              |
| Flexibility         | High                     | High             | Low (requires Beads changes) |
| Risk                | Low                      | Medium           | Medium (upstream dependency) |

---

## 7. Preferred Direction

### Summary

Implement a **script-based batch creation** approach using:

1. **JSON input format** for structured task plans
2. **Title + Parent Epic** for idempotency checks
3. **Two-pass creation** (tasks first, then dependencies)
4. **Simple progress indication** ([N/M] counter)

### Clear Rationale

**Why script-based?**

- Addresses the actual bottleneck (agent spawning overhead)
- Minimal implementation effort (1-2 days)
- No new dependencies or build processes
- Works within existing Maestro architecture

**Why JSON?**

- Fast, reliable parsing with jq
- Type-safe with schema validation
- Bidirectional compatibility with Beads CLI
- Industry standard for programmatic interfaces

**Why title-based idempotency?**

- Requires no state persistence
- Simple to implement and debug
- Matches existing Maestro conventions
- Trade-offs are well-understood and acceptable

**Why two-pass linking?**

- Proven pattern from mature tools (Jira)
- All IDs available before linking
- Clear error boundaries
- Supports cycle detection

### Expected Outcome

- **Speed:** 50 tasks in ~25-30 seconds (down from ~600 seconds)
- **Reliability:** Idempotent execution; can resume from partial failures
- **Maintainability:** Single script file; standard patterns
- **User Experience:** Clear progress indication; structured output

### Success Metrics

| Metric                     | Current  | Target            |
| -------------------------- | -------- | ----------------- |
| 50-task creation time      | ~600s    | <30s              |
| Duplicate task creation    | Possible | Prevented         |
| Manual intervention needed | Common   | Rare              |
| Progress visibility        | None     | Real-time counter |

---

## 8. Risk Summary

| Risk                                  | Likelihood | Impact | Mitigation                               |
| ------------------------------------- | ---------- | ------ | ---------------------------------------- |
| Title changes break idempotency       | Medium     | Medium | Document limitation; validation          |
| Script fails mid-execution            | Low        | High   | State file for resume; atomic operations |
| Beads CLI changes output format       | Low        | High   | Pin Beads version; integration tests     |
| Large plans (>100 tasks) cause issues | Low        | Medium | Document limits; batching support        |
| Dependency cycles in plan             | Low        | Medium | Validate before linking                  |

---

## 9. References

- [Technology Options Research](technology-options.md) - Detailed evaluation of idempotency and input format options
- [Pattern Catalog](pattern-catalog.md) - Implementation patterns for task creation, dependency linking, and error handling
- [Pitfall Register](pitfall-register.md) - Known failure modes and mitigation strategies
- [Competitive Analysis](competitive-analysis.md) - Comparison with GitHub CLI, Jira CLI, Linear, GitLab CLI, and ClickUp

---

**Next Step:** Proceed to implementation planning with confidence. All critical decisions have been made and validated.
