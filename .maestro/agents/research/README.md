# Research Agents

This directory contains specialized research agents that execute in parallel to investigate different aspects of a research query.

## Architecture

The research phase uses **4 specialized agents** that run simultaneously:

1. **Technology Research Agent** (`technology-agent.md`)
   - Researches external technologies, libraries, and tools
   - Compares options with pros/cons
   - Provides recommendations with rationale

2. **Pattern Research Agent** (`pattern-agent.md`)
   - Discovers existing patterns in codebase
   - Searches external pattern repositories
   - Maps patterns to current use case

3. **Pitfall Research Agent** (`pitfall-agent.md`)
   - Identifies common mistakes and gotchas
   - Documents known limitations
   - Assesses risks with mitigations

4. **Best Practices Agent** (`best-practices-agent.md`)
   - Researches domain-specific best practices
   - Identifies industry standards
   - Provides contextual recommendations

## Parallel Execution

When a complex research query is detected (contains keywords like "architecture", "comprehensive", "full analysis"), all 4 agents spawn simultaneously:

```
User Query
    ↓
[Orchestrator] → Spawns 4 agents in parallel
    ↓
[Tech Agent] ←→ [Pattern Agent] ←→ [Pitfall Agent] ←→ [Best Practices Agent]
    ↓
[Synthesis] → Unified research document
```

**Execution Rules:**

- Each agent has a 30-minute time limit
- Agents are independent (no dependencies between them)
- Results synthesized after all agents complete
- Conflicting findings weighted by confidence scores

## Agent Template

When creating a new research agent, follow this template:

````markdown
---
name: "{Agent Name}"
type: "{technology|pattern|pitfall|best_practices}"
description: "One sentence description"
triggers: ["keyword1", "keyword2"]
outputs:
  - finding_type
  - recommendation
  - risk_assessment
---

# {Agent Name}

## Purpose

{What this agent researches and why}

## Research Workflow

### Step 1: {Action}

{Detailed steps}

### Step 2: {Action}

{Detailed steps}

## Output Format

```markdown
### {Category}

- {Finding with evidence}
- {Finding with evidence}

**Recommendation:** {Clear recommendation}
```
````

## Quality Checklist

Before completing research, verify:

- [ ] {Criterion 1}
- [ ] {Criterion 2}
- [ ] {Criterion 3}

```

## Adding New Agents

1. Create a new file: `{agent-name}-agent.md`
2. Follow the template above
3. Add agent to orchestration logic in `maestro.research.md`
4. Update this README with agent summary

## Integration

Research agents are invoked by the `/maestro.research` command when:
- Query matches agent triggers
- Query complexity warrants parallel research
- User explicitly requests comprehensive research

Results are synthesized into a unified research document stored in `.maestro/research/`.
```
