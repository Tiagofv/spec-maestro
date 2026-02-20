package cmd

import (
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/spec-maestro/maestro-cli/internal/version"
	"github.com/spec-maestro/maestro-cli/pkg/agents"
	"github.com/spec-maestro/maestro-cli/pkg/assets"
	"github.com/spec-maestro/maestro-cli/pkg/config"
	"github.com/spec-maestro/maestro-cli/pkg/fs"
	ghclient "github.com/spec-maestro/maestro-cli/pkg/github"
)

var updateCmd = &cobra.Command{
	Use:   "update",
	Short: "Update maestro to the latest version",
	Long:  "Checks for a newer release and updates .maestro/ assets and CLI notification.",
	RunE:  runUpdate,
}

func init() {
	rootCmd.AddCommand(updateCmd)
}

func runUpdate(cmd *cobra.Command, args []string) error {
	// Check project is initialized
	if _, err := os.Stat(".maestro"); os.IsNotExist(err) {
		return fmt.Errorf("not initialized — run 'maestro init' first")
	}

	// Detect platform
	platform, err := fs.DetectPlatform()
	if err != nil {
		return fmt.Errorf("detecting platform: %w", err)
	}

	// Fetch latest release
	fmt.Println("Checking for updates...")
	token := ghclient.ResolveToken(os.Getenv("GITHUB_TOKEN"))
	client := ghclient.NewClient(githubOwner, githubRepo, token)

	release, err := client.FetchLatestRelease()
	if err != nil {
		return fmt.Errorf("checking for updates: %w", err)
	}

	current := version.Version
	latest := release.TagName
	fmt.Printf("Current version: %s\n", current)
	fmt.Printf("Latest version:  %s\n", latest)

	if current != "dev" && current == latest {
		fmt.Println("✓ Already up to date!")
		return nil
	}

	fmt.Printf("Updating to %s...\n", latest)

	// Find asset for platform
	asset, err := release.FindAssetForPlatform(platform.AssetSuffix())
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: no asset for platform %s: %v\n", platform.String(), err)
		fmt.Println("Please download the update manually from https://github.com/" + githubOwner + "/" + githubRepo + "/releases")
		return nil
	}

	// Download and extract to .maestro/
	cache, err := assets.NewCacheManager()
	if err != nil {
		return fmt.Errorf("initializing cache: %w", err)
	}
	// Invalidate cache to force fresh download
	if err := cache.Invalidate(asset.DownloadURL); err != nil {
		return fmt.Errorf("invalidating cache: %w", err)
	}

	cachedPath, err := cache.Get(asset.DownloadURL, 0)
	if err != nil {
		return fmt.Errorf("downloading update: %w", err)
	}

	if err := assets.ExtractAsset(cachedPath, ".maestro"); err != nil {
		return fmt.Errorf("extracting update: %w", err)
	}

	// Update config with new version
	if err := config.UpdateCLIVersion(".maestro/config.yaml", latest); err != nil {
		return fmt.Errorf("updating config version: %w", err)
	}

	fmt.Printf("✓ Updated to %s successfully!\n", latest)
	fmt.Println("Note: Custom modifications in .maestro/ have been preserved.")

	// Update agent configurations
	if err := updateAgentConfigs(client); err != nil {
		return fmt.Errorf("updating agent configs: %w", err)
	}

	return nil
}

// refreshInstalledAgentDirs refreshes existing agent directories from GitHub.
func refreshInstalledAgentDirs(client *ghclient.Client, installed []string) error {
	if len(installed) == 0 {
		return nil
	}

	fmt.Println("\nRefreshing installed agent configurations...")

	// Handle conflicts for all installed dirs
	action, conflicting, err := handleAgentConflicts(installed)
	if err != nil {
		return err
	}

	// Apply conflict resolution
	if err := applyConflictAction(action, conflicting); err != nil {
		return err
	}

	// If user chose cancel, stop here
	if action == agents.ConflictCancel {
		fmt.Println("Agent refresh cancelled.")
		return nil
	}

	// Fetch and install the installed directories (refresh them)
	if err := fetchAndInstallAgentDirs(client, installed); err != nil {
		return err
	}

	fmt.Printf("✓ Refreshed %d agent configuration(s)\n", len(installed))
	return nil
}

// promptInstallMissingAgentDirs prompts user to install missing agent directories.
func promptInstallMissingAgentDirs(client *ghclient.Client, missing []string) error {
	if len(missing) == 0 {
		return nil
	}

	fmt.Println("\nThe following agent configurations are available but not installed:")
	selected, err := agents.PromptAgentSelection(os.Stdin, os.Stdout, missing)
	if err != nil {
		return fmt.Errorf("selecting agent directories: %w", err)
	}

	if len(selected) == 0 {
		return nil
	}

	// No conflict handling needed since these directories don't exist yet
	if err := fetchAndInstallAgentDirs(client, selected); err != nil {
		return err
	}

	fmt.Printf("✓ Installed %d additional agent configuration(s)\n", len(selected))
	return nil
}

// updateAgentConfigs orchestrates the agent configuration update process.
func updateAgentConfigs(client *ghclient.Client) error {
	// Detect which agent directories are currently installed
	installed := agents.DetectInstalled(".")

	// Determine which known agent directories are missing
	known := agents.KnownAgentDirs()
	installedSet := make(map[string]bool)
	for _, dir := range installed {
		installedSet[dir] = true
	}

	var missing []string
	for _, dir := range known {
		if !installedSet[dir] {
			missing = append(missing, dir)
		}
	}

	// Refresh installed agent directories
	if err := refreshInstalledAgentDirs(client, installed); err != nil {
		return err
	}

	// Prompt to install missing agent directories
	if err := promptInstallMissingAgentDirs(client, missing); err != nil {
		return err
	}

	return nil
}

// handleAgentConflicts checks for existing agent directories and prompts for resolution.
func handleAgentConflicts(selected []string) (agents.ConflictAction, []string, error) {
	if len(selected) == 0 {
		return agents.ConflictCancel, nil, nil
	}

	// Detect which selected directories already exist
	conflicting := []string{}
	for _, dir := range selected {
		if info, err := os.Stat(dir); err == nil && info.IsDir() {
			conflicting = append(conflicting, dir)
		}
	}

	if len(conflicting) == 0 {
		return agents.ConflictOverwrite, nil, nil
	}

	// Prompt for conflict resolution
	action, err := agents.PromptConflictResolution(os.Stdin, os.Stdout, conflicting)
	if err != nil {
		return agents.ConflictCancel, nil, fmt.Errorf("prompting for conflict resolution: %w", err)
	}

	return action, conflicting, nil
}

// applyConflictAction applies the chosen conflict action to conflicting directories.
func applyConflictAction(action agents.ConflictAction, conflicting []string) error {
	switch action {
	case agents.ConflictOverwrite:
		fmt.Println("Overwriting existing agent directories...")
		return nil
	case agents.ConflictBackup:
		for _, dir := range conflicting {
			backupPath, err := agents.BackupDir(dir)
			if err != nil {
				return fmt.Errorf("backing up %s: %w", dir, err)
			}
			fmt.Printf("Backup created: %s\n", backupPath)
		}
		return nil
	case agents.ConflictCancel:
		fmt.Println("Aborted.")
		return nil
	default:
		return fmt.Errorf("unknown conflict action: %v", action)
	}
}

// fetchAndInstallAgentDirs fetches agent directories from GitHub and installs them.
func fetchAndInstallAgentDirs(client *ghclient.Client, selected []string) error {
	if len(selected) == 0 {
		return nil
	}

	for _, dir := range selected {
		fmt.Printf("Fetching %s from GitHub...\n", dir)

		// Fetch the directory content from GitHub (default branch fallback)
		content, err := fetchAgentDirWithRefFallback(client, dir, "main")
		if err != nil {
			return fmt.Errorf("fetching %s: %w", dir, err)
		}

		// Write the content to the project root
		if err := agents.WriteAgentDir(content, dir); err != nil {
			return fmt.Errorf("writing %s: %w", dir, err)
		}

		fmt.Printf("✓ Installed %s\n", dir)
	}

	return nil
}

func fetchAgentDirWithRefFallback(client *ghclient.Client, dir string, primaryRef string) (map[string][]byte, error) {
	refs := []string{primaryRef}
	if primaryRef == "main" {
		refs = append(refs, "master")
	}

	var lastErr error
	for _, ref := range refs {
		content, err := client.FetchAgentDir(dir, ref)
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
