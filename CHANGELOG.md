# Changelog

## Unreleased

- Docs/LP fact-check pass: synchronized benchmark numbers with `site/public/benchmarks.json` and clarified dependency/runtime wording (`libSystem` link + runtime `libcurl` for HTTP).
- Restored brand line wording: "The world's smallest AI agent infrastructure" across LP title/hero, README, CLI help banner, and formula description.
- Restored story-first narrative copy in README and LP future/author sections.

## v0.1.1 (2026-02-23)

## v0.1.0 (2025-02-24)

Initial release — pure ARM64 assembly AI agent infrastructure for Apple Silicon.

- CLI: `--help`, `--version`, `status`, `agent -m "..."`, `agent`
- NEON SIMD string operations (16 bytes/cycle)
- Zero-allocation streaming JSON parser
- Arena allocator (mmap-backed, zero fragmentation)
- HTTPS via libcurl FFI
- Config at `~/.assemblyclaw/config.json`
- Provider support: OpenRouter, Anthropic, OpenAI
- Agent loop with conversation history and tool calls
- Homebrew tap: `brew install gunta/assemblyclaw/assemblyclaw`
- Landing page deployed to GitHub Pages
- Benchmark suite with comparator automation (`bun bench.ts`)
- Test suite with 40+ black-box tests (`ninja test`)
