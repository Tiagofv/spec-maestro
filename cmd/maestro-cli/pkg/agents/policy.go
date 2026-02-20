package agents

// RequiredStarterAssetDirs returns the required starter directories
// that must be installed by `maestro init`.
func RequiredStarterAssetDirs() []string {
	return []string{
		".maestro/scripts",
		".maestro/skills",
		".maestro/templates",
	}
}
