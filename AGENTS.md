# AGENTS.md

Instructions for AI agents working on this repository.

## Package Manager

**Use Bun exclusively.** Do not use npm, yarn, or pnpm.

- `bun install` — not `npm install`
- `bun run <script>` — not `npm run <script>`
- Lock file is `bun.lock` — never create `package-lock.json`

This applies to the `site/` directory and any future JS/TS tooling in this repo.

## Assembly Core

See `CLAUDE.md` for full architecture rules, code conventions, and constraints.

Key points:

- All source is ARM64 assembly (`.s` files in `src/`)
- AAPCS64 calling convention, 128-byte cache-line alignment
- Arena allocator only (mmap-backed, no malloc/free)
- Test every change with `ninja test`
- Binary must stay under 32 KB stripped

## Site

The landing page lives in `site/` and uses Vite + Bun.

```bash
cd site
bun install
bun run dev       # Dev server
bun run build     # Production build
```

CI deploys to GitHub Pages via `.github/workflows/deploy.yml` using `oven-sh/setup-bun@v2`.

## Build

```bash
ninja              # Release build (optimized, stripped)
ninja debug        # Debug build (with symbols)
ninja test         # Run tests
ninja bench        # Full benchmark suite
ninja -t clean     # Remove build outputs
```

Requires macOS on Apple Silicon + Ninja + Xcode Command Line Tools. No other dependencies.
