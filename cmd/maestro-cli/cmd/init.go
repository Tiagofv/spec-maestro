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
	"github.com/spec-maestro/maestro-cli/pkg/assets"
	"github.com/spec-maestro/maestro-cli/pkg/config"
	"github.com/spec-maestro/maestro-cli/pkg/fs"
	ghclient "github.com/spec-maestro/maestro-cli/pkg/github"
)

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize maestro in the current project",
	Long:  "Downloads and installs maestro files into .maestro/ in the current directory.",
	RunE:  runInit,
}

const (
	githubOwner = "Tiagofv"
	githubRepo  = "spec-maestro"
)

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

	// Detect platform
	platform, err := fs.DetectPlatform()
	if err != nil {
		return fmt.Errorf("detecting platform: %w", err)
	}
	fmt.Printf("Platform: %s\n", platform.String())

	// Fetch latest release
	fmt.Println("Fetching latest release...")
	token := ghclient.ResolveToken(os.Getenv("GITHUB_TOKEN"))
	client := ghclient.NewClient(githubOwner, githubRepo, token)

	release, err := client.FetchLatestRelease()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not fetch release: %v\n", err)
		fmt.Println("Proceeding with local setup only...")
	}

	// Download and extract assets if release found
	assetDownloaded := false
	if release != nil {
		fmt.Printf("Using release: %s\n", release.TagName)
		asset, err := release.FindAssetForPlatform(platform.AssetSuffix())
		if err != nil {
			fmt.Fprintf(os.Stderr, "Warning: no asset for platform %s: %v\n", platform.String(), err)
		} else {
			fmt.Printf("Downloading %s...\n", asset.Name)
			cache, err := assets.NewCacheManager()
			if err == nil {
				cachedPath, err := cache.Get(asset.DownloadURL, 0)
				if err != nil {
					fmt.Fprintf(os.Stderr, "Warning: download failed: %v\n", err)
				} else {
					if err := assets.ExtractAsset(cachedPath, maestroDir); err != nil {
						fmt.Fprintf(os.Stderr, "Warning: extraction failed: %v\n", err)
					} else {
						assetDownloaded = true
					}
				}
			}
		}
	}

	// Fallback: Fetch from GitHub if no asset was downloaded
	if !assetDownloaded {
		fmt.Println("Falling back to fetching .maestro/ from GitHub main branch...")
		if err := initFromGitHub(client, maestroDir); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: GitHub fetch failed: %v\n", err)
		} else {
			fmt.Println("✓ Downloaded .maestro/ from GitHub")
		}
	}

	if err := installRequiredStarterAssets(client, os.Stdin, os.Stdout); err != nil {
		return fmt.Errorf("installing required starter assets: %w", err)
	}

	// Install required root files (constitution.md, etc.)
	if err := installRequiredStarterFiles(client); err != nil {
		return fmt.Errorf("installing required starter files: %w", err)
	}

	// Create minimal .maestro/ structure if not created by asset extraction
	for _, dir := range []string{
		filepath.Join(maestroDir, "specs"),
		filepath.Join(maestroDir, "state"),
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
			if err := fetchAndInstallAgentDirs(client, selectedAgentDirs); err != nil {
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

func installRequiredStarterAssets(client *ghclient.Client, r io.Reader, w io.Writer) error {
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

	result, err := agents.InstallRequiredAssets(required, action, func(dir string) (map[string][]byte, error) {
		return fetchAgentDirWithRefFallback(client, dir, "main")
	})
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

func installRequiredStarterFiles(client *ghclient.Client) error {
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

		// Fetch file from GitHub
		content, err := fetchFileWithRefFallback(client, filePath, "main")
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

func fetchFileWithRefFallback(client *ghclient.Client, filePath string, primaryRef string) ([]byte, error) {
	refs := []string{primaryRef}
	if primaryRef == "main" {
		refs = append(refs, "master")
	}

	var lastErr error
	for _, ref := range refs {
		content, err := client.FetchFile(filePath, ref)
		if err == nil {
			return content, nil
		}

		lastErr = err
		if strings.Contains(strings.ToLower(err.Error()), "resource not found") {
			continue
		}

		return nil, err
	}

	if lastErr == nil {
		return nil, fmt.Errorf("no refs attempted")
	}

	return nil, fmt.Errorf("tried refs %v: %w", refs, lastErr)
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

// initFromGitHub fetches only the core maestro directories from GitHub main branch
// when no release asset is available for the current platform.
// This preserves user data - specs/state/research/memory are created empty.
func initFromGitHub(client *ghclient.Client, maestroDir string) error {
	coreDirs := []string{".maestro/commands", ".maestro/scripts", ".maestro/templates", ".maestro/skills", ".maestro/cookbook", ".maestro/reference"}
	// User data directories - just create them empty, don't fetch from GitHub
	userDirs := []string{"specs", "state", "research", "memory"}

	if err := os.MkdirAll(maestroDir, 0755); err != nil {
		return fmt.Errorf("creating maestro directory: %w", err)
	}

	totalFiles := 0
	for _, dir := range coreDirs {
		content, err := client.FetchAgentDir(dir, "main")
		if err != nil {
			continue
		}

		for filePath, fileContent := range content {
			localPath := filePath
			if strings.HasPrefix(localPath, dir+"/") {
				localPath = strings.TrimPrefix(localPath, dir+"/")
			}

			fullPath := filepath.Join(maestroDir, strings.TrimPrefix(dir, ".maestro/"), localPath)

			parentDir := filepath.Dir(fullPath)
			if err := os.MkdirAll(parentDir, 0755); err != nil {
				return fmt.Errorf("creating directory %s: %w", parentDir, err)
			}

			if err := os.WriteFile(fullPath, fileContent, 0644); err != nil {
				return fmt.Errorf("writing %s: %w", fullPath, err)
			}
			totalFiles++
		}
	}

	for _, userDir := range userDirs {
		userPath := filepath.Join(maestroDir, userDir)
		if _, err := os.Stat(userPath); os.IsNotExist(err) {
			if err := os.MkdirAll(userPath, 0755); err != nil {
				return fmt.Errorf("creating user directory %s: %w", userPath, err)
			}
		}
	}

	if totalFiles == 0 {
		return fmt.Errorf("no files downloaded from GitHub")
	}

	fmt.Printf("✓ Downloaded %d core files from GitHub\n", totalFiles)
	fmt.Println("  (Existing user data preserved: specs, state, research, memory)")
	return nil
}
