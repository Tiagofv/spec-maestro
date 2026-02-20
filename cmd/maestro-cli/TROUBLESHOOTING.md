# Troubleshooting Maestro CLI

## Common Issues

### GitHub API rate limited

**Error:** `GitHub API rate limited (remaining: 0)`

**Fix:** For public repos, try again (the CLI now falls back to archive download for agent directories). If you still hit limits on release APIs, authenticate with GitHub CLI or set a token:

```bash
gh auth login
# OR
export GH_TOKEN=ghp_your_token
# OR
export GITHUB_TOKEN=ghp_your_token
maestro init
```

### Permission denied

**Error:** `permission denied` when installing to `/usr/local/bin/`

**Fix:** Use sudo or install to a user-writable location:

```bash
sudo mv maestro /usr/local/bin/
# OR
mkdir -p ~/bin && mv maestro ~/bin/ && export PATH="$HOME/bin:$PATH"
```

### Asset not found for platform

**Error:** `no asset found for platform`

**Fix:** Check that a release exists with assets for your platform. Download manually from GitHub Releases.

### Network failures

**Error:** Connection timeout or network error during download

**Fix:**

1. Check internet connection
2. Authenticate with `gh auth login` or set `GH_TOKEN`/`GITHUB_TOKEN` for better rate limits
3. Download manually from https://github.com/spec-maestro/maestro-cli/releases

## Getting Help

- File an issue: https://github.com/spec-maestro/maestro-cli/issues
- Check releases: https://github.com/spec-maestro/maestro-cli/releases
