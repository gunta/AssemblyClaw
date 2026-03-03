/* ═══════════════════════════════════════════════
   AssemblyClaw — Interactions & Animations
   ═══════════════════════════════════════════════ */

declare global {
  interface Window {
    __GLOSSARY__: Record<string, { title: string; aka: string; body: string; analogy?: string }>;
    __TYPING_TEXT__: string;
    __LANG__: string;
  }
}

// ─── HERO CANVAS: Circuit Particle Network ───

class CircuitCanvas {
  canvas: HTMLCanvasElement;
  ctx: CanvasRenderingContext2D;
  particles: { x: number; y: number; vx: number; vy: number; r: number; opacity: number }[];
  mouse: { x: number; y: number };
  dpr: number;
  w: number;
  h: number;

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d')!;
    this.particles = [];
    this.mouse = { x: -1000, y: -1000 };
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.w = 0;
    this.h = 0;
    this.resize();
    this.init();
    this.bind();
    this.loop();
  }

  resize() {
    const rect = this.canvas.parentElement!.getBoundingClientRect();
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
    this.canvas.parentElement!.addEventListener('mousemove', (e) => {
      const rect = this.canvas.parentElement!.getBoundingClientRect();
      this.mouse.x = e.clientX - rect.left;
      this.mouse.y = e.clientY - rect.top;
    });
    this.canvas.parentElement!.addEventListener('mouseleave', () => {
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
  if (!nav) return;
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

function setText(id: string, value: string) {
  const el = document.getElementById(id);
  if (el) el.textContent = value;
}

function formatDateUtc(iso: string) {
  if (!iso) return '—';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toISOString().replace('T', ' ').replace('.000Z', 'Z');
}

function logScaledWidth(value: number, maxValue: number) {
  if (!Number.isFinite(value) || value <= 0) return 0;
  if (!Number.isFinite(maxValue) || maxValue <= 0) return 0;
  const floor = 8;
  const ratio = Math.log10(value + 1) / Math.log10(maxValue + 1);
  return Math.min(100, Math.max(floor, floor + ratio * (100 - floor)));
}

function applyBenchmarkData(data: any) {
  const languages = data?.languages;
  if (!languages) return;

  const rows = Array.from(document.querySelectorAll('[data-bench-row]')) as HTMLElement[];
  const maxByMetric = new Map<string, number>();

  for (const row of rows) {
    const metric = row.dataset.benchMetric;
    const lang = row.dataset.benchLang;
    const value = languages?.[lang!]?.[metric!];
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
    const fill = row.querySelector('[data-bench-fill]') as HTMLElement | null;
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
            const width = (fill as HTMLElement).dataset.width;
            (fill as HTMLElement).style.setProperty('--bar-w', width + '%');
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
      const text = (btn as HTMLElement).dataset.copy!;
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

  const template = window.__TYPING_TEXT__ || "Hello! I'm running in {binarySize} of pure ARM64 assembly. How can I help you today?";
  const text = template.replace('{binarySize}', runtimeMetrics.binaryDisplay);
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
      el!.textContent += text[i];
      i++;
      setTimeout(typeChar, 25 + Math.random() * 35);
    } else {
      el!.style.borderRight = 'none';
    }
  }
}

// ─── SMOOTH ANCHOR SCROLL ───

function initSmoothScroll() {
  document.querySelectorAll('a[href^="#"]').forEach((link) => {
    link.addEventListener('click', (e) => {
      const id = link.getAttribute('href');
      if (id === '#') return;
      const target = document.querySelector(id!);
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  });
}

// ─── SOURCE CODE VIEWER ───

function escapeHtml(s: string) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function highlightASM(code: string) {
  return code.split('\n').map((raw) => {
    let line = escapeHtml(raw);

    line = line.replace(/("(?:[^"\\]|\\.)*")/g, '<span class="hl-string">$1</span>');
    line = line.replace(/(\/\/.*)$/g, '<span class="hl-comment">$1</span>');
    line = line.replace(/(?<![.\w])(\.(?:global|globl|section|include|set|p2align|balign|ascii|asciz|byte|short|long|quad|zero|space|data|text|bss|macro|endm|if|else|endif|equ|extern|type|size|loc|file|build_version|subsections_via_symbols))\b/g, '<span class="hl-directive">$1</span>');
    line = line.replace(/^(\s*)((?:_[\w.]+|\.L[\w.]+):)/gm, '$1<span class="hl-label">$2</span>');
    line = line.replace(/\b((?:[xwvqds](?:[12]?[0-9]|3[01]))|sp|lr|fp|xzr|wzr)\b/g, '<span class="hl-register">$1</span>');
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

  function open(filename: string) {
    const base = import.meta.env.BASE_URL || '/';
    fetch(`${base}source/${filename}`)
      .then((r) => { if (!r.ok) throw new Error(String(r.status)); return r.text(); })
      .then((code) => {
        const lineCount = code.split('\n').length;
        filenameEl!.textContent = filename;
        linesEl!.textContent = `${lineCount} lines`;
        codeEl!.innerHTML = highlightASM(code);
        overlay!.classList.add('active');
        document.body.style.overflow = 'hidden';
      })
      .catch((err) => console.warn('Failed to load source:', err));
  }

  function close() {
    overlay!.classList.remove('active');
    document.body.style.overflow = '';
  }

  document.querySelectorAll('.file-entry[data-file]').forEach((entry) => {
    entry.addEventListener('click', () => open((entry as HTMLElement).dataset.file!));
  });

  closeBtn!.addEventListener('click', close);
  overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && overlay!.classList.contains('active')) close();
  });
}

// ─── GLOSSARY POPOVERS ───

function initGlossary() {
  const glossary = window.__GLOSSARY__ || {};
  const terms = document.querySelectorAll('.term[data-term]');
  if (!terms.length) return;

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

  const arrow = popover.querySelector('.term-popover-arrow') as HTMLElement;
  const titleEl = popover.querySelector('.term-popover-title') as HTMLElement;
  const akaEl = popover.querySelector('.term-popover-aka') as HTMLElement;
  const bodyEl = popover.querySelector('.term-popover-body') as HTMLElement;
  const analogyEl = popover.querySelector('.term-popover-analogy') as HTMLElement;

  let activeTerm: Element | null = null;

  function show(term: Element) {
    const key = (term as HTMLElement).dataset.term!;
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

    popover.classList.remove('visible');
    popover.style.left = '0px';
    popover.style.top = '0px';
    arrow.classList.remove('term-popover-arrow--bottom');

    popover.style.opacity = '0';
    popover.style.pointerEvents = 'none';
    popover.classList.add('visible');

    const rect = term.getBoundingClientRect();
    const pop = popover.getBoundingClientRect();
    const gap = 10;
    const margin = 16;

    let top = rect.bottom + gap;
    let flipAbove = false;

    if (top + pop.height > window.innerHeight - margin) {
      top = rect.top - pop.height - gap;
      flipAbove = true;
    }

    let left = rect.left + rect.width / 2 - pop.width / 2;
    left = Math.max(margin, Math.min(left, window.innerWidth - pop.width - margin));

    popover.style.left = `${left}px`;
    popover.style.top = `${top}px`;

    const arrowLeft = Math.max(12, Math.min(rect.left + rect.width / 2 - left - 5, pop.width - 22));
    arrow.style.left = `${arrowLeft}px`;
    if (flipAbove) {
      arrow.classList.add('term-popover-arrow--bottom');
    }

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
    if (activeTerm && !popover.contains(e.target as Node)) {
      hide();
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && activeTerm) hide();
  });

  let repositionRaf = 0;
  function reposition() {
    if (!activeTerm) return;
    cancelAnimationFrame(repositionRaf);
    repositionRaf = requestAnimationFrame(() => show(activeTerm!));
  }
  window.addEventListener('scroll', reposition, { passive: true });
  window.addEventListener('resize', reposition, { passive: true });
}

// ─── INIT ───

document.addEventListener('DOMContentLoaded', async () => {
  const canvas = document.getElementById('hero-canvas') as HTMLCanvasElement | null;
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
