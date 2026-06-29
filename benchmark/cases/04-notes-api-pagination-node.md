# Case 04 — Notes API pagination (Node, brownfield + fork)

**Stack** Node (TS, Express, pnpm) · **Shape** **brownfield** — extend existing code

Every other case is greenfield; real work is brownfield. Ships a working notes API and asks
maestro to *extend* it, then `fork` a second feature off the first. Key questions: does
`specify`/`plan` **read the existing code** or re-spec from scratch? Does `implement` make
**surgical edits** or rewrite? Does `fork` branch a *second* feature cleanly without
entangling the first?

**Stresses:** `fork`, editing existing code, `list`.

## Domain
In-memory notes REST API that already exists (`GET /notes`, `POST /notes`). Add pagination,
then fork → add tag filtering.

## Seed (brownfield — must stay green)
`package.json`/`tsconfig.json` · `src/notes.ts` (store + add/all) · `src/index.ts`
(GET/POST routes) · `src/notes.test.ts` (passing tests). **Existing tests must stay green.**

## Specify
**Pagination (verbatim):**
> Add pagination to GET /notes on the existing notes API. Accept `?limit` (default 20, max
> 100) and `?offset` (default 0). Return `{ items, total, limit, offset }`. Invalid params
> return 400. Existing POST /notes behavior and the existing tests must be unchanged.

**Filtering (after fork, verbatim):**
> Add tag filtering to GET /notes: an optional `?tag` param returns only notes whose `tags`
> array includes that tag, combined with pagination. Notes gain an optional `tags: string[]`
> field on POST.

## Run protocol
`init` → `specify "<pagination>"` → `clarify` → `plan` → `tasks` → `implement` (**existing
tests still pass**) → `list` → **`fork <pagination-feature>`** → `specify "<filtering>"` →
`plan` → `implement` → `commit`.

## What good looks like
- **specify/plan**: reference real seed symbols/files; preserve POST + existing tests.
- **implement**: additive/surgical diffs; existing tests unchanged; envelope + 400s per spec.
- **fork**: distinct feature dir + branch, carries context, doesn't mutate the source feature.
- **list**: both features shown with correct status after the fork.

## Watch for
specify/plan ignoring seed code and writing a greenfield replacement · implement rewriting
`src/index.ts` and breaking tests · fork entangling the two features · pagination off-by-one.
