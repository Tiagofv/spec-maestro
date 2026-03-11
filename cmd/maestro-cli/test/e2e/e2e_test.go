package e2e_test

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

var maestroBin string
var moduleRoot string
var repoRoot string

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
	moduleRoot, _ = filepath.Abs("../..")
	repoRoot, _ = filepath.Abs(filepath.Join(moduleRoot, "..", ".."))
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

func copyFile(t *testing.T, srcPath, dstPath string) {
	t.Helper()

	src, err := os.Open(srcPath)
	if err != nil {
		t.Fatalf("open source file %s: %v", srcPath, err)
	}
	defer src.Close()

	if err := os.MkdirAll(filepath.Dir(dstPath), 0755); err != nil {
		t.Fatalf("create destination dir %s: %v", filepath.Dir(dstPath), err)
	}

	dst, err := os.Create(dstPath)
	if err != nil {
		t.Fatalf("create destination file %s: %v", dstPath, err)
	}
	defer dst.Close()

	if _, err := io.Copy(dst, src); err != nil {
		t.Fatalf("copy %s to %s: %v", srcPath, dstPath, err)
	}
}

func copyFixtureDir(t *testing.T, srcDir, dstDir string) {
	t.Helper()

	entries, err := os.ReadDir(srcDir)
	if err != nil {
		t.Fatalf("read fixture dir %s: %v", srcDir, err)
	}

	for _, entry := range entries {
		srcPath := filepath.Join(srcDir, entry.Name())
		dstPath := filepath.Join(dstDir, entry.Name())
		if entry.IsDir() {
			copyFixtureDir(t, srcPath, dstPath)
			continue
		}
		copyFile(t, srcPath, dstPath)
	}
}

func runCheckPrerequisitesPlan(t *testing.T, worktree, featureDir string) (string, error) {
	t.Helper()

	scriptPath := filepath.Join(repoRoot, ".maestro", "scripts", "check-prerequisites.sh")
	cmd := exec.Command("bash", scriptPath, "plan", featureDir)
	cmd.Dir = worktree
	cmd.Env = append(os.Environ(), "MAESTRO_MAIN_REPO="+worktree)
	out, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

func seedFeatureWithResearchFixture(t *testing.T, fixtureName string) (string, string) {
	t.Helper()

	worktree := t.TempDir()
	featureID := "fixture-feature"
	featureDir := filepath.Join(worktree, ".maestro", "specs", featureID)
	researchDir := filepath.Join(featureDir, "research")
	stateDir := filepath.Join(worktree, ".maestro", "state")

	if err := os.MkdirAll(researchDir, 0755); err != nil {
		t.Fatalf("create research dir: %v", err)
	}
	if err := os.MkdirAll(stateDir, 0755); err != nil {
		t.Fatalf("create state dir: %v", err)
	}

	if err := os.WriteFile(filepath.Join(featureDir, "spec.md"), []byte("# Spec\n"), 0644); err != nil {
		t.Fatalf("write spec.md: %v", err)
	}

	fixtureDir := filepath.Join(moduleRoot, "test", "fixtures", "research", fixtureName)
	copyFixtureDir(t, fixtureDir, researchDir)

	state := fmt.Sprintf(`{
  "feature_id": "%s",
  "research_ready": true,
  "research_path": ".maestro/specs/%s/research",
  "research_artifacts": [
    ".maestro/specs/%s/research/technology-options.md",
    ".maestro/specs/%s/research/pattern-catalog.md",
    ".maestro/specs/%s/research/pitfall-register.md",
    ".maestro/specs/%s/research/competitive-analysis.md",
    ".maestro/specs/%s/research/synthesis.md"
  ]
}`,
		featureID, featureID, featureID, featureID, featureID, featureID, featureID,
	)

	if err := os.WriteFile(filepath.Join(stateDir, featureID+".json"), []byte(state), 0644); err != nil {
		t.Fatalf("write state file: %v", err)
	}

	return worktree, featureDir
}

func TestPlanReadinessWithCompleteResearchArtifacts(t *testing.T) {
	worktree, featureDir := seedFeatureWithResearchFixture(t, "complete")

	out, err := runCheckPrerequisitesPlan(t, worktree, featureDir)
	if err != nil {
		t.Fatalf("plan prerequisites should pass for complete research artifacts, got error %v: %s", err, out)
	}
	if !strings.Contains(out, `"ok":true`) {
		t.Fatalf("expected ok true output, got %s", out)
	}
}

func TestPlanReadinessFailsForPartialResearchArtifacts(t *testing.T) {
	worktree, featureDir := seedFeatureWithResearchFixture(t, "partial")

	out, err := runCheckPrerequisitesPlan(t, worktree, featureDir)
	if err == nil {
		t.Fatalf("plan prerequisites should fail for partial research artifacts, got success output: %s", out)
	}
	if !strings.Contains(out, "required artifacts are missing") {
		t.Fatalf("expected missing required artifacts error, got %s", out)
	}
}

func TestPlanReadinessAllowsLegacyStateWithoutResearchFields(t *testing.T) {
	worktree := t.TempDir()
	featureID := "legacy-feature"
	featureDir := filepath.Join(worktree, ".maestro", "specs", featureID)
	stateDir := filepath.Join(worktree, ".maestro", "state")

	if err := os.MkdirAll(featureDir, 0755); err != nil {
		t.Fatalf("create feature dir: %v", err)
	}
	if err := os.MkdirAll(stateDir, 0755); err != nil {
		t.Fatalf("create state dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(featureDir, "spec.md"), []byte("# Legacy Spec\n"), 0644); err != nil {
		t.Fatalf("write spec.md: %v", err)
	}

	legacyState := `{
  "feature_id": "legacy-feature",
  "stage": "specify",
  "spec_path": ".maestro/specs/legacy-feature/spec.md"
}`
	if err := os.WriteFile(filepath.Join(stateDir, featureID+".json"), []byte(legacyState), 0644); err != nil {
		t.Fatalf("write legacy state: %v", err)
	}

	out, err := runCheckPrerequisitesPlan(t, worktree, featureDir)
	if err != nil {
		t.Fatalf("plan prerequisites should preserve legacy behavior, got %v: %s", err, out)
	}
	if !strings.Contains(out, `"ok":true`) {
		t.Fatalf("expected ok true output, got %s", out)
	}
}

func TestPlanCommandContractRetainsExactBypassPhrase(t *testing.T) {
	planCommandPath := filepath.Join(repoRoot, ".maestro", "commands", "maestro.plan.md")
	content, err := os.ReadFile(planCommandPath)
	if err != nil {
		t.Fatalf("read plan command contract: %v", err)
	}

	bypassPhrase := "I acknowledge proceeding without complete research"
	if !strings.Contains(string(content), bypassPhrase) {
		t.Fatalf("plan command must include exact bypass phrase %q", bypassPhrase)
	}
}
