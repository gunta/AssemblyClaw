/* ═══════════════════════════════════════════════
   AssemblyClaw — Interactions & Animations
   ═══════════════════════════════════════════════ */

// ─── HERO CANVAS: Circuit Particle Network ───

class CircuitCanvas {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.particles = [];
    this.mouse = { x: -1000, y: -1000 };
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.resize();
    this.init();
    this.bind();
    this.loop();
  }

  resize() {
    const rect = this.canvas.parentElement.getBoundingClientRect();
    this.w = rect.width;
    this.h = rect.height;
    this.canvas.width = this.w * this.dpr;
    this.canvas.height = this.h * this.dpr;
    this.canvas.style.width = this.w + 'px';
    this.canvas.style.height = this.h + 'px';
    this.ctx.scale(this.dpr, this.dpr);
  }

  init() {
    const count = Math.min(Math.floor((this.w * this.h) / 12000), 80);
    this.particles = Array.from({ length: count }, () => ({
      x: Math.random() * this.w,
      y: Math.random() * this.h,
      vx: (Math.random() - 0.5) * 0.3,
      vy: (Math.random() - 0.5) * 0.3,
      r: Math.random() * 1.5 + 0.5,
      opacity: Math.random() * 0.5 + 0.2,
    }));
  }

  bind() {
    window.addEventListener('resize', () => {
      this.resize();
      this.init();
    });
    this.canvas.parentElement.addEventListener('mousemove', (e) => {
      const rect = this.canvas.parentElement.getBoundingClientRect();
      this.mouse.x = e.clientX - rect.left;
      this.mouse.y = e.clientY - rect.top;
    });
    this.canvas.parentElement.addEventListener('mouseleave', () => {
      this.mouse.x = -1000;
      this.mouse.y = -1000;
    });
  }

  loop() {
    this.update();
    this.draw();
    requestAnimationFrame(() => this.loop());
  }

  update() {
    for (const p of this.particles) {
      p.x += p.vx;
      p.y += p.vy;
      if (p.x < 0 || p.x > this.w) p.vx *= -1;
      if (p.y < 0 || p.y > this.h) p.vy *= -1;
      p.x = Math.max(0, Math.min(this.w, p.x));
      p.y = Math.max(0, Math.min(this.h, p.y));
    }
  }

  draw() {
    this.ctx.clearRect(0, 0, this.w, this.h);
    const connectionDist = 140;
    const mouseDist = 200;

    for (let i = 0; i < this.particles.length; i++) {
      const a = this.particles[i];

      for (let j = i + 1; j < this.particles.length; j++) {
        const b = this.particles[j];
        const dx = a.x - b.x;
        const dy = a.y - b.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < connectionDist) {
          const alpha = (1 - dist / connectionDist) * 0.15;
          this.ctx.strokeStyle = `rgba(0, 232, 123, ${alpha})`;
          this.ctx.lineWidth = 0.5;
          this.ctx.beginPath();
          this.ctx.moveTo(a.x, a.y);
          this.ctx.lineTo(b.x, b.y);
          this.ctx.stroke();
        }
      }

      const mdx = a.x - this.mouse.x;
      const mdy = a.y - this.mouse.y;
      const mDist = Math.sqrt(mdx * mdx + mdy * mdy);
      if (mDist < mouseDist) {
        const alpha = (1 - mDist / mouseDist) * 0.3;
        this.ctx.strokeStyle = `rgba(0, 232, 123, ${alpha})`;
        this.ctx.lineWidth = 0.8;
        this.ctx.beginPath();
        this.ctx.moveTo(a.x, a.y);
        this.ctx.lineTo(this.mouse.x, this.mouse.y);
        this.ctx.stroke();
      }

      this.ctx.fillStyle = `rgba(0, 232, 123, ${a.opacity})`;
      this.ctx.beginPath();
      this.ctx.arc(a.x, a.y, a.r, 0, Math.PI * 2);
      this.ctx.fill();
    }
  }
}

// ─── SCROLL REVEAL ───

function initScrollReveal() {
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
        }
      }
    },
    { threshold: 0.1, rootMargin: '0px 0px -40px 0px' }
  );

  document.querySelectorAll('.reveal').forEach((el) => observer.observe(el));
}

// ─── NAVBAR SCROLL ───

function initNavScroll() {
  const nav = document.getElementById('nav');
  let ticking = false;

  window.addEventListener('scroll', () => {
    if (!ticking) {
      requestAnimationFrame(() => {
        nav.classList.toggle('scrolled', window.scrollY > 60);
        ticking = false;
      });
      ticking = true;
    }
  });
}

const runtimeMetrics = {
  binaryDisplay: '35 KB',
};

function setText(id, value) {
  const el = document.getElementById(id);
  if (el) el.textContent = value;
}

function formatDateUtc(iso) {
  if (!iso) return '—';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toISOString().replace('T', ' ').replace('.000Z', 'Z');
}

function logScaledWidth(value, maxValue) {
  if (!Number.isFinite(value) || value <= 0) return 0;
  if (!Number.isFinite(maxValue) || maxValue <= 0) return 0;
  const floor = 8;
  const ratio = Math.log10(value + 1) / Math.log10(maxValue + 1);
  return Math.min(100, Math.max(floor, floor + ratio * (100 - floor)));
}

function applyBenchmarkData(data) {
  const languages = data?.languages;
  if (!languages) return;

  const rows = Array.from(document.querySelectorAll('[data-bench-row]'));
  const maxByMetric = new Map();

  for (const row of rows) {
    const metric = row.dataset.benchMetric;
    const lang = row.dataset.benchLang;
    const value = languages?.[lang]?.[metric];
    if (typeof metric === 'string' && typeof value === 'number' && Number.isFinite(value)) {
      maxByMetric.set(metric, Math.max(maxByMetric.get(metric) ?? 0, value));
    }
  }

  for (const row of rows) {
    const metric = row.dataset.benchMetric;
    const lang = row.dataset.benchLang;
    if (!metric || !lang) continue;

    const langData = languages[lang];
    if (!langData) continue;

    const value = langData[metric];
    const display = langData[`${metric}_display`];
    const fill = row.querySelector('[data-bench-fill]');
    const valueEl = row.querySelector('[data-bench-value]');

    if (typeof value === 'number' && Number.isFinite(value) && fill) {
      const maxValue = maxByMetric.get(metric) ?? value;
      const width = logScaledWidth(value, maxValue);
      fill.dataset.width = width.toFixed(1);
      if (fill.classList.contains('animated')) {
        fill.style.setProperty('--bar-w', `${width}%`);
      }
    }

    if (valueEl && typeof display === 'string' && display.length > 0) {
      valueEl.textContent = display;
    }
  }

  const asm = languages.assembly;
  if (asm) {
    const binaryKB = typeof asm.binary_kb === 'number' ? asm.binary_kb : null;
    const startupMs = typeof asm.startup_ms === 'number' ? asm.startup_ms : null;
    const ramKB = typeof asm.ram_kb === 'number' ? asm.ram_kb : null;

    if (binaryKB !== null) setText('bench-hero-binary', Math.floor(binaryKB).toString());
    if (startupMs !== null) setText('bench-hero-startup', Math.floor(startupMs).toString());
    if (ramKB !== null) setText('bench-hero-ram', Math.floor(ramKB).toString());
    if (typeof asm.binary_display === 'string') {
      setText('bench-progression-asm-size', asm.binary_display);
      runtimeMetrics.binaryDisplay = asm.binary_display;
    }
  }

  const env = data.environment ?? {};
  setText('bench-cond-machine', `${env.machine_model ?? '—'} (${env.arch ?? '—'})`);
  setText('bench-cond-os', `${env.os ?? '—'} (${env.os_build ?? '—'})`);
  setText('bench-cond-cpu', env.cpu ?? '—');
  setText(
    'bench-cond-memory',
    typeof env.memory_gb === 'number' ? `${env.memory_gb} GB` : (env.memory_bytes ? `${env.memory_bytes} bytes` : '—')
  );
  setText('bench-cond-date', formatDateUtc(data.generated_at_utc));

  const notes = Array.isArray(data?.methodology?.notes) ? data.methodology.notes.join(' ') : '';
  if (notes) setText('bench-cond-notes', notes);
}

async function initBenchmarksFromJson() {
  try {
    const url = `${import.meta.env.BASE_URL}benchmarks.json`;
    const response = await fetch(url, { cache: 'no-store' });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    applyBenchmarkData(data);
  } catch (err) {
    console.warn('Benchmark JSON unavailable, using inline defaults.', err);
  }
}

// ─── BENCHMARK BAR ANIMATIONS ───

function initBenchmarkBars() {
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          const fills = entry.target.querySelectorAll('.bar-fill');
          fills.forEach((fill, i) => {
            const width = fill.dataset.width;
            fill.style.setProperty('--bar-w', width + '%');
            setTimeout(() => fill.classList.add('animated'), i * 120);
          });
          observer.unobserve(entry.target);
        }
      }
    },
    { threshold: 0.3 }
  );

  document.querySelectorAll('.benchmark-card').forEach((card) => observer.observe(card));
}

// ─── COPY TO CLIPBOARD ───

function initCopyButtons() {
  document.querySelectorAll('.copy-btn').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const text = btn.dataset.copy;
      try {
        await navigator.clipboard.writeText(text);
        btn.classList.add('copied');
        btn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M20 6L9 17l-5-5"/></svg>`;
        setTimeout(() => {
          btn.classList.remove('copied');
          btn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>`;
        }, 2000);
      } catch {
        /* clipboard API may not be available in non-HTTPS contexts */
      }
    });
  });
}

// ─── TYPING EFFECT ───

function initTypingEffect() {
  const el = document.getElementById('typing-output');
  if (!el) return;

  const text = `Hello! I'm running in ${runtimeMetrics.binaryDisplay} of pure ARM64 assembly. How can I help you today?`;
  let i = 0;

  const observer = new IntersectionObserver(
    (entries) => {
      if (entries[0].isIntersecting) {
        observer.disconnect();
        typeChar();
      }
    },
    { threshold: 0.5 }
  );

  observer.observe(el);

  function typeChar() {
    if (i < text.length) {
      el.textContent += text[i];
      i++;
      setTimeout(typeChar, 25 + Math.random() * 35);
    } else {
      el.style.borderRight = 'none';
    }
  }
}

// ─── SMOOTH ANCHOR SCROLL ───

function initSmoothScroll() {
  document.querySelectorAll('a[href^="#"]').forEach((link) => {
    link.addEventListener('click', (e) => {
      const id = link.getAttribute('href');
      if (id === '#') return;
      const target = document.querySelector(id);
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  });
}

// ─── SOURCE CODE VIEWER ───

function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function highlightASM(code) {
  return code.split('\n').map((raw) => {
    let line = escapeHtml(raw);

    // Strings (must be first — protect from other replacements)
    line = line.replace(/("(?:[^"\\]|\\.)*")/g, '<span class="hl-string">$1</span>');

    // Comments (// to end of line, but not inside strings)
    line = line.replace(/(\/\/.*)$/g, '<span class="hl-comment">$1</span>');

    // Directives (.global, .section, .include, .set, .p2align, .ascii, .asciz, .data, .text, .bss, .zero, .space, .byte, .quad, .long, .balign, .macro, .endm, .if, .endif, .equ, .extern, .type, .size, .loc, .file)
    line = line.replace(/(?<![.\w])(\.(?:global|globl|section|include|set|p2align|balign|ascii|asciz|byte|short|long|quad|zero|space|data|text|bss|macro|endm|if|else|endif|equ|extern|type|size|loc|file|build_version|subsections_via_symbols))\b/g, '<span class="hl-directive">$1</span>');

    // Labels (at start of line or after whitespace: _symbol: or .Llocal:)
    line = line.replace(/^(\s*)((?:_[\w.]+|\.L[\w.]+):)/gm, '$1<span class="hl-label">$2</span>');

    // Registers (x0-x30, w0-w30, sp, lr, fp, xzr, wzr, v0-v31, q0-q31, d0-d31, s0-s31)
    line = line.replace(/\b((?:[xwvqds](?:[12]?[0-9]|3[01]))|sp|lr|fp|xzr|wzr)\b/g, '<span class="hl-register">$1</span>');

    // Numbers (#imm, 0x hex, plain integers — but not inside already-highlighted spans)
    line = line.replace(/(#-?(?:0x[0-9a-fA-F]+|\d+))\b/g, '<span class="hl-number">$1</span>');
    line = line.replace(/\b(0x[0-9a-fA-F]+)\b/g, '<span class="hl-number">$1</span>');

    return `<span class="line">${line}</span>`;
  }).join('\n');
}

function initSourceViewer() {
  const overlay = document.getElementById('source-overlay');
  const filenameEl = document.getElementById('source-filename');
  const linesEl = document.getElementById('source-lines');
  const codeEl = document.getElementById('source-code');
  const closeBtn = document.getElementById('source-close');
  if (!overlay) return;

  function open(filename) {
    const base = import.meta.env.BASE_URL || '/';
    fetch(`${base}source/${filename}`)
      .then((r) => { if (!r.ok) throw new Error(r.status); return r.text(); })
      .then((code) => {
        const lineCount = code.split('\n').length;
        filenameEl.textContent = filename;
        linesEl.textContent = `${lineCount} lines`;
        codeEl.innerHTML = highlightASM(code);
        overlay.classList.add('active');
        document.body.style.overflow = 'hidden';
      })
      .catch((err) => console.warn('Failed to load source:', err));
  }

  function close() {
    overlay.classList.remove('active');
    document.body.style.overflow = '';
  }

  // Click handlers on file entries
  document.querySelectorAll('.file-entry[data-file]').forEach((entry) => {
    entry.addEventListener('click', () => open(entry.dataset.file));
  });

  closeBtn.addEventListener('click', close);
  overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && overlay.classList.contains('active')) close();
  });
}

// ─── GLOSSARY POPOVERS ───

const glossary = {
  'arm64': {
    title: 'ARM64',
    aka: 'AArch64 — 64-bit ARM instruction set',
    body: 'The instruction set used by <strong>Apple Silicon</strong> (M1–M5) and most modern phones. Each instruction is exactly 4 bytes. It\'s a RISC architecture — simple instructions, 31 general-purpose registers, designed for high throughput at low power.',
    analogy: 'Think x86 is a Swiss Army knife — ARM64 is a scalpel. Fewer tricks, but every cut is precise and fast.',
  },
  'libsystem': {
    title: 'libSystem',
    aka: 'macOS kernel interface library',
    body: 'The thinnest possible layer between your code and the macOS kernel. Provides <strong>write()</strong>, <strong>read()</strong>, <strong>mmap()</strong>, <strong>exit()</strong> and other OS primitives. Every macOS program links against it — it\'s the one dependency you literally cannot avoid.',
    analogy: 'If your code is a letter, libSystem is the postal service — it physically delivers your requests to the OS.',
  },
  'apple-silicon': {
    title: 'Apple Silicon',
    aka: 'Apple\'s ARM64-based SoC family',
    body: 'Apple\'s custom chips (M1, M2, M3, M4, M5) that power Macs, iPads, and iPhones. They use the <strong>ARM64 instruction set</strong> and feature unified memory (CPU and GPU share the same RAM), high-efficiency cores, and wide decode pipelines that can execute 8+ instructions per cycle.',
  },
  'neon-simd': {
    title: 'NEON SIMD',
    aka: 'Single Instruction, Multiple Data',
    body: 'ARM\'s built-in vector engine. Instead of processing one byte at a time, NEON handles <strong>16 bytes simultaneously</strong> using special 128-bit registers (v0–v31). AssemblyClaw uses this to scan through JSON and strings at 16 bytes per cycle.',
    analogy: 'Like reading a book one word at a time vs. photographing an entire paragraph and searching the image all at once.',
  },
  'cmeq': {
    title: 'CMEQ',
    aka: 'Compare Equal (Vector)',
    body: 'An ARM NEON instruction that compares <strong>16 bytes at once</strong> against a target value. For example, finding every <code>"</code> character in a string. It produces a mask: matching bytes become 0xFF, non-matches become 0x00.',
    analogy: 'Like shining a UV light on a page — all matching characters instantly glow, while everything else stays dark.',
  },
  'umaxv': {
    title: 'UMAXV',
    aka: 'Unsigned Maximum across Vector',
    body: 'Collapses a 16-byte comparison result into a <strong>single value</strong>. If any byte matched (is non-zero), the result is non-zero. Turns "did any of these 16 bytes match?" into a yes/no answer in <strong>one instruction</strong>.',
    analogy: 'After the UV light reveals the matches, UMAXV is glancing at the page and instantly knowing "yes, there\'s at least one."',
  },
  'vector-instructions': {
    title: 'Vector Instructions',
    aka: 'SIMD — parallel data processing',
    body: 'CPU instructions that operate on <strong>multiple data elements simultaneously</strong>. ARM NEON provides 128-bit registers that hold 16 bytes, 8 shorts, 4 ints, or 2 longs. One instruction processes all elements in parallel — this is how modern CPUs achieve throughput far beyond byte-at-a-time processing.',
  },
  'cache-aligned': {
    title: 'Cache-Aligned',
    aka: 'Memory alignment to cache line boundaries',
    body: 'Placing data at memory addresses that are <strong>exact multiples of the cache line size</strong>. On Apple M4/M5, cache lines are 128 bytes. When data is aligned, the CPU loads it in one read. Misaligned data can straddle two cache lines, causing two reads — doubling the latency.',
    analogy: 'Like parking a car perfectly within the lines vs. across two spaces — aligned data takes one "parking spot read," misaligned takes two.',
  },
  'cache-lines': {
    title: 'Cache Lines',
    aka: 'Smallest unit of CPU cache transfer',
    body: 'The smallest chunk of data the CPU moves between main memory and its fast on-chip cache. On <strong>Apple M4/M5, each cache line is 128 bytes</strong>. When you access one byte, the CPU actually fetches the entire 128-byte line containing it. Alignment ensures your data structures don\'t straddle two lines.',
  },
  'branchless': {
    title: 'Branchless Code',
    aka: 'Avoiding conditional jumps',
    body: 'Code written to avoid <code>if/else</code> jumps entirely. Modern CPUs <strong>speculate</strong> which branch to take — when they guess wrong, they waste ~12 cycles flushing the pipeline. Branchless code uses conditional-select instructions (<strong>CSEL/CSETM</strong>) instead, guaranteeing constant execution time regardless of the data.',
    analogy: 'Instead of asking "should I go left or right?" at every fork, you walk both paths simultaneously and pick the result at the end.',
  },
  'csel': {
    title: 'CSEL',
    aka: 'Conditional Select',
    body: 'An ARM64 instruction that picks one of two register values based on a condition flag — <strong>without branching</strong>. It\'s a hardware ternary operator: <code>result = condition ? A : B</code>, executed in a single cycle with zero pipeline risk.',
    analogy: 'In JavaScript: <code>const x = cond ? a : b</code> — but CSEL does this in the hardware itself, with zero branch prediction penalty.',
  },
  'csetm': {
    title: 'CSETM',
    aka: 'Conditional Set Mask',
    body: 'Sets a register to <strong>all 1-bits</strong> (0xFFFF…) if a condition is true, or <strong>all 0-bits</strong> if false. Creates bitmasks for branchless logic — you AND/OR the mask with data to conditionally keep or zero out values, without ever branching.',
  },
  'branch-prediction': {
    title: 'Branch Prediction',
    aka: 'CPU speculative execution',
    body: 'The CPU\'s mechanism for <strong>guessing</strong> which way an if/else will go before it\'s actually computed. Correct guesses keep the pipeline full. Wrong guesses ("mispredicts") cost <strong>~12–14 cycles</strong> on Apple Silicon as the CPU flushes speculative work and restarts from the correct path.',
    analogy: 'Like pre-loading the next webpage you think the user will click. Guess right → instant load. Guess wrong → visible delay while you fetch the actual page.',
  },
  'arena-allocator': {
    title: 'Arena Allocator',
    aka: 'Bump/region-based memory allocation',
    body: 'A memory strategy where one large block is reserved upfront (via <strong>mmap</strong>), and pieces are handed out <strong>sequentially</strong> — just bump a pointer forward. Nothing is individually freed. When done, the entire arena is released at once. Eliminates malloc/free overhead and fragmentation entirely.',
    analogy: 'Like writing on a notepad — just keep writing forward. When you\'re done, tear off the whole pad. Never erase individual lines.',
  },
  'mmap': {
    title: 'mmap',
    aka: 'Memory Map — OS-level allocation',
    body: 'A <strong>system call</strong> that asks the OS to map a region of virtual memory directly, bypassing malloc. The kernel hands back a contiguous block backed by physical pages <strong>on demand</strong> (lazy allocation). The memory is guaranteed zeroed by the OS. No initialization overhead.',
    analogy: 'malloc is like buying memory from a store (middleman markup). mmap is going directly to the factory (the OS kernel).',
  },
  'fragmentation': {
    title: 'Memory Fragmentation',
    aka: 'Unusable gaps between allocations',
    body: 'When memory is allocated and freed in random order (as with malloc/free), small <strong>unusable gaps</strong> appear between active allocations. Over time, you might have plenty of free memory but no contiguous block large enough to use. Arena allocators avoid this entirely by allocating sequentially and freeing everything at once.',
  },
  'zero-copy': {
    title: 'Zero-Copy Strings',
    aka: 'No-allocation string views',
    body: 'Instead of duplicating string data into new buffers, strings are represented as a <strong>pointer + length</strong> (16 bytes total). No copying, no allocation — just a lightweight view into existing memory. This is how Rust slices (<code>&str</code>) and Go strings work internally.',
    analogy: 'Instead of photocopying a page to quote one sentence, you just point at the page and say "from here to here."',
  },
  'ptr-len': {
    title: 'ptr+len',
    aka: 'Pointer + Length string representation',
    body: 'A string stored as two values: a <strong>memory address</strong> (pointer) to the first byte, and a <strong>byte count</strong> (length). Unlike C strings that scan for a NUL byte to find the end, ptr+len strings know their exact size — enabling <strong>O(1)</strong> length checks and safe handling of binary data.',
  },
  'nul-terminator': {
    title: 'NUL Terminator',
    aka: 'C-style string ending (0x00)',
    body: 'The byte <code>0x00</code> placed at the end of C-style strings to mark where the string ends. Finding a string\'s length requires scanning <strong>every byte</strong> until hitting 0x00 — an O(n) operation. Strings also can\'t safely contain the zero byte. ptr+len representation avoids both limitations.',
  },
  'syscalls': {
    title: 'System Calls',
    aka: 'Direct kernel requests',
    body: 'Requests from a program to the <strong>operating system kernel</strong>. When AssemblyClaw calls write() or read(), it triggers a hardware exception that transfers control to macOS, which performs the I/O and returns. No middleman library code — the most direct path from code to kernel.',
    analogy: 'Like yelling directly at the OS: "Write these bytes to this file!" — no receptionist, no queue, just a direct line.',
  },
  'ffi': {
    title: 'FFI',
    aka: 'Foreign Function Interface',
    body: 'A mechanism for calling functions written in <strong>one language from another</strong>. AssemblyClaw\'s assembly code calls C functions in libcurl and libSystem by following the ARM64 calling convention: arguments in registers x0–x7, return value in x0. No wrappers or bindings needed.',
    analogy: 'Like speaking another language fluently enough to order at a restaurant — you follow their conventions (register protocol) and get exactly what you asked for.',
  },
  'libc': {
    title: 'libc',
    aka: 'C Standard Library',
    body: 'The C standard library provides convenience wrappers like <strong>printf()</strong>, <strong>malloc()</strong>, <strong>strlen()</strong> around raw system calls. These wrappers add overhead — argument validation, buffering, errno handling. AssemblyClaw bypasses them and calls the underlying OS functions directly, shaving off every unnecessary instruction.',
  },
  'single-binary': {
    title: 'Single Binary',
    aka: 'Self-contained executable',
    body: 'A program compiled into <strong>one standalone file</strong> with no external dependencies to install. No node_modules, no .dll/.so files, no runtime. Just copy the binary anywhere and run it. Zig, Go, and Rust excel at producing single binaries.',
    analogy: 'Like a portable app on a USB stick vs. an installer that scatters files across your system.',
  },
};

function initGlossary() {
  const terms = document.querySelectorAll('.term[data-term]');
  if (!terms.length) return;

  // Create popover element
  const popover = document.createElement('div');
  popover.className = 'term-popover';
  popover.innerHTML = `
    <div class="term-popover-arrow"></div>
    <div class="term-popover-title"></div>
    <div class="term-popover-aka"></div>
    <div class="term-popover-body"></div>
    <div class="term-popover-analogy"></div>
  `;
  document.body.appendChild(popover);

  const arrow = popover.querySelector('.term-popover-arrow');
  const titleEl = popover.querySelector('.term-popover-title');
  const akaEl = popover.querySelector('.term-popover-aka');
  const bodyEl = popover.querySelector('.term-popover-body');
  const analogyEl = popover.querySelector('.term-popover-analogy');

  let activeTerm = null;

  function show(term) {
    const key = term.dataset.term;
    const entry = glossary[key];
    if (!entry) return;

    titleEl.textContent = entry.title;
    if (entry.aka) {
      akaEl.textContent = entry.aka;
      akaEl.style.display = '';
    } else {
      akaEl.style.display = 'none';
    }
    bodyEl.innerHTML = entry.body;
    if (entry.analogy) {
      analogyEl.textContent = entry.analogy;
      analogyEl.style.display = '';
    } else {
      analogyEl.style.display = 'none';
    }

    // Position: prefer below the term, flip above if no space
    popover.classList.remove('visible');
    popover.style.left = '0px';
    popover.style.top = '0px';
    arrow.classList.remove('term-popover-arrow--bottom');

    // Make visible to measure
    popover.style.opacity = '0';
    popover.style.pointerEvents = 'none';
    popover.classList.add('visible');

    const rect = term.getBoundingClientRect();
    const pop = popover.getBoundingClientRect();
    const gap = 10;
    const margin = 16;

    let top = rect.bottom + gap;
    let flipAbove = false;

    // Flip above if below would overflow viewport
    if (top + pop.height > window.innerHeight - margin) {
      top = rect.top - pop.height - gap;
      flipAbove = true;
    }

    // Horizontal: center on term, clamp to viewport
    let left = rect.left + rect.width / 2 - pop.width / 2;
    left = Math.max(margin, Math.min(left, window.innerWidth - pop.width - margin));

    popover.style.left = `${left}px`;
    popover.style.top = `${top}px`;

    // Arrow position
    const arrowLeft = Math.max(12, Math.min(rect.left + rect.width / 2 - left - 5, pop.width - 22));
    arrow.style.left = `${arrowLeft}px`;
    if (flipAbove) {
      arrow.classList.add('term-popover-arrow--bottom');
    }

    // Animate in
    popover.style.opacity = '';
    popover.style.pointerEvents = '';
    popover.style.transform = flipAbove ? 'translateY(-6px)' : 'translateY(6px)';
    requestAnimationFrame(() => {
      popover.style.transform = 'translateY(0)';
    });

    activeTerm = term;
  }

  function hide() {
    popover.classList.remove('visible');
    activeTerm = null;
  }

  terms.forEach((term) => {
    term.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      if (activeTerm === term) {
        hide();
      } else {
        show(term);
      }
    });
  });

  document.addEventListener('click', (e) => {
    if (activeTerm && !popover.contains(e.target)) {
      hide();
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && activeTerm) hide();
  });

  // Reposition on scroll/resize
  let repositionRaf = 0;
  function reposition() {
    if (!activeTerm) return;
    cancelAnimationFrame(repositionRaf);
    repositionRaf = requestAnimationFrame(() => show(activeTerm));
  }
  window.addEventListener('scroll', reposition, { passive: true });
  window.addEventListener('resize', reposition, { passive: true });
}

// ─── INIT ───

document.addEventListener('DOMContentLoaded', async () => {
  const canvas = document.getElementById('hero-canvas');
  if (canvas) new CircuitCanvas(canvas);

  await initBenchmarksFromJson();
  initScrollReveal();
  initNavScroll();
  initBenchmarkBars();
  initCopyButtons();
  initTypingEffect();
  initSmoothScroll();
  initSourceViewer();
  initGlossary();

  // trigger hero reveals immediately with stagger
  const heroReveals = document.querySelectorAll('.hero .reveal');
  heroReveals.forEach((el, i) => {
    setTimeout(() => el.classList.add('visible'), 200 + i * 150);
  });
});
