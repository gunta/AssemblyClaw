// memory.s — Arena allocator (mmap-backed)
// ARM64 macOS — M4/M5 Pro/Max optimized
//
// Zero-fragmentation arena with 64KB pages.
// All allocations are 16-byte aligned (NEON friendly).
// Reset without freeing individual allocations.

.include "include/constants.inc"

.section __TEXT,__text,regular,pure_instructions
.p2align 4

// Arena structure layout (in .bss):
//   +0:  base pointer (start of mmap'd region)
//   +8:  current offset (next free byte)
//   +16: capacity (total bytes mmap'd)
//   +24: page count (for munmap)

.set ARENA_BASE,     0
.set ARENA_OFFSET,   8
.set ARENA_CAPACITY, 16
.set ARENA_PAGES,    24
.set ARENA_SIZE,     32

// ──────────────────────────────────────────────────────────────────
// _arena_init: initialize the global arena
//   x0 = initial size in bytes (rounded up to page size)
//   Returns: x0 = 0 on success, error code on failure
// ──────────────────────────────────────────────────────────────────
.global _arena_init
_arena_init:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    // Round up to ARENA_PAGE_SIZE (65536 = 0x10000)
    // 65535 = 0xFFFF doesn't fit in 12-bit imm, use movz
    movz    x1, #0xFFFF                 // ARENA_PAGE_SIZE - 1
    add     x0, x0, x1
    bic     x0, x0, x1                  // clear low 16 bits (align up)
    mov     x19, x0                     // save size

    // mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_ANON|MAP_PRIVATE, -1, 0)
    mov     x0, #0                      // addr = NULL
    mov     x1, x19                     // length
    mov     x2, #3                      // PROT_READ|PROT_WRITE = 0x01|0x02
    movz    x3, #0x1002                 // MAP_ANON|MAP_PRIVATE = 0x1000|0x0002
    mov     x4, #-1                     // fd = -1
    mov     x5, #0                      // offset = 0
    bl      _mmap

    // Check for MAP_FAILED (-1)
    cmn     x0, #1
    b.eq    .Larena_init_fail

    // Store arena state
    adrp    x1, _g_arena@PAGE
    add     x1, x1, _g_arena@PAGEOFF
    str     x0, [x1, #ARENA_BASE]      // base = mmap result
    str     xzr, [x1, #ARENA_OFFSET]   // offset = 0
    str     x19, [x1, #ARENA_CAPACITY] // capacity = size
    lsr     x2, x19, #16               // pages = size / 64KB
    str     x2, [x1, #ARENA_PAGES]

    mov     x0, #ERR_OK
    b       .Larena_init_ret

.Larena_init_fail:
    mov     x0, #ERR_OUT_OF_MEMORY

.Larena_init_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ──────────────────────────────────────────────────────────────────
// _arena_alloc: allocate bytes from arena
//   x0 = size in bytes
//   Returns: x0 = pointer (16-byte aligned), or NULL if OOM
// ──────────────────────────────────────────────────────────────────
.global _arena_alloc
_arena_alloc:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    // Round up to 16-byte alignment.
    add     x19, x0, #15
    and     x19, x19, #~15
    cbz     x19, .Larena_alloc_fail

    adrp    x20, _g_arena@PAGE
    add     x20, x20, _g_arena@PAGEOFF

    ldr     x21, [x20, #ARENA_OFFSET]   // current offset
    ldr     x22, [x20, #ARENA_CAPACITY] // capacity
    ldr     x23, [x20, #ARENA_BASE]     // base
    cbz     x23, .Larena_alloc_fail

    add     x24, x21, x19               // required new offset
    cmp     x24, x22
    b.ls    .Larena_alloc_fit

    // Grow arena: double capacity until it fits the requested offset.
    mov     x25, x22
    cbz     x25, .Larena_alloc_fail

.Larena_grow_loop:
    cmp     x25, x24
    b.ge    .Larena_grow_ready
    lsl     x25, x25, #1
    cbz     x25, .Larena_alloc_fail
    b       .Larena_grow_loop

.Larena_grow_ready:
    // mmap new backing region
    mov     x0, #0
    mov     x1, x25
    mov     x2, #3
    movz    x3, #0x1002
    mov     x4, #-1
    mov     x5, #0
    bl      _mmap
    cmn     x0, #1
    b.eq    .Larena_alloc_fail
    mov     x26, x0                     // new base

    // Copy used bytes into the new region.
    cbz     x21, .Larena_grow_skip_copy
    mov     x0, x26
    mov     x1, x23
    mov     x2, x21
    bl      _memcpy_simd

.Larena_grow_skip_copy:
    // Release old region.
    mov     x0, x23
    mov     x1, x22
    bl      _munmap

    // Publish new arena state.
    str     x26, [x20, #ARENA_BASE]
    str     x25, [x20, #ARENA_CAPACITY]
    lsr     x0, x25, #16
    str     x0, [x20, #ARENA_PAGES]
    mov     x23, x26
    mov     x22, x25

.Larena_alloc_fit:
    str     x24, [x20, #ARENA_OFFSET]
    add     x0, x23, x21
    b       .Larena_alloc_ret

.Larena_alloc_fail:
    mov     x0, #0

.Larena_alloc_ret:
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

// ──────────────────────────────────────────────────────────────────
// _arena_reset: reset arena (free all allocations at once)
//   No arguments, no return value.
// ──────────────────────────────────────────────────────────────────
.global _arena_reset
_arena_reset:
    adrp    x0, _g_arena@PAGE
    add     x0, x0, _g_arena@PAGEOFF
    str     xzr, [x0, #ARENA_OFFSET]   // offset = 0
    ret

// ──────────────────────────────────────────────────────────────────
// _arena_destroy: unmap arena memory
//   Returns: x0 = 0 on success
// ──────────────────────────────────────────────────────────────────
.global _arena_destroy
_arena_destroy:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x1, _g_arena@PAGE
    add     x1, x1, _g_arena@PAGEOFF
    ldr     x0, [x1, #ARENA_BASE]
    ldr     x2, [x1, #ARENA_CAPACITY]

    cbz     x0, .Larena_destroy_done    // not initialized

    // munmap(base, capacity)
    mov     x1, x2
    bl      _munmap

    // Clear arena state
    adrp    x1, _g_arena@PAGE
    add     x1, x1, _g_arena@PAGEOFF
    stp     xzr, xzr, [x1, #ARENA_BASE]
    stp     xzr, xzr, [x1, #ARENA_CAPACITY]

.Larena_destroy_done:
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

// ──────────────────────────────────────────────────────────────────
// _arena_used: return bytes currently allocated
//   Returns: x0 = bytes used
// ──────────────────────────────────────────────────────────────────
.global _arena_used
_arena_used:
    adrp    x0, _g_arena@PAGE
    add     x0, x0, _g_arena@PAGEOFF
    ldr     x0, [x0, #ARENA_OFFSET]
    ret

// ── BSS: Global arena state ──
.section __DATA,__bss
.p2align 4
.global _g_arena
_g_arena:
    .space  ARENA_SIZE
