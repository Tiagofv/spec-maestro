# Maestro CLI

A native CLI for managing [maestro](https://github.com/spec-maestro/maestro-cli) projects.

## Installation

### Homebrew (macOS and Linux)

```bash
brew tap spec-maestro/maestro
brew install maestro
```

### Direct Download

Download the latest binary from [GitHub Releases](https://github.com/spec-maestro/maestro-cli/releases).

**macOS (Apple Silicon)**

```bash
curl -L https://github.com/spec-maestro/maestro-cli/releases/latest/download/maestro_Darwin_arm64.tar.gz | tar xz
sudo mv maestro /usr/local/bin/
```

**macOS (Intel)**

```bash
curl -L https://github.com/spec-maestro/maestro-cli/releases/latest/download/maestro_Darwin_x86_64.tar.gz | tar xz
sudo mv maestro /usr/local/bin/
```

**Linux (x86_64)**

```bash
curl -L https://github.com/spec-maestro/maestro-cli/releases/latest/download/maestro_Linux_x86_64.tar.gz | tar xz
sudo mv maestro /usr/local/bin/
```

**Linux (ARM64)**

```bash
curl -L https://github.com/spec-maestro/maestro-cli/releases/latest/download/maestro_Linux_arm64.tar.gz | tar xz
sudo mv maestro /usr/local/bin/
```

**Windows**
Download the `.zip` from [Releases](https://github.com/spec-maestro/maestro-cli/releases) and extract `maestro.exe` to a directory in your `PATH`.

### From Source

Requires Go 1.23+:

```bash
git clone https://github.com/spec-maestro/maestro-cli
cd maestro-cli/cmd/maestro-cli
go build -o maestro .
sudo mv maestro /usr/local/bin/
```

## Usage

```bash
maestro init      # Initialize maestro in the current project
maestro update    # Update to the latest version
maestro doctor    # Validate project setup
maestro version   # Show version information
maestro remove    # Remove maestro from the current project
```

## Shell Completion

```bash
# Bash
source <(maestro completion bash)

# Zsh
maestro completion zsh > "${fpath[1]}/_maestro"

# Fish
maestro completion fish | source
```

## Environment Variables

| Variable       | Description                                               |
| -------------- | --------------------------------------------------------- |
| `GITHUB_TOKEN` | GitHub personal access token (for higher API rate limits) |

## License

MIT
