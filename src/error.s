// error.s — AssemblyClaw error handling
// ARM64 macOS — Apple Silicon optimized
.include "include/constants.inc"

.section __TEXT,__text,regular,pure_instructions
.p2align 4

// ──────────────────────────────────────────────────────────────────
// _error_string: given error code in x0, return string pointer in x0
// Uses table lookup — branchless via bounded index
// ──────────────────────────────────────────────────────────────────
.global _error_string
_error_string:
    // Clamp to valid range: cmp + csel (branchless)
    cmp     x0, #10                     // ERR_HTTP is max
    csel    x0, x0, xzr, ls            // if > max, use 0 (ERR_OK)

    adrp    x1, _error_table@PAGE
    add     x1, x1, _error_table@PAGEOFF
    ldr     x0, [x1, x0, lsl #3]       // load pointer from table
    ret

// ──────────────────────────────────────────────────────────────────
// _error_print: print error message for code in x0 to stderr
// ──────────────────────────────────────────────────────────────────
.global _error_print
_error_print:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Get error string
    bl      _error_string

    // Print "error: " prefix
    stp     x0, xzr, [sp, #-16]!       // save error string
    adrp    x0, _str_error_prefix@PAGE
    add     x0, x0, _str_error_prefix@PAGEOFF
    mov     x1, #7                      // "error: " length
    mov     x2, #2                      // stderr
    bl      _write_fd

    // Print error message
    ldp     x0, xzr, [sp], #16
    bl      _strlen_simd                // get length
    mov     x2, #2                      // stderr
    mov     x1, x0                      // length
    // need to reload string pointer — we lost it
    // Simpler: just use fputs
    ldp     x29, x30, [sp], #16

    // Fall through to simpler approach
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    bl      _error_string
    mov     x1, x0
    adrp    x0, _str_error_fmt@PAGE
    add     x0, x0, _str_error_fmt@PAGEOFF
    // Use fprintf(stderr, "error: %s\n", msg)
    adrp    x8, ___stderrp@GOTPAGE
    ldr     x8, [x8, ___stderrp@GOTPAGEOFF]
    ldr     x0, [x8]                    // FILE* stderr
    adrp    x9, _str_error_fmt@PAGE
    add     x9, x9, _str_error_fmt@PAGEOFF
    mov     x1, x9
    // x2 = error string (need to get it again)
    bl      _error_string
    mov     x2, x0
    adrp    x8, ___stderrp@GOTPAGE
    ldr     x8, [x8, ___stderrp@GOTPAGEOFF]
    ldr     x0, [x8]
    adrp    x1, _str_error_fmt@PAGE
    add     x1, x1, _str_error_fmt@PAGEOFF
    bl      _fprintf

    ldp     x29, x30, [sp], #16
    ret

// ──────────────────────────────────────────────────────────────────
// _die: print error in x0, message in x1, then exit(1)
//   x0 = error string (c-string)
// ──────────────────────────────────────────────────────────────────
.global _die
_die:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // fprintf(stderr, "error: %s\n", x0)
    mov     x2, x0                      // error message
    adrp    x8, ___stderrp@GOTPAGE
    ldr     x8, [x8, ___stderrp@GOTPAGEOFF]
    ldr     x0, [x8]
    adrp    x1, _str_error_fmt@PAGE
    add     x1, x1, _str_error_fmt@PAGEOFF
    bl      _fprintf

    mov     x0, #1
    bl      _exit

// ── Data ──
.section __DATA,__const
.p2align 3

// Error string table — indexed by error code
_error_table:
    .quad   _err_ok
    .quad   _err_failed
    .quad   _err_oom
    .quad   _err_invalid_arg
    .quad   _err_not_found
    .quad   _err_io
    .quad   _err_parse
    .quad   _err_network
    .quad   _err_provider
    .quad   _err_config
    .quad   _err_http

_err_ok:            .asciz "ok"
_err_failed:        .asciz "operation failed"
_err_oom:           .asciz "out of memory"
_err_invalid_arg:   .asciz "invalid argument"
_err_not_found:     .asciz "not found"
_err_io:            .asciz "I/O error"
_err_parse:         .asciz "parse error"
_err_network:       .asciz "network error"
_err_provider:      .asciz "provider error"
_err_config:        .asciz "config error"
_err_http:          .asciz "HTTP error"

_str_error_prefix:  .asciz "error: "
_str_error_fmt:     .asciz "error: %s\n"
