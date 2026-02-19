package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/spec-maestro/maestro-cli/internal/version"
)

var rootCmd = &cobra.Command{
	Use:     "maestro",
	Short:   "Maestro CLI - manage maestro projects",
	Long:    "maestro is a CLI for initializing, updating, and validating maestro projects.",
	Version: version.Version,
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func init() {
	rootCmd.SetVersionTemplate("maestro " + version.String() + "\n")
}
