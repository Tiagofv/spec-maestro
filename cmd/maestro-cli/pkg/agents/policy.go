package agents

// RequiredStarterAssetDirs returns the required starter directories
// that must be installed by `maestro init`.
func RequiredStarterAssetDirs() []string {
	return []string{
		".maestro/commands",
		".maestro/cookbook",
		".maestro/reference",
		".maestro/scripts",
		".maestro/skills",
		".maestro/templates",
	}
}

// RequiredStarterAssetFiles returns the required starter files
// that must be installed at the root of .maestro/ by `maestro init`.
func RequiredStarterAssetFiles() []string {
	return []string{
		".maestro/constitution.md",
	}
}
