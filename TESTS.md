# AssemblyClaw — Test Tracking

## Test Strategy

Tests are black-box: they run the compiled binary and verify outputs.
The NullClaw Zig tests define the behavioral spec — AssemblyClaw must
produce compatible results for equivalent inputs.

## Test Categories

### 1. CLI Tests

| # | Test | Expected | Status |
|---|------|----------|--------|
| 1.1 | `assemblyclaw --help` | Print usage, exit 0 | [ ] |
| 1.2 | `assemblyclaw --version` | Print version string, exit 0 | [ ] |
| 1.3 | `assemblyclaw` (no args) | Print usage, exit 0 | [ ] |
| 1.4 | `assemblyclaw badcommand` | "Unknown command", exit 1 | [ ] |
| 1.5 | `assemblyclaw -h` | Same as --help | [ ] |
| 1.6 | `assemblyclaw help` | Same as --help | [ ] |

### 2. String Operations (Unit)

| # | Test | Expected | Status |
|---|------|----------|--------|
| 2.1 | strlen_simd("") | 0 | [ ] |
| 2.2 | strlen_simd("hello") | 5 | [ ] |
| 2.3 | strlen_simd(256-byte string) | 256 | [ ] |
| 2.4 | strlen_simd(unaligned pointer) | correct length | [ ] |
| 2.5 | strcmp_simd("abc", "abc") | 0 (equal) | [ ] |
| 2.6 | strcmp_simd("abc", "abd") | negative | [ ] |
| 2.7 | strcmp_simd("abd", "abc") | positive | [ ] |
| 2.8 | strcmp_simd("", "") | 0 | [ ] |
| 2.9 | memcpy_simd 16-byte aligned | exact copy | [ ] |
| 2.10 | memcpy_simd 4KB block | exact copy | [ ] |

### 3. Memory Allocator

| # | Test | Expected | Status |
|---|------|----------|--------|
| 3.1 | arena_init(64KB) | non-null arena | [ ] |
| 3.2 | arena_alloc(arena, 16) | aligned pointer | [ ] |
| 3.3 | arena_alloc fills page | auto-grows | [ ] |
| 3.4 | arena_reset | resets to start | [ ] |
| 3.5 | arena_destroy | munmap succeeds | [ ] |

### 4. JSON Parser

| # | Test | Expected | Status |
|---|------|----------|--------|
| 4.1 | Parse empty object `{}` | success | [ ] |
| 4.2 | Parse `{"key":"value"}` | key=key, val=value | [ ] |
| 4.3 | Parse nested `{"a":{"b":1}}` | correct nesting | [ ] |
| 4.4 | Parse array `[1,2,3]` | 3 elements | [ ] |
| 4.5 | Parse string with escapes | unescaped correctly | [ ] |
| 4.6 | Parse numbers (int, float) | correct values | [ ] |
| 4.7 | Parse booleans | true/false | [ ] |
| 4.8 | Parse null | null token | [ ] |
| 4.9 | Malformed JSON | error returned | [ ] |
| 4.10 | Large config (~4KB) | parses correctly | [ ] |

### 5. Config

| # | Test | Expected | Status |
|---|------|----------|--------|
| 5.1 | Load valid config.json | all fields populated | [ ] |
| 5.2 | Missing config file | clear error message | [ ] |
| 5.3 | Malformed JSON config | parse error | [ ] |
| 5.4 | Missing required fields | validation error | [ ] |
| 5.5 | Default values applied | defaults work | [ ] |

### 6. HTTP Client

| # | Test | Expected | Status |
|---|------|----------|--------|
| 6.1 | GET request | 200 OK + body | [ ] |
| 6.2 | POST with JSON body | correct Content-Type | [ ] |
| 6.3 | Custom headers (Auth) | headers sent | [ ] |
| 6.4 | Connection timeout | error, not hang | [ ] |
| 6.5 | Invalid URL | error returned | [ ] |

### 7. Provider

| # | Test | Expected | Status |
|---|------|----------|--------|
| 7.1 | Build chat request JSON | valid OpenAI format | [ ] |
| 7.2 | Parse chat response | extract content | [ ] |
| 7.3 | Parse tool calls | extract tool name/args | [ ] |
| 7.4 | Handle API error | error propagated | [ ] |
| 7.5 | Handle rate limit | retry or error | [ ] |

### 8. Agent

| # | Test | Expected | Status |
|---|------|----------|--------|
| 8.1 | Single message mode | sends and prints response | [ ] |
| 8.2 | Status command | shows config summary | [ ] |
| 8.3 | Empty message | error message | [ ] |

### 9. Benchmarks

| # | Metric | Target | Measured | Status |
|---|--------|--------|----------|--------|
| 9.1 | Binary size | < 32 KB | — | [ ] |
| 9.2 | Peak RSS | < 128 KB | — | [ ] |
| 9.3 | Startup (--help) | < 0.1 ms | — | [ ] |
| 9.4 | strlen 1KB string | < 100 ns | — | [ ] |
| 9.5 | JSON parse 4KB | < 10 us | — | [ ] |
| 9.6 | Config load | < 1 ms | — | [ ] |

## Running Tests

```bash
make test          # Run all tests
./bench.sh         # Run benchmarks
```

## Compatibility with NullClaw Spec

AssemblyClaw follows the same behavioral spec as NullClaw:
- Same config format (~/.assemblyclaw/config.json mirrors ~/.nullclaw/config.json)
- Same CLI interface (agent, status, --help, --version)
- Same provider API format (OpenAI-compatible)
- Same error messages where applicable
