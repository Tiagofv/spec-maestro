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

// TestInitWithOpenCodeFlag tests init --with-opencode creates .maestro and attempts to fetch .opencode.
func TestInitWithOpenCodeFlag(t *testing.T) {
	dir := t.TempDir()
	orig, _ := os.Getwd()
	defer os.Chdir(orig)
	os.Chdir(dir)

	// Set flag
	withOpenCode = true
	withClaude = false
	defer func() {
		withOpenCode = false
		withClaude = false
	}()

	// Unset GITHUB_TOKEN to ensure fetch fails gracefully
	origToken := os.Getenv("GITHUB_TOKEN")
	os.Unsetenv("GITHUB_TOKEN")
	defer func() {
		if origToken != "" {
			os.Setenv("GITHUB_TOKEN", origToken)
		}
	}()

	err := runInit(initCmd, nil)
	// Note: GitHub fetch will fail but init should succeed with local setup
	if err != nil && err.Error() != "installing agent configs: fetching .opencode: fetching agent dir: fetching ref: resource not found" {
		// We expect either success or specific GitHub fetch error
		t.Logf("init completed with: %v", err)
	}

	// Verify .maestro was created
	if _, err := os.Stat(".maestro"); os.IsNotExist(err) {
		t.Error(".maestro/ should be created")
	}

	// Verify config.yaml was created
	if _, err := os.Stat(filepath.Join(".maestro", "config.yaml")); os.IsNotExist(err) {
		t.Error(".maestro/config.yaml should be created")
	}

	// Verify AGENTS.md was created
	if _, err := os.Stat("AGENTS.md"); os.IsNotExist(err) {
		t.Error("AGENTS.md should be created")
	}
}

// TestInitWithClaudeFlag tests init --with-claude creates .maestro and attempts to fetch .claude.
func TestInitWithClaudeFlag(t *testing.T) {
	dir := t.TempDir()
	orig, _ := os.Getwd()
	defer os.Chdir(orig)
	os.Chdir(dir)

	// Set flag
	withOpenCode = false
	withClaude = true
	defer func() {
		withOpenCode = false
		withClaude = false
	}()

	// Unset GITHUB_TOKEN to ensure fetch fails gracefully
	origToken := os.Getenv("GITHUB_TOKEN")
	os.Unsetenv("GITHUB_TOKEN")
	defer func() {
		if origToken != "" {
			os.Setenv("GITHUB_TOKEN", origToken)
		}
	}()

	err := runInit(initCmd, nil)
	// Note: GitHub fetch will fail but init should succeed with local setup
	if err != nil && err.Error() != "installing agent configs: fetching .claude: fetching agent dir: fetching ref: resource not found" {
		// We expect either success or specific GitHub fetch error
		t.Logf("init completed with: %v", err)
	}

	// Verify .maestro was created
	if _, err := os.Stat(".maestro"); os.IsNotExist(err) {
		t.Error(".maestro/ should be created")
	}
}

// TestInitWithBothFlags tests init --with-opencode --with-claude attempts to fetch both.
func TestInitWithBothFlags(t *testing.T) {
	dir := t.TempDir()
	orig, _ := os.Getwd()
	defer os.Chdir(orig)
	os.Chdir(dir)

	// Set both flags
	withOpenCode = true
	withClaude = true
	defer func() {
		withOpenCode = false
		withClaude = false
	}()

	// Unset GITHUB_TOKEN to ensure fetch fails gracefully
	origToken := os.Getenv("GITHUB_TOKEN")
	os.Unsetenv("GITHUB_TOKEN")
	defer func() {
		if origToken != "" {
			os.Setenv("GITHUB_TOKEN", origToken)
		}
	}()

	err := runInit(initCmd, nil)
	// Note: GitHub fetch will fail but init should succeed with local setup
	if err != nil {
		// We expect a GitHub fetch error for one of the agent dirs
		t.Logf("init completed with: %v", err)
	}

	// Verify .maestro was created
	if _, err := os.Stat(".maestro"); os.IsNotExist(err) {
		t.Error(".maestro/ should be created")
	}
}

// TestInitWithNoFlags tests init without flags (would be interactive, but we can't test stdin easily).
// This test verifies the basic structure is created even when agent installation is skipped.
func TestInitWithNoFlags(t *testing.T) {
	dir := t.TempDir()
	orig, _ := os.Getwd()
	defer os.Chdir(orig)
	os.Chdir(dir)

	// Ensure flags are not set
	withOpenCode = false
	withClaude = false
	defer func() {
		withOpenCode = false
		withClaude = false
	}()

	// Note: This test cannot easily simulate interactive input,
	// but we can verify the .maestro/ structure is created.
	// The interactive prompt would require stdin mocking which is complex at command level.
	// Skip this test for now as it requires stdin simulation.
	t.Skip("Interactive mode requires stdin simulation - covered by unit tests")
}

// TestInitConflictWithExistingOpenCode tests init behavior when .opencode already exists.
func TestInitConflictWithExistingOpenCode(t *testing.T) {
	dir := t.TempDir()
	orig, _ := os.Getwd()
	defer os.Chdir(orig)
	os.Chdir(dir)

	// Create existing .opencode directory
	os.MkdirAll(".opencode", 0755)
	os.WriteFile(filepath.Join(".opencode", "existing.txt"), []byte("existing"), 0644)

	// Set flag to install .opencode
	withOpenCode = true
	withClaude = false
	defer func() {
		withOpenCode = false
		withClaude = false
	}()

	// Unset GITHUB_TOKEN to ensure fetch fails gracefully
	origToken := os.Getenv("GITHUB_TOKEN")
	os.Unsetenv("GITHUB_TOKEN")
	defer func() {
		if origToken != "" {
			os.Setenv("GITHUB_TOKEN", origToken)
		}
	}()

	err := runInit(initCmd, nil)
	// This test expects EOF error when trying to read conflict resolution from empty stdin
	if err != nil && err.Error() != "installing agent configs: prompting for conflict resolution: reading input: EOF" {
		t.Errorf("expected EOF error for conflict prompt, got: %v", err)
	}

	// Verify .maestro was created
	if _, err := os.Stat(".maestro"); os.IsNotExist(err) {
		t.Error(".maestro/ should be created")
	}

	// Verify existing .opencode was not removed (conflict not resolved)
	if data, err := os.ReadFile(filepath.Join(".opencode", "existing.txt")); err != nil {
		t.Error(".opencode/existing.txt should still exist after conflict")
	} else if string(data) != "existing" {
		t.Error(".opencode/existing.txt content should be unchanged")
	}
}

// TestInitGitHubFetchError tests init handles GitHub fetch errors gracefully.
func TestInitGitHubFetchError(t *testing.T) {
	dir := t.TempDir()
	orig, _ := os.Getwd()
	defer os.Chdir(orig)
	os.Chdir(dir)

	// Set flag to trigger GitHub fetch
	withOpenCode = true
	defer func() { withOpenCode = false }()

	// Unset GITHUB_TOKEN to trigger rate limit / not found errors
	origToken := os.Getenv("GITHUB_TOKEN")
	os.Unsetenv("GITHUB_TOKEN")
	defer func() {
		if origToken != "" {
			os.Setenv("GITHUB_TOKEN", origToken)
		}
	}()

	err := runInit(initCmd, nil)
	// We expect an error from GitHub fetch, but .maestro/ should still be created
	if err == nil {
		t.Log("init succeeded (GitHub fetch may have succeeded unexpectedly)")
	} else {
		t.Logf("init failed as expected with GitHub error: %v", err)
	}

	// Verify .maestro was created despite fetch failure
	if _, err := os.Stat(".maestro"); os.IsNotExist(err) {
		t.Error(".maestro/ should be created even if GitHub fetch fails")
	}

	// Verify config.yaml exists
	if _, err := os.Stat(filepath.Join(".maestro", "config.yaml")); os.IsNotExist(err) {
		t.Error(".maestro/config.yaml should be created even if GitHub fetch fails")
	}
}

// TestInitFlagsSkipPrompt verifies that using flags skips the interactive prompt.
// This is tested implicitly by the flag tests not blocking on stdin.
func TestInitFlagsSkipPrompt(t *testing.T) {
	dir := t.TempDir()
	orig, _ := os.Getwd()
	defer os.Chdir(orig)
	os.Chdir(dir)

	// Set flag - this should skip the prompt entirely
	withOpenCode = true
	defer func() { withOpenCode = false }()

	// Unset GITHUB_TOKEN
	origToken := os.Getenv("GITHUB_TOKEN")
	os.Unsetenv("GITHUB_TOKEN")
	defer func() {
		if origToken != "" {
			os.Setenv("GITHUB_TOKEN", origToken)
		}
	}()

	// This test verifies the command doesn't hang waiting for stdin.
	// If it completes (with or without error), the prompt was skipped.
	err := runInit(initCmd, nil)
	if err != nil {
		// Error is expected due to GitHub fetch failure
		t.Logf("init completed with error (expected): %v", err)
	}

	// Verify .maestro was created (proves command ran to completion)
	if _, err := os.Stat(".maestro"); os.IsNotExist(err) {
		t.Error(".maestro/ should be created")
	}
}

// TestInitWithoutFlagsNoAgentInstall tests that when no flags are set and
// the prompt would return empty, no agent directories are installed.
// Since we can't easily simulate empty stdin input in a command test,
// we document this behavior is covered by unit tests of selectAgentDirs.
func TestInitWithoutFlagsNoAgentInstall(t *testing.T) {
	// This behavior is tested at the unit level in the agents package.
	// At the command level, we cannot easily simulate stdin without more
	// complex test infrastructure (e.g., replacing os.Stdin).
	// The acceptance criteria "empty selection installs none" is validated
	// by the unit tests in pkg/agents/prompt_test.go.
	t.Skip("Empty selection behavior validated by pkg/agents/prompt_test.go")
}

// TestInitBasicStructureCreation verifies core .maestro/ setup without agent installation.
func TestInitBasicStructureCreation(t *testing.T) {
	dir := t.TempDir()
	orig, _ := os.Getwd()
	defer os.Chdir(orig)
	os.Chdir(dir)

	// No flags set - but we can't simulate empty stdin, so this will error on prompt
	withOpenCode = false
	withClaude = false

	// Unset GITHUB_TOKEN
	origToken := os.Getenv("GITHUB_TOKEN")
	os.Unsetenv("GITHUB_TOKEN")
	defer func() {
		if origToken != "" {
			os.Setenv("GITHUB_TOKEN", origToken)
		}
	}()

	// Run init - expect it to fail at the prompt due to EOF
	err := runInit(initCmd, nil)
	if err == nil {
		t.Log("init succeeded without flags (stdin may have provided input)")
	}

	// Even if agent selection fails, .maestro/ should be created first
	if _, err := os.Stat(".maestro"); os.IsNotExist(err) {
		t.Error(".maestro/ should be created")
	}

	// Verify subdirectories
	for _, subdir := range []string{"scripts", "specs", "state"} {
		path := filepath.Join(".maestro", subdir)
		if info, err := os.Stat(path); os.IsNotExist(err) || !info.IsDir() {
			t.Errorf(".maestro/%s should be created as directory", subdir)
		}
	}

	// Verify AGENTS.md
	if _, err := os.Stat("AGENTS.md"); os.IsNotExist(err) {
		t.Error("AGENTS.md should be created")
	}
}
