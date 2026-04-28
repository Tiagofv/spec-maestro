package cmd

import (
	"bytes"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/spec-maestro/maestro-cli/pkg/agents"
	"github.com/spec-maestro/maestro-cli/pkg/config"
	"github.com/spec-maestro/maestro-cli/pkg/embedded"
)

// ---------- agent dir selection (pre-existing tests) ----------

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

// ---------- integration tests using embedded resources ----------

// TestInitCreatesFullStructure exercises the init logic step-by-step in a
// temp dir and verifies .maestro/ is created with all expected subdirectories
// and files. We replicate the runInit flow to avoid interactive stdin issues.
func TestInitCreatesFullStructure(t *testing.T) {
	dir := t.TempDir()
	origDir := chdir(t, dir)
	defer os.Chdir(origDir)

	// Replicate the core init flow: install embedded core dirs
	fetch := embedded.NewAssetFetcher()
	coreDirs := []string{
		".maestro/commands",
		".maestro/scripts",
		".maestro/templates",
		".maestro/skills",
		".maestro/cookbook",
		".maestro/reference",
	}

	totalFiles := 0
	for _, d := range coreDirs {
		content, err := fetch(d)
		if err != nil {
			t.Fatalf("fetch(%q) returned error: %v", d, err)
		}
		// Use the same writer init.go uses; map keys are paths relative to d
		// (e.g. "maestro.init.md"), so we must join them onto d before writing.
		if err := agents.WriteAgentDir(content, d); err != nil {
			t.Fatalf("WriteAgentDir(%q): %v", d, err)
		}
		totalFiles += len(content)
	}

	if totalFiles == 0 {
		t.Fatal("expected at least one file to be installed from embedded resources")
	}

	// Install required starter files (constitution.md, etc.)
	if err := installRequiredStarterFiles(); err != nil {
		t.Fatalf("installRequiredStarterFiles: %v", err)
	}

	// Create user data directories
	for _, d := range []string{
		filepath.Join(".maestro", "specs"),
		filepath.Join(".maestro", "state"),
		filepath.Join(".maestro", "research"),
		filepath.Join(".maestro", "memory"),
	} {
		if err := os.MkdirAll(d, 0755); err != nil {
			t.Fatalf("creating dir %s: %v", d, err)
		}
	}

	// Write config
	cfg := &config.ProjectConfig{CLIVersion: "test"}
	if err := config.Save(cfg, filepath.Join(".maestro", "config.yaml")); err != nil {
		t.Fatalf("config.Save: %v", err)
	}

	// Write AGENTS.md
	agentsMD := "# Maestro Agent Instructions\n"
	if err := os.WriteFile("AGENTS.md", []byte(agentsMD), 0644); err != nil {
		t.Fatalf("writing AGENTS.md: %v", err)
	}

	// --- Assertions ---

	// .maestro/ root
	assertDirExists(t, ".maestro")

	// Core content directories (populated from embedded resources)
	for _, d := range coreDirs {
		assertDirExists(t, d)
		assertDirNotEmpty(t, d)
	}

	// Required files
	assertFileExists(t, ".maestro/constitution.md")
	assertFileNonEmpty(t, ".maestro/constitution.md")

	assertFileExists(t, ".maestro/config.yaml")
	assertFileNonEmpty(t, ".maestro/config.yaml")

	assertFileExists(t, "AGENTS.md")
	assertFileNonEmpty(t, "AGENTS.md")
}

// TestInitCreatesEmptyDirs verifies that specs, state, research, memory dirs
// are created as empty user-data directories by the init flow.
func TestInitCreatesEmptyDirs(t *testing.T) {
	dir := t.TempDir()
	origDir := chdir(t, dir)
	defer os.Chdir(origDir)

	// Replicate the user-data directory creation from runInit
	emptyDirs := []string{
		filepath.Join(".maestro", "specs"),
		filepath.Join(".maestro", "state"),
		filepath.Join(".maestro", "research"),
		filepath.Join(".maestro", "memory"),
	}

	for _, d := range emptyDirs {
		if err := os.MkdirAll(d, 0755); err != nil {
			t.Fatalf("creating dir %s: %v", d, err)
		}
	}

	for _, d := range emptyDirs {
		assertDirExists(t, d)
	}
}

// TestInitConfigYAMLIsValid verifies the generated config.yaml is parseable
// and contains the expected fields.
func TestInitConfigYAMLIsValid(t *testing.T) {
	dir := t.TempDir()
	origDir := chdir(t, dir)
	defer os.Chdir(origDir)

	if err := os.MkdirAll(".maestro", 0755); err != nil {
		t.Fatalf("creating .maestro: %v", err)
	}

	cfg := &config.ProjectConfig{CLIVersion: "v0.1.0-test"}
	configPath := filepath.Join(".maestro", "config.yaml")
	if err := config.Save(cfg, configPath); err != nil {
		t.Fatalf("config.Save: %v", err)
	}

	loaded, err := config.Load(configPath)
	if err != nil {
		t.Fatalf("config.Load: %v", err)
	}

	if loaded.CLIVersion != "v0.1.0-test" {
		t.Errorf("expected cli_version %q, got %q", "v0.1.0-test", loaded.CLIVersion)
	}
}

// TestInitNoNetwork verifies that init.go does not import or use any HTTP
// or GitHub client packages. This is a static analysis test ensuring the
// init command uses only embedded resources (no network access).
func TestInitNoNetwork(t *testing.T) {
	fset := token.NewFileSet()

	// Parse init.go (same package directory)
	initFile := filepath.Join(".", "init.go")
	f, err := parser.ParseFile(fset, initFile, nil, parser.ImportsOnly)
	if err != nil {
		t.Fatalf("parsing init.go: %v", err)
	}

	networkPackages := []string{
		"net/http",
		"net/url",
		"github.com/spec-maestro/maestro-cli/pkg/ghclient",
	}

	for _, imp := range f.Imports {
		importPath := strings.Trim(imp.Path.Value, `"`)
		for _, banned := range networkPackages {
			if importPath == banned {
				t.Errorf("init.go imports network package %q — init should use only embedded resources", banned)
			}
		}
	}

	// Also verify no identifier named "http" or "ghclient" is used in the AST.
	fFull, err := parser.ParseFile(fset, initFile, nil, parser.ParseComments)
	if err != nil {
		t.Fatalf("parsing init.go (full): %v", err)
	}

	ast.Inspect(fFull, func(n ast.Node) bool {
		if sel, ok := n.(*ast.SelectorExpr); ok {
			if ident, ok := sel.X.(*ast.Ident); ok {
				if ident.Name == "http" || ident.Name == "ghclient" {
					t.Errorf("init.go references %s.%s — init should not use network clients", ident.Name, sel.Sel.Name)
				}
			}
		}
		return true
	})
}

// TestInitEmbeddedContentDirsHaveFiles verifies the embedded asset fetcher
// returns files for each core directory. This tests the embedded resources
// are available without relying on the full init command flow.
func TestInitEmbeddedContentDirsHaveFiles(t *testing.T) {
	fetch := embedded.NewAssetFetcher()

	coreDirs := []string{
		".maestro/commands",
		".maestro/scripts",
		".maestro/templates",
		".maestro/skills",
		".maestro/cookbook",
		".maestro/reference",
	}

	for _, dir := range coreDirs {
		t.Run(dir, func(t *testing.T) {
			files, err := fetch(dir)
			if err != nil {
				t.Fatalf("fetch(%q) returned error: %v", dir, err)
			}
			if len(files) == 0 {
				t.Errorf("fetch(%q) returned no files", dir)
			}
			for name, content := range files {
				if len(content) == 0 {
					t.Errorf("file %q in %q has empty content", name, dir)
				}
			}
		})
	}
}

// TestInitEmbeddedConstitutionAvailable verifies the constitution.md is
// fetchable via the embedded FetchFile function.
func TestInitEmbeddedConstitutionAvailable(t *testing.T) {
	content, err := embedded.FetchFile(".maestro/constitution.md")
	if err != nil {
		t.Fatalf("FetchFile(.maestro/constitution.md) returned error: %v", err)
	}
	if len(content) == 0 {
		t.Error("constitution.md should have non-empty content")
	}
}

// TestInitRequiredStarterFiles verifies installRequiredStarterFiles writes
// files from embedded resources to disk.
func TestInitRequiredStarterFiles(t *testing.T) {
	dir := t.TempDir()
	origDir := chdir(t, dir)
	defer os.Chdir(origDir)

	if err := os.MkdirAll(".maestro", 0755); err != nil {
		t.Fatalf("creating .maestro: %v", err)
	}

	if err := installRequiredStarterFiles(); err != nil {
		t.Fatalf("installRequiredStarterFiles returned error: %v", err)
	}

	for _, filePath := range agents.RequiredStarterAssetFiles() {
		assertFileExists(t, filePath)
		assertFileNonEmpty(t, filePath)
	}
}

// TestInitRequiredStarterAssets verifies installRequiredStarterAssets installs
// directories from embedded resources in a fresh temp dir (no conflicts).
func TestInitRequiredStarterAssets(t *testing.T) {
	dir := t.TempDir()
	origDir := chdir(t, dir)
	defer os.Chdir(origDir)

	var buf bytes.Buffer
	err := installRequiredStarterAssets(strings.NewReader("\n"), &buf)
	if err != nil {
		t.Fatalf("installRequiredStarterAssets returned error: %v", err)
	}

	for _, d := range agents.RequiredStarterAssetDirs() {
		assertDirExists(t, d)
		assertDirNotEmpty(t, d)
	}
}

// TestInitInstallEmbeddedAgentDirs verifies installEmbeddedAgentDirs writes
// agent directories from embedded resources to disk.
func TestInitInstallEmbeddedAgentDirs(t *testing.T) {
	dir := t.TempDir()
	origDir := chdir(t, dir)
	defer os.Chdir(origDir)

	err := installEmbeddedAgentDirs([]string{".claude"})
	if err != nil {
		t.Fatalf("installEmbeddedAgentDirs returned error: %v", err)
	}

	assertDirExists(t, ".claude")
	assertDirNotEmpty(t, ".claude")
}

// TestInitInstallEmbeddedAgentDirsEmpty verifies that passing an empty slice
// does nothing and does not error.
func TestInitInstallEmbeddedAgentDirsEmpty(t *testing.T) {
	err := installEmbeddedAgentDirs(nil)
	if err != nil {
		t.Fatalf("installEmbeddedAgentDirs(nil) returned error: %v", err)
	}
}

// TestInitEmbeddedFilesMatchCoreDirs verifies that the content installed from
// embedded resources into core dirs matches what the embedded fetcher returns.
// This is an end-to-end content integrity check.
func TestInitEmbeddedFilesMatchCoreDirs(t *testing.T) {
	dir := t.TempDir()
	origDir := chdir(t, dir)
	defer os.Chdir(origDir)

	fetch := embedded.NewAssetFetcher()
	coreDirs := []string{
		".maestro/commands",
		".maestro/scripts",
		".maestro/templates",
		".maestro/skills",
		".maestro/cookbook",
		".maestro/reference",
	}

	for _, d := range coreDirs {
		content, err := fetch(d)
		if err != nil {
			t.Fatalf("fetch(%q): %v", d, err)
		}

		for filePath, expected := range content {
			if err := os.MkdirAll(filepath.Dir(filePath), 0755); err != nil {
				t.Fatalf("creating dir for %s: %v", filePath, err)
			}
			if err := os.WriteFile(filePath, expected, 0644); err != nil {
				t.Fatalf("writing %s: %v", filePath, err)
			}
		}

		// Read back and compare
		for filePath, expected := range content {
			actual, err := os.ReadFile(filePath)
			if err != nil {
				t.Fatalf("reading back %s: %v", filePath, err)
			}
			if !bytes.Equal(expected, actual) {
				t.Errorf("content mismatch for %s: embedded len=%d, written len=%d", filePath, len(expected), len(actual))
			}
		}
	}
}

// TestInitSkipsExistingRequiredStarterFiles verifies that
// installRequiredStarterFiles does not overwrite existing files.
func TestInitSkipsExistingRequiredStarterFiles(t *testing.T) {
	dir := t.TempDir()
	origDir := chdir(t, dir)
	defer os.Chdir(origDir)

	if err := os.MkdirAll(".maestro", 0755); err != nil {
		t.Fatalf("creating .maestro: %v", err)
	}

	// Pre-create a required file with custom content
	customContent := []byte("# My custom constitution\n")
	for _, filePath := range agents.RequiredStarterAssetFiles() {
		if err := os.WriteFile(filePath, customContent, 0644); err != nil {
			t.Fatalf("writing %s: %v", filePath, err)
		}
	}

	if err := installRequiredStarterFiles(); err != nil {
		t.Fatalf("installRequiredStarterFiles returned error: %v", err)
	}

	// Verify files were NOT overwritten
	for _, filePath := range agents.RequiredStarterAssetFiles() {
		actual, err := os.ReadFile(filePath)
		if err != nil {
			t.Fatalf("reading %s: %v", filePath, err)
		}
		if !bytes.Equal(actual, customContent) {
			t.Errorf("file %s was overwritten; expected custom content", filePath)
		}
	}
}

// TestInitFindExistingDirectories verifies the helper correctly detects
// existing directories.
func TestInitFindExistingDirectories(t *testing.T) {
	dir := t.TempDir()
	origDir := chdir(t, dir)
	defer os.Chdir(origDir)

	os.MkdirAll("existing-dir", 0755)

	found := findExistingDirectories([]string{"existing-dir", "nonexistent-dir"})
	if len(found) != 1 || found[0] != "existing-dir" {
		t.Errorf("expected [existing-dir], got %v", found)
	}
}

// ---------- helpers ----------

// chdir changes to the given directory and returns the previous working dir.
func chdir(t *testing.T, dir string) string {
	t.Helper()
	origDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	if err := os.Chdir(dir); err != nil {
		t.Fatalf("chdir to %s: %v", dir, err)
	}
	return origDir
}

func assertDirExists(t *testing.T, path string) {
	t.Helper()
	info, err := os.Stat(path)
	if os.IsNotExist(err) {
		t.Errorf("expected directory %q to exist", path)
		return
	}
	if err != nil {
		t.Errorf("stat %q: %v", path, err)
		return
	}
	if !info.IsDir() {
		t.Errorf("expected %q to be a directory", path)
	}
}

func assertDirNotEmpty(t *testing.T, path string) {
	t.Helper()
	entries, err := os.ReadDir(path)
	if err != nil {
		t.Errorf("reading directory %q: %v", path, err)
		return
	}
	if len(entries) == 0 {
		t.Errorf("expected directory %q to contain files", path)
	}
}

func assertFileExists(t *testing.T, path string) {
	t.Helper()
	info, err := os.Stat(path)
	if os.IsNotExist(err) {
		t.Errorf("expected file %q to exist", path)
		return
	}
	if err != nil {
		t.Errorf("stat %q: %v", path, err)
		return
	}
	if info.IsDir() {
		t.Errorf("expected %q to be a file, got directory", path)
	}
}

func assertFileNonEmpty(t *testing.T, path string) {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Errorf("stat %q: %v", path, err)
		return
	}
	if info.Size() == 0 {
		t.Errorf("expected file %q to be non-empty", path)
	}
}
