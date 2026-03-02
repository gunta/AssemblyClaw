// version.s — AssemblyClaw version info
// ARM64 macOS — Apple Silicon optimized
.include "include/constants.inc"

.section __TEXT,__text,regular,pure_instructions
.p2align 4

// ──────────────────────────────────────────────────────────────────
// _version_string: returns pointer to version string in x0
// ──────────────────────────────────────────────────────────────────
.global _version_string
_version_string:
    adrp    x0, _str_version@PAGE
    add     x0, x0, _str_version@PAGEOFF
    ret

// ──────────────────────────────────────────────────────────────────
// _version_print: prints version to stdout
// ──────────────────────────────────────────────────────────────────
.global _version_print
_version_print:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, _str_version_full@PAGE
    add     x0, x0, _str_version_full@PAGEOFF
    mov     x1, #_str_version_full_len
    mov     x2, #STDOUT
    bl      _write_fd

    ldp     x29, x30, [sp], #16
    ret

// ── Read-only Data ──
.section __DATA,__const
.p2align 4

_str_version:
    .asciz  "0.1.1"

_str_version_full:
    .ascii  "assemblyclaw 0.1.1 (arm64-apple-darwin)\n"
    .asciz  ""

.set _str_version_full_len, . - _str_version_full - 1
