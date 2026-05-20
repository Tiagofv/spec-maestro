---
description: >
  Search across research titles, summaries, tags, and findings.
  Returns ranked results with relevance scores.
argument-hint: <search query>
---

# maestro.research.search

Search across all research items stored in `.maestro/research/`.

## Step 1: Prerequisites Check

Verify the project is initialized:

1. Confirm `.maestro/` directory exists
2. Confirm `.maestro/state/research/` exists
3. If not initialized, tell user to run `/maestro.init`

## Step 2: Validate Query

**Query Requirements:**

- Minimum 2 characters
- Maximum 200 characters
- Cannot be empty or whitespace-only

If invalid, show error and example usage:

```
Error: Search query must be 2-200 characters

Usage: /maestro.research.search <query>
Example: /maestro.research.search authentication
```

## Step 3: Execute Search

Use the research-state.sh script:

```bash
.maestro/scripts/research-state.sh search "$ARGUMENTS"
```

Or implement search logic:

**Search Fields:**

1. Research titles (highest weight)
2. Tags (high weight)
3. Query text (medium weight)
4. Summary content (medium weight)
5. Finding content (lower weight)

**Relevance Scoring:**

```javascript
// Pseudocode for scoring
function calculateRelevance(research, query) {
  let score = 0;
  const queryLower = query.toLowerCase();

  // Title match: +10 points
  if (research.title.toLowerCase().includes(queryLower)) {
    score += 10;
  }

  // Tag match: +5 points
  for (const tag of research.tags) {
    if (tag.toLowerCase().includes(queryLower)) {
      score += 5;
    }
  }

  // Query match: +3 points
  if (research.query.toLowerCase().includes(queryLower)) {
    score += 3;
  }

  // Summary match: +2 points
  if (research.summary && research.summary.toLowerCase().includes(queryLower)) {
    score += 2;
  }

  // Findings match: +1 point
  for (const finding of research.findings || []) {
    if (finding.toLowerCase().includes(queryLower)) {
      score += 1;
      break; // Max 1 point for findings
    }
  }

  return score;
}
```

## Step 4: Rank and Sort Results

Sort results by relevance score (descending).

**Relevance Indicators:**

```
★★★★★ (5 stars) - Score >= 15
★★★★☆ (4 stars) - Score 10-14
★★★☆☆ (3 stars) - Score 5-9
★★☆☆☆ (2 stars) - Score 1-4
★☆☆☆☆ (1 star)  - Score < 1
```

## Step 5: Format Output

Display search results:

```
Search Results for "authentication" ({count} matches)

20250311-oauth-patterns
  Relevance: ★★★★☆
  Title: OAuth implementation patterns in this codebase
  Type: codebase
  Tags: auth, oauth, patterns
  Created: 2025-03-11
  Matched in: title, tags

20250312-jwt-security
  Relevance: ★★★☆☆
  Title: JWT token security considerations
  Type: external
  Tags: auth, jwt, security
  Created: 2025-03-12
  Matched in: summary

...
```

**Match Location Display:**

- Show which fields contained matches
- Multiple locations separated by commas

## Step 6: Handle No Results

If no research items match:

```
No research found for "{query}"

Suggestions:
  - Try different keywords
  - Run `/maestro.research.list` to see all research
  - Create new research: `/maestro.research {query}`
```

## Step 7: Support Combining Filters

Allow combining search with `--type` filter:

```
/maestro.research.search "database" --type external
```

Apply type filter after search ranking.

## Step 8: Suggest Next Steps

Based on results, suggest actions:

1. **To view full research:** `cat .maestro/research/{id}.md`
2. **To link to feature:** Reference in `/maestro.specify` as "(see research {id})"
3. **To refine search:** Try more specific terms
4. **To browse all:** `/maestro.research.list`

---

**Remember:** Research search helps discover prior knowledge. Good search terms are specific and domain-relevant.
