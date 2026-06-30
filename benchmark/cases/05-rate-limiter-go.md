# Case 05 — Rate limiter library (Go, ambiguous + review-response)

**Stack** Go · **Shape** **deliberately ambiguous** algorithmic library

Case 3 tested `clarify`'s *restraint*; this tests its *reach*. The prompt is vague on
everything that matters for a rate limiter (algorithm, scope key, concurrency, deny shape).
A good `clarify` surfaces *several* real questions; a bad one rubber-stamps the vague spec.
Also the only place exercising the two tail commands `respond` and `analyze`.

**Stresses:** `clarify` (heavy), `research`, `respond`, `analyze`, `pm-validate`.

## Domain
In-process rate limiter: "is this key allowed right now?" → allow/deny. Everything else is
left vague on purpose.

## Seed (greenfield)
`go.mod` (module `example.com/ratelimit`) + empty `ratelimit.go`.

## Specify (intentionally vague, verbatim)
> Add a rate limiter so callers don't get overwhelmed. It should limit how often something
> can happen and say no when there's too much.

## Run protocol
`init` → `specify "<vague>"` → **`clarify`** → `research` → `plan` → `tasks` → `implement`
→ `pm-validate` → *(simulate PR review, below)* → **`respond`** → `commit` → **`analyze`**.

Clarify answers to give: **token bucket, per-string-key, configurable rate+burst,
goroutine-safe, return allowed bool + remaining tokens.** Must land in spec.md.

**PR review comments to feed `respond`:**
1. *"`Allow` takes the mutex for the whole refill computation — under contention this
   serializes every caller. Tighten the hot path."*
2. *"No test for two goroutines hitting the same key concurrently. Add one."*
3. *"`rate <= 0` silently allows everything — error or panic at construction?"*

## What good looks like
- **clarify**: ≥4 substantive questions (algorithm, scope key, concurrency, deny shape);
  answers written back **as EARS criteria** — e.g. "When `Allow(key)` is called and the
  bucket has ≥1 token, the system shall return `true` and decrement the bucket"; "If
  `rate <= 0` at construction, then the system shall return an error". Clarify should also
  flag the vague spec's *missing* `If …, then …` paths (empty bucket, unknown/zero rate), and
  `validate-spec-format.sh` exits 0 on the written spec (EARS shapes valid, every `When` paired
  with an `If…then`, no vague terms, AND no solution-leakage (no technology/implementation
  nouns like Redis/endpoint/table/cache in any criterion's response)).
- **research**: short real comparison (token bucket vs sliding window), ends at the choice.
- **implement**: correct refill math, mutex/finer safety, tests exercising concurrency (`-race`).
- **respond**: addresses **all three** comments with real code changes; replies per thread; logs learnings.
- **analyze**: proposals reference real friction in this run (heavy clarify, the contention fix).

## Watch for
clarify accepting the vague spec with one token question · clarify answers written back as
free prose instead of EARS criteria · criteria that prescribe HOW (name a technology/endpoint/
table) instead of observable WHAT/WHY · non-thread-safe limiter or wrong refill math · respond
acknowledging without changing code (or fixing 1 of 3) · generic analyze · specify/clarify
proceeding while validate-spec-format.sh still reports violations (validator output ignored).
