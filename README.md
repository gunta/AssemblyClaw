# AssemblyClaw

**The world's smallest and fastest AI agent infrastructure. Pure ARM64 assembly.**

```
36 KB binary · 6 ms startup (--help) · 5 MB peak RSS · libSystem + libcurl
```

## Why

Everyone complains about TypeScript using too much memory. But TS is the fastest
way to iterate and get community hooked. Ship value first, then optimize.

The natural progression:
1. **TypeScript** — ship fast, build community, iterate
2. **Zig** — harden it, single binary, zero overhead
3. **ARM64 Assembly** — absolute minimum, prove the point (AssemblyClaw: 36 KB now, targeting < 32 KB)

This project proves that with the spec in hand, AI coding agents can write and
maintain even assembly. The future is Bend (GPU parallelism), Lean 4 (zero bugs),
and languages we haven't invented yet.

## Benchmark

Latest measured run (source of truth: `site/public/benchmarks.json`):
- **Run date (UTC):** 2026-02-23T21:38:56.880Z
- **Machine:** Mac16,5 (Apple M4 Max, 64 GB RAM)
- **OS:** macOS 26.3 (build 25D125)
- **Method:** `hyperfine --shell=none --warmup 10 --min-runs 50 --time-unit millisecond ./build/assemblyclaw --help` + `/usr/bin/time -l ./build/assemblyclaw --help`

| | OpenClaw (TS) | NullClaw (Zig) | CClaw (C) | **AssemblyClaw (ARM64)** |
|---|---|---|---|---|
| **Binary** | 41 MB | 2 MB | 143 KB | **36 KB** |
| **RAM** | 372 MB | 1 MB | 5 MB | **5 MB** |
| **Startup** | 1163 ms | 8 ms | 11 ms | **6 ms** |
| **Language** | TypeScript | Zig | C | **ARM64 Assembly** |
| **Cost** | Mac Mini $599 | Any $5 hardware | Any $10 hardware | **Any $1 hardware** |

Targets remain:
- Binary `< 32 KB`
- Peak RSS `< 128 KB`
- Startup `< 0.1 ms`

`ninja bench` regenerates `site/public/benchmarks.json`, and the landing page reads from that JSON directly.

Comparison provenance for this run:
- OpenClaw measured from `openclaw@latest` CLI package (`2026.2.22-2`)
- NullClaw measured from latest release binary (`nullclaw 2026.2.21`, tag `v2026.2.21`)
- CClaw measured from local `context/cclaw-main` snapshot (`CClaw 0.1.0`)

`bun bench.ts` now automates comparator fetch/build/benchmark:
- OpenClaw package install/update
- NullClaw git fetch + Zig release build (falls back to latest macOS arm64 release binary if source build fails)
- CClaw latest upstream fetch/build from `https://github.com/aresbit/cclaw.git` (or `CCLAW_REPO_URL` override, with local snapshot fallback)

> Currently targeting Apple Silicon (M4 Pro/Max) because that's what I have.
> Even at 36 KB today (and targeting < 32 KB) with pure ARM64, there's nothing stopping this from running on
> the cheapest ARM board that exists. This is about what's *possible*.

## Install

### Homebrew (recommended)

```bash
brew tap gunta/assemblyclaw
brew install assemblyclaw
```

Or install the latest from main:

```bash
brew install --HEAD gunta/assemblyclaw/assemblyclaw
```

### Build from source

Requires macOS on Apple Silicon, Ninja, and Xcode Command Line Tools.

```bash
git clone https://github.com/gunta/AssemblyClaw.git
cd AssemblyClaw
ninja
sudo cp build/assemblyclaw /usr/local/bin/
```

## Quick Start

```bash
assemblyclaw --help
assemblyclaw --version
assemblyclaw status

# Chat with AI
assemblyclaw agent -m "Hello from assembly!"

# Benchmark (from source tree)
bun bench.ts
```

## Architecture

Pure ARM64 assembly optimized for Apple Silicon M4/M5 Pro/Max:

- **NEON SIMD**: 16 bytes/cycle string scanning (CMEQ + UMAXV)
- **Cache-aligned**: 128-byte alignment for M4 cache lines
- **Branchless**: CSEL/CSETM for conditional operations
- **Arena allocator**: mmap-backed, zero fragmentation
- **Zero-copy strings**: ptr+len views, no NUL overhead
- **System calls**: Direct libSystem FFI, no libc wrapper tax
- **libcurl**: HTTPS via system libcurl (ships with macOS)

```
src/
  main.s        CLI entry point and argument dispatch
  string.s      NEON SIMD string operations
  memory.s      Arena allocator (mmap-backed)
  io.s          File I/O wrappers
  json.s        Zero-allocation streaming JSON parser
  http.s        HTTPS client (libcurl FFI)
  config.s      Config reader (~/.assemblyclaw/config.json)
  provider.s    LLM provider (OpenRouter, Anthropic, OpenAI)
  agent.s       Agent loop with conversation history
  error.s       Error codes and messages
  version.s     Version and build info
```

## Configuration

```bash
mkdir -p ~/.assemblyclaw
cat > ~/.assemblyclaw/config.json << 'EOF'
{
  "default_provider": "openrouter",
  "providers": {
    "openrouter": {
      "api_key": "sk-or-...",
      "model": "anthropic/claude-sonnet-4"
    },
    "anthropic": {
      "api_key": "sk-ant-...",
      "model": "claude-sonnet-4-20250514"
    }
  }
}
EOF
```

## Commands

| Command | Description |
|---------|-------------|
| `--help` | Show usage |
| `--version` | Show version |
| `status` | System status |
| `agent -m "..."` | Single message mode |
| `agent` | Interactive chat |

## Build Requirements

- macOS on Apple Silicon (M1/M2/M3/M4/M5)
- Xcode Command Line Tools (`xcode-select --install`)
- Ninja (`brew install ninja`)

## Development

```bash
ninja              # Release build (optimized, stripped)
ninja debug        # Debug build (with symbols)
ninja test         # Run tests
ninja bench        # Full benchmark suite
ninja -t clean     # Remove build outputs
```

## The Story

Programming languages will keep evolving. The world needs:
- **Bend** — regular programs running on GPUs automatically
- **Lean 4** — programs without bugs, proven correct
- **Zig** — the pragmatic middle ground (powering Bun)

But right now, this project shows that even assembly is within reach
when you have a spec and an AI coding agent. Good times to be alive.

## License

MIT
