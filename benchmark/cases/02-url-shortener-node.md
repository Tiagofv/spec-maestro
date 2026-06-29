# Case 02 — URL shortener API (Node)

**Stack** Node (TS, Express, pnpm) · **Shape** greenfield with real design choices

Case 1 had nothing to research; this has real, decidable forks (code generation, collision
handling, storage). A good `research` pass produces readiness artifacts the plan *cites*;
a bad one skips research or emits generic filler.

**Stresses:** `research`, `research.list`, `research.search` (+ specify/clarify/plan/tasks/implement/commit).

## Domain
URL shortener HTTP API: `POST /shorten` → short code; `GET /:code` → 302 redirect.
In-process storage is acceptable — *whether* to use it vs a DB is part of what research evaluates.

## Seed (greenfield)
`package.json` (pnpm; build=tsc, test:run=node --test; deps express+typescript) ·
`tsconfig.json` (strict) · `src/index.ts` (express app that listens, no routes yet).

## Specify (verbatim)
> Add a URL shortener API. POST /shorten accepts a JSON body with a `url` field and returns
> a short code. GET /:code redirects (HTTP 302) to the original URL, or returns 404 if the
> code is unknown. Reject invalid URLs with 400. The short code should be short, URL-safe,
> and collision-free.

"short, URL-safe, collision-free" is the hook that should drive research.

## Run protocol
`init` → `specify` → `clarify` → **`research`** → `research.list` → `research.search "collision"`
(and `"storage"`) → `plan` → `tasks` → `implement` → `commit`.

## What good looks like
- **research**: ≥2 distinct artifacts under `specs/<id>/research/`, each with options +
  recommendation + rationale — not one vague notes file.
- **research.list**: every artifact with a status; nothing missing.
- **research.search**: hits the right artifact, *omits* irrelevant ones.
- **plan**: chosen approach matches a research recommendation and says so; no silent re-decide.
- **implement**: shorten→redirect round-trips; 400 bad URL / 404 unknown / 302 redirect; gate green.

## Watch for
research as a single generic file or skipping options · search returning everything ·
plan re-deciding encoding inline · implement returning 200+body instead of a 302.
