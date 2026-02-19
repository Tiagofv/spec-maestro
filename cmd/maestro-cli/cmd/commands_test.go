package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

// TestDoctorOnUninitializedProject tests doctor when .maestro/ doesn't exist.
func TestDoctorOnUninitializedProject(t *testing.T) {
	dir := t.TempDir()
	orig, _ := os.Getwd()
	defer os.Chdir(orig)
	os.Chdir(dir)

	err := runDoctor(doctorCmd, nil)
	if err == nil {
		t.Error("doctor should return error when .maestro/ not found")
	}
}

// TestDoctorOnInitializedProject tests doctor with a valid .maestro/ directory.
func TestDoctorOnInitializedProject(t *testing.T) {
	dir := t.TempDir()
	orig, _ := os.Getwd()
	defer os.Chdir(orig)
	os.Chdir(dir)

	// Set up minimal .maestro/ structure
	os.MkdirAll(filepath.Join(".maestro", "scripts"), 0755)
	os.MkdirAll(filepath.Join(".maestro", "specs"), 0755)
	os.MkdirAll(filepath.Join(".maestro", "state"), 0755)
	os.WriteFile(filepath.Join(".maestro", "config.yaml"), []byte("cli_version: v0.1.0\n"), 0644)

	err := runDoctor(doctorCmd, nil)
	if err != nil {
		t.Errorf("doctor should pass on valid project, got: %v", err)
	}
}

// TestRemoveNonExistent tests remove when .maestro/ doesn't exist.
func TestRemoveNonExistent(t *testing.T) {
	dir := t.TempDir()
	orig, _ := os.Getwd()
	defer os.Chdir(orig)
	os.Chdir(dir)

	err := runRemove(removeCmd, nil)
	if err != nil {
		t.Errorf("remove on non-existent .maestro/ should not error: %v", err)
	}
}

// TestRemoveWithForce tests remove --force removes .maestro/.
func TestRemoveWithForce(t *testing.T) {
	dir := t.TempDir()
	orig, _ := os.Getwd()
	defer os.Chdir(orig)
	os.Chdir(dir)

	// Create .maestro/
	os.MkdirAll(".maestro", 0755)
	os.WriteFile(filepath.Join(".maestro", "config.yaml"), []byte(""), 0644)

	// Force remove
	removeForce = true
	defer func() { removeForce = false }()

	err := runRemove(removeCmd, nil)
	if err != nil {
		t.Errorf("remove --force error: %v", err)
	}

	if _, err := os.Stat(".maestro"); !os.IsNotExist(err) {
		t.Error(".maestro/ should be removed")
	}
}
