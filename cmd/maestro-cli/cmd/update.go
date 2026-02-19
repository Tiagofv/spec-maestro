package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/spec-maestro/maestro-cli/internal/version"
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
	token := os.Getenv("GITHUB_TOKEN")
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
	return nil
}
