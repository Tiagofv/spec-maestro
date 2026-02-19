# Feature: Expand Maestro Agent Support to Multi-Agent Ecosystem

**Spec ID:** 004-expand-maestro-s-agent-support-beyond-claude-code-
**Author:** Maestro
**Created:** 2026-02-19
**Last Updated:** 2026-02-19
**Status:** Draft

---

## 1. Problem Statement

Currently, maestro only supports Claude Code and OpenCode as underlying AI agents. This limitation restricts adoption because many teams use alternative AI coding assistants like Cursor, Gemini CLI, GitHub Copilot, Codex CLI, and Windsurf. When developers working with these tools attempt to use maestro's specification-driven development workflow, they encounter incompatibility issues or cannot leverage the full feature set.

The current single-agent approach creates friction for:

- Teams that have standardized on other AI agents
- Developers who prefer specific agent capabilities (e.g., Cursor's IDE integration, Copilot's context awareness)
- Organizations with existing agent investments
- Projects requiring agent-specific optimizations

Expanding maestro to support multiple agents will significantly increase adoption while maintaining the unified workflow that makes maestro valuable.

---

## 2. Proposed Solution

Create a unified abstraction layer that enables maestro to detect, configure, and work with multiple AI agents. The solution will provide:

1. **Agent Detection & Discovery**: Automatic detection of which AI agents are installed and available on the developer's system
2. **Unified Configuration**: A consistent way to configure and customize behavior across all supported agents
3. **Runtime Switching**: The ability to switch between agents without restarting or reconfiguring the entire workflow
4. **Agent-Specific Optimizations**: Support for each agent's unique capabilities and command formats while maintaining a common interface
5. **Backward Compatibility**: Existing Claude Code and OpenCode setups continue to work without modification

The core idea is to treat agents as interchangeable backends while preserving maestro's specification-driven development methodology and user experience.

---

## 3. User Stories

### Story 1: Agent-Agnostic Workflow Setup

**As a** developer using Cursor,
**I want** to initialize maestro and have it automatically detect my Cursor installation,
**so that** I can start using specification-driven development without manual configuration.

**Acceptance Criteria:**

- [ ] Running `/maestro.init` detects Cursor installation automatically
- [ ] Maestro creates agent-specific command directories for Cursor
- [ ] The initialization completes without requiring manual agent selection
- [ ] A confirmation message shows which agent was detected and configured

### Story 2: Multi-Agent Team Collaboration

**As a** tech lead managing a diverse team,
**I want** to set up maestro once and have it work for team members using different agents (Claude, Cursor, Copilot),
**so that** our entire team can follow the same specification-driven workflow regardless of their preferred AI assistant.

**Acceptance Criteria:**

- [ ] Project initialization detects and configures all available agents on the system
- [ ] Team members using different agents can run the same `/maestro.specify` command
- [ ] Specifications created by one agent are readable and actionable by others
- [ ] The `.maestro/` directory structure supports multiple agent configurations simultaneously

### Story 3: Runtime Agent Switching

**As a** developer working on a complex feature,
**I want** to switch from my default agent to Gemini CLI for a specific planning session,
**so that** I can leverage Gemini's strengths for that particular task without changing my overall setup.

**Acceptance Criteria:**

- [ ] A command exists to list available agents (e.g., `/maestro.agents` or `--list-agents`)
- [ ] A command exists to switch agents (e.g., `/maestro.switch agent:cursor`)
- [ ] Switching agents preserves the current workflow state and context
- [ ] The active agent is displayed in maestro status or prompt

### Story 4: Agent-Specific Capability Support

**As a** developer using Windsurf,
**I want** maestro to utilize Windsurf's unique features (like cascade composition),
**so that** I'm getting the full benefit of my chosen agent within the maestro framework.

**Acceptance Criteria:**

- [ ] Agent-specific command formats are supported (e.g., Windsurf's cascade syntax)
- [ ] Agent capabilities are documented in the agent's configuration
- [ ] Maestro commands adapt to use agent-specific features when beneficial
- [ ] Fallback to common behavior when agent-specific features aren't available

### Story 5: Installation and Onboarding

**As a** new user with Codex CLI installed,
**I want** to run a single installation script that detects my agent and configures maestro appropriately,
**so that** I can be productive within minutes of discovering maestro.

**Acceptance Criteria:**

- [ ] An installation script (`install.sh` or similar) exists in the repository root
- [ ] The script detects available agents on the system (Claude, Cursor, Gemini, Copilot, Codex, Windsurf, OpenCode)
- [ ] The script prompts for agent preference if multiple are detected
- [ ] The script creates all necessary configuration files and directories
- [ ] The script provides clear next steps after installation

---

## 4. Success Criteria

The feature is considered complete when:

1. Maestro successfully detects and configures at minimum 5 agents: Claude Code, OpenCode, Cursor, Gemini CLI, and GitHub Copilot
2. The existing specification-driven workflow (`/maestro.specify`, `/maestro.plan`, `/maestro.implement`) works identically across all supported agents
3. A developer can switch between agents at runtime without losing workflow context
4. Installation documentation covers all supported agents with copy-paste commands
5. All existing maestro projects continue to work without modification (backward compatibility)
6. At least one agent-specific optimization is implemented per supported agent
7. The initialization time remains under 10 seconds for single-agent setup

---

## 5. Scope

### 5.1 In Scope

- Agent detection for: Claude Code, OpenCode, Cursor, Gemini CLI, GitHub Copilot, Codex CLI, Windsurf
- Unified abstraction layer for agent interface
- Agent-specific command directory creation (`.cursor/commands/`, `.gemini/commands/`, etc.)
- Agent-specific skill directory structure
- Runtime agent switching capability
- Installation script with multi-agent detection
- Configuration file format supporting multiple agents
- Documentation for each supported agent

### 5.2 Out of Scope

- Automatic migration from other workflow tools (users must manually adopt maestro)
- IDE plugins or extensions (focus is on CLI agents only)
- Real-time collaboration between different agents on the same task
- Cloud-based agent orchestration (keep it local/CLI-focused)
- Performance benchmarking between agents

### 5.3 Deferred

- GUI/Web interface for agent management
- Automatic agent capability detection and feature enablement
- Community-contributed agent adapters
- Enterprise SSO integration for agent authentication
- Telemetry and usage analytics across agents

---

## 6. Dependencies

- Existing `.maestro/` directory structure and templates
- Current specification-driven development workflow implementation
- Git integration for branch management
- Agent CLI binaries must be installed and available in PATH for detection

---

## 7. Open Questions

- [NEEDS CLARIFICATION: Should agent switching happen at the project level (per-project agent preference) or system level (global default)?]
- [NEEDS CLARIFICATION: How should maestro handle agents with conflicting command syntax? For example, if two agents use `/command` format differently]
- [NEEDS CLARIFICATION: What is the minimum version requirement for each supported agent? Should we support all versions or only recent releases?]
- [NEEDS CLARIFICATION: Should there be a "preferred agent" hierarchy (e.g., try Claude first, fall back to Cursor) or always require explicit selection when multiple agents are present?]

---

## 8. Risks

1. **Fragmentation Risk**: Supporting too many agents may lead to inconsistent experiences across different agent combinations
2. **Maintenance Burden**: Each new agent increases ongoing maintenance work when agents update their APIs or command formats
3. **Configuration Complexity**: Multi-agent support could overwhelm new users with too many options
4. **Compatibility Issues**: Agent-specific features may create hard-to-debug issues when switching between agents

Mitigation: Start with strict common interface requirements, defer agent-specific optimizations until core multi-agent support is stable.

---

## Changelog

| Date       | Change               | Author  |
| ---------- | -------------------- | ------- |
| 2026-02-19 | Initial spec created | Maestro |
