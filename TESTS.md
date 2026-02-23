# AssemblyClaw — Test Tracking

## Test Strategy

Tests are a mix of black-box binary checks and small C unit harnesses
linked against compiled object files.
The NullClaw Zig tests define the behavioral spec — AssemblyClaw must
produce compatible results for equivalent inputs.

## Test Categories

### 1. CLI Tests

| # | Test | Expected | Status |
|---|------|----------|--------|
| 1.1 | `assemblyclaw --help` | Print usage, exit 0 | [x] |
| 1.2 | `assemblyclaw --version` | Print version string, exit 0 | [x] |
| 1.3 | `assemblyclaw` (no args) | Print usage, exit 0 | [x] |
| 1.4 | `assemblyclaw badcommand` | "Unknown command", exit 1 | [x] |
| 1.5 | `assemblyclaw -h` | Same as --help | [x] |
| 1.6 | `assemblyclaw help` | Same as --help | [x] |

### 2. String Operations (Unit)

| # | Test | Expected | Status |
|---|------|----------|--------|
| 2.1 | strlen_simd("") | 0 | [x] |
| 2.2 | strlen_simd("hello") | 5 | [x] |
| 2.3 | strlen_simd(256-byte string) | 256 | [x] |
| 2.4 | strlen_simd(unaligned pointer) | correct length | [x] |
| 2.5 | strcmp_simd("abc", "abc") | 0 (equal) | [x] |
| 2.6 | strcmp_simd("abc", "abd") | negative | [x] |
| 2.7 | strcmp_simd("abd", "abc") | positive | [x] |
| 2.8 | strcmp_simd("", "") | 0 | [x] |
| 2.9 | memcpy_simd 16-byte aligned | exact copy | [x] |
| 2.10 | memcpy_simd 4KB block | exact copy | [x] |

### 3. Memory Allocator

| # | Test | Expected | Status |
|---|------|----------|--------|
| 3.1 | arena_init(64KB) | non-null arena | [x] |
| 3.2 | arena_alloc(arena, 16) | aligned pointer | [x] |
| 3.3 | arena_alloc fills page | auto-grows | [x] |
| 3.4 | arena_reset | resets to start | [x] |
| 3.5 | arena_destroy | munmap succeeds | [x] |

### 4. JSON Parser

| # | Test | Expected | Status |
|---|------|----------|--------|
| 4.1 | Parse empty object `{}` | success | [x] |
| 4.2 | Parse `{"key":"value"}` | key=key, val=value | [x] |
| 4.3 | Parse nested `{"a":{"b":1}}` | correct nesting | [x] |
| 4.4 | Parse array `[1,2,3]` | 3 elements | [x] |
| 4.5 | Parse string with escapes | token parsed without corruption | [x] |
| 4.6 | Parse numbers (int, float) | correct values | [x] |
| 4.7 | Parse booleans | true/false | [x] |
| 4.8 | Parse null | null token | [x] |
| 4.9 | Malformed JSON | handled safely (no crash) | [x] |
| 4.10 | Large config (~4KB) | parses correctly | [x] |

### 5. Config

| # | Test | Expected | Status |
|---|------|----------|--------|
| 5.1 | Load valid config.json | all fields populated | [x] |
| 5.2 | Missing config file | clear error message | [x] |
| 5.3 | Malformed JSON config | parse error | [x] |
| 5.4 | Missing required fields | validation error | [x] |
| 5.5 | Default values applied | defaults work | [x] |
| 5.6 | File-backed memory log | appends conversation entries | [x] |

### 6. HTTP Client

| # | Test | Expected | Status |
|---|------|----------|--------|
| 6.1 | POST request | 200 OK + body | [x] |
| 6.2 | POST with JSON body | correct Content-Type | [x] |
| 6.3 | Custom headers (Auth) | headers sent | [x] |
| 6.4 | Connection failure | error, not hang | [x] |
| 6.5 | Invalid URL | error returned | [x] |

### 7. Provider

| # | Test | Expected | Status |
|---|------|----------|--------|
| 7.1 | Build chat request JSON | valid OpenAI format | [x] |
| 7.2 | Parse chat response | extract content | [x] |
| 7.3 | Parse tool calls | extract tool name/args | [x] |
| 7.4 | Handle API error | error propagated | [x] |
| 7.5 | Handle rate limit | retry or error | [x] |

### 8. Agent

| # | Test | Expected | Status |
|---|------|----------|--------|
| 8.1 | Single message mode | sends and prints response | [x] |
| 8.2 | Status command | shows config summary | [x] |
| 8.3 | Empty message | error message | [x] |

### 9. Benchmarks

| # | Metric | Target | Measured | Status |
|---|--------|--------|----------|--------|
| 9.1 | Binary size | < 32 KB | 36.63 KB | [ ] |
| 9.2 | Peak RSS | < 128 KB | 5552 KB | [ ] |
| 9.3 | Startup (--help) | < 0.1 ms | 4.5 ms | [ ] |
| 9.4 | strlen 1KB string | < 100 ns | — | [ ] |
| 9.5 | JSON parse 4KB | < 10 us | — | [ ] |
| 9.6 | Config load | < 1 ms | — | [ ] |

## Running Tests

```bash
ninja test         # Run all tests
ninja bench        # Run benchmarks
```

`ninja test` now runs `bun tests/run.ts` and currently passes all functional checks (1.x–8.x).

## Compatibility with NullClaw Spec

AssemblyClaw follows the same behavioral spec as NullClaw:
- Same config format (~/.assemblyclaw/config.json mirrors ~/.nullclaw/config.json)
- Same CLI interface (agent, status, --help, --version)
- Same provider API format (OpenAI-compatible)
- Same error messages where applicable
