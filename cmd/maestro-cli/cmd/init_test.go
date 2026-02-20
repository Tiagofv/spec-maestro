package cmd

import (
	"bytes"
	"strings"
	"testing"
)

func TestSelectInitAgentDirs_WithOpenCodeFlag(t *testing.T) {
	selected, err := selectInitAgentDirs(true, false, strings.NewReader("\n"), &bytes.Buffer{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(selected) != 1 || selected[0] != ".opencode" {
		t.Fatalf("expected [.opencode], got %v", selected)
	}
}

func TestSelectInitAgentDirs_WithClaudeFlag(t *testing.T) {
	selected, err := selectInitAgentDirs(false, true, strings.NewReader("\n"), &bytes.Buffer{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(selected) != 1 || selected[0] != ".claude" {
		t.Fatalf("expected [.claude], got %v", selected)
	}
}

func TestSelectInitAgentDirs_WithBothFlags(t *testing.T) {
	selected, err := selectInitAgentDirs(true, true, strings.NewReader("\n"), &bytes.Buffer{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(selected) != 2 || selected[0] != ".opencode" || selected[1] != ".claude" {
		t.Fatalf("expected [.opencode .claude], got %v", selected)
	}
}

func TestSelectInitAgentDirs_NoFlagsPromptsForSelection(t *testing.T) {
	selected, err := selectInitAgentDirs(false, false, strings.NewReader("1 2\n"), &bytes.Buffer{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(selected) != 2 || selected[0] != ".opencode" || selected[1] != ".claude" {
		t.Fatalf("expected [.opencode .claude], got %v", selected)
	}
}
