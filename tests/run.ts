#!/usr/bin/env bun
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";

type Result = { id: string; name: string; pass: boolean; detail?: string };

const ROOT = process.cwd();
const BIN = join(ROOT, "build", "assemblyclaw");
const TEST_BIN_DIR = mkdtempSync(join(tmpdir(), "assemblyclaw-test-bin-"));

const NAMES: Record<string, string> = {
  "1.1": "--help prints usage",
  "1.2": "--version prints version",
  "1.3": "no args prints usage",
  "1.4": "unknown command exits 1",
  "1.5": "-h matches --help",
  "1.6": "help matches --help",
  "2.1": "strlen empty",
  "2.2": "strlen hello",
  "2.3": "strlen 256 bytes",
  "2.4": "strlen unaligned",
  "2.5": "strcmp equal",
  "2.6": "strcmp negative",
  "2.7": "strcmp positive",
  "2.8": "strcmp empty",
  "2.9": "memcpy 16-byte aligned",
  "2.10": "memcpy 4KB",
  "3.1": "arena_init",
  "3.2": "arena_alloc alignment",
  "3.3": "arena auto-grow",
  "3.4": "arena_reset",
  "3.5": "arena_destroy",
  "4.1": "parse empty object",
  "4.2": "parse key/value",
  "4.3": "parse nested object",
  "4.4": "parse array first object",
  "4.5": "parse escaped string token",
  "4.6": "parse numeric literal",
  "4.7": "parse booleans",
  "4.8": "parse null",
  "4.9": "malformed JSON handling",
  "4.10": "large config parse",
  "5.1": "load valid config",
  "5.2": "missing config handling",
  "5.3": "malformed config handling",
  "5.4": "missing required fields validation",
  "5.5": "default values applied",
  "6.1": "successful POST request",
  "6.2": "JSON content-type header",
  "6.3": "auth headers sent",
  "6.4": "connection failure returns error",
  "6.5": "invalid URL returns error",
  "7.1": "build OpenAI-compatible request JSON",
  "7.2": "parse chat response content",
  "7.3": "parse and execute tool calls",
  "7.4": "API error propagates",
  "7.5": "rate limit returns error",
  "8.1": "single message mode",
  "8.2": "status command",
  "8.3": "empty message error",
};

function decode(buf: Uint8Array | Buffer | null | undefined): string {
  if (!buf) return "";
  return new TextDecoder().decode(buf);
}

function runCmd(cmd: string[], env?: Record<string, string>) {
  const proc = Bun.spawnSync(cmd, {
    cwd: ROOT,
    env: { ...process.env, ...(env ?? {}) },
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    code: proc.exitCode,
    out: decode(proc.stdout),
    err: decode(proc.stderr),
  };
}

function runBinary(args: string[], home?: string) {
  const env = home ? { HOME: home } : undefined;
  return runCmd([BIN, ...args], env);
}

async function runBinaryAsync(args: string[], home?: string) {
  const proc = Bun.spawn([BIN, ...args], {
    cwd: ROOT,
    env: { ...process.env, ...(home ? { HOME: home } : {}) },
    stdout: "pipe",
    stderr: "pipe",
  });
  const [code, out, err] = await Promise.all([
    proc.exited,
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  return { code, out, err };
}

function makeHome(configObj?: unknown, rawConfig?: string) {
  const home = mkdtempSync(join(tmpdir(), "assemblyclaw-test-"));
  const cfgDir = join(home, ".assemblyclaw");
  mkdirSync(cfgDir, { recursive: true });
  if (rawConfig !== undefined) {
    writeFileSync(join(cfgDir, "config.json"), rawConfig, "utf8");
  } else if (configObj !== undefined) {
    writeFileSync(join(cfgDir, "config.json"), JSON.stringify(configObj, null, 2), "utf8");
  }
  return home;
}

async function withServer(
  responder: (
    req: IncomingMessage,
    body: Buffer,
    res: ServerResponse,
    state: { requests: Array<{ headers: IncomingMessage["headers"]; body: string; method: string }> }
  ) => void | Promise<void>,
  fn: (
    port: number,
    state: { requests: Array<{ headers: IncomingMessage["headers"]; body: string; method: string }> }
  ) => Promise<void>
) {
  const state = {
    requests: [] as Array<{ headers: IncomingMessage["headers"]; body: string; method: string }>,
  };

  const server = createServer(async (req, res) => {
    const chunks: Buffer[] = [];
    for await (const chunk of req) {
      chunks.push(Buffer.from(chunk));
    }
    const body = Buffer.concat(chunks);
    state.requests.push({
      headers: req.headers,
      body: body.toString("utf8"),
      method: req.method ?? "",
    });
    await responder(req, body, res, state);
  });

  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const addr = server.address() as AddressInfo;
  try {
    await fn(addr.port, state);
  } finally {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
}

function setMany(results: Result[], ids: string[], pass: boolean, detail?: string) {
  for (const id of ids) {
    results.push({ id, name: NAMES[id] ?? id, pass, detail });
  }
}

function sortId(a: string, b: string) {
  const [am, an] = a.split(".").map(Number);
  const [bm, bn] = b.split(".").map(Number);
  if (am !== bm) return am - bm;
  return an - bn;
}

const results: Result[] = [];

// ── 1. CLI Tests ─────────────────────────────────────────────────────────────
{
  const r11 = runBinary(["--help"]);
  results.push({
    id: "1.1",
    name: NAMES["1.1"],
    pass: r11.code === 0 && r11.out.includes("usage:"),
  });

  const r12 = runBinary(["--version"]);
  results.push({
    id: "1.2",
    name: NAMES["1.2"],
    pass: r12.code === 0 && r12.out.toLowerCase().includes("assemblyclaw"),
  });

  const r13 = runBinary([]);
  results.push({
    id: "1.3",
    name: NAMES["1.3"],
    pass: r13.code === 0 && r13.out.includes("usage:"),
  });

  const r14 = runBinary(["badcommand"]);
  results.push({
    id: "1.4",
    name: NAMES["1.4"],
    pass: r14.code === 1 && r14.err.includes("unknown command"),
  });

  const r15 = runBinary(["-h"]);
  results.push({
    id: "1.5",
    name: NAMES["1.5"],
    pass: r15.code === 0 && r15.out.includes("usage:"),
  });

  const r16 = runBinary(["help"]);
  results.push({
    id: "1.6",
    name: NAMES["1.6"],
    pass: r16.code === 0 && r16.out.includes("usage:"),
  });
}

// ── 2. String Unit Tests ─────────────────────────────────────────────────────
{
  const out = join(TEST_BIN_DIR, "unit_string");
  const c = runCmd(["clang", "-arch", "arm64", "-o", out, "tests/unit_string.c", "build/string.o"]);
  const ok = c.code === 0 && runCmd([out]).code === 0;
  setMany(results, ["2.1", "2.2", "2.3", "2.4", "2.5", "2.6", "2.7", "2.8", "2.9", "2.10"], ok, c.err.trim());
}

// ── 3. Memory Unit Tests ─────────────────────────────────────────────────────
{
  const out = join(TEST_BIN_DIR, "unit_memory");
  const c = runCmd([
    "clang",
    "-arch",
    "arm64",
    "-o",
    out,
    "tests/unit_memory.c",
    "build/memory.o",
    "build/string.o",
  ]);
  const ok = c.code === 0 && runCmd([out]).code === 0;
  setMany(results, ["3.1", "3.2", "3.3", "3.4", "3.5"], ok, c.err.trim());
}

// ── 4. JSON Unit Tests ───────────────────────────────────────────────────────
{
  const out = join(TEST_BIN_DIR, "unit_json");
  const c = runCmd(["clang", "-arch", "arm64", "-o", out, "tests/unit_json.c", "build/json.o", "build/string.o"]);
  const ok = c.code === 0 && runCmd([out]).code === 0;
  setMany(results, ["4.1", "4.2", "4.3", "4.4", "4.5", "4.6", "4.7", "4.8", "4.9", "4.10"], ok, c.err.trim());
}

// ── 5. Config Tests ──────────────────────────────────────────────────────────
{
  const homeValid = makeHome({
    default_provider: "openai",
    providers: {
      openai: {
        api_key: "sk-test",
        model: "gpt-4o-mini",
        base_url: "https://api.openai.com/v1/chat/completions",
      },
    },
  });
  const r51 = runBinary(["status"], homeValid);
  results.push({
    id: "5.1",
    name: NAMES["5.1"],
    pass: r51.code === 0 && r51.out.includes("config:   loaded"),
  });

  const homeMissing = mkdtempSync(join(tmpdir(), "assemblyclaw-test-"));
  const r52 = runBinary(["status"], homeMissing);
  let autoCreatedTemplate = false;
  try {
    const generated = readFileSync(join(homeMissing, ".assemblyclaw", "config.json"), "utf8");
    autoCreatedTemplate = generated.includes("\"default_provider\": \"openrouter\"");
  } catch {
    autoCreatedTemplate = false;
  }
  results.push({
    id: "5.2",
    name: NAMES["5.2"],
    pass: r52.code === 0 && r52.out.includes("not configured") && autoCreatedTemplate,
  });

  const homeMalformed = makeHome(undefined, "not-json");
  const r53 = runBinary(["status"], homeMalformed);
  results.push({
    id: "5.3",
    name: NAMES["5.3"],
    pass: r53.code === 0 && r53.out.includes("not configured"),
  });

  const homeMissingFields = makeHome({
    default_provider: "openai",
    providers: { openai: { model: "gpt-4o-mini" } },
  });
  const r54 = runBinary(["agent", "-m", "hello"], homeMissingFields);
  results.push({
    id: "5.4",
    name: NAMES["5.4"],
    pass: r54.code === 1 && r54.err.includes("could not load config"),
  });

  const homeDefaults = makeHome({
    default_provider: "openai",
    providers: { openai: { api_key: "sk-test" } },
  });
  const r55 = runBinary(["status"], homeDefaults);
  results.push({
    id: "5.5",
    name: NAMES["5.5"],
    pass:
      r55.code === 0 &&
      r55.out.includes("provider: openai") &&
      r55.out.includes("model:    gpt-4.1-mini"),
  });
}

// ── 6 / 7 / 8 Integration Tests ────────────────────────────────────────────
let openaiReqBody: any = null;
let t61 = false;
let t62 = false;
let t71 = false;
let t72 = false;
let t81 = false;
await withServer(
  async (_req, _body, res) => {
    const body = JSON.stringify({
      choices: [{ message: { role: "assistant", content: "ok-provider" } }],
    });
    res.statusCode = 200;
    res.setHeader("Content-Type", "application/json");
    res.setHeader("Content-Length", String(Buffer.byteLength(body)));
    res.end(body);
  },
  async (port, state) => {
    const home = makeHome({
      default_provider: "openai",
      providers: {
        openai: {
          api_key: "sk-test",
          model: "gpt-4o-mini",
          base_url: `http://127.0.0.1:${port}/v1/chat/completions`,
        },
      },
    });
    const res = await runBinaryAsync(["agent", "-m", "hello"], home);
    const req = state.requests[0];
    openaiReqBody = req ? JSON.parse(req.body) : null;
    t61 = res.code === 0 && res.out.trim() === "ok-provider" && req?.method === "POST";
    t62 = !!req && String(req.headers["content-type"] || "").includes("application/json");
    t71 =
      !!openaiReqBody &&
      openaiReqBody.model === "gpt-4o-mini" &&
      Array.isArray(openaiReqBody.messages) &&
      openaiReqBody.messages[0]?.role === "user" &&
      Array.isArray(openaiReqBody.tools) &&
      openaiReqBody.tool_choice === "auto";
    t72 = res.code === 0 && res.out.trim() === "ok-provider";
    t81 = res.code === 0 && res.out.trim() === "ok-provider";
  }
);
results.push({ id: "6.1", name: NAMES["6.1"], pass: t61 });
results.push({ id: "6.2", name: NAMES["6.2"], pass: t62 });
results.push({ id: "7.1", name: NAMES["7.1"], pass: t71 });
results.push({ id: "7.2", name: NAMES["7.2"], pass: t72 });
results.push({ id: "8.1", name: NAMES["8.1"], pass: t81 });

// 6.3 Anthropic auth headers
let t63 = false;
await withServer(
  async (_req, _body, res) => {
    const body = JSON.stringify({
      content: [{ type: "text", text: "ok-anth" }],
      stop_reason: "end_turn",
    });
    res.statusCode = 200;
    res.setHeader("Content-Type", "application/json");
    res.setHeader("Content-Length", String(Buffer.byteLength(body)));
    res.end(body);
  },
  async (port, state) => {
    const home = makeHome({
      default_provider: "anthropic",
      providers: {
        anthropic: {
          api_key: "test-key",
          model: "claude-sonnet-4-20250514",
          base_url: `http://127.0.0.1:${port}/v1/messages`,
        },
      },
    });
    const res = await runBinaryAsync(["agent", "-m", "hello"], home);
    const req = state.requests[0];
    t63 =
      res.code === 0 &&
      !!req &&
      String(req.headers["x-api-key"] || "") === "test-key" &&
      String(req.headers["anthropic-version"] || "") === "2023-06-01";
  }
);
results.push({ id: "6.3", name: NAMES["6.3"], pass: t63 });

// 6.4 / 6.5 connection and URL errors
{
  const homeConnErr = makeHome({
    default_provider: "openai",
    providers: {
      openai: {
        api_key: "sk-test",
        model: "gpt-4o-mini",
        base_url: "http://127.0.0.1:9/v1/chat/completions",
      },
    },
  });
  const r64 = runBinary(["agent", "-m", "hello"], homeConnErr);
  results.push({
    id: "6.4",
    name: NAMES["6.4"],
    pass: r64.code === 1 && r64.err.includes("HTTP request failed"),
  });

  const homeBadUrl = makeHome({
    default_provider: "openai",
    providers: {
      openai: {
        api_key: "sk-test",
        model: "gpt-4o-mini",
        base_url: "http://",
      },
    },
  });
  const r65 = runBinary(["agent", "-m", "hello"], homeBadUrl);
  results.push({
    id: "6.5",
    name: NAMES["6.5"],
    pass: r65.code === 1 && r65.err.includes("HTTP request failed"),
  });
}

// 7.3 tool-calls
let t73 = false;
await withServer(
  async (_req, _body, res, state) => {
    const n = state.requests.length;
    const payload =
      n === 1
        ? {
            choices: [
              {
                message: {
                  role: "assistant",
                  tool_calls: [
                    {
                      id: "call_1",
                      type: "function",
                      function: { name: "status", arguments: "{}" },
                    },
                  ],
                },
              },
            ],
          }
        : { choices: [{ message: { role: "assistant", content: "tool-finished" } }] };
    const body = JSON.stringify(payload);
    res.statusCode = 200;
    res.setHeader("Content-Type", "application/json");
    res.setHeader("Content-Length", String(Buffer.byteLength(body)));
    res.end(body);
  },
  async (port, state) => {
    const home = makeHome({
      default_provider: "openai",
      providers: {
        openai: {
          api_key: "sk-test",
          model: "gpt-4o-mini",
          base_url: `http://127.0.0.1:${port}/v1/chat/completions`,
        },
      },
    });
    const res = await runBinaryAsync(["agent", "-m", "hello"], home);
    const req2 = state.requests[1];
    const body2 = req2 ? JSON.parse(req2.body) : null;
    const hasToolResult =
      !!body2 &&
      Array.isArray(body2.messages) &&
      body2.messages.some((m: any) =>
        typeof m?.content === "string"
          ? m.content.includes("status: provider=openai model=gpt-4o-mini")
          : false
      );
    t73 = res.code === 0 && res.out.trim() === "tool-finished" && state.requests.length === 2 && hasToolResult;
  }
);
results.push({ id: "7.3", name: NAMES["7.3"], pass: t73 });

// 7.4 API error propagation
let t74 = false;
await withServer(
  async (_req, _body, res) => {
    const body = JSON.stringify({ error: { message: "server error" } });
    res.statusCode = 500;
    res.setHeader("Content-Type", "application/json");
    res.setHeader("Content-Length", String(Buffer.byteLength(body)));
    res.end(body);
  },
  async (port) => {
    const home = makeHome({
      default_provider: "openai",
      providers: {
        openai: {
          api_key: "sk-test",
          model: "gpt-4o-mini",
          base_url: `http://127.0.0.1:${port}/v1/chat/completions`,
        },
      },
    });
    const res = await runBinaryAsync(["agent", "-m", "hello"], home);
    t74 = res.code === 1 && res.err.includes("HTTP request failed");
  }
);
results.push({ id: "7.4", name: NAMES["7.4"], pass: t74 });

// 7.5 rate limit handling (error path)
let t75 = false;
await withServer(
  async (_req, _body, res) => {
    const body = JSON.stringify({ error: { message: "rate limited" } });
    res.statusCode = 429;
    res.setHeader("Content-Type", "application/json");
    res.setHeader("Content-Length", String(Buffer.byteLength(body)));
    res.end(body);
  },
  async (port) => {
    const home = makeHome({
      default_provider: "openai",
      providers: {
        openai: {
          api_key: "sk-test",
          model: "gpt-4o-mini",
          base_url: `http://127.0.0.1:${port}/v1/chat/completions`,
        },
      },
    });
    const res = await runBinaryAsync(["agent", "-m", "hello"], home);
    t75 = res.code === 1 && res.err.includes("HTTP request failed");
  }
);
results.push({ id: "7.5", name: NAMES["7.5"], pass: t75 });

// 8.2 status command and 8.3 empty message
{
  const home = makeHome({
    default_provider: "openai",
    providers: {
      openai: {
        api_key: "sk-test",
        model: "gpt-4o-mini",
        base_url: "https://api.openai.com/v1/chat/completions",
      },
    },
  });
  const r82 = runBinary(["status"], home);
  results.push({
    id: "8.2",
    name: NAMES["8.2"],
    pass: r82.code === 0 && r82.out.includes("assemblyclaw status"),
  });

  const r83 = runBinary(["agent", "-m"], home);
  results.push({
    id: "8.3",
    name: NAMES["8.3"],
    pass: r83.code === 1 && r83.err.includes("requires a message argument"),
  });
}

// memory backend smoke check (not in TESTS.md table): ensure log gets written.
{
  let memoryLogOk = false;
  await withServer(
    async (_req, _body, res) => {
      const body = JSON.stringify({
        choices: [{ message: { role: "assistant", content: "persist-check" } }],
      });
      res.statusCode = 200;
      res.setHeader("Content-Type", "application/json");
      res.setHeader("Content-Length", String(Buffer.byteLength(body)));
      res.end(body);
    },
    async (port) => {
      const home = makeHome({
        default_provider: "openai",
        providers: {
          openai: {
            api_key: "sk-test",
            model: "gpt-4o-mini",
            base_url: `http://127.0.0.1:${port}/v1/chat/completions`,
          },
        },
      });
      const r = await runBinaryAsync(["agent", "-m", "persist-me"], home);
      if (r.code !== 0) return;
      const logPath = join(home, ".assemblyclaw", "memory.log");
      const log = readFileSync(logPath, "utf8");
      memoryLogOk = log.includes("user\tpersist-me") && log.includes("assistant\tpersist-check");
    }
  );
  results.push({
    id: "5.6",
    name: "file-based memory backend appends history",
    pass: memoryLogOk,
  });
}

// ── Report ───────────────────────────────────────────────────────────────────
const sorted = [...results].sort((a, b) => sortId(a.id, b.id));
let passCount = 0;
for (const r of sorted) {
  const tag = r.pass ? "PASS" : "FAIL";
  if (r.pass) passCount++;
  const detail = r.detail ? ` (${r.detail})` : "";
  console.log(`${tag} ${r.id.padEnd(4)} ${r.name}${detail}`);
}

const failCount = sorted.length - passCount;
console.log(`\nSummary: ${passCount}/${sorted.length} passing`);

if (failCount > 0) process.exit(1);
