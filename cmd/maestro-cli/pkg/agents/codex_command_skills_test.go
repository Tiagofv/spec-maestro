package agents

import (
	"strings"
	"testing"
)

func TestAddCodexCommandSkillsGeneratesSkillWrapper(t *testing.T) {
	content := map[string][]byte{
		"commands/maestro.list.md": []byte(`---
description: >
  List active features with status and suggested actions.
  Shows a dashboard of in-flight features.
argument-hint: [--all]
---

# maestro.list
`),
	}

	got := AddCodexCommandSkills(content)
	skill, ok := got["skills/maestro-list/SKILL.md"]
	if !ok {
		t.Fatalf("expected generated maestro-list skill; got keys %v", mapKeysForTest(got))
	}

	text := string(skill)
	for _, want := range []string{
		"name: maestro-list",
		"`maestro.list`",
		"`/maestro.list`",
		"`$maestro-list`",
		"List active features with status and suggested actions. Shows a dashboard of in-flight features.",
		"`.codex/commands/maestro.list.md`",
		"`.maestro/commands/maestro.list.md`",
		"`~/.codex/commands/maestro.list.md`",
		"Do not run `maestro list`",
	} {
		if !strings.Contains(text, want) {
			t.Fatalf("generated skill missing %q:\n%s", want, text)
		}
	}
}

func TestAddCodexCommandSkillsGeneratesNestedCommandSkillName(t *testing.T) {
	content := map[string][]byte{
		"commands/maestro.research.list.md": []byte("---\ndescription: Search research\n---\n"),
	}

	got := AddCodexCommandSkills(content)
	if _, ok := got["skills/maestro-research-list/SKILL.md"]; !ok {
		t.Fatalf("expected nested command skill; got keys %v", mapKeysForTest(got))
	}
}

func TestAddCodexCommandSkillsDoesNotOverwriteExistingSkill(t *testing.T) {
	existing := []byte("custom skill")
	content := map[string][]byte{
		"commands/maestro.list.md":          []byte("---\ndescription: List\n---\n"),
		"skills/maestro-list/SKILL.md":      existing,
		"commands/not-a-maestro-command.md": []byte("ignored"),
	}

	got := AddCodexCommandSkills(content)
	if string(got["skills/maestro-list/SKILL.md"]) != string(existing) {
		t.Fatalf("expected existing skill to be preserved")
	}
	if _, ok := got["skills/not-a-maestro-command/SKILL.md"]; ok {
		t.Fatalf("unexpected skill generated for non-Maestro command")
	}
}

func TestAddCodexCommandSkillsDoesNotMutateInput(t *testing.T) {
	content := map[string][]byte{
		"commands/maestro.list.md": []byte("---\ndescription: List\n---\n"),
	}

	_ = AddCodexCommandSkills(content)
	if _, ok := content["skills/maestro-list/SKILL.md"]; ok {
		t.Fatalf("input map was mutated")
	}
}

func mapKeysForTest(m map[string][]byte) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	return keys
}
