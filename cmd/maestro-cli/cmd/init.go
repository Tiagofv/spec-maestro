package cmd

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/spec-maestro/maestro-cli/internal/version"
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
	githubOwner = "spec-maestro"
	githubRepo  = "maestro-cli"
)

func init() {
	rootCmd.AddCommand(initCmd)
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
	token := os.Getenv("GITHUB_TOKEN")
	client := ghclient.NewClient(githubOwner, githubRepo, token)

	release, err := client.FetchLatestRelease()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not fetch release: %v\n", err)
		fmt.Println("Proceeding with local setup only...")
	}

	// Download and extract assets if release found
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
					}
				}
			}
		}
	}

	// Create minimal .maestro/ structure if not created by asset extraction
	for _, dir := range []string{
		filepath.Join(maestroDir, "scripts"),
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

	fmt.Println("✓ Maestro initialized successfully!")
	return nil
}
