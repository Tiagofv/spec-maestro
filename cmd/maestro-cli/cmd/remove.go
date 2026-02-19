package cmd

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

var removeCmd = &cobra.Command{
	Use:   "remove",
	Short: "Remove maestro from the current project",
	Long:  "Removes the .maestro/ directory from the current project. Optionally creates a backup first.",
	RunE:  runRemove,
}

var removeForce bool
var removeBackup bool

func init() {
	rootCmd.AddCommand(removeCmd)
	removeCmd.Flags().BoolVarP(&removeForce, "force", "f", false, "Skip confirmation prompt")
	removeCmd.Flags().BoolVar(&removeBackup, "backup", false, "Create a backup before removing")
}

func runRemove(cmd *cobra.Command, args []string) error {
	maestroDir := ".maestro"

	if _, err := os.Stat(maestroDir); os.IsNotExist(err) {
		fmt.Println("No .maestro/ directory found — nothing to remove.")
		return nil
	}

	if !removeForce {
		fmt.Print("Are you sure you want to remove .maestro/ from this project? [y/N] ")
		reader := bufio.NewReader(os.Stdin)
		response, err := reader.ReadString('\n')
		if err != nil {
			return fmt.Errorf("reading input: %w", err)
		}
		response = strings.TrimSpace(strings.ToLower(response))
		if response != "y" && response != "yes" {
			fmt.Fprintln(os.Stderr, "Aborted.")
			return nil
		}
	}

	if removeBackup {
		backupDir := fmt.Sprintf(".maestro-backup-%s", time.Now().Format("20060102-150405"))
		if err := copyDir(maestroDir, backupDir); err != nil {
			return fmt.Errorf("creating backup: %w", err)
		}
		fmt.Printf("Backup created at %s\n", backupDir)
	}

	if err := os.RemoveAll(maestroDir); err != nil {
		return fmt.Errorf("removing .maestro/: %w", err)
	}

	fmt.Println("✓ .maestro/ removed successfully.")
	return nil
}

// copyDir copies a directory recursively.
func copyDir(src, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		if info.IsDir() {
			return os.MkdirAll(target, info.Mode())
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(target, data, info.Mode())
	})
}
