# AssemblyClaw — Test Tracking

## Test Strategy

`ninja test` runs `bun tests/run.ts`, which executes:
- CLI behavior checks
- C unit harnesses for string/memory/json objects
- Config loading scenarios
- HTTP/provider integration via local Bun test servers
- Agent/tool-call execution paths

## Test Categories

### 1. CLI Tests

| # | Test | Expected | Status |
|---|---|---|---|
| 1.1 | `assemblyclaw --help` | Prints usage, exit 0 | [x] |
| 1.2 | `assemblyclaw --version` | Prints version, exit 0 | [x] |
| 1.3 | `assemblyclaw` (no args) | Prints usage, exit 0 | [x] |
| 1.4 | `assemblyclaw badcommand` | Error, exit 1 | [x] |
| 1.5 | `assemblyclaw -h` | Same as `--help` | [x] |
| 1.6 | `assemblyclaw help` | Same as `--help` | [x] |

### 2. String Unit Tests

| # | Test | Expected | Status |
|---|---|---|---|
| 2.1 | `strlen_simd("")` | `0` | [x] |
| 2.2 | `strlen_simd("hello")` | `5` | [x] |
| 2.3 | `strlen_simd(256-byte)` | `256` | [x] |
| 2.4 | unaligned strlen pointer | correct length | [x] |
| 2.5 | `strcmp_simd("abc","abc")` | `0` | [x] |
| 2.6 | `strcmp_simd("abc","abd")` | negative | [x] |
| 2.7 | `strcmp_simd("abd","abc")` | positive | [x] |
| 2.8 | `strcmp_simd("","")` | `0` | [x] |
| 2.9 | `memcpy_simd` aligned | exact copy | [x] |
| 2.10 | `memcpy_simd` 4KB | exact copy | [x] |

### 3. Memory Allocator

| # | Test | Expected | Status |
|---|---|---|---|
| 3.1 | `arena_init(64KB)` | success | [x] |
| 3.2 | `arena_alloc(16)` | aligned pointer | [x] |
| 3.3 | arena growth | succeeds | [x] |
| 3.4 | `arena_reset` | offset reset | [x] |
| 3.5 | `arena_destroy` | cleanup succeeds | [x] |

### 4. JSON Parser

| # | Test | Expected | Status |
|---|---|---|---|
| 4.1 | parse `{}` | success | [x] |
| 4.2 | parse key/value | expected token | [x] |
| 4.3 | parse nested object | expected nesting | [x] |
| 4.4 | parse array | expected first object | [x] |
| 4.5 | escaped string token | no corruption | [x] |
| 4.6 | numeric literal parse | correct token | [x] |
| 4.7 | boolean parse | true/false tokens | [x] |
| 4.8 | null parse | null token | [x] |
| 4.9 | malformed JSON | handled safely | [x] |
| 4.10 | large config (~4KB) | parses correctly | [x] |

### 5. Config

| # | Test | Expected | Status |
|---|---|---|---|
| 5.1 | valid config | loaded | [x] |
| 5.2 | missing config file | bootstrap + not-configured output | [x] |
| 5.3 | malformed config | handled | [x] |
| 5.4 | missing required fields | validation failure on use | [x] |
| 5.5 | defaults applied | provider/model defaults in status | [x] |
| 5.6 | memory log append | user/assistant entries persisted | [x] |
| 5.7 | env provider/key fallback | provider selected from env | [x] |

### 6. HTTP Client

| # | Test | Expected | Status |
|---|---|---|---|
| 6.1 | POST request | 200 + body parsed | [x] |
| 6.2 | JSON content-type | header sent | [x] |
| 6.3 | auth headers | provider headers sent | [x] |
| 6.4 | connection failure | error returned | [x] |
| 6.5 | invalid URL | error returned | [x] |

### 7. Provider

| # | Test | Expected | Status |
|---|---|---|---|
| 7.1 | request JSON build | OpenAI-compatible payload | [x] |
| 7.2 | response parse | assistant content extracted | [x] |
| 7.3 | tool-call handling | tool parsed + executed | [x] |
| 7.4 | API error path | error propagated | [x] |
| 7.5 | rate-limit path | error propagated | [x] |

### 8. Agent

| # | Test | Expected | Status |
|---|---|---|---|
| 8.1 | single message mode | response printed | [x] |
| 8.2 | status command | config summary printed | [x] |
| 8.3 | empty message arg | usage error | [x] |

### 9. Benchmarks

| # | Metric | Target | Measured | Status |
|---|---|---|---|---|
| 9.1 | Binary size | `< 32 KB` | `35.19 KB` | [ ] |
| 9.2 | Peak RSS | `< 128 KB` | `1312 KB` | [ ] |
| 9.3 | Startup (`--help`) | `< 0.1 ms` | `4.468 ms` | [ ] |
| 9.4 | `strlen` kernel speedup | scalar baseline | `14.99x` | [x] |
| 9.5 | `json_find_key` kernel speedup | scalar baseline | `1.82x` | [x] |

Benchmark run conditions (from `site/public/benchmarks.json`):
- Date (UTC): `2026-02-23T22:37:59.338Z`
- Machine: `Mac16,5` (`Apple M4 Max`, `64 GB RAM`)
- OS: `macOS 26.3` (`25D125`)
- Tooling: `hyperfine 1.20.0`, `/usr/bin/time -l`

## Running Tests

```bash
ninja test
ninja bench
```

Current local test run: `51/51` passing (`ninja test`).
