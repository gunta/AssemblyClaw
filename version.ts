#!/usr/bin/env bun
// AssemblyClaw — Bun-native version bump script
//
// Usage:
//   bun version.ts patch        0.1.0 → 0.1.1
//   bun version.ts minor        0.1.0 → 0.2.0
//   bun version.ts major        0.1.0 → 1.0.0

import { $ } from "bun";
import { join } from "node:path";

const CONSTANTS_INC = join(import.meta.dir, "include", "constants.inc");
const VERSION_S = join(import.meta.dir, "src", "version.s");
const CHANGELOG = join(import.meta.dir, "CHANGELOG.md");

const bold = (s: string) => `\x1b[1m${s}\x1b[0m`;
const green = (s: string) => `\x1b[32m${s}\x1b[0m`;
const red = (s: string) => `\x1b[31m${s}\x1b[0m`;

// ── Parse current version from constants.inc ──

async function readCurrentVersion(): Promise<[number, number, number]> {
  const text = await Bun.file(CONSTANTS_INC).text();
  const major = text.match(/\.set VERSION_MAJOR,\s*(\d+)/)?.[1];
  const minor = text.match(/\.set VERSION_MINOR,\s*(\d+)/)?.[1];
  const patch = text.match(/\.set VERSION_PATCH,\s*(\d+)/)?.[1];
  if (major == null || minor == null || patch == null) {
    throw new Error(`Could not parse version from ${CONSTANTS_INC}`);
  }
  return [Number(major), Number(minor), Number(patch)];
}

function bump(
  [major, minor, patch]: [number, number, number],
  level: string
): [number, number, number] {
  switch (level) {
    case "major":
      return [major + 1, 0, 0];
    case "minor":
      return [major, minor + 1, 0];
    case "patch":
      return [major, minor, patch + 1];
    default:
      throw new Error(`Unknown bump level: ${level}. Use: patch | minor | major`);
  }
}

// ── Update constants.inc ──

async function updateConstantsInc(major: number, minor: number, patch: number) {
  let text = await Bun.file(CONSTANTS_INC).text();
  text = text.replace(
    /\.set VERSION_MAJOR,\s*\d+/,
    `.set VERSION_MAJOR, ${major}`
  );
  text = text.replace(
    /\.set VERSION_MINOR,\s*\d+/,
    `.set VERSION_MINOR, ${minor}`
  );
  text = text.replace(
    /\.set VERSION_PATCH,\s*\d+/,
    `.set VERSION_PATCH, ${patch}`
  );
  await Bun.write(CONSTANTS_INC, text);
}

// ── Update version.s ──

async function updateVersionS(version: string) {
  let text = await Bun.file(VERSION_S).text();

  // Replace the short version string: "X.Y.Z"
  text = text.replace(
    /(_str_version:\n\s+\.asciz\s+")[\d.]+(")/,
    `$1${version}$2`
  );

  // Replace the full version string: "assemblyclaw X.Y.Z (arm64-apple-darwin)\n"
  text = text.replace(
    /(_str_version_full:\n\s+\.ascii\s+")assemblyclaw [\d.]+ \(arm64-apple-darwin\)\\n(")/,
    `$1assemblyclaw ${version} (arm64-apple-darwin)\\n$2`
  );

  await Bun.write(VERSION_S, text);
}

// ── Update CHANGELOG.md ──

async function updateChangelog(version: string) {
  const date = new Date().toISOString().slice(0, 10);
  const header = `## v${version} (${date})\n\n`;

  const exists = await Bun.file(CHANGELOG).exists();
  if (!exists) {
    await Bun.write(CHANGELOG, `# Changelog\n\n${header}`);
    return;
  }

  const text = await Bun.file(CHANGELOG).text();

  // Replace "## Unreleased" with the versioned header if present
  if (text.includes("## Unreleased")) {
    const updated = text.replace("## Unreleased", `## v${version} (${date})`);
    await Bun.write(CHANGELOG, updated);
  } else {
    // Insert after the "# Changelog" heading
    const updated = text.replace(
      /^(# Changelog\n\n)/,
      `$1${header}`
    );
    await Bun.write(CHANGELOG, updated);
  }
}

// ── Main ──

const level = Bun.argv[2];
if (!level || !["patch", "minor", "major"].includes(level)) {
  console.error(`Usage: bun version.ts ${bold("patch|minor|major")}`);
  process.exit(1);
}

const current = await readCurrentVersion();
const [major, minor, patch] = bump(current, level);
const version = `${major}.${minor}.${patch}`;
const tag = `v${version}`;

console.log(`\n  ${current.join(".")} → ${bold(green(version))}\n`);

// Update source files
await updateConstantsInc(major, minor, patch);
console.log(`  ✓ ${CONSTANTS_INC}`);

await updateVersionS(version);
console.log(`  ✓ ${VERSION_S}`);

await updateChangelog(version);
console.log(`  ✓ ${CHANGELOG}`);

// Git commit + tag
await $`git add ${CONSTANTS_INC} ${VERSION_S} ${CHANGELOG}`;
await $`git commit -m ${"chore: bump to " + tag}`;
await $`git tag ${tag}`;

console.log(`\n  ${green("✓")} Committed and tagged ${bold(tag)}`);
console.log(`\n  Ready. Run: ${bold("git push && git push --tags")}\n`);
