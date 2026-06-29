# Case 03 — Static site generator (Python)

**Stack** Python (`py_compile` + `ruff`) · **Shape** greenfield, well-specified

Isolates two things: (1) the **Python compile gate** — does `implement` run it and refuse
to close tasks on a `ruff` failure? (2) **clarify restraint** — a near-zero-ambiguity spec
should make `clarify` find *little or nothing*. If it invents questions here, that's a
finding. Score `clarify` on restraint, not volume (opposite of Case 5).

**Stresses:** Python gate, multi-file `plan`/`tasks`, `pm-validate`, `commit`.

> Requires `ruff` on PATH; without it the Python gate can only partially run — note that in results.

## Domain
Static site generator: read `.md` from `content/`, convert to HTML, wrap in
`templates/base.html`, write to `dist/<name>.html`.

## Seed (greenfield)
`pyproject.toml` ([tool.ruff]) · `ssg/__init__.py` · `content/hello.md` · `templates/base.html` (`{{content}}`).

## Specify (verbatim)
> Build a static site generator. It reads every `.md` file under `content/`, converts the
> Markdown to HTML, inserts the HTML into the `{{content}}` placeholder of
> `templates/base.html`, and writes the result to `dist/<name>.html`. Headings, paragraphs,
> bold, italic, and links must convert correctly. Running it twice produces identical
> output. Print the count of files generated.

## Run protocol
`init` (stack: python) → `specify` → `clarify` (**expect ≤2 markers, maybe 0**) → `plan`
→ `tasks` → `implement` (**gate must run**) → `pm-validate` → `commit`.

## What good looks like
- **clarify**: zero-to-few markers; no invented questions.
- **plan**: separates conversion / templating / file-walking; no heavyweight framework.
- **implement**: `ruff`-clean + `py_compile`-clean; treats a `ruff` failure as blocking.
- **pm-validate**: actually runs the generator twice and diffs (proves idempotency).

## Watch for
clarify manufacturing ambiguity · implement ignoring/disabling ruff · reaching for Jinja/a
SSG lib when a small converter suffices · pm-validate asserting idempotency without rerunning.
