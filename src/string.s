// string.s — NEON SIMD string operations
// ARM64 macOS — M4/M5 Pro/Max optimized
//
// Key optimizations:
//   - 16 bytes/cycle null scan with CMEQ + UMAXV
//   - 16-byte LDR Q / STR Q block copies
//   - PRFM prefetch 256 bytes ahead
//   - Branchless CSEL for edge cases

.section __TEXT,__text,regular,pure_instructions
.p2align 4

// ──────────────────────────────────────────────────────────────────
// _strlen_simd: NEON-accelerated strlen
//   x0 = pointer to NUL-terminated string
//   Returns: x0 = length (not including NUL)
//
// Algorithm: scan 16 bytes at a time using CMEQ against zero vector.
// UMAXV collapses the comparison result to check for any NUL byte.
// ──────────────────────────────────────────────────────────────────
.global _strlen_simd
_strlen_simd:
    mov     x1, x0                      // save original pointer
    movi    v1.16b, #0                  // zero vector for comparison

    // Handle unaligned prefix (up to 15 bytes) byte-by-byte
    // Check alignment: x0 & 0xF
    ands    x2, x0, #0xF
    b.eq    .Lstrlen_aligned

.Lstrlen_prefix:
    ldrb    w3, [x0], #1
    cbz     w3, .Lstrlen_found_prefix
    ands    x2, x0, #0xF
    b.ne    .Lstrlen_prefix

.Lstrlen_aligned:
    // Main SIMD loop: 16 bytes per iteration
    // Prefetch 256 bytes ahead for M4 cache
    prfm    pldl1strm, [x0, #256]

.Lstrlen_loop:
    ldr     q0, [x0]                    // load 16 bytes
    cmeq    v2.16b, v0.16b, v1.16b     // compare each byte to zero
    umaxv   b3, v2.16b                  // max across lanes (0 if no NUL)
    fmov    w4, s3
    cbnz    w4, .Lstrlen_found_simd     // found a NUL byte
    add     x0, x0, #16
    prfm    pldl1strm, [x0, #256]      // prefetch ahead
    b       .Lstrlen_loop

.Lstrlen_found_simd:
    // NUL found in this 16-byte chunk. Find exact position.
    // v2 has 0xFF at NUL positions. Use clz on the bitmask.
    // Move comparison result to general register
    fmov    x4, d2                      // low 8 bytes
    mov     x5, v2.d[1]                 // high 8 bytes
    // Find first set byte in x4 (each byte is 0xFF or 0x00)
    rbit    x4, x4
    rbit    x5, x5
    clz     x4, x4                      // count leading zeros
    clz     x5, x5
    // x4 = bit position of first 0xFF byte in low half (0,8,16,...,56 or 64)
    // Convert to byte position
    lsr     x4, x4, #3                  // divide by 8
    // Check if NUL is in low or high half
    cmp     x4, #8
    b.lt    .Lstrlen_in_low
    // In high half
    lsr     x5, x5, #3
    add     x4, x5, #8
.Lstrlen_in_low:
    add     x0, x0, x4                  // point to NUL byte
    sub     x0, x0, x1                  // length = current - original
    ret

.Lstrlen_found_prefix:
    sub     x0, x0, #1                  // back up past NUL
    sub     x0, x0, x1                  // length = current - original
    ret

// ──────────────────────────────────────────────────────────────────
// _strcmp_simd: compare two NUL-terminated strings
//   x0 = string a
//   x1 = string b
//   Returns: x0 = 0 if equal, <0 if a<b, >0 if a>b
// ──────────────────────────────────────────────────────────────────
.global _strcmp_simd
_strcmp_simd:
    // Simple byte-by-byte for now (correctness first)
    // TODO: SIMD version for long strings
.Lstrcmp_loop:
    ldrb    w2, [x0], #1
    ldrb    w3, [x1], #1
    cmp     w2, w3
    b.ne    .Lstrcmp_diff
    cbz     w2, .Lstrcmp_equal          // both NUL = equal
    b       .Lstrcmp_loop

.Lstrcmp_diff:
    sub     x0, x2, x3                  // return difference
    ret

.Lstrcmp_equal:
    mov     x0, #0
    ret

// ──────────────────────────────────────────────────────────────────
// _memcpy_simd: NEON-accelerated memcpy
//   x0 = destination
//   x1 = source
//   x2 = byte count
//   Returns: x0 = destination (unchanged)
//
// Uses 16-byte NEON loads/stores for bulk, byte-by-byte for tail.
// Prefetch source 256 bytes ahead.
// ──────────────────────────────────────────────────────────────────
.global _memcpy_simd
_memcpy_simd:
    mov     x3, x0                      // save dest for return
    cbz     x2, .Lmemcpy_done

    // If less than 16 bytes, go byte-by-byte
    cmp     x2, #16
    b.lt    .Lmemcpy_tail

    // If less than 64 bytes, do single SIMD copies
    cmp     x2, #64
    b.lt    .Lmemcpy_small

    // Main loop: 64 bytes per iteration (4x NEON)
    prfm    pldl1strm, [x1, #256]
    prfm    pstl1strm, [x0, #256]
.Lmemcpy_loop64:
    ldp     q0, q1, [x1]               // load 32 bytes
    ldp     q2, q3, [x1, #32]          // load 32 more
    stp     q0, q1, [x0]               // store 32 bytes
    stp     q2, q3, [x0, #32]          // store 32 more
    add     x0, x0, #64
    add     x1, x1, #64
    sub     x2, x2, #64
    prfm    pldl1strm, [x1, #256]
    cmp     x2, #64
    b.ge    .Lmemcpy_loop64

    cbz     x2, .Lmemcpy_done

.Lmemcpy_small:
    // 16-byte copies
    cmp     x2, #16
    b.lt    .Lmemcpy_tail
.Lmemcpy_loop16:
    ldr     q0, [x1], #16
    str     q0, [x0], #16
    sub     x2, x2, #16
    cmp     x2, #16
    b.ge    .Lmemcpy_loop16

.Lmemcpy_tail:
    cbz     x2, .Lmemcpy_done
.Lmemcpy_tail_loop:
    ldrb    w4, [x1], #1
    strb    w4, [x0], #1
    subs    x2, x2, #1
    b.ne    .Lmemcpy_tail_loop

.Lmemcpy_done:
    mov     x0, x3                      // return original dest
    ret

// ──────────────────────────────────────────────────────────────────
// _memset_fast: fast memset using NEON
//   x0 = destination
//   x1 = byte value (w1)
//   x2 = count
//   Returns: x0 = destination
// ──────────────────────────────────────────────────────────────────
.global _memset_fast
_memset_fast:
    mov     x3, x0                      // save dest
    cbz     x2, .Lmemset_done

    // Duplicate byte across NEON vector
    dup     v0.16b, w1

    cmp     x2, #64
    b.lt    .Lmemset_small

.Lmemset_loop64:
    stp     q0, q0, [x0]
    stp     q0, q0, [x0, #32]
    add     x0, x0, #64
    sub     x2, x2, #64
    cmp     x2, #64
    b.ge    .Lmemset_loop64

.Lmemset_small:
    cmp     x2, #16
    b.lt    .Lmemset_tail
.Lmemset_loop16:
    str     q0, [x0], #16
    sub     x2, x2, #16
    cmp     x2, #16
    b.ge    .Lmemset_loop16

.Lmemset_tail:
    cbz     x2, .Lmemset_done
.Lmemset_tail_loop:
    strb    w1, [x0], #1
    subs    x2, x2, #1
    b.ne    .Lmemset_tail_loop

.Lmemset_done:
    mov     x0, x3
    ret

// ──────────────────────────────────────────────────────────────────
// _str_starts_with: check if string starts with prefix
//   x0 = string (NUL-terminated)
//   x1 = prefix (NUL-terminated)
//   Returns: x0 = 1 if starts with prefix, 0 otherwise
// ──────────────────────────────────────────────────────────────────
.global _str_starts_with
_str_starts_with:
.Lstartswith_loop:
    ldrb    w2, [x1], #1               // load prefix byte
    cbz     w2, .Lstartswith_yes        // prefix exhausted = match
    ldrb    w3, [x0], #1               // load string byte
    cmp     w2, w3
    b.ne    .Lstartswith_no
    b       .Lstartswith_loop

.Lstartswith_yes:
    mov     x0, #1
    ret

.Lstartswith_no:
    mov     x0, #0
    ret

// ──────────────────────────────────────────────────────────────────
// _str_equal: check if two NUL-terminated strings are equal
//   x0 = string a
//   x1 = string b
//   Returns: x0 = 1 if equal, 0 if not
// ──────────────────────────────────────────────────────────────────
.global _str_equal
_str_equal:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    bl      _strcmp_simd
    // x0 = 0 if equal
    cmp     x0, #0
    cset    x0, eq                      // branchless: 1 if equal, 0 if not

    ldp     x29, x30, [sp], #16
    ret
