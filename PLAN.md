# AssemblyClaw — Implementation Plan

**The world's smallest and fastest AI agent infrastructure. Pure ARM64 assembly.**

## Vision

AssemblyClaw proves that once you have a spec, coding agents can write and maintain
even assembly language. It's a statement piece:

> TS first (get people using it) → Zig to harden (like Bun) → Assembly to flex.

The progression mirrors how production software should evolve:
1. **TypeScript** — fastest iteration, biggest community, get value shipped
2. **Zig** — zero overhead, zero compromise, single binary (what NullClaw does)
3. **Assembly** — absolute control, smallest binary, lowest latency (this project)

And looking ahead:
- **Bend** (HigherOrderCO) — automatic GPU parallelism, will change everything
- **Lean 4** — provably correct programs, zero bugs by construction
- **Zig** — the pragmatic middle ground that powers Bun

## Target Metrics

| Metric | NullClaw (Zig) | CClaw (C) | **AssemblyClaw (ARM64)** |
|--------|---------------|-----------|--------------------------|
| Binary Size | 678 KB | ~100 KB | **< 32 KB** |
| Peak RSS | ~1 MB | ~3 MB | **< 128 KB** |
| Startup | < 2 ms | < 5 ms | **< 0.1 ms** |
| Dependencies | libc + SQLite | curl, sqlite3 | **libSystem + libcurl** |
| Source Files | ~110 | ~40 | **~15** |

## Architecture

### M4/M5 Pro/Max ARM64 Optimizations

```
┌─────────────────────────────────────────────────────────────────────┐
│                    M4/M5 Pro Max CPU Utilization                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │  NEON SIMD       │    │  P-Core Cache    │    │  Branch Unit    │ │
│  │  128-bit vectors │    │  Large L1 cache  │    │  Wide decode    │ │
│  │  v0-v31 regs     │    │  Cache-line align│    │  Modern predict │ │
│  └────────┬─────────┘    └────────┬─────────┘    └────────┬────────┘│
│           │                       │                       │          │
│           ▼                       ▼                       ▼          │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    AssemblyClaw Optimizations                  │  │
│  ├───────────────────────────────────────────────────────────────┤  │
│  │  • strlen_simd: 16 bytes/cycle null scan (CMEQ+UMAXV)       │  │
│  │  • strcpy_simd: 16-byte LDR Q/STR Q block copies            │  │
│  │  • PRFM prefetch 256 bytes ahead (pldl1strm, pstl1strm)     │  │
│  │  • 128-byte cache line aligned data (.p2align 7)             │  │
│  │  • Branchless CSEL/CSETM conditional operations              │  │
│  │  • TBNZ single-bit branch tests for error checks             │  │
│  │  • 8KB buffer reads for memory bandwidth                     │  │
│  │  • Arena allocator with mmap (no malloc overhead)            │  │
│  │  • Zero-copy string views (ptr+len, no NUL termination)     │  │
│  │  • Direct syscalls via libSystem (no libc wrapper overhead)  │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Module Layout

```
src/
  main.s              Entry point, CLI argument dispatch
  string.s            NEON SIMD string operations
  memory.s            Arena allocator (mmap-backed)
  io.s                File I/O (read/write via libSystem)
  json.s              Zero-alloc JSON parser (streaming)
  http.s              HTTPS client (libcurl FFI wrapper)
  config.s            Config loader (~/.assemblyclaw/config.json)
  provider.s          LLM provider (Anthropic/OpenRouter API)
  agent.s             Agent loop (send message, get response, tools)
  error.s             Error codes and formatting
  version.s           Version string and build info

include/
  syscall.inc         macOS ARM64 syscall numbers
  neon.inc            NEON helper macros
  constants.inc       Buffer sizes, error codes, string constants
```

### Calling Convention (AAPCS64)

- x0-x7: function arguments and return values
- x8: indirect result location
- x9-x15: temporary registers (caller-saved)
- x16-x17: intra-procedure-call scratch (PLT)
- x18: platform register (reserved on macOS)
- x19-x28: callee-saved registers
- x29: frame pointer (FP)
- x30: link register (LR)
- sp: stack pointer (16-byte aligned)
- v0-v7: NEON argument/return registers
- v8-v15: callee-saved (lower 64 bits only)
- v16-v31: temporary NEON registers

### Data Layout Strategy

All structures aligned to cache line boundaries (128 bytes on M4):
- Arena blocks: 64KB pages via mmap
- String views: 16 bytes (8-byte ptr + 4-byte len + 4-byte cap)
- Config struct: single contiguous allocation
- JSON tokens: stack-allocated ring buffer (no heap)
- HTTP response: arena-allocated with recycling

## Phase Plan

### Phase 1: Foundation (GET IT WORKING)
- [x] Project structure and build system
- [x] PLAN.md, README.md, TESTS.md
- [x] `build.ninja` with release/debug targets
- [x] `bench.ts` benchmarking script
- [x] `main.s` — CLI entry, arg parsing, --help, --version
- [x] `string.s` — SIMD strlen, strcmp, strcpy, memcpy
- [x] `memory.s` — Arena allocator with mmap (+ auto-grow)
- [x] `io.s` — File read/write wrappers
- [x] `error.s` — Error codes and messages

### Phase 2: Config & JSON
- [x] `json.s` — Streaming JSON parser (zero-alloc)
- [x] `config.s` — Read ~/.assemblyclaw/config.json
- [x] Parse provider settings, API keys, model defaults

### Phase 3: HTTP & Provider
- [x] `http.s` — libcurl FFI (curl_easy_init, setopt, perform)
- [x] `provider.s` — Build OpenAI-compatible chat request JSON
- [x] `provider.s` — Parse streaming/non-streaming responses
- [x] Support: OpenRouter, Anthropic, OpenAI, DeepSeek

### Phase 4: Agent
- [x] `agent.s` — Single message mode (`agent -m "hello"`)
- [x] `agent.s` — Interactive mode (readline-style input)
- [x] `agent.s` — Conversation history (arena-allocated)
- [x] Basic status command

### Phase 5: Hardening
- [x] Tool call parsing and dispatch
- [x] Memory backend (file-based, minimal)
- [x] Config validation
- [x] Proper error propagation
- [x] Signal handling (SIGINT, SIGTERM)

### Phase 6: Performance Tuning
- [x] Profile with Instruments.app
- [x] Optimize hot paths with NEON
- [x] Prefetch tuning for M4/M5
- [x] Binary size optimization (strip, dead code elimination)
- [x] Startup time measurement and optimization

## Build System

```ninja
# Release: optimized + stripped
rule as
  command = clang -arch arm64 -c -o $out $in
rule link_strip
  command = clang -arch arm64 -lcurl -Wl,-dead_strip -o $out $in && strip -x $out

# Debug: symbols, no stripping
rule as_debug
  command = clang -arch arm64 -c -g -o $out $in
rule link_debug
  command = clang -arch arm64 -lcurl -o $out $in
```

## Testing Strategy

Tests run as a mix of black-box binary checks and small object-level unit harnesses:
1. CLI flag tests (--help, --version, unknown command)
2. Config parsing tests (valid JSON, missing fields, malformed)
3. String operation tests (via test harness linked against .o files)
4. HTTP mock tests (local server, verify request format)
5. Integration tests (real API call with test key)

The Zig tests in NullClaw define the behavioral spec. AssemblyClaw must produce
compatible output for the same inputs.

## Philosophy

> "Everyone complains about TypeScript using too much memory. But TS is critical
> because it's the fastest way to iterate and build community. Ship in TS first,
> get real users, then optimize. Zig is the best bet right now for hardening
> (Bun proves this). And sometimes you need assembly to prove a point."

This project proves that with AI coding agents, even assembly is possible —
and maybe even maintainable.
