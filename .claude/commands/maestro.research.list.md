---
description: >
  List all research items with metadata and filtering options.
  Supports filtering by type, tag, and linked features.
argument-hint: [--type {codebase|external|artifact}] [--tag {tag}]
---

# maestro.research.list

List all research items stored in `.maestro/research/` with their metadata.

## Step 1: Prerequisites Check

Verify the project is initialized:

1. Confirm `.maestro/` directory exists
2. Confirm `.maestro/state/research/` exists
3. If not initialized, tell user to run `/maestro.init`

## Step 2: Parse Filters

Parse optional filter arguments:

**Supported Filters:**

| Flag       | Description                           | Values                                         |
| ---------- | ------------------------------------- | ---------------------------------------------- |
| `--type`   | Filter by source type                 | `codebase`, `external`, `artifact`, `parallel` |
| `--tag`    | Filter by tag                         | Any tag string                                 |
| `--linked` | Show only research linked to features | (no value)                                     |
| `--orphan` | Show only unlinked research           | (no value)                                     |

## Step 3: Load Research State

Use the research-state.sh script to list research:

```bash
.maestro/scripts/research-state.sh list [type] [tag]
```

Or read directly from `.maestro/state/research/*.json`.

## Step 4: Format Output

Display research items in a formatted table:

```
Research Items ({count} total)

ID                     Title                           Type       Created     Linked
--------------------   -----------------------------   --------   ----------  ------
20250311-oauth-patt..  OAuth implementation patterns   codebase   2025-03-11  2
20250312-db-compar..   PostgreSQL vs MongoDB          external   2025-03-12  0
...
```

**Column Details:**

- **ID:** Research ID (YYYYMMDD-slug, truncated)
- **Title:** Research title or query summary
- **Type:** Source type (codebase/external/artifact/parallel)
- **Created:** Date created
- **Linked:** Number of linked features

## Step 5: Apply Filters

If filters provided, apply them:

**Filter Logic:**

- `--type`: Match exact source_type in state
- `--tag`: Check if tag exists in tags array
- `--linked`: linked_features.length > 0
- `--orphan`: linked_features.length == 0

Multiple filters combine with AND logic.

## Step 6: Handle Empty Results

If no research items match:

```
No research items found matching:
  - Type: {type}
  - Tag: {tag}

Suggestions:
  - Run `/maestro.research <query>` to create research
  - Run `/maestro.research.list` to see all research
  - Check available tags with `/maestro.research.tags`
```

## Step 7: Show Summary Statistics

At the end of output, display:

```
Summary:
  Total items: {count}
  By type:
    - Codebase: {count}
    - External: {count}
    - Artifact: {count}
    - Parallel: {count}
  Linked to features: {count}
  Orphaned: {count}
```

## Step 8: Suggest Next Steps

Suggest follow-up actions:

1. **To view research details:** `cat .maestro/research/{id}.md`
2. **To search research:** `/maestro.research.search <query>`
3. **To link to feature:** Include in `/maestro.specify` as "(see research {id})"
4. **To create new research:** `/maestro.research <query>`

---

**Remember:** Research items are discoverable knowledge. Listing helps find prior work and avoid redundant research.
