# Troubleshooting Maestro CLI

## Common Issues

### GitHub API rate limited

**Error:** `GitHub API rate limited (remaining: 0)`

**Fix:** Set `GITHUB_TOKEN` environment variable:

```bash
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
2. Try with `GITHUB_TOKEN` for better rate limits
3. Download manually from https://github.com/spec-maestro/maestro-cli/releases

## Getting Help

- File an issue: https://github.com/spec-maestro/maestro-cli/issues
- Check releases: https://github.com/spec-maestro/maestro-cli/releases
