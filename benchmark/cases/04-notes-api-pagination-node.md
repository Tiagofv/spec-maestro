# Case 04 — Notes API pagination (Node, brownfield + fork)

| | |
|---|---|
| **Stack** | Node (TypeScript, Express, pnpm) |
| **Shape** | **Brownfield** — modify an existing small codebase |
| **Difficulty** | Medium (S feature on top of seed code) |
| **Goal** | Test the pipeline when it must read and extend existing code rather than start clean, and exercise `/maestro.fork` to branch a second feature off the first. |
| **Primary commands stressed** | `fork`, `specify`/`plan`/`implement` against existing code, `list` |

## Why this case

Every other case is greenfield. Real work is mostly brownfield. This case ships a working
(if minimal) notes API and asks maestro to *extend* it. The key questions:

- Does `specify`/`plan` actually **read the existing code** and build on it, or does it
  re-spec a from-scratch API and clobber what's there?
- Does `implement` make **surgical edits** to existing files, or rewrite them?
- Does `/maestro.fork` correctly branch a *second* feature (filtering) off the *first*
  (pagination), carrying spec/plan/research context without entangling the two?

## Domain (generic — no proprietary code)

A tiny in-memory notes REST API that already exists: `GET /notes` (returns all),
`POST /notes` (creates one). The benchmark adds **pagination** to `GET /notes`, then
**forks** a second feature that adds **tag filtering**.

## Starting state — seed code (brownfield)

The setup script seeds a working API:

```
package.json        // pnpm; build (tsc) + test:run (node --test); deps express, typescript
tsconfig.json       // strict
src/notes.ts         // in-memory Note[] store + add()/all() helpers
src/index.ts         // express app: GET /notes -> all(), POST /notes -> add()
src/notes.test.ts    // a couple of passing node:test cases for the existing behavior
```

The existing tests must stay green after the feature — a regression check is part of the
score.

## The feature to specify

**First feature (pagination)** — feed verbatim to `/maestro.specify`:

> Add pagination to GET /notes on the existing notes API. Accept `?limit` (default 20,
> max 100) and `?offset` (default 0) query params. Return `{ items, total, limit, offset }`.
> Invalid params (non-numeric, negative, limit over 100) return 400. Existing POST /notes
> behavior and the existing tests must be unchanged.

**Second feature (fork → filtering)** — after pagination is planned, run
`/maestro.fork` to branch a new feature, then specify:

> Add tag filtering to GET /notes: an optional `?tag` param returns only notes whose
> `tags` array includes that tag, combined with the existing pagination. Notes gain an
> optional `tags: string[]` field on POST.

## Run protocol

1. `/maestro.init` (node stack).
2. `/maestro.specify "<pagination feature text>"` — spec should reference the *existing*
   endpoint and explicitly preserve current behavior.
3. `/maestro.clarify` — expect questions about response envelope shape, max-limit
   enforcement, out-of-range offset behavior.
4. `/maestro.plan` — must edit `src/index.ts` / `src/notes.ts`, **not** recreate them.
5. `/maestro.tasks`
6. `/maestro.implement` — pagination works; **existing tests still pass** (regression).
7. `/maestro.list` — pagination feature shows active.
8. `/maestro.fork <pagination-feature>` — **the focus.** Branches a new numbered feature
   carrying the pagination context; new branch, fresh spec scaffold.
9. `/maestro.specify "<tag filtering feature text>"` on the forked feature.
10. `/maestro.plan` then `/maestro.implement` for filtering, layered on pagination.
11. `/maestro.commit`.

## What good looks like (checkpoints)

- **specify/plan**: demonstrably read the seed code (reference real symbols/files);
  preserve `POST /notes` and the existing tests.
- **implement**: diffs are additive/surgical on existing files; existing `node:test`
  cases pass unchanged; pagination envelope + 400s behave per spec.
- **fork**: creates a distinct feature dir + branch, copies relevant spec/plan/research,
  and does **not** mutate the original pagination feature's artifacts.
- **list**: shows both features with correct status after the fork.

## Known failure modes to watch for

- `specify`/`plan` ignoring the seed code and writing a greenfield spec that would replace
  the existing API.
- `implement` rewriting `src/index.ts` wholesale (and breaking the existing tests) instead
  of extending it.
- `fork` entangling the two features (editing the source feature's spec, reusing its
  branch, or losing the carried context).
- Pagination math off-by-one (offset/limit boundaries), or missing the 400 validations.
