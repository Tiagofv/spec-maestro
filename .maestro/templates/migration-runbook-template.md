# Migration Runbook: Stabilizing the `bd` Workspace Prefix

One-time human migration that converts an existing `bd` workspace's
per-feature `<old-prefix>` (ids like `<old-prefix>NNN.M`) to a stable,
repo-level `<stable-prefix>`, so maestro's `/maestro.tasks` pre-flight check
(`.maestro/scripts/bd-preflight.sh`) can succeed on subsequent features.

If you arrived here from `bd-preflight.sh`'s drift exit (exit code 3), this
is the runbook it pointed you at — the script's stdout begins with
`✗ bd workspace prefix drift detected.` and includes the line
`See <path-to-this-runbook>`. For the spec that introduced this machinery,
see `.maestro/specs/061-fix-maestro-beads-issue-prefix/spec.md` in the
consuming project (specs live project-side, not toolkit-side).

---

## Preconditions

1. Snapshot `.beads/` so the rename is reversible even after the new prefix is
   in active use:

   ```sh
   cp -R .beads .beads.pre-migration-$(date +%Y%m%d)
   ```

2. Identify the prior feature's epic id (you'll need it to back-fill the
   `feature:NNN` label onto its tree): `bd list --type=epic`, then locate
   the feature's epic and note its id. For example, in the spec-maestro
   authors' own first run, this was `bd_058 → altpay-` with `feature:058`
   back-fill — your `<stable-prefix>`, `<prior_epic_id>`, and `feature:NNN`
   will differ.

3. Pick a `<stable-prefix>` that satisfies `bd rename-prefix --help`'s
   validation rules so the `--dry-run` below doesn't reject it: max 8
   chars, lowercase letters + digits + hyphens, starts with a letter, ends
   with a hyphen.

---

## Migration steps

Every destructive command is preceded by its `--dry-run`. Do not skip them.

1. Review the rename plan (non-destructive; safe to abort here):

   ```sh
   bd rename-prefix <stable-prefix> --dry-run
   ```

2. Apply the rename (irreversible without the snapshot from Preconditions
   step 1):

   ```sh
   bd rename-prefix <stable-prefix>
   ```

3. Back-fill the `feature:NNN` label onto the prior feature's epic tree, so
   it's queryable by label like everything created post-migration:

   ```sh
   bd label propagate <prior_epic_id> feature:NNN
   ```

   *Note: `bd label propagate` does **not** support `--dry-run` — `bd label
   propagate --help` lists no preview flag. It is safe to run without a dry-run
   because it is idempotent and additive: it adds the label to children that
   don't already have it and is a no-op for children that do. To preview the
   target set before running, list the children first:*

   ```sh
   bd children <prior_epic_id>
   ```

---

## Verification

Run all three checks. Any failure: stop and investigate.

1. The new prefix is the active workspace prefix:

   ```sh
   bd config get issue_prefix
   # expect: <stable-prefix>
   ```

2. The prior feature's full tree is queryable by its back-filled label:

   ```sh
   bd list --label feature:NNN
   # expect: every issue from the prior feature, now under <stable-prefix>
   ```

3. No issue retains the old prefix:

   ```sh
   bd list --all | grep <old-prefix>
   # expect: no output (exit code 1 from grep is the success signal)
   ```

---

## Fallback (skip the rename)

If you'd rather not touch historical ids, leave the prior feature's issues
alone forever (they keep their `<old-prefix>` ids) and only enforce the
stable prefix from the next feature onward.

**Explicit cost:** `.maestro/scripts/bd-preflight.sh` will refuse all future
`/maestro.tasks` runs until the workspace prefix is stabilized — it exits 3
("drift detected") on every invocation. This fallback trades one persistent
broken state for another: old ids stay untouched, but every future feature
is blocked at the tasks gate until you come back and run the migration.

---

## Rollback

If no new issues have been created under the new prefix yet, reverse the
rename in place: `bd rename-prefix <old-prefix> --repair`.

Once the new prefix is in active use, `--repair` is no longer safe — the
only path back is to restore the snapshot from Preconditions step 1:

```sh
rm -rf .beads && cp -R .beads.pre-migration-<YYYYMMDD> .beads
```

A snapshot restore loses any `bd` work tracked since the migration.
Communicate before doing this.
