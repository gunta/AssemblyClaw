#!/usr/bin/env bun
// AssemblyClaw — Dev CLI
//
// Usage:
//   bun x <command> [args...]
//
// Commands:
//   build              Release build (ninja)
//   build debug        Debug build with symbols
//   clean              Remove all build outputs
//   test               Run full test suite (51 tests)
//   bench [opts]       Benchmark suite (--quick, --no-comparators, --no-export)
//   run [args...]      Run the binary (pass args through)
//   debug              Launch lldb with debug binary
//   size               Show binary size breakdown
//   site dev           Dev server for landing page
//   site build         Production build for landing page
//   site preview       Preview production build
//   source sync        Copy .s/.inc files to site/public/source/
//   version patch      Bump patch version (0.1.1 → 0.1.2)
//   version minor      Bump minor version (0.1.1 → 0.2.0)
//   version major      Bump major version (0.1.1 → 1.0.0)
//   release patch      Bump + push + trigger full CI release
//   release minor      Same for minor
//   release major      Same for major
//   install            Build + install to /usr/local/bin

import { $, type ShellOutput } from "bun";
import { join } from "node:path";

const ROOT = import.meta.dir;
const BINARY = join(ROOT, "build", "assemblyclaw");
const SITE = join(ROOT, "site");

const bold = (s: string) => `\x1b[1m${s}\x1b[0m`;
const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;
const green = (s: string) => `\x1b[32m${s}\x1b[0m`;
const red = (s: string) => `\x1b[31m${s}\x1b[0m`;

const cmd = Bun.argv[2];
const sub = Bun.argv[3];
const rest = Bun.argv.slice(3);

// ── Helpers ──

async function ensureBinary() {
  if (!(await Bun.file(BINARY).exists())) {
    console.log(dim("  Binary not found — building..."));
    await $`ninja`.cwd(ROOT);
  }
}

function fail(msg: string): never {
  console.error(`\n  ${red("✗")} ${msg}\n`);
  process.exit(1);
}

// ── Commands ──

const commands: Record<string, () => Promise<void>> = {
  async build() {
    if (sub === "debug") {
      await $`ninja debug`.cwd(ROOT);
    } else {
      await $`ninja`.cwd(ROOT);
    }
  },

  async clean() {
    await $`ninja -t clean`.cwd(ROOT);
  },

  async test() {
    await $`ninja test`.cwd(ROOT);
  },

  async bench() {
    await $`bun bench.ts ${rest}`.cwd(ROOT);
  },

  async run() {
    await ensureBinary();
    const proc = Bun.spawn([BINARY, ...rest], {
      stdio: ["inherit", "inherit", "inherit"],
    });
    const code = await proc.exited;
    process.exit(code);
  },

  async debug() {
    const debugBin = join(ROOT, "build", "debug", "assemblyclaw");
    if (!(await Bun.file(debugBin).exists())) {
      console.log(dim("  Debug binary not found — building..."));
      await $`ninja debug`.cwd(ROOT);
    }
    const proc = Bun.spawn(["lldb", debugBin, ...rest], {
      stdio: ["inherit", "inherit", "inherit"],
    });
    process.exit(await proc.exited);
  },

  async size() {
    await ensureBinary();
    const file = Bun.file(BINARY);
    const bytes = file.size;
    const kb = (bytes / 1024).toFixed(1);
    const sections = Bun.spawnSync(["size", "-m", BINARY]);
    console.log(`\n  ${bold("Binary")}: ${green(`${bytes.toLocaleString()} bytes`)} (${kb} KB)\n`);
    console.log(sections.stdout.toString());
  },

  async site() {
    const siteCmd = sub;
    if (!siteCmd || !["dev", "build", "preview"].includes(siteCmd)) {
      fail("Usage: bun x site <dev|build|preview>");
    }
    await $`bun run ${siteCmd}`.cwd(SITE);
  },

  async source() {
    if (sub !== "sync") fail("Usage: bun x source sync");
    const srcDir = join(ROOT, "src");
    const incDir = join(ROOT, "include");
    const dest = join(SITE, "public", "source");
    await $`mkdir -p ${dest}`;
    await $`cp ${srcDir}/*.s ${dest}/`;
    await $`cp ${incDir}/*.inc ${dest}/`;
    // Count files
    const sFiles = (await $`ls ${dest}/*.s`.text()).trim().split("\n").length;
    const incFiles = (await $`ls ${dest}/*.inc`.text()).trim().split("\n").length;
    console.log(`\n  ${green("✓")} Synced ${sFiles} .s + ${incFiles} .inc files to site/public/source/\n`);
  },

  async version() {
    if (!sub || !["patch", "minor", "major"].includes(sub)) {
      fail("Usage: bun x version <patch|minor|major>");
    }
    await $`bun version.ts ${sub}`.cwd(ROOT);
  },

  async release() {
    if (!sub || !["patch", "minor", "major"].includes(sub)) {
      fail("Usage: bun x release <patch|minor|major>");
    }
    await $`bun version.ts ${sub}`.cwd(ROOT);
    console.log(dim("\n  Pushing to origin...\n"));
    await $`git push && git push --tags`.cwd(ROOT);
    console.log(`\n  ${green("✓")} Release triggered — CI will build, publish, and update Homebrew.\n`);
  },

  async install() {
    await $`ninja`.cwd(ROOT);
    await $`cp ${BINARY} /usr/local/bin/assemblyclaw`;
    const version = Bun.spawnSync([BINARY, "--version"]);
    console.log(`\n  ${green("✓")} Installed: ${version.stdout.toString().trim()}\n`);
  },
};

// ── Dispatch ──

if (!cmd || cmd === "help" || cmd === "--help" || cmd === "-h") {
  console.log(`
  ${bold("AssemblyClaw Dev CLI")}

  ${bold("Build")}
    bun x build              Release build
    bun x build debug        Debug build with symbols
    bun x clean              Remove build outputs
    bun x test               Run test suite
    bun x bench              Full benchmark suite

  ${bold("Run")}
    bun x run                Run binary (default: --help)
    bun x run agent -m "hi"  Run with arguments
    bun x debug              Launch lldb debugger
    bun x size               Binary size breakdown

  ${bold("Site")}
    bun x site dev           Dev server
    bun x site build         Production build
    bun x site preview       Preview build
    bun x source sync        Sync .s/.inc to site

  ${bold("Release")}
    bun x version patch      Bump version (no push)
    bun x release patch      Bump + push + CI release
    bun x release minor      Same for minor
    bun x release major      Same for major
    bun x install            Build + install to /usr/local/bin
`);
  process.exit(0);
}

const handler = commands[cmd];
if (!handler) {
  fail(`Unknown command: ${cmd}\n\n  Run ${bold("bun x help")} for available commands.`);
}

await handler();
