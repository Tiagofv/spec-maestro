package agents

import (
	"fmt"
	"path"
	"sort"
	"strings"
)

// AddCodexCommandSkills returns a copy of content with Codex skill wrappers
// for each Maestro command markdown file. Codex CLI does not dispatch custom
// slash commands from .codex/commands, but it does discover project skills.
func AddCodexCommandSkills(content map[string][]byte) map[string][]byte {
	if content == nil {
		return nil
	}

	withSkills := make(map[string][]byte, len(content))
	keys := make([]string, 0, len(content))
	for key, value := range content {
		withSkills[key] = value
		keys = append(keys, key)
	}
	sort.Strings(keys)

	for _, key := range keys {
		commandName, ok := codexCommandNameFromPath(key)
		if !ok {
			continue
		}

		skillName := CodexCommandSkillName(commandName)
		skillPath := path.Join("skills", skillName, "SKILL.md")
		if _, exists := withSkills[skillPath]; exists {
			continue
		}

		withSkills[skillPath] = []byte(renderCodexCommandSkill(commandName, content[key]))
	}

	return withSkills
}

// CodexCommandSkillName converts a Maestro command name into the generated
// Codex skill name, e.g. maestro.research.list -> maestro-research-list.
func CodexCommandSkillName(commandName string) string {
	suffix := strings.TrimPrefix(commandName, "maestro.")
	return "maestro-" + strings.ReplaceAll(suffix, ".", "-")
}

func codexCommandNameFromPath(filePath string) (string, bool) {
	normalized := path.Clean(strings.ReplaceAll(filePath, "\\", "/"))
	if !strings.HasPrefix(normalized, "commands/maestro.") || !strings.HasSuffix(normalized, ".md") {
		return "", false
	}

	base := strings.TrimSuffix(path.Base(normalized), ".md")
	if base == "maestro" || !strings.HasPrefix(base, "maestro.") {
		return "", false
	}

	return base, true
}

func renderCodexCommandSkill(commandName string, commandContent []byte) string {
	skillName := CodexCommandSkillName(commandName)
	cliCommand := "maestro " + strings.ReplaceAll(strings.TrimPrefix(commandName, "maestro."), ".", " ")
	summary := extractCommandDescription(commandContent)
	if summary == "" {
		summary = "Follow the matching Maestro command markdown workflow."
	}

	return fmt.Sprintf(
		"---\n"+
			"name: %s\n"+
			"description: >\n"+
			"  Run the Maestro %q workflow command. Use when the user asks for %q, \"/%s\",\n"+
			"  \"$%s\", or the matching Maestro workflow. %s Do not call %q as a CLI subcommand.\n"+
			"---\n\n"+
			"# %s\n\n"+
			"Follow this workflow when the user asks for `%s`, `/%s`, `$%s`, or the matching Maestro action.\n\n"+
			"1. Treat any text after the command name as `$ARGUMENTS`.\n"+
			"2. Read the first available command file:\n"+
			"   - `.codex/commands/%s.md`\n"+
			"   - `.maestro/commands/%s.md`\n"+
			"   - `~/.codex/commands/%s.md`\n"+
			"3. Follow the command file exactly, substituting `$ARGUMENTS` wherever it appears.\n"+
			"4. Do not run `%s`; the Maestro binary only manages lifecycle commands like `init`, `update`, `doctor`, and `remove`.\n"+
			"5. If no command file is available, tell the user the Maestro command markdown is missing and stop.\n",
		skillName, commandName, commandName, commandName, skillName, summary, cliCommand, commandName, commandName, commandName, skillName, commandName, commandName, commandName, cliCommand)
}

func extractCommandDescription(content []byte) string {
	lines := strings.Split(string(content), "\n")
	if len(lines) < 3 || strings.TrimSpace(lines[0]) != "---" {
		return ""
	}

	for i := 1; i < len(lines); i++ {
		line := strings.TrimSpace(lines[i])
		if line == "---" {
			return ""
		}

		if strings.HasPrefix(line, "description: >") || strings.HasPrefix(line, "description: |") {
			return extractFoldedDescription(lines[i+1:])
		}

		if strings.HasPrefix(line, "description:") {
			value := strings.TrimSpace(strings.TrimPrefix(line, "description:"))
			return strings.Trim(value, `"'`)
		}
	}

	return ""
}

func extractFoldedDescription(lines []string) string {
	parts := []string{}
	for _, raw := range lines {
		if strings.TrimSpace(raw) == "---" {
			break
		}
		if raw != "" && raw[0] != ' ' && raw[0] != '\t' {
			break
		}

		part := strings.TrimSpace(raw)
		if part != "" {
			parts = append(parts, part)
		}
	}

	return strings.Join(parts, " ")
}
