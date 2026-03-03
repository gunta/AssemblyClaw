export interface GlossaryEntry {
  title: string;
  aka: string;
  body: string;
  analogy?: string;
}

export const glossary: Record<string, GlossaryEntry> = {
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
    body: 'Apple\'s custom chips (M1, M2, M3, M4, M5) that power Macs, iPads, and iPhones. They use the <strong>ARM64 instruction set</strong> and unified memory (CPU and GPU share the same RAM).',
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
    body: 'Placing data at memory addresses that are <strong>exact multiples of an alignment boundary</strong>. Good alignment can reduce split loads and keep memory access patterns predictable.',
    analogy: 'Like parking a car perfectly within the lines vs. across two spaces — aligned data takes one "parking spot read," misaligned takes two.',
  },
  'cache-lines': {
    title: 'Cache Lines',
    aka: 'Smallest unit of CPU cache transfer',
    body: 'The smallest chunk of data the CPU moves between main memory and its fast on-chip cache. Accessing one byte can pull in a whole line, so alignment and locality matter for performance.',
  },
  'branchless': {
    title: 'Branchless Code',
    aka: 'Avoiding conditional jumps',
    body: 'Code written to reduce conditional jumps in hot paths. Modern CPUs speculate on branches; reducing unpredictable branches can improve throughput. One approach is using conditional-select instructions like <strong>CSEL</strong>.',
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
    body: 'The CPU\'s mechanism for <strong>guessing</strong> which way an if/else will go before it\'s actually computed. Correct guesses keep the pipeline full; wrong guesses require speculative work to be discarded and redone.',
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
    body: 'Requests from a program to the <strong>operating system kernel</strong>. In this project, assembly code calls macOS APIs exposed by libSystem (such as write/read wrappers) rather than issuing raw syscall instructions directly.',
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
    body: 'The C standard library provides convenience APIs like <strong>printf()</strong>, <strong>malloc()</strong>, and <strong>strlen()</strong>. AssemblyClaw mixes direct symbol calls with custom assembly implementations depending on the path.',
  },
  'single-binary': {
    title: 'Single Binary',
    aka: 'Self-contained executable',
    body: 'A program compiled into <strong>one standalone file</strong> with no external dependencies to install. No node_modules, no .dll/.so files, no runtime. Just copy the binary anywhere and run it. Zig, Go, and Rust excel at producing single binaries.',
    analogy: 'Like a portable app on a USB stick vs. an installer that scatters files across your system.',
  },
  'register-allocation': {
    title: 'Register Allocation',
    aka: 'Mapping variables to CPU registers',
    body: 'Registers are the <strong>fastest storage</strong> inside the CPU — accessed in a single cycle, no memory bus needed. ARM64 gives you 31 general-purpose registers (x0–x30). In assembly, you decide exactly which variable lives in which register. Compilers try to do this automatically but often "spill" values to RAM when they run out of registers or can\'t prove safety.',
    analogy: 'Like having 31 hands — in assembly you choose what each hand holds. A compiler might drop things on the floor (RAM) and pick them up again, wasting time.',
  },
  'gp-registers': {
    title: 'General-Purpose Registers',
    aka: 'x0–x30 on ARM64',
    body: 'ARM64 provides <strong>31 registers</strong>, each 64 bits wide — that\'s 248 bytes of instant-access storage inside the CPU. For comparison, x86-64 has only 16. More registers means fewer memory accesses, less "spilling" to RAM, and more data kept hot in the fastest possible location.',
  },
  'spilling': {
    title: 'Register Spilling',
    aka: 'When the CPU runs out of registers',
    body: 'When a program needs more live variables than available registers, the compiler <strong>"spills"</strong> some values to the stack (memory). Spills add extra loads/stores and can increase latency; hand-written assembly can reduce this by careful register planning.',
    analogy: 'Like a chef with limited counter space — if you have more ingredients than counters, you keep putting them in the fridge and taking them back out. Assembly gives you 31 counters and you decide what stays out.',
  },
  'isa-awareness': {
    title: 'ISA-Aware Code',
    aka: 'Coding to the instruction set architecture',
    body: 'Every CPU family (ARM64, x86, RISC-V) has a unique <strong>instruction set architecture</strong> with different strengths. ARM64 favors: fixed-width 4-byte instructions (fast decoding), load/store separation (predictable pipelines), and instruction fusion (two ops merged into one). Writing assembly that exploits these traits beats what a generic compiler produces.',
  },
  'isa': {
    title: 'ISA',
    aka: 'Instruction Set Architecture',
    body: 'The contract between software and hardware — it defines every instruction the CPU understands, how registers work, and how memory is addressed. <strong>ARM64 (AArch64)</strong> and <strong>x86-64</strong> are the two dominant ISAs today. They have fundamentally different design philosophies: ARM64 is RISC (simple, uniform instructions), x86-64 is CISC (complex, variable-length instructions).',
    analogy: 'Like speaking different languages to different CPUs. ARM64 is Japanese (consistent grammar, every word is the same length). x86 is English (irregular rules, words vary from 1 to 15 bytes).',
  },
  'fixed-width': {
    title: 'Fixed-Width Decoding',
    aka: 'Every ARM64 instruction is exactly 4 bytes',
    body: 'ARM64 instructions are always <strong>32 bits (4 bytes)</strong>. The CPU knows exactly where each instruction starts without scanning ahead. x86 instructions vary in length, which requires more complex decode logic.',
    analogy: 'Like a conveyor belt of identical boxes vs. a pile of packages in random sizes — fixed-size items are trivially fast to sort and process.',
  },
  'load-store': {
    title: 'Load/Store Discipline',
    aka: 'Separate memory ops from compute ops',
    body: 'ARM64 is a <strong>load/store architecture</strong>: arithmetic instructions only work on registers, never directly on memory. You must explicitly load data from RAM into a register, compute, then store back. This separation keeps the CPU pipeline clean and predictable — the hardware always knows which instructions hit memory and which don\'t.',
    analogy: 'Like a kitchen rule: ingredients go on the counter first, then you cook. You never chop directly inside the fridge. This discipline makes everything faster and more predictable.',
  },
  'instruction-fusion': {
    title: 'Instruction Fusion',
    aka: 'Two instructions executed as one',
    body: 'Apple Silicon can fuse certain instruction pairs into a <strong>single operation</strong>. For example, a compare (<code>CMP</code>) followed by a branch (<code>B.EQ</code>) may execute as one fused micro-op. The CPU detects these patterns in the decode stage. Writing assembly that creates fusible pairs gives you <strong>free performance</strong> that compilers don\'t always achieve.',
    analogy: 'Like a conveyor belt that spots two small packages going to the same address and merges them into one shipment — same result, half the handling.',
  },
};
