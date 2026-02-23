// io.s — File I/O wrappers
// ARM64 macOS — uses libSystem functions

.include "include/constants.inc"

.section __TEXT,__text,regular,pure_instructions
.p2align 4

// ──────────────────────────────────────────────────────────────────
// _write_fd: write buffer to file descriptor
//   x0 = buffer pointer
//   x1 = byte count
//   x2 = file descriptor
//   Returns: x0 = bytes written or -1 on error
// ──────────────────────────────────────────────────────────────────
.global _write_fd
_write_fd:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Rearrange args for write(fd, buf, count)
    mov     x3, x0                      // save buf
    mov     x0, x2                      // fd
    mov     x4, x1                      // save count
    mov     x1, x3                      // buf
    mov     x2, x4                      // count
    bl      _write

    ldp     x29, x30, [sp], #16
    ret

// ──────────────────────────────────────────────────────────────────
// _print: write NUL-terminated string to stdout
//   x0 = string pointer
// ──────────────────────────────────────────────────────────────────
.global _print
_print:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    bl      _puts

    ldp     x29, x30, [sp], #16
    ret

// ──────────────────────────────────────────────────────────────────
// _print_stderr: write NUL-terminated string to stderr + newline
//   x0 = string pointer
// ──────────────────────────────────────────────────────────────────
.global _print_stderr
_print_stderr:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // fputs(str, stderr)
    mov     x1, x0
    adrp    x8, ___stderrp@GOTPAGE
    ldr     x8, [x8, ___stderrp@GOTPAGEOFF]
    ldr     x0, [x8]
    // fprintf(stderr, "%s\n", str)
    mov     x2, x1
    adrp    x1, _str_fmt_sn@PAGE
    add     x1, x1, _str_fmt_sn@PAGEOFF
    bl      _fprintf_va1

    ldp     x29, x30, [sp], #16
    ret

// ──────────────────────────────────────────────────────────────────
// _read_file: read entire file into arena-allocated buffer
//   x0 = file path (NUL-terminated)
//   Returns: x0 = pointer to buffer (NUL-terminated), x1 = length
//            x0 = NULL on error
// ──────────────────────────────────────────────────────────────────
.global _read_file
_read_file:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]

    mov     x19, x0                     // save path

    // open(path, O_RDONLY)
    mov     x1, #0                      // O_RDONLY
    bl      _open
    cmp     x0, #0
    b.lt    .Lread_file_err
    mov     x20, x0                     // save fd

    // fstat to get file size — use lseek instead (simpler)
    // lseek(fd, 0, SEEK_END)
    mov     x0, x20
    mov     x1, #0
    mov     x2, #2                      // SEEK_END
    bl      _lseek
    cmp     x0, #0
    b.lt    .Lread_file_close_err
    mov     x21, x0                     // save size

    // lseek back to start
    mov     x0, x20
    mov     x1, #0
    mov     x2, #0                      // SEEK_SET
    bl      _lseek

    // Allocate buffer from arena (size + 1 for NUL)
    add     x0, x21, #1
    bl      _arena_alloc
    cbz     x0, .Lread_file_close_err
    mov     x19, x0                     // save buffer pointer

    // read(fd, buf, size)
    mov     x0, x20                     // fd
    mov     x1, x19                     // buf
    mov     x2, x21                     // size
    bl      _read

    // NUL-terminate
    strb    wzr, [x19, x21]

    // close(fd)
    mov     x0, x20
    bl      _close

    // Return buffer and length
    mov     x0, x19
    mov     x1, x21

    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Lread_file_close_err:
    mov     x0, x20
    bl      _close
.Lread_file_err:
    mov     x0, #0
    mov     x1, #0
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ──────────────────────────────────────────────────────────────────
// _path_expand_home: expand ~ to home directory
//   x0 = path (NUL-terminated, may start with ~)
//   Returns: x0 = expanded path in arena
// ──────────────────────────────────────────────────────────────────
.global _path_expand_home
_path_expand_home:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // save path

    // Check if starts with ~
    ldrb    w1, [x19]
    cmp     w1, #'~'
    b.ne    .Lpath_return_orig

    // Only expand "~" and "~/" forms.
    ldrb    w1, [x19, #1]
    cbz     w1, .Lpath_expand
    cmp     w1, #'/'
    b.ne    .Lpath_return_orig

.Lpath_expand:
    add     x22, x19, #1                // suffix after "~"

    // Get HOME env var
    adrp    x0, _str_home@PAGE
    add     x0, x0, _str_home@PAGEOFF
    bl      _getenv
    cbz     x0, .Lpath_return_orig      // no HOME, return as-is
    mov     x20, x0                     // HOME pointer

    // home_len = strlen(HOME)
    mov     x0, x20
    bl      _strlen_simd
    mov     x21, x0

    // suffix_len = strlen(path + 1)
    mov     x0, x22
    bl      _strlen_simd
    mov     x23, x0

    // Allocate result = home_len + suffix_len + 1
    add     x0, x21, x23
    add     x0, x0, #1
    bl      _arena_alloc
    cbz     x0, .Lpath_return_orig
    mov     x24, x0                     // destination

    // Copy home
    mov     x0, x24
    mov     x1, x20
    mov     x2, x21
    bl      _memcpy_simd

    // Copy suffix (starts with '/' or empty)
    add     x0, x24, x21
    mov     x1, x22
    mov     x2, x23
    bl      _memcpy_simd

    // NUL-terminate
    add     x8, x24, x21
    add     x8, x8, x23
    strb    wzr, [x8]

    mov     x0, x24
    b       .Lpath_done

.Lpath_return_orig:
    mov     x0, x19

.Lpath_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

// ── Data ──
.section __DATA,__const
.p2align 3

_str_fmt_sn:
    .asciz  "%s\n"
_str_home:
    .asciz  "HOME"
