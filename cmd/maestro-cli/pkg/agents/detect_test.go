package agents

import (
	"os"
	"path/filepath"
	"testing"
)

func TestKnownAgentDirs(t *testing.T) {
	got := KnownAgentDirs()
	want := []string{".opencode", ".claude", ".codex"}

	if len(got) != len(want) {
		t.Fatalf("KnownAgentDirs() length = %d, want %d (got %v)", len(got), len(want), got)
	}
	for i, dir := range want {
		if got[i] != dir {
			t.Errorf("KnownAgentDirs()[%d] = %q, want %q", i, got[i], dir)
		}
	}
}

func TestDetectInstalled_FindsCodex(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "maestro-detect-codex-")
	if err != nil {
		t.Fatalf("MkdirTemp failed: %v", err)
	}
	t.Cleanup(func() {
		_ = os.RemoveAll(tempDir)
	})

	if err := os.MkdirAll(filepath.Join(tempDir, ".codex"), 0o755); err != nil {
		t.Fatalf("MkdirAll .codex failed: %v", err)
	}

	installed := DetectInstalled(tempDir)

	found := false
	for _, dir := range installed {
		if dir == ".codex" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("DetectInstalled(%q) = %v, expected to include %q", tempDir, installed, ".codex")
	}
}

func TestDetectInstalled_EmptyDir(t *testing.T) {
	tempDir := t.TempDir()
	installed := DetectInstalled(tempDir)
	if len(installed) != 0 {
		t.Fatalf("DetectInstalled(empty) = %v, want []", installed)
	}
}

func TestDetectInstalled_AllAgents(t *testing.T) {
	tempDir := t.TempDir()
	for _, dir := range KnownAgentDirs() {
		if err := os.MkdirAll(filepath.Join(tempDir, dir), 0o755); err != nil {
			t.Fatalf("MkdirAll %s failed: %v", dir, err)
		}
	}

	installed := DetectInstalled(tempDir)
	if len(installed) != 3 {
		t.Fatalf("DetectInstalled = %v, want 3 entries", installed)
	}
	want := []string{".opencode", ".claude", ".codex"}
	for i, dir := range want {
		if installed[i] != dir {
			t.Errorf("installed[%d] = %q, want %q", i, installed[i], dir)
		}
	}
}
