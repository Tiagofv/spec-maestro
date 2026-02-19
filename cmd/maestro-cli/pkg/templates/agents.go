package templates

import (
	"bytes"
	"fmt"
	"runtime"
	"text/template"
)

// AgentsMDData holds template variables.
type AgentsMDData struct {
	Platform   string
	OS         string
	HomeDir    string
	MaestroDir string
	BDHelp     string
}

const agentsMDTemplate = `# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run ` + "`bd onboard`" + ` to get started.

## Quick Reference

` + "```bash" + `
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
` + "```" + `

## Platform

- OS: {{ .OS }}
- Maestro directory: {{ .MaestroDir }}

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below.

1. **File issues for remaining work**
2. **Run quality gates** (if code changed)
3. **Update issue status** — Close finished work
4. **PUSH TO REMOTE** — This is MANDATORY:
   ` + "```bash" + `
   git pull --rebase
   bd sync
   git push
   ` + "```" + `
5. **Verify** — All changes committed AND pushed
`

// GenerateAgentsMD produces the AGENTS.md content for the current platform.
func GenerateAgentsMD(maestroDir string) (string, error) {
	data := AgentsMDData{
		Platform:   fmt.Sprintf("%s/%s", runtime.GOOS, runtime.GOARCH),
		OS:         runtime.GOOS,
		MaestroDir: maestroDir,
	}

	tmpl, err := template.New("agents").Parse(agentsMDTemplate)
	if err != nil {
		return "", fmt.Errorf("parsing template: %w", err)
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", fmt.Errorf("executing template: %w", err)
	}

	return buf.String(), nil
}
