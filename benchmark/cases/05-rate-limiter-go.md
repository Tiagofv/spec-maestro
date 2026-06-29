# Case 05 — Rate limiter library (Go, ambiguous + review-response)

| | |
|---|---|
| **Stack** | Go |
| **Shape** | **Deliberately ambiguous** algorithmic library |
| **Difficulty** | Hard (M feature, under-specified on purpose) |
| **Goal** | Stress `clarify` with a genuinely under-specified ask, and exercise `respond` (answering PR review comments) and `analyze` (post-epic learning) at the tail of the pipeline. |
| **Primary commands stressed** | `clarify` (heavy), `research`, `respond`, `analyze`, `pm-validate` |

## Why this case

Case 3 tested `clarify`'s **restraint** (don't invent questions). This case tests its
**reach**: the prompt is intentionally vague on the dimensions that matter for a rate
limiter (algorithm, scope key, thread-safety, what happens when the limit is hit). A good
`clarify` should surface *several* real questions; a bad one rubber-stamps the vague spec
and lets the ambiguity flow downstream into a confused plan.

It's also the place to exercise the two tail commands the other cases don't:

- **`respond`** — simulate a PR review (the protocol gives you canned review comments to
  paste) and check that `respond` fetches/derives the feedback, proposes targeted fixes,
  applies them with approval, and records findings.
- **`analyze`** — run after a full, messy pipeline so there's real signal for it to mine.

## Domain (generic — no proprietary code)

A reusable in-process rate limiter package: callers ask "is this key allowed right now?"
and get allow/deny. Everything else — the algorithm, the key model, concurrency, headers —
is left vague on purpose.

## Starting state

Greenfield Go module:

```
go.mod          // module example.com/ratelimit, go 1.21
ratelimit.go    // package ratelimit — empty
```

## The feature to specify

Feed this **intentionally vague** text verbatim to `/maestro.specify`:

> Add a rate limiter so callers don't get overwhelmed. It should limit how often something
> can happen and say no when there's too much.

That's it. This is under-specified on purpose. The work of pinning it down belongs to
`clarify`, not `specify`.

## Run protocol

1. `/maestro.init`.
2. `/maestro.specify "<the vague text above>"`.
3. `/maestro.clarify` — **the focus.** Expect it to surface several real questions:
   - which algorithm (token bucket / fixed window / sliding window)?
   - what's the limit keyed on (global / per-key/identifier)?
   - the actual numbers (N requests per window) — or is it configurable?
   - thread-safe for concurrent callers?
   - on deny, just a bool, or remaining/retry-after info?
   Answer consistently: **token bucket, per-string-key, configurable rate+burst,
   goroutine-safe, return allowed bool + remaining tokens.** These answers must land in
   spec.md.
4. `/maestro.research` — should compare token bucket vs sliding window briefly and confirm
   the clarified choice (or push back with rationale).
5. `/maestro.plan` — a `Limiter` type, `Allow(key)` method, per-key bucket state, a mutex.
6. `/maestro.tasks`.
7. `/maestro.implement` — Go gate green; concurrency-safe; table tests for refill + burst +
   deny.
8. `/maestro.pm-validate` — verify each clarified decision is actually implemented.
9. **Simulate a PR review, then `/maestro.respond`.** Paste these as the review comments
   to respond to (they're realistic and each requires a real fix):
   - *"`Allow` takes the mutex for the whole refill computation — under contention this
     serializes every caller. Can the hot path be tightened?"*
   - *"There's no test for two goroutines hitting the same key concurrently. Add one."*
   - *"`rate <= 0` silently allows everything — should it error or panic at construction?"*
   `respond` should propose targeted fixes for each, apply with approval, and record
   findings to memory.
10. `/maestro.commit`.
11. `/maestro.analyze` — post-epic metrics + improvement proposals grounded in this run
    (the clarify volume, the review churn, the concurrency fix).

## What good looks like (checkpoints)

- **clarify**: ≥4 substantive questions covering algorithm, scope key, concurrency, and
  deny-result shape; answers written back into spec.md; no cosmetic filler.
- **research**: a real (if short) comparison, ending at the clarified choice.
- **implement**: correct token-bucket refill math, a mutex (or finer-grained safety), and
  tests that actually exercise concurrency (e.g. `-race`).
- **respond**: addresses **all three** comments with specific code changes (not hand-waves),
  replies per-thread, and logs what it learned.
- **analyze**: proposals reference the real friction in this run (heavy clarify, the
  contention fix, the missing concurrency test) — not boilerplate.

## Known failure modes to watch for

- `clarify` accepting the vague spec and asking one token question, letting ambiguity leak
  into `plan`.
- `implement` shipping a non-thread-safe limiter (map writes without a lock) or wrong
  refill math (burst not capped, tokens never replenished).
- `respond` acknowledging comments without making the corresponding code change, or fixing
  one of three and claiming all done.
- `analyze` producing generic advice unrelated to what actually happened.
