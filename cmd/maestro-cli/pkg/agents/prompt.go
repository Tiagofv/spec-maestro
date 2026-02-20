package agents

import (
	"bufio"
	"fmt"
	"io"
	"strconv"
	"strings"
	"time"
)

// ConflictAction represents the user's choice for handling conflicts
type ConflictAction int

const (
	ConflictOverwrite ConflictAction = iota
	ConflictBackup
	ConflictCancel
)

// agentDescriptions maps agent directory names to their descriptions
var agentDescriptions = map[string]string{
	".opencode": "slash commands and skills for OpenCode",
	".claude":   "slash commands and skills for Claude Code",
}

// PromptAgentSelection presents a multi-select prompt listing available
// agent config directories. Returns the user's selections.
// Empty selection (Enter with no input) returns an empty slice.
// Available is typically KnownAgentDirs().
func PromptAgentSelection(r io.Reader, w io.Writer, available []string) ([]string, error) {
	if len(available) == 0 {
		return []string{}, nil
	}

	fmt.Fprintln(w, "The following agent config directories are available:")
	for i, dir := range available {
		desc := agentDescriptions[dir]
		if desc == "" {
			desc = "agent configuration"
		}
		fmt.Fprintf(w, "  [%d] %s  (%s)\n", i+1, dir, desc)
	}
	fmt.Fprintln(w, "")
	fmt.Fprint(w, "Enter numbers to install (e.g. 1 2), or press Enter to skip: ")

	reader := bufio.NewReader(r)
	input, err := reader.ReadString('\n')
	if err != nil {
		return nil, fmt.Errorf("reading input: %w", err)
	}

	input = strings.TrimSpace(input)
	if input == "" {
		return []string{}, nil
	}

	// Parse the input numbers
	parts := strings.Fields(input)
	selected := []string{}
	seen := make(map[int]bool)

	for _, part := range parts {
		num, err := strconv.Atoi(part)
		if err != nil {
			return nil, fmt.Errorf("invalid number '%s': %w", part, err)
		}
		if num < 1 || num > len(available) {
			return nil, fmt.Errorf("number %d is out of range (1-%d)", num, len(available))
		}
		if !seen[num] {
			seen[num] = true
			selected = append(selected, available[num-1])
		}
	}

	return selected, nil
}

// PromptConflictResolution presents the existing .maestro/ conflict pattern:
// [o]verwrite / [b]ackup / [c]ancel for all conflicting dirs at once.
// conflicting is the list of dirs that already exist.
func PromptConflictResolution(r io.Reader, w io.Writer, conflicting []string) (ConflictAction, error) {
	if len(conflicting) == 0 {
		return ConflictCancel, nil
	}

	if len(conflicting) == 1 {
		fmt.Fprintf(w, "%s already exists. What would you like to do?\n", conflicting[0])
	} else {
		fmt.Fprintln(w, "The following directories already exist:")
		for _, dir := range conflicting {
			fmt.Fprintf(w, "  - %s\n", dir)
		}
		fmt.Fprintln(w, "\nWhat would you like to do?")
	}

	fmt.Fprintln(w, "  [o] Overwrite existing files")
	fmt.Fprintln(w, "  [b] Backup existing and reinitialize")
	fmt.Fprintln(w, "  [c] Cancel (default)")
	fmt.Fprint(w, "Choice [o/b/c]: ")

	reader := bufio.NewReader(r)
	choice, err := reader.ReadString('\n')
	if err != nil {
		return ConflictCancel, fmt.Errorf("reading input: %w", err)
	}

	choice = strings.TrimSpace(strings.ToLower(choice))

	switch choice {
	case "o":
		return ConflictOverwrite, nil
	case "b":
		return ConflictBackup, nil
	default:
		return ConflictCancel, nil
	}
}

// BackupPath generates a timestamped backup path for a directory
func BackupPath(dir string) string {
	timestamp := time.Now().Format("20060102-150405")
	return fmt.Sprintf("%s-backup-%s", dir, timestamp)
}
