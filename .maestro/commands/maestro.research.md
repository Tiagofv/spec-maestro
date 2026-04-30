---
description: >
  Conduct structured research on technologies, patterns, or solutions.
  Automatically detects research type from query patterns and stores findings
  in .maestro/research/ for reference during specification and planning.
argument-hint: <research query in plain language>
---

# maestro.research

Research topic: **$ARGUMENTS**

## Prerequisites

Before starting, verify the project has been initialized:

1. Confirm `.maestro/` directory exists in the project root
2. Confirm `.maestro/templates/research-template.md` exists
3. If either is missing, tell the user to run `/maestro.init` first and stop

## Step 0c: Find the Feature (for research linking)

If the user's query references a feature explicitly, extract that feature ID. Otherwise, infer the active feature to associate this research with using the following rules.

**Resolving the feature ID (AI inference):**

1. If the user supplied an explicit feature ID or number (e.g., `070`, `070-improve-...`), use it directly.
2. Otherwise, infer from context using these signals in priority order:
   a. **Recent state activity**: List `.maestro/state/*.json` files, read their `updated_at` field, pick the most recently updated non-`complete` feature.
   b. **Current git branch**: Run `git branch --show-current`. If the branch matches `feat/NNN-...` or `NNN-...`, extract and use that feature ID.
   c. **Conversation context**: If the current conversation referenced a feature earlier, use that feature.
3. Surface the inferred feature ID to the user BEFORE taking any action:
   ```
   Inferred feature: 070-improve-maestro-tasks-command-speed (from: recent state activity)
   Proceeding… (reply with a different feature ID to override)
   ```
4. **On signal conflict** (e.g., state recency says 070 but branch says 069): Ask the user which to use.
5. **On no signals**: Ask the user for an explicit feature ID.
6. **Exclude from inference**: Empty feature directories (spec.md missing or 0 bytes).

The inferred `feature_id` is used when linking research to a feature in Step 7.

## Step 1: Detect Research Type

Analyze the query to determine the research source type:

| Query Pattern | Source Type | Description |
|--------------|-------------|-------------|
| "How do we...", "Where is...", "Show me..." | **codebase** | Search existing code patterns and implementations |
| "What is...", "Compare...", "Trade-offs..." | **external** | Research external technologies, libraries, or approaches |
| "Find specs...", "Previous plans...", "Related features..." | **artifacts** | Search project specs, plans, and research items |

**Automatic Detection Rules:**

- **Codebase research**: Queries about existing implementations, patterns, or conventions in the current codebase
- **External research**: Queries about technologies, libraries, or external patterns not yet in the codebase
- **Artifact research**: Queries about existing specs, plans, or prior research items

## Query Pattern Detection

The research command uses pattern matching to automatically classify query intent. This section defines the detection patterns and classification logic.

### Pattern Matching Rules

Patterns are matched in order of specificity. The first matching pattern determines the source type.

#### Codebase Patterns (Priority: 1)

These patterns indicate the user wants to search within the current codebase:

| Pattern | Regex | Examples |
|---------|-------|----------|
| How do we | `(?i)^how\s+do\s+(we\|you\|I)` | "How do we handle errors?", "How do you implement auth?" |
| Where is | `(?i)^where\s+(is\|are\|does)` | "Where is the config?", "Where are models defined?" |
| Show me | `(?i)^show\s+me` | "Show me examples of...", "Show me the code for..." |
| Find examples | `(?i)find\s+examples?\s+of` | "Find examples of API calls" |
| Find implementation | `(?i)find\s+(the\s+)?implementations?` | "Find implementation of login" |
| How is X implemented | `(?i)how\s+is\s+\w+\s+implemented` | "How is caching implemented?" |
| Where do we | `(?i)^where\s+do\s+(we\|you)` | "Where do we define routes?" |
| Existing pattern | `(?i)existing\s+(code\|pattern\|implementation)` | "Show existing error handling" |
| In the codebase | `(?i)in\s+(the\s+)?(codebase\|project\|repo)` | "How is auth done in the codebase?" |
| Current implementation | `(?i)current\s+implementations?` | "Current implementation of logging" |

**Keywords (fallback matching):**
- `codebase`, `project`, `repository`, `source`, `existing`, `current`, `our`, `we`, `implementation`

#### External Patterns (Priority: 2)

These patterns indicate the user wants to research external technologies or compare options:

| Pattern | Regex | Examples |
|---------|-------|----------|
| What is | `(?i)^what\s+(is\|are)` | "What is gRPC?", "What are the options?" |
| Compare | `(?i)compare` | "Compare React vs Vue", "Compare approaches" |
| Trade-offs | `(?i)trade[\s-]?offs?` | "Trade-offs of REST vs GraphQL" |
| Best practices | `(?i)best\s+practices?` | "Best practices for Go error handling" |
| Pros and cons | `(?i)pros?\s+(and\|&|\/)?\s*cons?` | "Pros and cons of MongoDB" |
| Alternatives | `(?i)alternatives?\s+(to\|for)` | "Alternatives to PostgreSQL" |
| Should we use | `(?i)should\s+(we\|I)\s+use` | "Should we use Redis?" |
| Recommended | `(?i)recommended\s+(way\|approach\|library)` | "Recommended way to test" |
| Library for | `(?i)library\s+(for\|to)` | "Library for JSON parsing" |
| Tool for | `(?i)tool\s+(for\|to)` | "Tool for database migrations" |
| Framework | `(?i)framework\s+(for\|to)` | "Framework for building APIs" |
| Technology | `(?i)technology\s+(for\|to)` | "Technology for real-time updates" |
| Overview of | `(?i)overview\s+of` | "Overview of microservices" |
| Explain | `(?i)^explain` | "Explain how OAuth works" |

**Keywords (fallback matching):**
- `vs`, `versus`, `comparison`, `options`, `library`, `framework`, `tool`, `package`, `npm`, `pip`, `go get`, `documentation`

#### Artifact Patterns (Priority: 3)

These patterns indicate the user wants to search within project artifacts:

| Pattern | Regex | Examples |
|---------|-------|----------|
| Find specs | `(?i)find\s+(the\s+)?specs?` | "Find specs for auth" |
| Find plans | `(?i)find\s+(the\s+)?plans?` | "Find plans for migration" |
| Search plans | `(?i)search\s+(the\s+)?plans?` | "Search plans for API design" |
| Previous | `(?i)previous\s+(specs?\|plans?\|research)` | "Previous plans for auth" |
| Related features | `(?i)related\s+features?` | "Find related features" |
| Research on | `(?i)research\s+on` | "Research on payment patterns" |
| Specs for | `(?i)specs?\s+(for\|about\|on)` | "Specs for user management" |
| Plans for | `(?i)plans?\s+(for\|about\|on)` | "Plans for database setup" |
| Documentation on | `(?i)documentation\s+(on\|for)` | "Documentation on deployment" |
| Find research | `(?i)find\s+research` | "Find research on caching" |
| Existing specs | `(?i)existing\s+(specs?\|plans?)` | "Existing specs for payments" |
| Prior work | `(?i)prior\s+(work\|research)` | "Prior work on auth" |

**Keywords (fallback matching):**
- `spec`, `specs`, `specification`, `plan`, `plans`, `artifact`, `document`, `research item`, `.maestro`

### Classification Logic

```
function classifyQuery(query: string): IntentClassification {
  const normalizedQuery = query.toLowerCase().trim();
  
  // Priority 1: Codebase patterns (most specific)
  for (const pattern of CODEBASE_PATTERNS) {
    if (pattern.regex.test(normalizedQuery)) {
      return {
        type: 'codebase',
        confidence: 'high',
        matchedPattern: pattern.name,
        reasoning: `Matched pattern "${pattern.name}"`
      };
    }
  }
  
  // Priority 2: External patterns
  for (const pattern of EXTERNAL_PATTERNS) {
    if (pattern.regex.test(normalizedQuery)) {
      return {
        type: 'external',
        confidence: 'high',
        matchedPattern: pattern.name,
        reasoning: `Matched pattern "${pattern.name}"`
      };
    }
  }
  
  // Priority 3: Artifact patterns
  for (const pattern of ARTIFACT_PATTERNS) {
    if (pattern.regex.test(normalizedQuery)) {
      return {
        type: 'artifact',
        confidence: 'high',
        matchedPattern: pattern.name,
        reasoning: `Matched pattern "${pattern.name}"`
      };
    }
  }
  
  // Fallback: Keyword-based classification
  return classifyByKeywords(normalizedQuery);
}

function classifyByKeywords(query: string): IntentClassification {
  const codebaseScore = countKeywords(query, CODEBASE_KEYWORDS);
  const externalScore = countKeywords(query, EXTERNAL_KEYWORDS);
  const artifactScore = countKeywords(query, ARTIFACT_KEYWORDS);
  
  const scores = [
    { type: 'codebase', score: codebaseScore },
    { type: 'external', score: externalScore },
    { type: 'artifact', score: artifactScore }
  ];
  
  scores.sort((a, b) => b.score - a.score);
  
  if (scores[0].score === 0) {
    // No clear classification - default to external for open-ended questions
    return {
      type: 'external',
      confidence: 'low',
      matchedPattern: null,
      reasoning: 'No clear pattern match, defaulting to external research'
    };
  }
  
  return {
    type: scores[0].type,
    confidence: scores[0].score === scores[1].score ? 'medium' : 'medium',
    matchedPattern: null,
    reasoning: `Keyword match: ${scores[0].score} ${scores[0].type}-related terms`
  };
}
```

### Intent Classification Structure

```typescript
interface IntentClassification {
  type: 'codebase' | 'external' | 'artifact';
  confidence: 'high' | 'medium' | 'low';
  matchedPattern: string | null;
  reasoning: string;
}
```

### Query Classification Examples

| Query | Detected Type | Matched Pattern | Confidence |
|-------|--------------|-----------------|------------|
| "How do we handle authentication?" | codebase | How do we | high |
| "Where is the user model defined?" | codebase | Where is | high |
| "Show me examples of API error handling" | codebase | Show me | high |
| "Find examples of middleware usage" | codebase | Find examples | high |
| "What is the best library for JSON parsing?" | external | What is | high |
| "Compare PostgreSQL vs MongoDB for time-series" | external | Compare | high |
| "Trade-offs of REST vs GraphQL" | external | Trade-offs | high |
| "Best practices for Go error handling" | external | Best practices | high |
| "Pros and cons of using Redis" | external | Pros and cons | high |
| "Should we use gRPC for internal APIs?" | external | Should we use | high |
| "Find specs for payment processing" | artifact | Find specs | high |
| "Previous plans for database migration" | artifact | Previous | high |
| "Research on caching strategies" | artifact | Research on | high |
| "Existing specs for authentication" | artifact | Existing specs | high |
| "How to implement rate limiting" | external | How to + no codebase keywords | medium |
| "User authentication implementation" | codebase | implementation keyword | medium |
| "Database options" | external | options keyword | low |

### Ambiguous Query Handling

When a query could match multiple patterns:

1. **Explicit override**: User can prefix with source type:
   - `[codebase] How to implement X` → Forces codebase search
   - `[external] How to implement X` → Forces external research
   - `[artifact] How to implement X` → Forces artifact search

2. **Confidence threshold**: If confidence is 'low', ask user for clarification:
   ```
   I'm not sure what type of research you want:
   
   [1] Search the codebase for existing implementations
   [2] Research external libraries and approaches
   [3] Search project specs and plans
   
   Please reply with 1, 2, or 3.
   ```

3. **Compound queries**: If query contains patterns from multiple types, use the first explicit pattern or the most specific match.

## Step 2: Create Research Scaffold

Generate a research ID based on the current date and query slug using the create-research.sh helper script.

### Scaffold Generation Process

Use the helper script at `.maestro/scripts/create-research.sh`:

```bash
.maestro/scripts/create-research.sh "$ARGUMENTS"
```

### Slug Generation Rules

The script converts queries to kebab-case slugs with these transformations:

1. **Lowercase conversion**: All characters converted to lowercase
2. **Character substitution**: Non-alphanumeric characters replaced with dashes (`-`)
3. **Dash collapse**: Multiple consecutive dashes collapsed to single dash
4. **Trim**: Leading and trailing dashes removed
5. **Length limit**: Maximum 50 characters (to keep filenames manageable)
6. **Empty fallback**: If result is empty, use `"research"`

**Example transformations:**

| Query | Slug |
|-------|------|
| "How do we handle error logging?" | `how-do-we-handle-error-logging` |
| "PostgreSQL vs MongoDB" | `postgresql-vs-mongodb` |
| "Best practices for API rate limiting" | `best-practices-for-api-rate-limiting` |

### Date-Based Naming

The final filename follows the pattern:

```
{YYYYMMDD}-{slug}.md
```

Example: `/maestro.research How do we handle error logging?` → `20250311-how-do-we-handle-error-logging.md`

### Script Behavior

The `create-research.sh` script:

1. **Validates input**: Ensures query argument is provided
2. **Checks prerequisites**: Verifies template file exists at `.maestro/templates/research-template.md`
3. **Creates directory**: Ensures `.maestro/research/` exists
4. **Generates filename**: Applies slug rules and date prefix
5. **Handles conflicts**: Exits with error if file already exists
6. **Populates template**: Copies template and replaces placeholders:
   - `{Research Title}` → Original query
   - `{Original research query}` → Original query
   - `{ISO timestamp}` → Current UTC timestamp
   - `{author}` → Current user ($USER)
   - `{Query Title}` → Original query
   - Date placeholders → Current date
7. **Error handling**: Returns non-zero exit code on any failure with stderr message

### YAML Frontmatter Population

The generated research file includes populated frontmatter:

```yaml
---
title: "{Original research query}"
query: "{Original research query}"
created_at: "2025-03-11T12:00:00Z"
author: "username"
tags: []
source_type: "codebase"
linked_features: []
---
```

### Error Handling

The script handles these error conditions:

| Condition | Exit Code | Error Message |
|-----------|-----------|---------------|
| Missing query argument | 1 | "Error: Research query is required" |
| Template not found | 1 | "Error: Research template not found at {path}" |
| Directory creation failed | 1 | "Error: Failed to create research directory {path}" |
| File already exists | 1 | "Error: Research file already exists: {path}" |
| Template read failed | 1 | "Error: Failed to read template file" |
| File write failed | 1 | "Error: Failed to write research file {path}" |

If script execution fails, report the error to the user and stop.

## Step 3: Execute Research by Source Type

### Source Type 1: Codebase Research

**Trigger patterns:** "How do we...", "Where is...", "Show me...", "Find examples of..."

**Process:**

1. Search through project source code for relevant patterns
2. Examine existing specs in `.maestro/specs/` for related implementations
3. Look for established conventions in the codebase
4. Extract code snippets with file paths and line numbers

**Findings structure:**
- Code location (file path, line numbers)
- Pattern description
- Usage examples
- Related files

**Example queries:**
- `/maestro.research How do we handle authentication in this codebase?`
- `/maestro.research Show me examples of error handling patterns`
- `/maestro.research Where do we define database models?`

### Source Type 2: External Research

**Trigger patterns:** "What is...", "Compare...", "Trade-offs...", "Best practices for..."

**Process:**

1. Research external technologies, libraries, or patterns
2. Identify multiple options with pros/cons for each
3. Document recommendations based on project context
4. Include references to documentation or authoritative sources

**Findings structure:**
- Technology/library name
- Description and purpose
- Pros and cons
- Use cases
- References (URLs, docs)

**Example queries:**
- `/maestro.research What are the trade-offs between PostgreSQL and MongoDB for time-series data?`
- `/maestro.research Compare React Query vs SWR for data fetching`
- `/maestro.research Best practices for implementing rate limiting in Go`

#### External Research Workflow

When conducting external research, follow this structured approach to generate comprehensive findings:

##### Step 1: Identify Research Scope

Analyze the query to determine:
- **Technology domain** (database, frontend framework, API style, etc.)
- **Comparison type** (single technology deep-dive, multi-option comparison, pattern analysis)
- **Project constraints** (language ecosystem, scale requirements, team expertise)

##### Step 2: Research Multiple Options

For each technology or approach identified, gather:

**Core Information:**
- Official name and latest stable version
- Primary purpose and problem it solves
- Maturity level (experimental, stable, legacy)
- Community size and activity level
- License type and commercial considerations

**Technical Details:**
- Supported languages and platforms
- Integration patterns with common stacks
- Performance characteristics (throughput, latency, resource usage)
- Scalability limits and horizontal scaling support

##### Step 3: Structured Pros/Cons Analysis

For each option, document:

**Pros (Advantages):**
- List 3-7 specific advantages
- Include technical benefits (performance, simplicity, features)
- Include ecosystem benefits (community, tooling, documentation)
- Include business benefits (cost, hiring, long-term viability)

**Cons (Disadvantages):**
- List 3-7 specific disadvantages
- Include technical limitations (complexity, overhead, constraints)
- Include operational concerns (hosting, maintenance, monitoring)
- Include adoption barriers (learning curve, migration effort)

**Use scoring when helpful:**
```
Criterion          | Option A | Option B | Option C
-------------------|----------|----------|----------
Performance        | ★★★★☆    | ★★★☆☆    | ★★★★★
Ease of use        | ★★★★★    | ★★★★☆    | ★★★☆☆
Community support  | ★★★☆☆    | ★★★★★    | ★★★★☆
Documentation      | ★★★★☆    | ★★★★★    | ★★★☆☆
Integration        | ★★★★☆    | ★★★★☆    | ★★★☆☆
```

##### Step 4: Use Case Mapping

Identify specific scenarios where each option excels:

**Best For:**
- Scenario 1: Description and why this option fits
- Scenario 2: Description and why this option fits

**Avoid When:**
- Scenario 1: Description and why this option is unsuitable
- Scenario 2: Description and why this option is unsuitable

##### Step 5: Source Documentation

For each technology, capture authoritative sources:

**Required Sources:**
- Official documentation URL (primary reference)
- GitHub/repository URL (if open source)
- Getting started guide URL
- API reference or specification URL

**Additional Sources (when available):**
- Comparison articles from trusted sources
- Case studies from production usage
- Benchmark results or performance studies
- Community discussions (Reddit, Hacker News, Stack Overflow)

**Source Format:**
```markdown
**{Technology Name}**
- **Official Docs**: [Documentation](https://docs.example.com) - Primary reference
- **Repository**: [GitHub](https://github.com/org/repo) - Source code and issues
- **Getting Started**: [Quick Start Guide](https://docs.example.com/quickstart) - Tutorial for beginners
- **API Reference**: [API Docs](https://api.example.com) - Detailed API specification
```

##### Step 6: Synthesize Recommendations

Based on the analysis, provide clear guidance:

**Recommendation Structure:**
1. **Primary Recommendation**: The top choice and why
2. **Alternative Option**: When the primary isn't suitable
3. **Avoid**: Technologies that don't fit the use case

**Recommendation Template:**
```markdown
## Recommendation

**Recommended Approach**: {Technology Name}

**Rationale**:
- {Reason 1 based on analysis}
- {Reason 2 based on analysis}
- {Reason 3 based on analysis}

**When to choose alternatives**:
- {Scenario where Option B is better}: {Explanation}
- {Scenario where Option C is better}: {Explanation}

**Migration/Adoption Path**:
1. {Step 1 for adopting the recommendation}
2. {Step 2 for adopting the recommendation}
3. {Step 3 for adopting the recommendation}
```

##### Step 7: Risk Assessment

Document potential risks and mitigation strategies:

**Risk Categories:**
- **Technical risks**: Performance issues, bugs, limitations
- **Ecosystem risks**: Abandonment, breaking changes, community fragmentation
- **Operational risks**: Security concerns, compliance issues, vendor lock-in

**Risk Documentation:**
```markdown
### Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| {Risk description} | Low/Medium/High | Low/Medium/High | {Mitigation strategy} |
```

#### External Research Output Template

Research documents for external sources should follow this structure:

```markdown
# Research: {Query Title}

**Research ID:** YYYYMMDD-{slug}  
**Date:** YYYY-MM-DD  
**Source Type:** external  
**Domain:** {technology domain}

## Query

{Original user query}

## Summary

{2-3 sentence overview of findings and primary recommendation}

## Options Analyzed

### Option 1: {Technology Name}

**Overview**: {Brief description of what it is and does}

**Latest Version**: {version number}  
**Maturity**: {experimental/beta/stable/legacy}  
**License**: {license type}

#### Pros
- {Advantage 1 with brief explanation}
- {Advantage 2 with brief explanation}
- {Advantage 3 with brief explanation}

#### Cons
- {Disadvantage 1 with brief explanation}
- {Disadvantage 2 with brief explanation}
- {Disadvantage 3 with brief explanation}

#### Best For
- {Use case 1}
- {Use case 2}

#### Sources
- **Official Docs**: [{Title}]({URL}) - {Description}
- **Repository**: [{Title}]({URL}) - {Description}
- **Getting Started**: [{Title}]({URL}) - {Description}

---

### Option 2: {Technology Name}

[Same structure as Option 1]

## Comparison Matrix

| Criteria | Option 1 | Option 2 | Option 3 |
|----------|----------|----------|----------|
| {Criterion} | {Rating} | {Rating} | {Rating} |

## Recommendation

**Recommended**: {Technology Name}

**Rationale**:
1. {Key reason}
2. {Key reason}
3. {Key reason}

**When to use alternatives**:
- {Scenario}: Use {Alternative} because {reason}

**Adoption Path**:
1. {Step 1}
2. {Step 2}
3. {Step 3}

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| {Risk} | {level} | {level} | {strategy} |

## References

- [{Title}]({URL}) - {Description}
- [{Title}]({URL}) - {Description}
```

#### Quality Checks

Before completing external research, verify:

- [ ] At least 2-3 options were researched (even if query asks for one)
- [ ] Each option has 3+ pros and 3+ cons documented
- [ ] All source URLs are included and valid
- [ ] Recommendation includes clear rationale
- [ ] Risks and mitigations are documented
- [ ] Use cases are specific to the project context
- [ ] Analysis considers team expertise and existing stack

### Source Type 3: Artifact Research

**Trigger patterns:** "Find specs...", "Previous plans...", "Related features...", "Research on..."

**Process:**

1. Search through `.maestro/specs/` for relevant specifications
2. Check `.maestro/plans/` for implementation approaches
3. Review `.maestro/research/` for existing research items
4. Identify patterns across multiple features

**Findings structure:**
- Artifact type (spec, plan, research)
- Artifact ID and title
- Summary of relevant content
- Cross-references to related items

**Example queries:**
- `/maestro.research Find specs related to authentication`
- `/maestro.research Previous plans for database migrations`
- `/maestro.research Research on payment processing patterns`

## Step 4: Read the Research Template

Read the template from `.maestro/templates/research-template.md`.

## Step 5: Generate Research Document

Fill in the template based on the query and research findings.

**Research document structure:**

```markdown
# Research: {Query Title}

**Research ID:** YYYYMMDD-{slug}  
**Date:** YYYY-MM-DD  
**Source Type:** codebase | external | artifacts  
**Tags:** tag1, tag2, tag3

## Query

{Original user query}

## Summary

{Brief overview of findings and key recommendations}

## Findings

### {Finding Category 1}

- {Bullet point with key fact}
- {Bullet point with key fact}

{Short paragraph explaining conclusion or recommendation}

### {Finding Category 2}

...

## Sources

- **Code:** `file/path.go:123` - Description
- **External:** [Title](https://url.com) - Description
- **Artifact:** `specs/001-feature/spec.md` - Description

## Related Research

- `YYYYMMDD-other-research` - Brief description
- `specs/001-feature/spec.md` - Related specification
```

## Step 6: Write Research File

Write the completed research to `.maestro/research/{research_id}.md`.

## Step 7: Update State

Create or update the research state file at `.maestro/state/research/{research_id}.json`:

```json
{
  "research_id": "YYYYMMDD-{slug}",
  "title": "{query summary}",
  "source_type": "codebase|external|artifacts",
  "created_at": "{ISO timestamp}",
  "updated_at": "{ISO timestamp}",
  "file_path": ".maestro/research/{research_id}.md",
  "tags": ["tag1", "tag2"],
  "linked_features": [],
  "history": [{ "action": "created", "timestamp": "{ISO}" }]
}
```

## Step 8: Report and Suggest Next Steps

Show the user:

1. Research summary:
   - Research ID and file path
   - Source type detected
   - Number of findings
   - Tags applied

2. Suggest next steps:
   - To reference this research during specification: "When running `/maestro.specify`, mention this research ID to include it as context"
   - To view all research: "Run `/maestro.list research` to see all research items"
   - To search research: "Use `/maestro.search research <query>` to find related research"

## Integration with Specify Command

Research can be referenced during feature specification:

### During `/maestro.specify`:

When a user runs `/maestro.specify <feature description>`, they can reference research:

```
/maestro.specify Implement OAuth authentication (see research 20250311-oauth-patterns)
```

### Research Linking:

When research is referenced during specify:

1. The research file is read and its findings are included as context
2. The research ID is added to the spec's `References` section
3. The spec file is added to the research's `linked_features` array in state

### Spec Template Integration:

Research findings appear in the specification under a **Research** section:

```markdown
## Research

- **20250311-oauth-patterns** - OAuth implementation patterns in this codebase
  - Found in: `auth/oauth.go`, `middleware/auth.go`
  - Key pattern: JWT tokens with refresh mechanism
- **20250312-oauth-libraries** - External OAuth library comparison
  - Recommended: `golang.org/x/oauth2` for Go projects
```

## Research Discovery

Users can discover existing research:

### List All Research:

```
/maestro.list research
```

Shows:
- Research ID and title
- Source type
- Creation date
- Number of linked features
- Tags

### Search Research:

```
/maestro.search research <query>
```

Searches:
- Research titles and summaries
- Tags
- Linked feature names
- Finding content

### Filter by Source Type:

```
/maestro.list research --type codebase
/maestro.list research --type external
/maestro.list research --type artifacts
```

---

## Research Listing and Search

The `/maestro.research` command supports listing and searching research items stored in `.maestro/research/`.

### Commands

| Command | Description |
|---------|-------------|
| `/maestro.research.list` | List all research items with metadata |
| `/maestro.research.list --type {codebase\|external\|artifact}` | Filter by source type |
| `/maestro.research.list --tag {tag}` | Filter by tag |
| `/maestro.research.search {keyword}` | Search across titles and summaries |

### /maestro.research.list

Lists all research items with their metadata.

**Usage:**
```
/maestro.research.list
```

**Output Format:**
```
Research Items (12 total)

20250311-oauth-patterns
  Title: OAuth implementation patterns in this codebase
  Type: codebase
  Tags: auth, oauth, patterns
  Created: 2025-03-11
  Linked Features: 2

20250312-postgresql-mongodb
  Title: Compare PostgreSQL vs MongoDB for time-series data
  Type: external
  Tags: database, comparison
  Created: 2025-03-12
  Linked Features: 0
```

**Metadata Fields:**
- **Research ID**: Unique identifier (YYYYMMDD-slug format)
- **Title**: Original research query or summary
- **Type**: Source type (codebase, external, artifact)
- **Tags**: List of assigned tags
- **Created**: Date the research was created
- **Linked Features**: Number of specs/plans referencing this research

### Filter by Source Type

Filter research items by their source type.

**Usage:**
```
/maestro.research.list --type codebase
/maestro.research.list --type external
/maestro.research.list --type artifact
```

**Output:** Only shows research items matching the specified source type.

### Filter by Tag

Filter research items by one or more tags.

**Usage:**
```
/maestro.research.list --tag auth
/maestro.research.list --tag database
/maestro.research.list --tag "performance optimization"
```

**Behavior:**
- Shows research items that have the specified tag
- Tag matching is case-insensitive
- Multiple `--tag` flags can be combined (OR logic)

### /maestro.research.search

Search across research titles and summaries.

**Usage:**
```
/maestro.research.search authentication
/maestro.research.search "database migration"
/maestro.research.search caching
```

**Search Scope:**
- Research titles
- Research summaries
- Finding content
- Tags

**Output Format:**
```
Search Results for "authentication" (3 matches)

20250311-oauth-patterns
  Relevance: ★★★★☆
  Summary: OAuth 2.0 implementation patterns found in the codebase...
  Matched in: title, tags

20250310-jwt-security
  Relevance: ★★★☆☆
  Summary: Security considerations for JWT token handling...
  Matched in: summary, findings
```

**Relevance Scoring:**
- **Title match**: Highest priority
- **Tag match**: High priority
- **Summary match**: Medium priority
- **Finding content match**: Lower priority

### Combining Filters

Filters can be combined for precise discovery:

```
/maestro.research.list --type external --tag database
/maestro.research.search "error handling" --type codebase
```

### Empty Results

When no research items match the criteria:

```
No research items found matching:
  - Type: external
  - Tag: deprecated

Suggestions:
  - Run /maestro.research.list to see all research
  - Try different search terms
  - Check available tags with /maestro.research.tags
```

---

**Remember:** Research is reusable knowledge. Good research captures not just facts, but the reasoning and context that led to conclusions. Write research you'd want to reference 6 months from now.
