# Case 09 — Compile-gate failure + regression (Node, brownfield)

**Stack** Node (TS, pnpm) · **Shape** brownfield change that tempts a broken gate / regression

Other cases assume the gate goes green on the first try and nothing regresses. This case
**stresses the failure paths**: the implementation is easy to get wrong in a way that (a)
fails the compile gate (type error / failing new test) so `implement` must loop until
green, and (b) risks breaking an **existing** passing test so `pm-validate`'s regression
scan has something real to catch.

**Stresses:** `implement` compile-gate loop (never closes a task on a red gate) and
`pm-validate` regression detection (existing tests must still pass).

## Domain
An existing money-formatting utility. The feature changes rounding behavior — easy to
implement in a way that breaks the existing rounding tests.

## Seed (brownfield — existing tests must stay green)
`package.json` (build=tsc, test:run=node --test) · `tsconfig.json` (strict) ·
`src/money.ts` (`format(cents)` → `"$1.23"`, `round(cents, step)`) ·
`src/money.test.ts` (passing tests pinning current `format`/`round` behavior).

## Specify (verbatim)
> Add `formatWithCurrency(cents, code)` that formats an amount with a currency symbol
> (`USD`→`$`, `EUR`→`€`, `GBP`→`£`), reusing the existing `format`. Unknown codes return a
> 400-style error value. Do not change existing `format`/`round` behavior or their tests.

## Run protocol
`init` → `specify` → `clarify` → `plan` → `tasks` → `implement` (**gate must end green**)
→ `pm-validate` (**regression scan**) → `commit`-less: just verify.

## What good looks like
- **implement**: if the first attempt fails `tsc` or a new test, the agent iterates and
  does **not** mark the task done until `pnpm run build && pnpm run test:run` passes.
- **regression**: the existing `format`/`round` tests still pass unchanged.
- **pm-validate**: actually runs the suite and confirms zero regressions; if the change had
  altered `format`, it flags REGRESSION rather than passing.

## Watch for
`implement` closing a task with a red/again-skipped gate · the change editing `format` and
breaking existing tests · `pm-validate` claiming success without running the existing
suite · TypeScript `strict` errors waved through.
