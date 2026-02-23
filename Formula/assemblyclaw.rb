class Assemblyclaw < Formula
  desc "World's smallest AI agent infrastructure — pure ARM64 assembly"
  homepage "https://github.com/gunta/AssemblyClaw"
  url "https://github.com/gunta/AssemblyClaw/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "70965924089369d38c87c4b32d9a3ba601a93d61f26dd684fcedd8b27c9b4abe"
  license "MIT"
  head "https://github.com/gunta/AssemblyClaw.git", branch: "main"

  depends_on arch: :arm64
  depends_on :macos
  depends_on "ninja" => :build

  def install
    system "ninja"
    bin.install "build/assemblyclaw"
  end

  def caveats
    <<~EOS
      Configure your LLM provider:
        mkdir -p ~/.assemblyclaw
        cat > ~/.assemblyclaw/config.json << 'JSON'
        {
          "default_provider": "openrouter",
          "providers": {
            "openrouter": {
              "api_key": "sk-or-...",
              "model": "anthropic/claude-sonnet-4"
            }
          }
        }
        JSON
    EOS
  end

  test do
    assert_match "assemblyclaw", shell_output("#{bin}/assemblyclaw --version")
    shell_output("#{bin}/assemblyclaw --help")
  end
end
