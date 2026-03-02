# AssemblyClaw

Pure ARM64 assembly AI agent infrastructure for macOS on Apple Silicon.

## Build & Test

```bash
ninja              # Release build (optimized, stripped)
ninja debug        # Debug build (with symbols)
ninja test         # Full test suite (bun tests/run.ts)
ninja bench        # Benchmark suite (bun bench.ts)
ninja -t clean     # Remove build outputs
```

Requires: macOS on Apple Silicon + Ninja + Xcode Command Line Tools.

Notes:
- Runtime links against libSystem.
- HTTP path loads system libcurl dynamically at runtime.

## Project Structure

```text
src/                  ARM64 assembly source (.s files)
  main.s              CLI entry point and argument dispatch
  string.s            NEON SIMD string operations
  memory.s            Arena allocator (mmap-backed)
  io.s                File I/O wrappers
  json.s              Streaming JSON parser helpers
  http.s              HTTPS client (libcurl via dlopen/dlsym)
  config.s            Config reader (~/.assemblyclaw/config.json)
  provider.s          Provider request/response logic
  agent.s             Agent loop with history + tool calls
  error.s             Error codes and messages
  version.s           Version and build metadata
include/
  constants.inc       Buffer sizes, error codes, curl/mmap constants
  syscall.inc         macOS ARM64 syscall numbers (reference)
build.ninja           Ninja build configuration
bench.ts              Benchmark script + JSON export
tests/                Test harnesses and integration tests
site/                 Landing page (Vite + Bun)
Formula/              Homebrew formula
context/              Comparator/reference projects
```

## Site (Landing Page)

The `site/` directory is a Vite project managed with Bun.

```bash
cd site
bun install
bun run dev
bun run build
bun run preview
```

- Lock file: `bun.lock`
- CI setup: `oven-sh/setup-bun@v2`
- Deploy: `.github/workflows/deploy.yml`

## Architecture Rules

- AAPCS64 calling convention (x0-x7 args, x19-x28 callee-saved)
- `sp` 16-byte aligned at call boundaries
- Function entry points generally use `.p2align 4`; constants commonly use `.p2align 3`
- Arena allocator only (mmap-backed, no malloc/free in project code)
- Prefer branch-efficient code paths (`csel` where useful)
- Keep hot string paths SIMD-capable (`CMEQ` + `UMAXV` patterns in `string.s`)
- Preserve clear register-contract comments on exported functions

## Key Constraints

- Keep stripped binary as small as possible (target `< 32 KB`)
- Peak RSS target `< 128 KB`
- Startup target `< 0.1 ms` on `--help`
- macOS Apple Silicon only (no x86 fallback)
- Config path: `~/.assemblyclaw/config.json`

## Behavioral Spec

- CLI: `--help`, `--version`, `status`, `agent -m "..."`, `agent`
- Config-driven provider selection and model/base URL resolution
- OpenAI-compatible and Anthropic request handling
- Exit code `0` on success, `1` on user/runtime error paths

## Scripting Rules

All `.ts` scripts run with Bun and should use Bun-native APIs.

Required:
- `Bun.file(...).text()/json()/exists()/size`
- `Bun.write(...)`
- `Bun.spawn()/Bun.spawnSync()`
- `Bun.serve({ fetch })`
- `Bun.env`, `Bun.argv`
- `$` from `bun`
- `join` from `node:path`

Avoid Node built-ins for fs/os/http workflows when Bun-native APIs cover the same operation.

## Release & Changelog

Every meaningful change should add an entry under `## Unreleased` in `CHANGELOG.md`.

Version bump helper:

```bash
bun version.ts patch|minor|major
```

This updates:
- `include/constants.inc`
- `src/version.s`
- `CHANGELOG.md`

Release flow:

```bash
git push && git push --tags
```

`release.yml` then builds, creates a release artifact, and updates `Formula/assemblyclaw.rb` URL/SHA.
