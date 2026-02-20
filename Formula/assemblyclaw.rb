class Assemblyclaw < Formula
  desc "World's smallest AI agent infrastructure — pure ARM64 assembly"
  homepage "https://github.com/gunta/AssemblyClaw"
  url "https://github.com/gunta/AssemblyClaw.git",
      tag:      "v0.1.0",
      revision: ""
  license "MIT"
  head "https://github.com/gunta/AssemblyClaw.git", branch: "main"

  depends_on arch: :arm64
  depends_on :macos

  def install
    system "make"
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
    assert_match version.to_s, shell_output("#{bin}/assemblyclaw --version")
    shell_output("#{bin}/assemblyclaw --help")
    shell_output("#{bin}/assemblyclaw status")
  end
end
