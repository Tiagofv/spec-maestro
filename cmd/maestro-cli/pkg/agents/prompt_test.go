package agents

import (
	"bytes"
	"strings"
	"testing"
)

func TestPromptAgentSelection_SingleSelection(t *testing.T) {
	input := "1\n"
	r := strings.NewReader(input)
	w := &bytes.Buffer{}
	available := []string{".opencode", ".claude"}

	selected, err := PromptAgentSelection(r, w, available)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(selected) != 1 || selected[0] != ".opencode" {
		t.Errorf("expected [.opencode], got %v", selected)
	}
}

func TestPromptAgentSelection_MultipleSelection(t *testing.T) {
	input := "1 2\n"
	r := strings.NewReader(input)
	w := &bytes.Buffer{}
	available := []string{".opencode", ".claude"}

	selected, err := PromptAgentSelection(r, w, available)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(selected) != 2 {
		t.Fatalf("expected 2 selections, got %d", len(selected))
	}
	if selected[0] != ".opencode" || selected[1] != ".claude" {
		t.Errorf("expected [.opencode .claude], got %v", selected)
	}
}

func TestPromptAgentSelection_EmptyInput(t *testing.T) {
	input := "\n"
	r := strings.NewReader(input)
	w := &bytes.Buffer{}
	available := []string{".opencode", ".claude"}

	selected, err := PromptAgentSelection(r, w, available)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(selected) != 0 {
		t.Errorf("expected empty slice, got %v", selected)
	}
}

func TestPromptAgentSelection_EmptyAvailable(t *testing.T) {
	input := ""
	r := strings.NewReader(input)
	w := &bytes.Buffer{}
	available := []string{}

	selected, err := PromptAgentSelection(r, w, available)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(selected) != 0 {
		t.Errorf("expected empty slice, got %v", selected)
	}
}

func TestPromptAgentSelection_InvalidNumber(t *testing.T) {
	input := "5\n"
	r := strings.NewReader(input)
	w := &bytes.Buffer{}
	available := []string{".opencode", ".claude"}

	_, err := PromptAgentSelection(r, w, available)
	if err == nil {
		t.Error("expected error for out of range number")
	}
}

func TestPromptAgentSelection_DuplicateNumbers(t *testing.T) {
	input := "1 1 2\n"
	r := strings.NewReader(input)
	w := &bytes.Buffer{}
	available := []string{".opencode", ".claude"}

	selected, err := PromptAgentSelection(r, w, available)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Should only have 2 items despite duplicate "1"
	if len(selected) != 2 {
		t.Errorf("expected 2 unique selections, got %d", len(selected))
	}
}

func TestPromptConflictResolution_Overwrite(t *testing.T) {
	input := "o\n"
	r := strings.NewReader(input)
	w := &bytes.Buffer{}
	conflicting := []string{".opencode"}

	action, err := PromptConflictResolution(r, w, conflicting)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if action != ConflictOverwrite {
		t.Errorf("expected ConflictOverwrite, got %v", action)
	}
}

func TestPromptConflictResolution_Backup(t *testing.T) {
	input := "b\n"
	r := strings.NewReader(input)
	w := &bytes.Buffer{}
	conflicting := []string{".opencode", ".claude"}

	action, err := PromptConflictResolution(r, w, conflicting)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if action != ConflictBackup {
		t.Errorf("expected ConflictBackup, got %v", action)
	}
}

func TestPromptConflictResolution_Cancel(t *testing.T) {
	input := "c\n"
	r := strings.NewReader(input)
	w := &bytes.Buffer{}
	conflicting := []string{".opencode"}

	action, err := PromptConflictResolution(r, w, conflicting)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if action != ConflictCancel {
		t.Errorf("expected ConflictCancel, got %v", action)
	}
}

func TestPromptConflictResolution_DefaultCancel(t *testing.T) {
	input := "\n"
	r := strings.NewReader(input)
	w := &bytes.Buffer{}
	conflicting := []string{".opencode"}

	action, err := PromptConflictResolution(r, w, conflicting)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if action != ConflictCancel {
		t.Errorf("expected ConflictCancel (default), got %v", action)
	}
}

func TestPromptConflictResolution_EmptyConflicting(t *testing.T) {
	input := ""
	r := strings.NewReader(input)
	w := &bytes.Buffer{}
	conflicting := []string{}

	action, err := PromptConflictResolution(r, w, conflicting)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if action != ConflictCancel {
		t.Errorf("expected ConflictCancel for empty conflicting, got %v", action)
	}
}

func TestBackupPath(t *testing.T) {
	path := BackupPath(".opencode")
	if !strings.HasPrefix(path, ".opencode-backup-") {
		t.Errorf("expected prefix '.opencode-backup-', got %s", path)
	}
	if len(path) < len(".opencode-backup-20060102-150405") {
		t.Errorf("backup path too short: %s", path)
	}
}
