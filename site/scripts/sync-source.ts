#!/usr/bin/env bun

import { $ } from 'bun';
import { join } from 'node:path';

const SITE = join(import.meta.dir, '..');
const ROOT = join(SITE, '..');
const SOURCE_DIR = join(SITE, 'public', 'source');
const GENERATED_DIR = join(SITE, 'src', 'generated');
const GENERATED_FILE = join(GENERATED_DIR, 'repo-data.ts');
const FALLBACK_REPO_URL = 'https://github.com/gunta/AssemblyClaw';
const FALLBACK_CLONE_URL = `${FALLBACK_REPO_URL}.git`;

type Section = 'src' | 'include';

type SourceFile = {
  blobUrl: string;
  bytes: number;
  file: string;
  lines: number;
  mirrorPath: string;
  rawUrl: string;
  relativePath: string;
  section: Section;
  sha256: string;
};

function countLines(text: string) {
  if (text.length === 0) return 0;
  return text.split(/\r?\n/).length;
}

function toHex(buffer: ArrayBuffer) {
  return Array.from(new Uint8Array(buffer), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function sha256(text: string) {
  const bytes = new TextEncoder().encode(text);
  return toHex(await crypto.subtle.digest('SHA-256', bytes));
}

async function readVersion() {
  const text = await Bun.file(join(ROOT, 'include', 'constants.inc')).text();
  const major = text.match(/\.set VERSION_MAJOR,\s*(\d+)/)?.[1];
  const minor = text.match(/\.set VERSION_MINOR,\s*(\d+)/)?.[1];
  const patch = text.match(/\.set VERSION_PATCH,\s*(\d+)/)?.[1];

  if (!major || !minor || !patch) {
    throw new Error('Could not parse version from include/constants.inc');
  }

  return `${major}.${minor}.${patch}`;
}

async function readCliVersionLine(version: string) {
  const text = await Bun.file(join(ROOT, 'src', 'version.s')).text();
  const match = text.match(/"assemblyclaw ([^"]+)\\n"/);
  return match ? `assemblyclaw ${match[1]}` : `assemblyclaw ${version} (arm64-apple-darwin)`;
}

function normalizeRepoContext(remote: string) {
  const trimmed = remote.trim();
  const httpsMatch = trimmed.match(/^https:\/\/github\.com\/([^/]+)\/([^/.]+?)(?:\.git)?$/);
  if (httpsMatch) {
    const [, owner, repo] = httpsMatch;
    return {
      cloneUrl: `https://github.com/${owner}/${repo}.git`,
      owner,
      repo,
      repoUrl: `https://github.com/${owner}/${repo}`,
    };
  }

  const sshMatch = trimmed.match(/^git@github\.com:([^/]+)\/([^/.]+?)(?:\.git)?$/);
  if (sshMatch) {
    const [, owner, repo] = sshMatch;
    return {
      cloneUrl: `https://github.com/${owner}/${repo}.git`,
      owner,
      repo,
      repoUrl: `https://github.com/${owner}/${repo}`,
    };
  }

  return {
    cloneUrl: FALLBACK_CLONE_URL,
    owner: 'gunta',
    repo: 'AssemblyClaw',
    repoUrl: FALLBACK_REPO_URL,
  };
}

async function gitText(strings: TemplateStringsArray, ...values: unknown[]) {
  try {
    return (await $(strings, ...values).quiet().text()).trim();
  } catch {
    return '';
  }
}

async function getRepoContext() {
  const remote = (await gitText`git -C ${ROOT} remote get-url origin`) || FALLBACK_CLONE_URL;
  const commit = (await gitText`git -C ${ROOT} rev-parse HEAD`) || 'HEAD';
  const commitShort = (await gitText`git -C ${ROOT} rev-parse --short HEAD`) || commit.slice(0, 7);
  return {
    commit,
    commitShort,
    ...normalizeRepoContext(remote),
  };
}

async function removeOldMirror() {
  for await (const file of new Bun.Glob('*').scan({ cwd: SOURCE_DIR })) {
    await $`rm -f ${join(SOURCE_DIR, file)}`;
  }
}

async function collectFiles(section: Section, repoContext: Awaited<ReturnType<typeof getRepoContext>>): Promise<SourceFile[]> {
  const pattern = section === 'src' ? '*.s' : '*.inc';
  const cwd = join(ROOT, section);
  const files: SourceFile[] = [];

  for await (const file of new Bun.Glob(pattern).scan({ cwd })) {
    const absolutePath = join(cwd, file);
    const relativePath = `${section}/${file}`;
    const mirrorPath = `source/${file}`;
    const source = Bun.file(absolutePath);
    const text = await source.text();

    await Bun.write(join(SOURCE_DIR, file), source);

    files.push({
      blobUrl: `${repoContext.repoUrl}/blob/${repoContext.commit}/${relativePath}`,
      bytes: source.size,
      file,
      lines: countLines(text),
      mirrorPath,
      rawUrl: `https://raw.githubusercontent.com/${repoContext.owner}/${repoContext.repo}/${repoContext.commit}/${relativePath}`,
      relativePath,
      section,
      sha256: await sha256(text),
    });
  }

  return files.sort((a, b) => a.file.localeCompare(b.file));
}

await $`mkdir -p ${SOURCE_DIR}`;
await $`mkdir -p ${GENERATED_DIR}`;
await removeOldMirror();

const version = await readVersion();
const cliVersionLine = await readCliVersionLine(version);
const repoContext = await getRepoContext();
const sourceFiles = [
  ...(await collectFiles('src', repoContext)),
  ...(await collectFiles('include', repoContext)),
];

const totalBytes = sourceFiles.reduce((sum, file) => sum + file.bytes, 0);
const totalLines = sourceFiles.reduce((sum, file) => sum + file.lines, 0);

const repoData = {
  cliVersionLine,
  cloneUrl: repoContext.cloneUrl,
  commit: repoContext.commit,
  commitShort: repoContext.commitShort,
  generatedAtUtc: new Date().toISOString(),
  repoUrl: repoContext.repoUrl,
  sourceFiles,
  sourceSummary: {
    files: sourceFiles.length,
    includeFiles: sourceFiles.filter((file) => file.section === 'include').length,
    srcFiles: sourceFiles.filter((file) => file.section === 'src').length,
    totalBytes,
    totalLines,
  },
  version,
  versionTag: `v${version}`,
} as const;

await Bun.write(
  GENERATED_FILE,
  `// Generated by site/scripts/sync-source.ts\n` +
    `export type RepoSourceSection = 'src' | 'include';\n\n` +
    `export interface RepoSourceFile {\n` +
    `  blobUrl: string;\n` +
    `  bytes: number;\n` +
    `  file: string;\n` +
    `  lines: number;\n` +
    `  mirrorPath: string;\n` +
    `  rawUrl: string;\n` +
    `  relativePath: string;\n` +
    `  section: RepoSourceSection;\n` +
    `  sha256: string;\n` +
    `}\n\n` +
    `export const repoData = ${JSON.stringify(repoData, null, 2)} as const;\n` +
    `export const defaultSourceFile = repoData.sourceFiles.find((file) => file.file === 'main.s') ?? repoData.sourceFiles[0] ?? null;\n`
);

console.log(
  `Synced ${repoData.sourceSummary.srcFiles} src + ${repoData.sourceSummary.includeFiles} include files (${repoData.sourceSummary.totalLines} lines) for site source browsing.`
);
