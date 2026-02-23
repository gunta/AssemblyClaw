#!/usr/bin/env bun
// AssemblyClaw Benchmark Suite
// Requires: hyperfine (brew install hyperfine)
//
// Usage:
//   bun bench.ts                    Full suite + JSON export + comparator automation
//   bun bench.ts --quick            Timing only for AssemblyClaw static analysis (comparators still measured)
//   bun bench.ts --no-export        Full suite without JSON export
//   bun bench.ts --no-comparators   Benchmark AssemblyClaw only
//
// Optional env:
//   CCLAW_REPO_URL=<git-url>        Override default CClaw upstream repo URL

import { $ } from "bun";
import { existsSync, mkdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const BINARY = "./build/assemblyclaw";
const BENCH_RAW_JSON = "./build/bench.hyperfine.json";
const BENCH_COMPARE_JSON = "./build/bench.compare.hyperfine.json";
const BENCH_SITE_JSON = "./site/public/benchmarks.json";

const COMPARATOR_ROOT = "./build/comparators";
const OPENCLAW_PKG_DIR = join(COMPARATOR_ROOT, "openclaw-pkg");
const NULLCLAW_REPO_DIR = join(COMPARATOR_ROOT, "nullclaw");
const CCLAW_FETCH_DIR = join(COMPARATOR_ROOT, "cclaw");
const CCLAW_LOCAL_DIR = "./context/cclaw-main";

const OPENCLAW_REPO_URL = "https://github.com/openclaw/openclaw.git";
const NULLCLAW_REPO_URL = "https://github.com/nullclaw/nullclaw.git";
const CCLAW_DEFAULT_REPO_URL = "https://github.com/aresbit/cclaw.git";

const targets = { binaryKB: 32, rssKB: 128, startupMs: 0.1 } as const;

const quick = Bun.argv.includes("--quick");
const doExport = !Bun.argv.includes("--no-export");
const doComparators = !Bun.argv.includes("--no-comparators");

const bold = (s: string) => `\x1b[1m${s}\x1b[0m`;
const green = (s: string) => `\x1b[32m${s}\x1b[0m`;
const yellow = (s: string) => `\x1b[33m${s}\x1b[0m`;
const cyan = (s: string) => `\x1b[36m${s}\x1b[0m`;
const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;

const section = (title: string) => console.log(`\n${cyan(`── ${title} ──`)}`);
const metric = (label: string, value: string) =>
  console.log(`  ${label.padEnd(30)} ${green(value)}`);
const warn = (label: string, value: string) =>
  console.log(`  ${label.padEnd(30)} ${yellow(value)}`);

type LanguageKey = "typescript" | "zig" | "c";

type ComparatorMetrics = {
  key: LanguageKey;
  name: string;
  version: string;
  source: string;
  binaryKB: number;
  rssKB: number;
  startupMs: number;
};

function round(value: number, places: number): number {
  const factor = 10 ** places;
  return Math.round(value * factor) / factor;
}

function formatStorageDisplay(kb: number): string {
  if (!Number.isFinite(kb) || kb <= 0) return "—";
  const kbInt = Math.floor(kb);
  if (kbInt >= 1024) return `${Math.floor(kbInt / 1024)} MB`;
  return `${kbInt} KB`;
}

function formatMsDisplay(ms: number): string {
  if (!Number.isFinite(ms) || ms < 0) return "—";
  return `${Math.floor(ms)} ms`;
}

function check(label: string, value: number, target: number, unit: string) {
  const pass = value <= target;
  const icon = pass ? green("✓") : yellow("✗");
  const display =
    unit === "KB" ? formatStorageDisplay(value) : unit === "ms" ? formatMsDisplay(value) : `${value} ${unit}`;
  const val = (pass ? green : yellow)(display);
  console.log(
    `  ${label.padEnd(30)} ${icon} ${val}  ${dim(`(target: < ${target} ${unit})`)}`
  );
}

function decode(buf: Uint8Array | Buffer | null | undefined): string {
  if (!buf) return "";
  return new TextDecoder().decode(buf);
}

function firstLine(text: string): string {
  return text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find((line) => line.length > 0) ?? "";
}

function runCapture(
  cmd: string[],
  opts?: { cwd?: string; env?: Record<string, string | undefined>; allowFail?: boolean }
) {
  const proc = Bun.spawnSync(cmd, {
    cwd: opts?.cwd,
    env: { ...process.env, ...(opts?.env ?? {}) },
    stdout: "pipe",
    stderr: "pipe",
  });
  const out = decode(proc.stdout);
  const err = decode(proc.stderr);
  const code = proc.exitCode ?? 1;
  if (code !== 0 && !opts?.allowFail) {
    throw new Error(`command failed (${code}): ${cmd.join(" ")}\n${err || out}`);
  }
  return { code, out, err };
}

async function runInherit(
  cmd: string[],
  opts?: { cwd?: string; env?: Record<string, string | undefined>; allowFail?: boolean }
) {
  const proc = Bun.spawn(cmd, {
    cwd: opts?.cwd,
    env: { ...process.env, ...(opts?.env ?? {}) },
    stdout: "inherit",
    stderr: "inherit",
  });
  const code = await proc.exited;
  if (code !== 0 && !opts?.allowFail) {
    throw new Error(`command failed (${code}): ${cmd.join(" ")}`);
  }
  return code;
}

function commandString(argv: string[]): string {
  return argv
    .map((arg) => {
      if (/^[A-Za-z0-9_./:@%+=,-]+$/.test(arg)) return arg;
      return `'${arg.replace(/'/g, `'\\''`)}'`;
    })
    .join(" ");
}

function parseMaxResidentKB(stderrText: string): number | null {
  const match = stderrText.match(/(\d+)\s+maximum resident set size/);
  if (!match) return null;
  const bytes = Number.parseInt(match[1], 10);
  if (!Number.isFinite(bytes)) return null;
  return bytes / 1024;
}

function measureRssKB(argv: string[]): number | null {
  const proc = Bun.spawnSync(["/usr/bin/time", "-l", ...argv], {
    env: process.env,
    stdout: "ignore",
    stderr: "pipe",
  });
  const stderrText = decode(proc.stderr);
  return parseMaxResidentKB(stderrText);
}

function duKB(path: string): number {
  const { out } = runCapture(["du", "-sk", path]);
  const kb = Number.parseInt(out.trim().split(/\s+/)[0] ?? "", 10);
  if (!Number.isFinite(kb)) {
    throw new Error(`could not parse du output for ${path}: ${out}`);
  }
  return kb;
}

function binarySizeKB(path: string): number {
  return statSync(path).size / 1024;
}

async function findHyperfine(): Promise<string> {
  for (const path of ["hyperfine", "/opt/homebrew/bin/hyperfine", "/usr/local/bin/hyperfine"]) {
    const { code } = runCapture([path, "--version"], { allowFail: true });
    if (code === 0) return path;
  }
  console.error("Error: hyperfine not found. Install with: brew install hyperfine");
  process.exit(1);
}

function findZig(): string {
  for (const candidate of [
    "zig",
    join(process.env.HOME ?? "", ".proto/tools/zig/0.15.1/zig"),
    "/opt/homebrew/bin/zig",
    "/usr/local/bin/zig",
  ]) {
    if (!candidate) continue;
    const { code } = runCapture([candidate, "version"], { allowFail: true });
    if (code === 0) return candidate;
  }
  throw new Error("zig not found (required for nullclaw comparator build)");
}

const HF_ARGS = [
  "--shell=none",
  "--warmup",
  "10",
  "--min-runs",
  "50",
  "--time-unit",
  "millisecond",
];

async function bench(
  hyperfinePath: string,
  commands: { name: string; args: string }[],
  exportJson?: string
) {
  const args = [...HF_ARGS];
  if (exportJson) args.push("--export-json", exportJson);
  for (const command of commands) args.push("-n", command.name, command.args);
  const proc = Bun.spawn([hyperfinePath, ...args], { stdout: "inherit", stderr: "inherit" });
  await proc.exited;
}

async function readHyperfineMeans(exportPath: string): Promise<Map<string, number>> {
  const result = new Map<string, number>();
  if (!existsSync(exportPath)) return result;
  const parsed = (await Bun.file(exportPath).json()) as {
    results?: Array<{ command?: string; mean?: number }>;
  };
  for (const row of parsed.results ?? []) {
    if (typeof row.command !== "string") continue;
    if (typeof row.mean !== "number") continue;
    result.set(row.command, row.mean * 1000);
  }
  return result;
}

async function readHyperfineMean(exportPath: string, commandName: string): Promise<number | null> {
  const map = await readHyperfineMeans(exportPath);
  return map.get(commandName) ?? null;
}

async function ensureGitRepoLatest(repoUrl: string, repoDir: string) {
  if (!existsSync(repoDir)) {
    await runInherit(["git", "clone", "--depth", "1", repoUrl, repoDir]);
    return;
  }

  if (!existsSync(join(repoDir, ".git"))) {
    rmSync(repoDir, { recursive: true, force: true });
    await runInherit(["git", "clone", "--depth", "1", repoUrl, repoDir]);
    return;
  }

  await runInherit(["git", "-C", repoDir, "fetch", "origin", "--depth", "1"]);
  await runInherit(["git", "-C", repoDir, "reset", "--hard", "origin/HEAD"]);
}

function gitHeadShort(repoDir: string): string | null {
  if (!existsSync(join(repoDir, ".git"))) return null;
  const { code, out } = runCapture(["git", "-C", repoDir, "rev-parse", "--short", "HEAD"], {
    allowFail: true,
  });
  if (code !== 0) return null;
  const head = firstLine(out);
  return head || null;
}

async function prepareOpenClawComparator(): Promise<{
  argv: string[];
  version: string;
  source: string;
  binaryKB: number;
}> {
  mkdirSync(OPENCLAW_PKG_DIR, { recursive: true });

  const packageJsonPath = join(OPENCLAW_PKG_DIR, "package.json");
  if (!existsSync(packageJsonPath)) {
    writeFileSync(
      packageJsonPath,
      `${JSON.stringify(
        {
          name: "openclaw-bench",
          private: true,
          version: "0.0.0",
        },
        null,
        2
      )}\n`,
      "utf8"
    );
  }

  await runInherit(["bun", "add", "openclaw@latest"], { cwd: OPENCLAW_PKG_DIR });

  const cliPath = join(OPENCLAW_PKG_DIR, "node_modules", ".bin", "openclaw");
  if (!existsSync(cliPath)) {
    throw new Error(`openclaw CLI not found at ${cliPath}`);
  }

  const ver = runCapture([cliPath, "--version"]);
  const version = firstLine(ver.out) || firstLine(ver.err) || "openclaw (unknown version)";

  const distDir = join(OPENCLAW_PKG_DIR, "node_modules", "openclaw", "dist");
  if (!existsSync(distDir)) {
    throw new Error(`openclaw dist directory not found: ${distDir}`);
  }

  return {
    argv: [cliPath, "--help"],
    version,
    source: "npm openclaw@latest",
    binaryKB: duKB(distDir),
  };
}

async function prepareNullClawReleaseComparator(): Promise<{
  argv: string[];
  version: string;
  source: string;
  binaryKB: number;
}> {
  const releaseDir = join(COMPARATOR_ROOT, "nullclaw-release");
  mkdirSync(releaseDir, { recursive: true });

  const api = "https://api.github.com/repos/nullclaw/nullclaw/releases/latest";
  const metaRes = await fetch(api, { headers: { Accept: "application/vnd.github+json" } });
  if (!metaRes.ok) {
    throw new Error(`failed to fetch nullclaw releases: HTTP ${metaRes.status}`);
  }
  const meta = (await metaRes.json()) as {
    tag_name?: string;
    assets?: Array<{ name?: string; browser_download_url?: string }>;
  };

  const tag = typeof meta.tag_name === "string" ? meta.tag_name : "unknown-tag";
  const asset = (meta.assets ?? []).find((a) => a.name === "nullclaw-macos-aarch64.bin");
  if (!asset?.browser_download_url) {
    throw new Error("nullclaw macOS arm64 release asset not found");
  }

  const binRes = await fetch(asset.browser_download_url);
  if (!binRes.ok) {
    throw new Error(`failed to download nullclaw release binary: HTTP ${binRes.status}`);
  }

  const binaryPath = join(releaseDir, "nullclaw");
  const bytes = await binRes.arrayBuffer();
  writeFileSync(binaryPath, Buffer.from(bytes));
  await runInherit(["chmod", "+x", binaryPath]);

  const ver = runCapture([binaryPath, "--version"], { allowFail: true });
  const version = firstLine(ver.out) || firstLine(ver.err) || `nullclaw ${tag}`;

  return {
    argv: [binaryPath, "--help"],
    version,
    source: `github release ${tag}`,
    binaryKB: binarySizeKB(binaryPath),
  };
}

async function prepareNullClawComparator(): Promise<{
  argv: string[];
  version: string;
  source: string;
  binaryKB: number;
}> {
  await ensureGitRepoLatest(NULLCLAW_REPO_URL, NULLCLAW_REPO_DIR);

  try {
    const zig = findZig();
    await runInherit([zig, "build", "-Doptimize=ReleaseSmall"], { cwd: NULLCLAW_REPO_DIR });

    const binaryPath = join(NULLCLAW_REPO_DIR, "zig-out", "bin", "nullclaw");
    if (!existsSync(binaryPath)) {
      throw new Error(`nullclaw binary not found: ${binaryPath}`);
    }

    const ver = runCapture([binaryPath, "--version"]);
    const version = firstLine(ver.out) || firstLine(ver.err) || "nullclaw (unknown version)";
    const head = gitHeadShort(NULLCLAW_REPO_DIR);

    return {
      argv: [binaryPath, "--help"],
      version,
      source: head ? `git ${NULLCLAW_REPO_URL}@${head}` : `git ${NULLCLAW_REPO_URL}`,
      binaryKB: binarySizeKB(binaryPath),
    };
  } catch (err) {
    warn(
      "NullClaw source build",
      `failed, falling back to latest release binary (${err instanceof Error ? err.message : "unknown error"})`
    );
    return await prepareNullClawReleaseComparator();
  }
}

async function prepareCClawComparator(): Promise<{
  argv: string[];
  version: string;
  source: string;
  binaryKB: number;
}> {
  const repoUrl = process.env.CCLAW_REPO_URL?.trim() || CCLAW_DEFAULT_REPO_URL;
  let repoDir = CCLAW_FETCH_DIR;
  let source = "";

  try {
    await ensureGitRepoLatest(repoUrl, CCLAW_FETCH_DIR);
    const head = gitHeadShort(repoDir);
    source = head ? `git ${repoUrl}@${head}` : `git ${repoUrl}`;
  } catch (err) {
    if (!existsSync(CCLAW_LOCAL_DIR)) {
      throw err;
    }

    warn(
      "CClaw fetch",
      `failed, falling back to local snapshot (${err instanceof Error ? err.message : "unknown error"})`
    );

    repoDir = CCLAW_LOCAL_DIR;
    source = "local context/cclaw-main snapshot";
  }

  await runInherit(["make", "clean"], { cwd: repoDir, allowFail: true });

  const env: Record<string, string | undefined> = {};
  if (existsSync("/opt/homebrew/include")) {
    env.CPATH = process.env.CPATH
      ? `${process.env.CPATH}:/opt/homebrew/include`
      : "/opt/homebrew/include";
  }
  if (existsSync("/opt/homebrew/lib")) {
    env.LIBRARY_PATH = process.env.LIBRARY_PATH
      ? `${process.env.LIBRARY_PATH}:/opt/homebrew/lib`
      : "/opt/homebrew/lib";
  }

  const fallbackLdfLags =
    "-lm -ldl -lpthread -lcurl -lsqlite3 -lsodium -luv -Lthird_party -framework CoreFoundation -framework Security";

  let buildOk = false;
  try {
    await runInherit(["make", "-j4"], { cwd: repoDir, env });
    buildOk = true;
  } catch {
    await runInherit(["make", "-j4", `LDFLAGS=${fallbackLdfLags}`], { cwd: repoDir, env });
    buildOk = true;
  }

  if (!buildOk) {
    throw new Error(`cclaw build failed in ${repoDir}`);
  }

  const binaryPath = join(repoDir, "bin", "cclaw");
  if (!existsSync(binaryPath)) {
    throw new Error(`cclaw binary not found: ${binaryPath}`);
  }

  const ver = runCapture([binaryPath, "--version"], { allowFail: true });
  const version = firstLine(ver.out) || firstLine(ver.err) || "cclaw (unknown version)";

  return {
    argv: [binaryPath, "--help"],
    version,
    source,
    binaryKB: binarySizeKB(binaryPath),
  };
}

const hyperfinePath = await findHyperfine();

if (!existsSync(BINARY)) {
  console.log("Binary not found. Building...");
  await runInherit(["ninja"]);
}

const nowIso = new Date().toISOString();
const arch = (await $`uname -m`.text()).trim();
const cpu = (await $`sysctl -n machdep.cpu.brand_string`.nothrow().text()).trim() || "unknown";
const machineModel = (await $`sysctl -n hw.model`.nothrow().text()).trim() || "unknown";
const osName = (await $`sw_vers -productName`.nothrow().text()).trim() || "macOS";
const osVersion = (await $`sw_vers -productVersion`.nothrow().text()).trim() || "unknown";
const osBuild = (await $`sw_vers -buildVersion`.nothrow().text()).trim() || "unknown";
const memBytesRaw = (await $`sysctl -n hw.memsize`.nothrow().text()).trim();
const memBytes = Number.parseInt(memBytesRaw, 10);
const memoryGB = Number.isFinite(memBytes) ? round(memBytes / (1024 ** 3), 2) : null;
const gitCommit = (await $`git rev-parse --short HEAD`.nothrow().text()).trim() || null;
const hyperfineVersion = (await $`${hyperfinePath} --version`.text()).replace("hyperfine ", "").trim();

console.log();
console.log(bold("═══════════════════════════════════════════════════════"));
console.log(bold("  AssemblyClaw Benchmark Suite"));
console.log(bold(`  ${nowIso.replace("T", " ").slice(0, 19)} UTC`));
console.log(bold(`  ${arch} / ${cpu}`));
console.log(bold(`  hyperfine ${hyperfineVersion}`));
console.log(bold("═══════════════════════════════════════════════════════"));

section("Startup Time");
console.log();
await bench(hyperfinePath, [{ name: "assemblyclaw --help", args: `${BINARY} --help` }]);
console.log();
await bench(hyperfinePath, [{ name: "assemblyclaw --version", args: `${BINARY} --version` }]);

section("Subcommand Dispatch");
console.log();
await bench(hyperfinePath, [{ name: "assemblyclaw status", args: `${BINARY} status` }]);

section("Comparison (--help vs --version vs status)");
console.log();
await bench(hyperfinePath, [
  { name: "help", args: `${BINARY} --help` },
  { name: "version", args: `${BINARY} --version` },
  { name: "status", args: `${BINARY} status` },
]);

if (doExport) {
  section("Export (Raw Timing)");
  await bench(
    hyperfinePath,
    [
      { name: "help", args: `${BINARY} --help` },
      { name: "version", args: `${BINARY} --version` },
      { name: "status", args: `${BINARY} status` },
    ],
    BENCH_RAW_JSON
  );
  metric("Written", BENCH_RAW_JSON);
}

const startupHelpMs = await readHyperfineMean(BENCH_RAW_JSON, "help");
if (startupHelpMs !== null) {
  section("Startup Metric");
  check("Startup (--help)", startupHelpMs, targets.startupMs, "ms");
}

let sizeBytes: number | null = null;
let sizeKB: number | null = null;
let rssBytes: number | null = null;
let rssKB: number | null = null;
let pageFaults: number | null = null;
let involuntaryContextSwitches: number | null = null;
let instructionsRetired: number | null = null;

if (!quick) {
  section("Binary Size");
  sizeBytes = statSync(BINARY).size;
  sizeKB = sizeBytes / 1024;
  check("Binary size", sizeKB, targets.binaryKB, "KB");
  metric("Raw bytes", sizeBytes.toLocaleString());

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

  section("Memory Usage");
  const { stderr: memBuf } = await $`/usr/bin/time -l ${BINARY} --help`.quiet().nothrow();
  const memOut = memBuf.toString();

  const rssMatch = memOut.match(/(\d+)\s+maximum resident/);
  if (rssMatch) {
    rssBytes = Number.parseInt(rssMatch[1], 10);
    rssKB = rssBytes / 1024;
    check("Peak RSS", rssKB, targets.rssKB, "KB");
    metric("Raw bytes", rssBytes.toLocaleString());
  } else {
    warn("Peak RSS", "Could not measure");
  }

  const pageFaultMatch = memOut.match(/(\d+)\s+page faults/);
  if (pageFaultMatch) {
    pageFaults = Number.parseInt(pageFaultMatch[1], 10);
    metric("Page faults", pageFaultMatch[1]);
  }

  const ctxMatch = memOut.match(/(\d+)\s+involuntary context/);
  if (ctxMatch) {
    involuntaryContextSwitches = Number.parseInt(ctxMatch[1], 10);
    metric("Context switches (inv)", ctxMatch[1]);
  }

  const instrMatch = memOut.match(/(\d+)\s+instructions retired/);
  if (instrMatch) {
    instructionsRetired = Number.parseInt(instrMatch[1], 10);
    metric("Instructions retired", instructionsRetired.toLocaleString());
  }

  section("Mach-O Details");
  try {
    const otoolOut = await $`otool -L ${BINARY}`.text();
    const libs = otoolOut
      .split("\n")
      .slice(1)
      .map((line) => line.trim().split(/\s/)[0])
      .filter(Boolean);
    metric("Linked libraries", libs.length.toString());
    for (const lib of libs) metric("  →", lib);
  } catch {
    warn("Mach-O", "otool unavailable");
  }
} else {
  console.log(`\n${dim("  (--quick mode: skipping static analysis)")}`);
}

let comparatorMetrics: ComparatorMetrics[] = [];
let assemblyComparatorStartupMs: number | null = null;

if (doComparators) {
  section("Comparator Setup");
  mkdirSync(COMPARATOR_ROOT, { recursive: true });

  const openclaw = await prepareOpenClawComparator();
  metric("OpenClaw", `${openclaw.version} (${openclaw.source})`);

  const nullclaw = await prepareNullClawComparator();
  metric("NullClaw", `${nullclaw.version} (${nullclaw.source})`);

  const cclaw = await prepareCClawComparator();
  metric("CClaw", `${cclaw.version} (${cclaw.source})`);

  section("Comparator Startup (--help)");
  await bench(
    hyperfinePath,
    [
      { name: "assemblyclaw", args: commandString([BINARY, "--help"]) },
      { name: "openclaw", args: commandString(openclaw.argv) },
      { name: "nullclaw", args: commandString(nullclaw.argv) },
      { name: "cclaw", args: commandString(cclaw.argv) },
    ],
    BENCH_COMPARE_JSON
  );

  const means = await readHyperfineMeans(BENCH_COMPARE_JSON);
  assemblyComparatorStartupMs = means.get("assemblyclaw") ?? null;
  const openclawStartup = means.get("openclaw");
  const nullclawStartup = means.get("nullclaw");
  const cclawStartup = means.get("cclaw");

  if (openclawStartup == null || nullclawStartup == null || cclawStartup == null) {
    throw new Error("missing comparator startup means from hyperfine export");
  }

  const openclawRssKB = measureRssKB(openclaw.argv);
  const nullclawRssKB = measureRssKB(nullclaw.argv);
  const cclawRssKB = measureRssKB(cclaw.argv);

  if (openclawRssKB == null || nullclawRssKB == null || cclawRssKB == null) {
    throw new Error("failed to measure comparator RSS via /usr/bin/time -l");
  }

  comparatorMetrics = [
    {
      key: "typescript",
      name: "TypeScript",
      version: openclaw.version,
      source: openclaw.source,
      binaryKB: openclaw.binaryKB,
      rssKB: openclawRssKB,
      startupMs: openclawStartup,
    },
    {
      key: "zig",
      name: "Zig",
      version: nullclaw.version,
      source: nullclaw.source,
      binaryKB: nullclaw.binaryKB,
      rssKB: nullclawRssKB,
      startupMs: nullclawStartup,
    },
    {
      key: "c",
      name: "C",
      version: cclaw.version,
      source: cclaw.source,
      binaryKB: cclaw.binaryKB,
      rssKB: cclawRssKB,
      startupMs: cclawStartup,
    },
  ];

  section("Comparator Summary");
  for (const cmp of comparatorMetrics) {
    metric(
      cmp.name,
      `bin ${formatStorageDisplay(cmp.binaryKB)} · ram ${formatStorageDisplay(cmp.rssKB)} · start ${formatMsDisplay(cmp.startupMs)}`
    );
  }
}

section("Summary");
console.log();
const summaryStartupMs = assemblyComparatorStartupMs ?? startupHelpMs;
console.log(`  ${bold("AssemblyClaw")}`);
console.log(`  Binary: ${green(sizeKB !== null ? formatStorageDisplay(sizeKB) : "?")}`);
console.log(`  RAM:    ${green(rssKB !== null ? formatStorageDisplay(rssKB) : "?")}`);
console.log(`  Start:  ${green(summaryStartupMs !== null ? formatMsDisplay(summaryStartupMs) : "?")}`);
console.log();
console.log(`  ${bold("Targets")}`);
console.log(`  Binary: < ${targets.binaryKB} KB`);
console.log(`  RAM:    < ${targets.rssKB} KB`);
console.log(`  Start:  < ${targets.startupMs} ms`);
console.log();

if (doExport) {
  mkdirSync(dirname(BENCH_SITE_JSON), { recursive: true });

  const assemblyBinaryKB = sizeKB ?? binarySizeKB(BINARY);
  const assemblyRssKB = rssKB ?? measureRssKB([BINARY, "--help"]);
  const compareMeans = existsSync(BENCH_COMPARE_JSON)
    ? await readHyperfineMeans(BENCH_COMPARE_JSON)
    : new Map<string, number>();
  const assemblyStartupMs =
    assemblyComparatorStartupMs ?? compareMeans.get("assemblyclaw") ?? startupHelpMs;

  if (assemblyRssKB == null || assemblyStartupMs == null) {
    throw new Error("assembly metrics unavailable for JSON export");
  }

  const languagePayload: Record<string, unknown> = {
    assembly: {
      name: "Assembly",
      binary_kb: round(assemblyBinaryKB, 2),
      binary_bytes: Math.round(assemblyBinaryKB * 1024),
      binary_display: formatStorageDisplay(assemblyBinaryKB),
      ram_kb: round(assemblyRssKB, 2),
      ram_bytes: Math.round(assemblyRssKB * 1024),
      ram_display: formatStorageDisplay(assemblyRssKB),
      startup_ms: assemblyStartupMs,
      startup_display: formatMsDisplay(assemblyStartupMs),
    },
  };

  for (const cmp of comparatorMetrics) {
    languagePayload[cmp.key] = {
      name: cmp.name,
      binary_kb: round(cmp.binaryKB, 2),
      binary_display: formatStorageDisplay(cmp.binaryKB),
      ram_kb: round(cmp.rssKB, 2),
      ram_display: formatStorageDisplay(cmp.rssKB),
      startup_ms: cmp.startupMs,
      startup_display: formatMsDisplay(cmp.startupMs),
    };
  }

  if (!languagePayload.typescript) {
    languagePayload.typescript = {
      name: "TypeScript",
      binary_kb: null,
      binary_display: "—",
      ram_kb: null,
      ram_display: "—",
      startup_ms: null,
      startup_display: "—",
    };
  }
  if (!languagePayload.zig) {
    languagePayload.zig = {
      name: "Zig",
      binary_kb: null,
      binary_display: "—",
      ram_kb: null,
      ram_display: "—",
      startup_ms: null,
      startup_display: "—",
    };
  }
  if (!languagePayload.c) {
    languagePayload.c = {
      name: "C",
      binary_kb: null,
      binary_display: "—",
      ram_kb: null,
      ram_display: "—",
      startup_ms: null,
      startup_display: "—",
    };
  }

  const comparisonNotes = comparatorMetrics.length
    ? comparatorMetrics.map((cmp) => `${cmp.name}: ${cmp.version} (${cmp.source})`)
    : ["Comparators disabled (--no-comparators)."];

  const payload = {
    schema_version: 1,
    generated_at_utc: nowIso,
    git_commit: gitCommit,
    source_binary: BINARY,
    targets: {
      binary_kb: targets.binaryKB,
      peak_rss_kb: targets.rssKB,
      startup_help_ms: targets.startupMs,
    },
    environment: {
      os: `${osName} ${osVersion}`,
      os_build: osBuild,
      arch,
      machine_model: machineModel,
      cpu,
      memory_bytes: Number.isFinite(memBytes) ? memBytes : null,
      memory_gb: memoryGB,
      hyperfine_version: hyperfineVersion,
    },
    methodology: {
      startup_help: {
        tool: `hyperfine ${hyperfineVersion}`,
        args: HF_ARGS.join(" "),
        command: `${BINARY} --help`,
      },
      comparator_startup_help: {
        tool: `hyperfine ${hyperfineVersion}`,
        args: HF_ARGS.join(" "),
        command_file: BENCH_COMPARE_JSON,
      },
      binary_size: {
        tool: "stat / du",
        command: `stat -f%z ${BINARY} (+ du -sk for OpenClaw dist)`,
      },
      peak_rss: {
        tool: "/usr/bin/time -l",
        command: "<binary> --help",
      },
      notes: [
        "Values are measured locally on this machine.",
        "Display strings are integer-only by design (no decimal places).",
        ...comparisonNotes,
      ],
    },
    languages: languagePayload,
    extra_metrics: {
      page_faults: pageFaults,
      involuntary_context_switches: involuntaryContextSwitches,
      instructions_retired: instructionsRetired,
    },
    status: {
      binary_target_met: assemblyBinaryKB <= targets.binaryKB,
      peak_rss_target_met: assemblyRssKB <= targets.rssKB,
      startup_target_met: assemblyStartupMs <= targets.startupMs,
    },
  };

  writeFileSync(BENCH_SITE_JSON, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
  section("Export (Canonical JSON)");
  metric("Written", BENCH_SITE_JSON);
}
