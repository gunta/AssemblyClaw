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
    // Round up to 16-byte alignment
    add     x0, x0, #15
    and     x0, x0, #~15

    adrp    x1, _g_arena@PAGE
    add     x1, x1, _g_arena@PAGEOFF

    ldr     x2, [x1, #ARENA_OFFSET]    // current offset
    ldr     x3, [x1, #ARENA_CAPACITY]  // capacity

    add     x4, x2, x0                 // new offset
    cmp     x4, x3
    b.gt    .Larena_alloc_oom           // would exceed capacity

    // Update offset
    str     x4, [x1, #ARENA_OFFSET]

    // Return pointer = base + old offset
    ldr     x5, [x1, #ARENA_BASE]
    add     x0, x5, x2
    ret

.Larena_alloc_oom:
    mov     x0, #0                      // return NULL
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
