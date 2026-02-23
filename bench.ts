#!/usr/bin/env bun
// AssemblyClaw Benchmark Suite
// Requires: hyperfine (brew install hyperfine)
//
// Usage:
//   bun bench.ts              Full suite
//   bun bench.ts --quick      Timing only (skip static analysis)
//   bun bench.ts --export     Full suite + JSON export

import { $ } from "bun";
import { existsSync, statSync } from "node:fs";

// ── Config ──────────────────────────────────────────────

const BINARY = "./build/assemblyclaw";
const BENCH_JSON = "./build/bench.json";

const targets = { binaryKB: 32, rssKB: 128, startupMs: 0.1 } as const;

const comparisons = {
  nullclaw: { name: "NullClaw (Zig)", sizeKB: 678 },
  cclaw: { name: "CClaw (C)", sizeKB: 100 },
} as const;

// ── CLI flags ───────────────────────────────────────────

const quick = Bun.argv.includes("--quick");
const doExport = Bun.argv.includes("--export");

// ── ANSI formatting ─────────────────────────────────────

const bold = (s: string) => `\x1b[1m${s}\x1b[0m`;
const green = (s: string) => `\x1b[32m${s}\x1b[0m`;
const yellow = (s: string) => `\x1b[33m${s}\x1b[0m`;
const cyan = (s: string) => `\x1b[36m${s}\x1b[0m`;
const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;

const section = (t: string) => console.log(`\n${cyan(`── ${t} ──`)}`);
const metric = (l: string, v: string) =>
  console.log(`  ${l.padEnd(30)} ${green(v)}`);
const warn = (l: string, v: string) =>
  console.log(`  ${l.padEnd(30)} ${yellow(v)}`);

function check(label: string, value: number, target: number, unit: string) {
  const pass = value <= target;
  const icon = pass ? green("✓") : yellow("✗");
  const val = (pass ? green : yellow)(`${value.toFixed(2)} ${unit}`);
  console.log(
    `  ${label.padEnd(30)} ${icon} ${val}  ${dim(`(target: < ${target} ${unit})`)}`
  );
}

// ── Locate hyperfine ────────────────────────────────────

async function findHyperfine(): Promise<string> {
  for (const p of ["hyperfine", "/opt/homebrew/bin/hyperfine", "/usr/local/bin/hyperfine"]) {
    try {
      await $`${p} --version`.quiet();
      return p;
    } catch {
      continue;
    }
  }
  console.error("Error: hyperfine not found. Install with: brew install hyperfine");
  process.exit(1);
}

// ── Hyperfine runner ────────────────────────────────────

const HF_ARGS = ["--shell=none", "--warmup", "10", "--min-runs", "50", "--time-unit", "millisecond"];

async function bench(
  hf: string,
  commands: { name: string; args: string }[],
  exportJson?: string
) {
  const args = [...HF_ARGS];
  if (exportJson) args.push("--export-json", exportJson);
  for (const c of commands) args.push("-n", c.name, c.args);
  // Passthrough — let hyperfine write its progress bar and results directly
  const proc = Bun.spawn([hf, ...args], { stdout: "inherit", stderr: "inherit" });
  await proc.exited;
}

// ── Main ────────────────────────────────────────────────

const hf = await findHyperfine();

// Build if needed
if (!existsSync(BINARY)) {
  console.log("Binary not found. Building...");
  await $`ninja`;
}

// Header
const arch = await $`uname -m`.text();
const cpu = await $`sysctl -n machdep.cpu.brand_string`.nothrow().text();
const hfVer = (await $`${hf} --version`.text()).replace("hyperfine ", "");

console.log();
console.log(bold("═══════════════════════════════════════════════════════"));
console.log(bold("  AssemblyClaw Benchmark Suite"));
console.log(bold(`  ${new Date().toISOString().replace("T", " ").slice(0, 19)}`));
console.log(bold(`  ${arch.trim()} / ${cpu.trim()}`));
console.log(bold(`  hyperfine ${hfVer.trim()}`));
console.log(bold("═══════════════════════════════════════════════════════"));

// ──────────────────────────────────────────────────────
// Timing Benchmarks
// ──────────────────────────────────────────────────────

section("Startup Time");
console.log();
await bench(hf, [{ name: "assemblyclaw --help", args: `${BINARY} --help` }]);
console.log();
await bench(hf, [{ name: "assemblyclaw --version", args: `${BINARY} --version` }]);

section("Subcommand Dispatch");
console.log();
await bench(hf, [{ name: "assemblyclaw status", args: `${BINARY} status` }]);

section("Comparison (--help vs --version vs status)");
console.log();
await bench(hf, [
  { name: "help", args: `${BINARY} --help` },
  { name: "version", args: `${BINARY} --version` },
  { name: "status", args: `${BINARY} status` },
]);

// JSON export (runs even in --quick mode)
if (doExport) {
  section("Export");
  await bench(
    hf,
    [
      { name: "help", args: `${BINARY} --help` },
      { name: "version", args: `${BINARY} --version` },
      { name: "status", args: `${BINARY} status` },
    ],
    BENCH_JSON
  );
  metric("Written", BENCH_JSON);
}

if (quick) {
  console.log(`\n${dim("  (--quick mode: skipping static analysis)")}\n`);
  process.exit(0);
}

// ──────────────────────────────────────────────────────
// Static Analysis
// ──────────────────────────────────────────────────────

section("Binary Size");
const sizeBytes = statSync(BINARY).size;
const sizeKB = sizeBytes / 1024;
check("Binary size", sizeKB, targets.binaryKB, "KB");
metric("Raw bytes", sizeBytes.toLocaleString());
metric("vs NullClaw (Zig)", `${comparisons.nullclaw.sizeKB} KB`);
metric("vs CClaw (C)", `~${comparisons.cclaw.sizeKB} KB`);
metric(
  "Size ratio (NullClaw/Asm)",
  `${((comparisons.nullclaw.sizeKB * 1024) / sizeBytes).toFixed(1)}x smaller`
);

section("Binary Sections");
try {
  const sizeOut = await $`size ${BINARY}`.text();
  const parts = sizeOut.split("\n")[1]?.trim().split(/\s+/);
  if (parts && parts.length >= 4) {
    metric("__TEXT (code)", `${parts[0]} bytes`);
    metric("__DATA (data)", `${parts[1]} bytes`);
    metric("__BSS (zeroed)", `${parts[2]} bytes`);
    metric("Total", `${parts[3]} bytes`);
  }
} catch {
  warn("Sections", "Could not read (size command unavailable)");
}

// ── Memory ──

section("Memory Usage");
const { stderr: memBuf } = await $`/usr/bin/time -l ${BINARY} --help`
  .quiet()
  .nothrow();
const memOut = memBuf.toString();

const rssMatch = memOut.match(/(\d+)\s+maximum resident/);
let rssKB: number | null = null;
if (rssMatch) {
  const rssBytes = parseInt(rssMatch[1], 10);
  rssKB = rssBytes / 1024;
  check("Peak RSS", rssKB, targets.rssKB, "KB");
  metric("Raw bytes", rssBytes.toLocaleString());
  metric("vs NullClaw", "~1024 KB");
} else {
  warn("Peak RSS", "Could not measure");
}

const pf = memOut.match(/(\d+)\s+page faults/);
if (pf) metric("Page faults", pf[1]);

const ctx = memOut.match(/(\d+)\s+involuntary context/);
if (ctx) metric("Context switches (inv)", ctx[1]);

const instr = memOut.match(/(\d+)\s+instructions retired/);
if (instr) metric("Instructions retired", parseInt(instr[1], 10).toLocaleString());

// ── Mach-O ──

section("Mach-O Details");
try {
  const otoolOut = await $`otool -L ${BINARY}`.text();
  const libs = otoolOut
    .split("\n")
    .slice(1)
    .map((l) => l.trim().split(/\s/)[0])
    .filter(Boolean);
  metric("Linked libraries", libs.length.toString());
  for (const lib of libs) metric("  \u2192", lib);
} catch {
  warn("Mach-O", "otool unavailable");
}

// ──────────────────────────────────────────────────────
// Summary
// ──────────────────────────────────────────────────────

section("Summary");
console.log();
console.log(`  ${bold("AssemblyClaw")}`);
console.log(`  Binary: ${green(`${sizeKB.toFixed(2)} KB`)}`);
console.log(`  RAM:    ${green(`${rssKB?.toFixed(2) ?? "?"} KB`)}`);
console.log();
console.log(`  ${bold("Targets")}`);
console.log(`  Binary: < ${targets.binaryKB} KB`);
console.log(`  RAM:    < ${targets.rssKB} KB`);
console.log(`  Start:  < ${targets.startupMs} ms`);
console.log();
