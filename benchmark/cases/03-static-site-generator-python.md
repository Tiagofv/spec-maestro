# Case 03 — Static site generator (Python)

| | |
|---|---|
| **Stack** | Python (`py_compile` + `ruff`) |
| **Shape** | Greenfield, file-I/O + transformation, well-specified |
| **Difficulty** | Medium (S–M feature) |
| **Goal** | Verify the pipeline on the Python stack and on a multi-file plan, with a feature concrete enough that `clarify` should be near-empty. |
| **Primary commands stressed** | Python **compile gate**, multi-file `plan`/`tasks`, `pm-validate`, `commit` |

## Why this case

Two things this case isolates that the others don't:

1. **The Python compile gate** (`python -m py_compile **/*.py && ruff check .`). Does
   `implement` actually run it, and does it refuse to mark tasks done when `ruff` fails?
2. **A near-zero-ambiguity spec.** A well-specified feature should make `clarify` find
   *little or nothing*. If `clarify` invents questions here, that's a finding — it tells
   you the command pads its output. Score `clarify` on restraint, not volume.

## Domain (generic — no proprietary code)

A static site generator: read Markdown files from a `content/` directory, convert each to
an HTML file in `dist/`, wrapping the body in a shared HTML template. A simple, dependency
-light transform over the filesystem.

## Starting state

Greenfield Python. The setup script seeds:

```
pyproject.toml          // [tool.ruff] minimal config
ssg/__init__.py         // empty package
content/hello.md        // "# Hello\n\nWorld." — one sample input
templates/base.html     // <html><body>{{content}}</body></html>
```

## The feature to specify

Feed this verbatim to `/maestro.specify`:

> Build a static site generator. It reads every `.md` file under `content/`, converts the
> Markdown to HTML, inserts the HTML into the `{{content}}` placeholder of
> `templates/base.html`, and writes the result to `dist/<name>.html` (same basename, `.html`
> extension). Headings, paragraphs, bold, italic, and links must convert correctly. Running
> it twice produces identical output (idempotent). Print the count of files generated.

Concrete enough that the only legitimate clarifications are tiny (e.g. handling of nested
`content/` subdirectories, what to do if `dist/` already exists).

## Run protocol

1. `/maestro.init` — set `compile_gate.stack: python`.
2. `/maestro.specify "<the feature text above>"`
3. `/maestro.clarify` — **expect ≤2 markers, possibly zero.** Restraint is the signal.
4. `/maestro.plan` — a multi-file plan: a markdown→HTML converter, a template renderer, a
   file walker, a CLI entrypoint. Watch for it pulling in a heavy framework when stdlib +
   a tiny converter suffices.
5. `/maestro.tasks` — converter and renderer as independent tasks; the walker/entrypoint
   depends on both.
6. `/maestro.implement` — **Python gate must run**: `py_compile` clean and `ruff check`
   clean before any task closes.
7. `/maestro.pm-validate` — verify the idempotency and the per-element conversion
   acceptance criteria with actual evidence (run it twice, diff output).
8. `/maestro.commit`

## What good looks like (checkpoints)

- **clarify**: zero-to-few markers; no invented questions. (Compare against Case 5, where
  many markers are *correct*.)
- **plan**: separates conversion / templating / file-walking; chooses a reasonable
  approach (stdlib or a single small dep) without over-building.
- **implement**: code is `ruff`-clean and `py_compile`-clean; the agent treats a `ruff`
  failure as blocking, not advisory.
- **pm-validate**: actually demonstrates idempotency (second-run output identical) rather than
  asserting it; checks each required Markdown element converts.

## Known failure modes to watch for

- `clarify` manufacturing ambiguity to look thorough.
- `implement` ignoring `ruff` warnings or disabling the gate to get green.
- `plan`/`implement` reaching for a full framework (Jinja, a SSG library) when the spec is
  satisfiable with a small converter.
- `pm-validate` claiming idempotency without running the generator twice.
