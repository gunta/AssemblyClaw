# AssemblyClaw

Pure ARM64 assembly AI agent infrastructure for Apple Silicon (macOS).

## Build & Test

```bash
make              # Release build (optimized, stripped)
make debug        # Debug build (with symbols)
make clean        # Remove build/
make test         # Black-box CLI tests
./bench.sh        # Full benchmark suite
```

Requires: macOS on Apple Silicon + Xcode Command Line Tools. No other dependencies.

The binary links against libSystem and libcurl (both ship with macOS).

## Project Structure

```
src/                  ARM64 assembly source (.s files)
  main.s              CLI entry point and argument dispatch
  string.s            NEON SIMD string operations
  memory.s            Arena allocator (mmap-backed)
  io.s                File I/O wrappers
  json.s              Zero-allocation streaming JSON parser
  http.s              HTTPS client (libcurl FFI)
  config.s            Config reader (~/.assemblyclaw/config.json)
  provider.s          LLM provider API (OpenRouter, Anthropic, OpenAI)
  agent.s             Agent loop with conversation history
  error.s             Error codes and messages
  version.s           Version and build metadata
include/
  constants.inc       Buffer sizes, error codes, curl/mmap constants
  syscall.inc         macOS ARM64 syscall numbers (reference)
build/                Compiled .o and final binary
Formula/              Homebrew tap formula
site/                 Landing page (Vite)
context/              Reference implementations (CClaw in C, NullClaw in Zig)
bench.sh              Benchmark script (size, RAM, startup)
PLAN.md               Implementation phases and architecture notes
TESTS.md              Test matrix tracking
```

## Architecture Rules

- **AAPCS64 calling convention**: x0-x7 args, x19-x28 callee-saved, x29=FP, x30=LR, sp 16-byte aligned
- **All data cache-line aligned**: `.p2align 7` (128 bytes) for M4/M5 cache lines
- **NEON SIMD for strings**: CMEQ + UMAXV pattern for 16 bytes/cycle scanning
- **Branchless where possible**: use CSEL, CSETM, TBNZ over conditional branches
- **Arena allocator only**: mmap-backed, no malloc/free, zero fragmentation
- **Zero-copy strings**: ptr+len views, no NUL-termination overhead
- **Direct libSystem FFI**: call _write, _read, _mmap directly — no libc wrappers

## Code Conventions

- All source files are `.s` (GNU assembler syntax via clang)
- Include files are `.inc` in `include/`
- Function names prefixed with `_` (C-compatible symbols)
- Local labels use `.L` prefix (e.g., `.Lmain_help`)
- Comment style: `//` line comments
- Section headers use `// ──────` visual separators
- Every exported function documents its register contract in a comment block
- Constants defined in `constants.inc` with `.set` directives

## Key Constraints

- Binary must stay under 32 KB (stripped release build)
- Peak RSS target: < 128 KB
- Startup target: < 0.1 ms (--help path)
- Zero runtime dependencies beyond libSystem and libcurl
- Apple Silicon only (ARM64, no x86 fallback)
- Config lives at `~/.assemblyclaw/config.json`

## Behavioral Spec

AssemblyClaw follows NullClaw's behavioral spec:
- Same CLI interface: `--help`, `--version`, `status`, `agent -m "..."`, `agent`
- Same config format (JSON with providers/api_key/model)
- Same provider API format (OpenAI-compatible chat completions)
- Exit 0 on success, exit 1 on error

## Working with Assembly

- Use `make debug` and `lldb ./build/assemblyclaw` for debugging
- When editing `.s` files, always preserve frame pointer setup (`stp x29, x30, [sp, ...]`)
- Register allocation is manual — check existing usage before claiming registers
- Test every change with `make test` — a single wrong offset breaks everything
- The `context/` directory has C and Zig reference implementations for behavioral guidance
