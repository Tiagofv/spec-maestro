# Case 08 — Constitution enforcement + review CRITICAL (Go)

**Stack** Go · **Shape** strict constitution that the work tempts a violation of

No other case has a constitution with teeth, so **constitution enforcement and the inline
review's CRITICAL path are untested**. This case writes a strict constitution, then asks
for a feature whose obvious implementation violates it — so a faithful pipeline should
flag the violation in review (CRITICAL), spawn a fix task, and surface the bug/fix-chain in
`analyze`.

**Stresses:** constitution is read + enforced; inline review produces a **CRITICAL** verdict
→ fix task → fix chain; `analyze` reports a non-zero bug rate / fix-chain count (vs Case 5's
clean run).

## Domain
A small Go library `safejson` that parses config. The constitution forbids the easy path.

## Seed
`go.mod` (module `example.com/safejson`) + empty `safejson.go` · a **strict**
`.maestro/constitution.md`:
> - FORBIDDEN: `panic()` anywhere in library code — return an `error` instead.
> - FORBIDDEN: ignoring an `error` (no `_ = f()` on fallible calls).
> - REQUIRED: every exported function has a table-driven test.

## Specify (verbatim)
> Add `Parse(data []byte) (Config, error)` to safejson: parse JSON config into a Config
> struct, returning a useful error on malformed input. Also add `MustParse(data []byte)
> Config` for tests.

`MustParse` is the trap — the obvious implementation panics, which the constitution forbids.

## Run protocol
`init` → `specify` → `clarify` → `plan` → `tasks` → `implement` → `pm-validate` → `analyze`.

## What good looks like
- **specify/plan**: surface the constitution's constraints (error-not-panic, tests
  required) in success criteria / design; `MustParse` is flagged or designed to satisfy
  the rule (e.g. documented narrow exception or test-only).
- **implement + review**: if an implementation panics or ignores an error, the inline
  review returns **CRITICAL**, a fix task is created, and the fix lands before close.
- **analyze**: reports the bug (review finding) and the fix chain — a non-zero bug rate,
  not the all-green metrics of a clean run.

## Watch for
constitution never read (panic ships unflagged) · review rubber-stamping a violating diff
as PASS · no fix task created for a CRITICAL · `analyze` reporting 0 bugs despite the fix
chain.
