package e2e_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

var maestroBin string

func TestMain(m *testing.M) {
	// Build the binary for testing
	dir, err := os.MkdirTemp("", "maestro-e2e-*")
	if err != nil {
		panic(err)
	}

	ext := ""
	if runtime.GOOS == "windows" {
		ext = ".exe"
	}
	maestroBin = filepath.Join(dir, "maestro"+ext)

	// Build from module root
	moduleRoot, _ := filepath.Abs("../..")
	cmd := exec.Command("go", "build", "-o", maestroBin, ".")
	cmd.Dir = moduleRoot
	if out, err := cmd.CombinedOutput(); err != nil {
		panic("build failed: " + string(out))
	}

	code := m.Run()
	os.RemoveAll(dir)
	os.Exit(code)
}

func run(t *testing.T, args ...string) (string, int) {
	t.Helper()
	cmd := exec.Command(maestroBin, args...)
	out, err := cmd.CombinedOutput()
	code := 0
	if exitErr, ok := err.(*exec.ExitError); ok {
		code = exitErr.ExitCode()
	}
	return string(out), code
}

func TestVersion(t *testing.T) {
	out, code := run(t, "--version")
	if code != 0 {
		t.Fatalf("--version exited with code %d: %s", code, out)
	}
	if !strings.Contains(out, "maestro") {
		t.Errorf("--version output %q does not contain 'maestro'", out)
	}
}

func TestHelp(t *testing.T) {
	out, code := run(t, "--help")
	if code != 0 {
		t.Fatalf("--help exited with code %d: %s", code, out)
	}
	for _, cmd := range []string{"init", "update", "doctor", "remove", "completion"} {
		if !strings.Contains(out, cmd) {
			t.Errorf("--help output missing command: %s", cmd)
		}
	}
}

func TestDoctorOnEmptyDir(t *testing.T) {
	dir := t.TempDir()
	cmd := exec.Command(maestroBin, "doctor")
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err == nil {
		t.Errorf("doctor should fail in empty directory, got: %s", out)
	}
}

func TestFullWorkflow(t *testing.T) {
	dir := t.TempDir()
	orig, _ := os.Getwd()
	defer os.Chdir(orig)
	os.Chdir(dir)

	// Create minimal .maestro/ structure (simulating offline init)
	for _, sub := range []string{".maestro/scripts", ".maestro/specs", ".maestro/state"} {
		os.MkdirAll(sub, 0755)
	}
	os.WriteFile(".maestro/config.yaml", []byte("cli_version: v0.1.0\n"), 0644)

	// Test doctor passes
	cmd := exec.Command(maestroBin, "doctor")
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("doctor should pass, got error %v: %s", err, out)
	}

	// Test remove --force
	cmd = exec.Command(maestroBin, "remove", "--force")
	cmd.Dir = dir
	out, err = cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("remove --force should pass, got error %v: %s", err, out)
	}

	// Verify .maestro/ is gone
	if _, err := os.Stat(filepath.Join(dir, ".maestro")); !os.IsNotExist(err) {
		t.Error(".maestro/ should be removed after 'remove --force'")
	}
}

func TestCompletionBash(t *testing.T) {
	out, code := run(t, "completion", "bash")
	if code != 0 {
		t.Fatalf("completion bash exited with code %d: %s", code, out)
	}
	if !strings.Contains(out, "maestro") {
		t.Errorf("completion bash output missing 'maestro'")
	}
}
