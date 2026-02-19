package version

var (
	// Version is the semantic version, injected at build time.
	Version = "dev"
	// Commit is the git commit SHA, injected at build time.
	Commit = "none"
	// Date is the build date, injected at build time.
	Date = "unknown"
)

// String returns the full version string.
func String() string {
	return Version + " (commit: " + Commit + ", built: " + Date + ")"
}
