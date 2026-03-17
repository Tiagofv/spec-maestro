package cmd

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/spec-maestro/maestro-cli/internal/version"
	"github.com/spec-maestro/maestro-cli/pkg/agents"
	"github.com/spec-maestro/maestro-cli/pkg/config"
	"github.com/spec-maestro/maestro-cli/pkg/embedded"
)

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize maestro in the current project",
	Long:  "Installs maestro files into .maestro/ in the current directory from embedded resources.",
	RunE:  runInit,
}

var (
	initWithOpenCode bool
	initWithClaude   bool
)

func init() {
	rootCmd.AddCommand(initCmd)
	initCmd.Flags().BoolVar(&initWithOpenCode, "with-opencode", false, "Install .opencode agent config directory")
	initCmd.Flags().BoolVar(&initWithClaude, "with-claude", false, "Install .claude agent config directory")
}

func runInit(cmd *cobra.Command, args []string) error {
	maestroDir := ".maestro"

	fmt.Printf("Installing maestro %s resources...\n", version.Version)

	// Check if already initialized
	if _, err := os.Stat(maestroDir); err == nil {
		fmt.Println(".maestro/ already exists. What would you like to do?")
		fmt.Println("  [o] Overwrite existing files")
		fmt.Println("  [b] Backup existing and reinitialize")
		fmt.Println("  [c] Cancel (default)")
		fmt.Print("Choice [o/b/c]: ")

		reader := bufio.NewReader(os.Stdin)
		choice, err := reader.ReadString('\n')
		if err != nil {
			return fmt.Errorf("reading input: %w", err)
		}
		choice = strings.TrimSpace(strings.ToLower(choice))

		switch choice {
		case "o":
			fmt.Println("Overwriting existing .maestro/...")
		case "b":
			backup := fmt.Sprintf(".maestro-backup-%s", time.Now().Format("20060102-150405"))
			if err := os.Rename(maestroDir, backup); err != nil {
				return fmt.Errorf("creating backup: %w", err)
			}
			fmt.Printf("Backup created: %s\n", backup)
		default:
			fmt.Println("Aborted.")
			return nil
		}
	}

	// Install .maestro/ core directories from embedded resources
	// Uses the transactional installer with conflict handling
	if err := installRequiredStarterAssets(os.Stdin, os.Stdout); err != nil {
		return fmt.Errorf("installing required starter assets: %w", err)
	}

	// Install required root files (constitution.md, etc.)
	if err := installRequiredStarterFiles(); err != nil {
		return fmt.Errorf("installing required starter files: %w", err)
	}

	// Create user data directories (empty — not fetched from embedded)
	for _, dir := range []string{
		filepath.Join(maestroDir, "specs"),
		filepath.Join(maestroDir, "state"),
		filepath.Join(maestroDir, "research"),
		filepath.Join(maestroDir, "memory"),
	} {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("creating directory %s: %w", dir, err)
		}
	}

	// Write config
	cfg := &config.ProjectConfig{
		CLIVersion:    version.Version,
		InitializedAt: time.Now(),
	}
	if err := config.Save(cfg, filepath.Join(maestroDir, "config.yaml")); err != nil {
		return fmt.Errorf("saving config: %w", err)
	}

	// Generate AGENTS.md (basic version)
	agentsMD := "# Maestro Agent Instructions\n\nRun `maestro doctor` to validate setup.\nRun `maestro update` to update to the latest version.\n"
	if err := os.WriteFile("AGENTS.md", []byte(agentsMD), 0644); err != nil {
		return fmt.Errorf("writing AGENTS.md: %w", err)
	}

	selectedAgentDirs, err := selectInitAgentDirs(initWithOpenCode, initWithClaude, os.Stdin, os.Stdout)
	if err != nil {
		return fmt.Errorf("installing agent configs: selecting agent directories: %w", err)
	}

	if len(selectedAgentDirs) > 0 {
		action, conflicting, err := handleAgentConflicts(selectedAgentDirs)
		if err != nil {
			return fmt.Errorf("installing agent configs: %w", err)
		}

		if err := applyConflictAction(action, conflicting); err != nil {
			return fmt.Errorf("installing agent configs: %w", err)
		}

		if action != agents.ConflictCancel {
			if err := installEmbeddedAgentDirs(selectedAgentDirs); err != nil {
				return fmt.Errorf("installing agent configs: %w", err)
			}
		}
	}

	fmt.Println("✓ Maestro initialized successfully!")
	return nil
}

func selectInitAgentDirs(withOpenCode, withClaude bool, r io.Reader, w io.Writer) ([]string, error) {
	selected := make([]string, 0, 2)
	if withOpenCode {
		selected = append(selected, ".opencode")
	}
	if withClaude {
		selected = append(selected, ".claude")
	}

	if len(selected) > 0 {
		return selected, nil
	}

	return agents.PromptAgentSelection(r, w, agents.KnownAgentDirs())
}

func installRequiredStarterAssets(r io.Reader, w io.Writer) error {
	required := agents.RequiredStarterAssetDirs()
	conflicting := findExistingDirectories(required)
	action := agents.ConflictOverwrite

	if len(conflicting) > 0 {
		if !isInteractiveStdin() {
			return fmt.Errorf("detected existing starter assets in non-interactive mode (%s). rerun interactively to choose overwrite/backup/cancel", strings.Join(conflicting, ", "))
		}

		var err error
		action, err = agents.PromptConflictResolution(r, w, conflicting)
		if err != nil {
			return fmt.Errorf("prompting for conflict resolution: %w", err)
		}
	}

	result, err := agents.InstallRequiredAssets(required, action, embedded.NewAssetFetcher())
	if err != nil {
		return err
	}

	if len(result.Installed) > 0 {
		fmt.Fprintf(w, "Installed required starter assets: %s\n", strings.Join(result.Installed, ", "))
	}
	for _, backup := range result.Backups {
		fmt.Fprintf(w, "Backup created: %s\n", backup)
	}

	return nil
}

func installRequiredStarterFiles() error {
	requiredFiles := agents.RequiredStarterAssetFiles()
	if len(requiredFiles) == 0 {
		return nil
	}

	for _, filePath := range requiredFiles {
		// Check if file already exists
		if _, err := os.Stat(filePath); err == nil {
			// File exists, skip
			continue
		}

		// Fetch file from embedded resources
		content, err := embedded.FetchFile(filePath)
		if err != nil {
			// Log warning but don't fail - files might not be critical
			fmt.Fprintf(os.Stderr, "Warning: could not fetch %s: %v\n", filePath, err)
			continue
		}

		// Ensure parent directory exists
		dir := filepath.Dir(filePath)
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("creating directory for %s: %w", filePath, err)
		}

		// Write file
		if err := os.WriteFile(filePath, content, 0644); err != nil {
			return fmt.Errorf("writing %s: %w", filePath, err)
		}

		fmt.Printf("Installed: %s\n", filePath)
	}

	return nil
}

// installEmbeddedAgentDirs installs agent directories from embedded resources.
func installEmbeddedAgentDirs(selected []string) error {
	if len(selected) == 0 {
		return nil
	}

	fetch := embedded.NewAssetFetcher()

	for _, dir := range selected {
		fmt.Printf("Installing %s from embedded resources...\n", dir)

		content, err := fetch(dir)
		if err != nil {
			return fmt.Errorf("reading embedded %s: %w", dir, err)
		}

		if err := agents.WriteAgentDir(content, dir); err != nil {
			return fmt.Errorf("writing %s: %w", dir, err)
		}

		fmt.Printf("✓ Installed %s\n", dir)
	}

	return nil
}

func findExistingDirectories(dirs []string) []string {
	conflicting := make([]string, 0, len(dirs))
	for _, dir := range dirs {
		if info, err := os.Stat(dir); err == nil && info.IsDir() {
			conflicting = append(conflicting, dir)
		}
	}
	return conflicting
}

func isInteractiveStdin() bool {
	info, err := os.Stdin.Stat()
	if err != nil {
		return false
	}
	return (info.Mode() & os.ModeCharDevice) != 0
}
