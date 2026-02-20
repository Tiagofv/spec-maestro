package agents

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestInstallRequiredAssets_Success(t *testing.T) {
	root := t.TempDir()
	required := []string{
		filepath.Join(root, ".maestro", "scripts"),
		filepath.Join(root, ".maestro", "skills"),
		filepath.Join(root, ".maestro", "templates"),
	}

	fetch := func(dir string) (map[string][]byte, error) {
		return map[string][]byte{
			"README.md": []byte("installed: " + dir),
		}, nil
	}

	result, err := InstallRequiredAssets(required, ConflictOverwrite, fetch)
	if err != nil {
		t.Fatalf("InstallRequiredAssets failed: %v", err)
	}

	if len(result.Installed) != 3 {
		t.Fatalf("expected 3 installed directories, got %d", len(result.Installed))
	}

	for _, dir := range required {
		data, err := os.ReadFile(filepath.Join(dir, "README.md"))
		if err != nil {
			t.Fatalf("reading installed file from %s: %v", dir, err)
		}
		if !strings.Contains(string(data), "installed") {
			t.Fatalf("unexpected file content in %s: %q", dir, string(data))
		}
	}
}

func TestInstallRequiredAssets_FetchFailureNoWrites(t *testing.T) {
	root := t.TempDir()
	required := []string{
		filepath.Join(root, ".maestro", "scripts"),
		filepath.Join(root, ".maestro", "skills"),
		filepath.Join(root, ".maestro", "templates"),
	}

	fetch := func(dir string) (map[string][]byte, error) {
		if strings.HasSuffix(dir, "skills") {
			return nil, fmt.Errorf("network failure")
		}
		return map[string][]byte{"ok.txt": []byte("ok")}, nil
	}

	_, err := InstallRequiredAssets(required, ConflictOverwrite, fetch)
	if err == nil {
		t.Fatal("expected fetch failure")
	}

	for _, dir := range required {
		if _, statErr := os.Stat(dir); !os.IsNotExist(statErr) {
			t.Fatalf("expected no writes for %s, stat err: %v", dir, statErr)
		}
	}
}

func TestInstallRequiredAssets_WriteFailureRollsBack(t *testing.T) {
	root := t.TempDir()
	required := []string{
		filepath.Join(root, ".maestro", "scripts"),
		filepath.Join(root, ".maestro", "skills"),
		filepath.Join(root, ".maestro", "templates"),
	}

	fetch := func(dir string) (map[string][]byte, error) {
		if strings.HasSuffix(dir, "skills") {
			return map[string][]byte{"../bad.txt": []byte("bad")}, nil
		}
		return map[string][]byte{"ok.txt": []byte("ok")}, nil
	}

	_, err := InstallRequiredAssets(required, ConflictOverwrite, fetch)
	if err == nil {
		t.Fatal("expected write failure")
	}

	for _, dir := range required {
		if _, statErr := os.Stat(dir); !os.IsNotExist(statErr) {
			t.Fatalf("expected rollback for %s, stat err: %v", dir, statErr)
		}
	}
}
