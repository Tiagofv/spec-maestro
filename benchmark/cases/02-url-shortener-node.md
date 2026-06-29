# Case 02 — URL shortener API (Node)

| | |
|---|---|
| **Stack** | Node (TypeScript, Express, pnpm) |
| **Shape** | Greenfield with genuine design choices |
| **Difficulty** | Medium (S–M feature) |
| **Goal** | Stress the research sub-pipeline: a feature with real, decidable design questions that `research` should investigate before `plan`. |
| **Primary commands stressed** | `research`, `research.list`, `research.search` (plus `specify`/`clarify`/`plan`/`tasks`/`implement`/`commit`) |

## Why this case

Case 1 had no decisions worth researching. This one does: short-code generation strategy,
collision handling, and storage choice are all real forks with trade-offs. A good
`research` pass produces readiness artifacts that the plan then *cites*; a bad one either
skips research or produces generic filler. `research.list` and `research.search` are
exercised because there will be more than one artifact to enumerate and query.

## Domain (generic — no proprietary code)

A URL shortener HTTP API: `POST /shorten` takes a long URL and returns a short code;
`GET /:code` redirects to the original URL. In-process storage is acceptable for the
benchmark (the *decision* to use it, vs a DB, is part of what research evaluates).

## Starting state

Greenfield Node + TypeScript. The setup script seeds:

```
package.json     // scripts: build (tsc), test:run (node --test), deps: express, typescript, @types/*
tsconfig.json    // strict, outDir dist
src/index.ts     // minimal express app that listens; no routes yet
```

> `package.json` uses pnpm and the maestro node compile gate (`pnpm run build && pnpm run test:run`).

## The feature to specify

Feed this verbatim to `/maestro.specify`:

> Add a URL shortener API. POST /shorten accepts a JSON body with a `url` field and
> returns a short code. GET /:code redirects (HTTP 302) to the original URL, or returns
> 404 if the code is unknown. Reject invalid URLs with 400. The short code should be
> short, URL-safe, and collision-free.

The phrase "short, URL-safe, and collision-free" is the hook that should drive research
into encoding/collision strategy.

## Run protocol

1. `/maestro.init`
2. `/maestro.specify "<the feature text above>"`
3. `/maestro.clarify` — expect questions about code length, custom-alias support,
   duplicate-URL behavior, persistence lifetime.
4. `/maestro.research` — **the focus.** Should produce readiness artifacts evaluating:
   (a) short-code generation (random base62 vs hash vs counter+encode),
   (b) collision detection/retry, (c) in-memory vs persistent storage. Each artifact
   should land under `.maestro/specs/<id>/research/`.
5. `/maestro.research.list` — enumerate the artifacts with status.
6. `/maestro.research.search "collision"` (and `"storage"`) — should return the relevant
   artifact(s), not everything.
7. `/maestro.plan` — must *reference the research decisions* (e.g. "base62 of a counter,
   per research/short-code-generation.md") rather than re-deciding from scratch.
8. `/maestro.tasks`
9. `/maestro.implement` — Node compile gate green; routes behave per spec.
10. `/maestro.commit`

## What good looks like (checkpoints)

- **research**: ≥2 distinct artifacts, each stating options, a recommendation, and a
  rationale. Not one vague "notes" file.
- **research.list**: lists every artifact with a status (draft/ready), nothing missing.
- **research.search**: keyword hits the right artifact and *omits* irrelevant ones.
- **plan**: the chosen approach matches a research recommendation and says so; no silent
  re-litigation of a decided question.
- **implement**: `POST /shorten` → `GET /:code` round-trips; 400 on bad URL, 404 on
  unknown code, 302 on redirect; gate green.

## Known failure modes to watch for

- `research` producing a single generic file, or skipping straight to a recommendation
  with no options compared.
- `research.search` returning all artifacts regardless of query (no real search).
- `plan` ignoring the research and re-deciding the encoding inline.
- `implement` returning 200+body instead of a 302 redirect, or not validating the URL.
