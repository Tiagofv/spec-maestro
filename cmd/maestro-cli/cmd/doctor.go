package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"
)

// requiredMaestroFiles lists files that must exist in a valid .maestro/ directory.
var requiredMaestroFiles = []string{
	"config.yaml",
}

// requiredMaestroDirs lists directories that must exist.
var requiredMaestroDirs = []string{
	"scripts",
	"specs",
	"state",
}

var doctorCmd = &cobra.Command{
	Use:   "doctor",
	Short: "Validate your maestro project setup",
	Long:  "Checks the .maestro/ directory structure and reports any issues with remediation steps.",
	RunE:  runDoctor,
}

func init() {
	rootCmd.AddCommand(doctorCmd)
}

type checkResult struct {
	name    string
	ok      bool
	message string
	fix     string
}

func runDoctor(cmd *cobra.Command, args []string) error {
	maestroDir := ".maestro"
	results := []checkResult{}

	// Check .maestro/ directory exists
	if _, err := os.Stat(maestroDir); os.IsNotExist(err) {
		fmt.Println("✗ .maestro/ directory not found")
		fmt.Println("  Fix: Run 'maestro init' to initialize this project")
		return fmt.Errorf("project not initialized")
	}
	results = append(results, checkResult{
		name: ".maestro/ directory", ok: true, message: "found",
	})

	// Check required files
	for _, file := range requiredMaestroFiles {
		path := filepath.Join(maestroDir, file)
		_, err := os.Stat(path)
		results = append(results, checkResult{
			name:    file,
			ok:      err == nil,
			message: map[bool]string{true: "found", false: "missing"}[err == nil],
			fix:     fmt.Sprintf("Run 'maestro init' to restore %s", file),
		})
	}

	// Check required directories
	for _, dir := range requiredMaestroDirs {
		path := filepath.Join(maestroDir, dir)
		_, err := os.Stat(path)
		results = append(results, checkResult{
			name:    dir + "/",
			ok:      err == nil,
			message: map[bool]string{true: "found", false: "missing"}[err == nil],
			fix:     fmt.Sprintf("Run 'maestro init' to restore %s/", dir),
		})
	}

	// Print results
	allOK := true
	for _, r := range results {
		if r.ok {
			fmt.Printf("✓ %-30s %s\n", r.name, r.message)
		} else {
			fmt.Printf("✗ %-30s %s\n", r.name, r.message)
			if r.fix != "" {
				fmt.Printf("  Fix: %s\n", r.fix)
			}
			allOK = false
		}
	}

	if allOK {
		fmt.Println("\n✓ All checks passed — project looks healthy!")
		return nil
	}
	return fmt.Errorf("some checks failed")
}
