class Maestro < Formula
  desc "Maestro CLI - manage maestro projects"
  homepage "https://github.com/spec-maestro/maestro-cli"
  version "0.1.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/spec-maestro/maestro-cli/releases/download/v#{version}/maestro_Darwin_arm64.tar.gz"
      sha256 "PLACEHOLDER_SHA256_DARWIN_ARM64"
    else
      url "https://github.com/spec-maestro/maestro-cli/releases/download/v#{version}/maestro_Darwin_x86_64.tar.gz"
      sha256 "PLACEHOLDER_SHA256_DARWIN_AMD64"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/spec-maestro/maestro-cli/releases/download/v#{version}/maestro_Linux_arm64.tar.gz"
      sha256 "PLACEHOLDER_SHA256_LINUX_ARM64"
    else
      url "https://github.com/spec-maestro/maestro-cli/releases/download/v#{version}/maestro_Linux_x86_64.tar.gz"
      sha256 "PLACEHOLDER_SHA256_LINUX_AMD64"
    end
  end

  def install
    bin.install "maestro"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/maestro --version")
  end
end
