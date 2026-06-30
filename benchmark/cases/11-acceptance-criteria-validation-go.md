# Case 11 — Acceptance-criteria validation (Go)

**Stack** Go · **Shape** greenfield, malformed-AC trap · **Role** EARS quality gate

Cases 01 and 05 say the spec *should* be EARS-shaped; this case makes that **deterministic**.
The verbatim prompt is worded to invite vague, free-prose, happy-path-only criteria. A good
`specify` runs `validate-spec-format.sh`, **sees** the violations, and iterates until the
validator exits 0. A bad one writes the malformed criteria and proceeds on red.

**Stresses:** `validate-spec-format.sh` (EARS shape + failure-path pairing + vague-term
denylist), `specify` iterate-to-valid, `clarify`, `plan`.

## Domain
A small config-file loader/validator: read a config file at startup, validate the declared
fields, refuse to start on a bad file. No network/DB/auth.

## Seed (greenfield)
`go.mod` (module `example.com/configloader`) + empty `config.go`.

## Specify (verbatim — worded to invite malformed criteria)
> Add a config loader. It should read the config file at startup and be fast. It should handle
> bad files gracefully and support several config formats. Make the whole thing easy to use.

## Clarify answers to give
- **Config format:** a single fixed-name file `config.json` in the working directory.
- **Bad file:** on a missing/unreadable/invalid file, print a named error and exit non-zero
  (do not start the service).
- **Fields:** validate that required fields are present; unknown fields are ignored.
- **"Several formats":** JSON only for this feature; other formats are out of scope.

## Run protocol
`init` → `specify "<above>"` → `clarify` → `plan`. One command at a time; score each.

## What good looks like
- **specify**: the agent fills the template, runs `bash .maestro/scripts/validate-spec-format.sh
  {spec_dir}/spec.md`, and the validator initially **fails** on the seeded prompt (non-EARS
  free prose, vague terms `fast`/`gracefully`/`easy`/`several`, happy-path-only criteria). The
  agent ITERATES — rewriting each criterion into an EARS shape, adding a paired
  `If …, then …` for every `When …`, removing vague terms or marking
  `[NEEDS CLARIFICATION]` — until `validate-spec-format.sh` **exits 0** on the written spec
  (EARS shapes valid, every `When` paired with an `If…then`, no vague terms survive, ≥1
  `[NEEDS CLARIFICATION]`).
- **clarify**: resolves the format/bad-file/fields questions, writes each answer back **as an
  EARS criterion**, and re-runs the validator to 0 before stamping state.
- **plan**: concrete loader/validator files + JSON decoding; no invented DB/HTTP layer.

## Watch for
agent ignoring the validator output and proceeding on red · happy-path-only criteria (no
`If …, then …`) · vague terms (`fast`, `gracefully`, `easy`, `several`) surviving into the
final spec · specify/clarify proceeding while `validate-spec-format.sh` still reports
violations (validator output ignored).
