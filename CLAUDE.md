# AssemblyClaw

Pure ARM64 assembly AI agent infrastructure for Apple Silicon (macOS).

## Build & Test

```bash
ninja              # Release build (optimized, stripped)
ninja debug        # Debug build (with symbols)
ninja test         # Black-box CLI tests
ninja bench        # Full benchmark suite
ninja -t clean     # Remove build outputs
```

Requires: macOS on Apple Silicon + Ninja + Xcode Command Line Tools. No other dependencies.

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
build.ninja           Ninja build configuration
build/                Compiled .o and final binary
Formula/              Homebrew tap formula
site/                 Landing page (Vite + Bun)
context/              Reference implementations (CClaw in C, NullClaw in Zig)
bench.sh              Benchmark script (size, RAM, startup)
PLAN.md               Implementation phases and architecture notes
TESTS.md              Test matrix tracking
```

## Site (Landing Page)

The `site/` directory is a Vite project managed exclusively with **Bun**. Do not use npm.

```bash
cd site
bun install           # Install dependencies (uses bun.lock)
bun run dev           # Dev server
bun run build         # Production build → site/dist/
bun run preview       # Preview production build
```

- Lock file: `bun.lock` (never generate package-lock.json)
- CI uses `oven-sh/setup-bun@v2` in GitHub Actions
- Deployed to GitHub Pages via `.github/workflows/deploy.yml`

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

## Scripting Rules

All `.ts` scripts in this repo run under **Bun** and must use Bun-native APIs exclusively.

**Required:**
- `Bun.file(path).text()` / `Bun.file(path).json()` — read files
- `Bun.file(path).exists()` — check file existence
- `Bun.file(path).size` — file size in bytes
- `Bun.write(path, data)` — write files
- `Bun.serve({ port, fetch })` — HTTP servers (fetch-handler pattern)
- `Bun.spawn()` / `Bun.spawnSync()` — subprocesses
- `Bun.env` — environment variables (not `process.env`)
- `Bun.argv` — CLI arguments
- `$` from `"bun"` — shell commands (Bun Shell)
- `join` from `"node:path"` — path manipulation (Bun supports this natively)

**Forbidden:**
- `node:fs` — no `readFileSync`, `writeFileSync`, `existsSync`, `statSync`, `mkdirSync`, `mkdtempSync`, `rmSync`
- `node:os` — no `tmpdir()`
- `node:http` / `node:net` — no `createServer`
- `process.env` — use `Bun.env` instead

For directory operations use `$` shell: `await $\`mkdir -p ${dir}\``, `await $\`rm -rf ${dir}\``.

## Release & Changelog

**Every meaningful change** must add an entry to `CHANGELOG.md` under `## Unreleased`:
- New features, bug fixes, refactors, build changes, dependency updates
- One bullet per change, concise description
- Skip trivial whitespace/comment-only changes

**Version bump workflow:**

```bash
bun version.ts patch      # 0.1.0 → 0.1.1
bun version.ts minor      # 0.1.0 → 0.2.0
bun version.ts major      # 0.1.0 → 1.0.0
```

This script:
1. Bumps version in `include/constants.inc` and `src/version.s`
2. Replaces `## Unreleased` in `CHANGELOG.md` with `## vX.Y.Z (date)`
3. Git commits + tags `vX.Y.Z`

**Release:**
```bash
git push && git push --tags
```

The CI workflow (`.github/workflows/release.yml`) then:
- Creates a GitHub Release with the `assemblyclaw-macos-arm64` binary
- Computes SHA256 of the source tarball
- Auto-updates `Formula/assemblyclaw.rb` with the new version + hash

**Version lives in 3 places** (the script keeps them in sync):
- `include/constants.inc` — `.set VERSION_MAJOR/MINOR/PATCH`
- `src/version.s` — string literals (`"X.Y.Z"` and full version string)

## Working with Assembly

- Use `ninja debug` and `lldb ./build/debug/assemblyclaw` for debugging
- When editing `.s` files, always preserve frame pointer setup (`stp x29, x30, [sp, ...]`)
- Register allocation is manual — check existing usage before claiming registers
- Test every change with `ninja test` — a single wrong offset breaks everything
- The `context/` directory has C and Zig reference implementations for behavioral guidance
