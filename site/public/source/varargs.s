// varargs.s — Darwin ARM64 variadic-call helpers
// On Apple ARM64, variadic arguments must be passed on the stack.
// These wrappers centralize that ABI detail for assembly callers.

.section __TEXT,__text,regular,pure_instructions
.p2align 4

// snprintf(buf, size, fmt, arg1)
.global _snprintf_va1
_snprintf_va1:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #16
    str     x3, [sp]
    bl      _snprintf
    add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ret

// snprintf(buf, size, fmt, arg1, arg2)
.global _snprintf_va2
_snprintf_va2:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #16
    stp     x3, x4, [sp]
    bl      _snprintf
    add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ret

// snprintf(buf, size, fmt, arg1, arg2, arg3)
.global _snprintf_va3
_snprintf_va3:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #32
    stp     x3, x4, [sp]
    str     x5, [sp, #16]
    bl      _snprintf
    add     sp, sp, #32
    ldp     x29, x30, [sp], #16
    ret

// snprintf(buf, size, fmt, arg1, arg2, arg3, arg4)
.global _snprintf_va4
_snprintf_va4:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #32
    stp     x3, x4, [sp]
    stp     x5, x6, [sp, #16]
    bl      _snprintf
    add     sp, sp, #32
    ldp     x29, x30, [sp], #16
    ret

// fprintf(file, fmt, arg1)
.global _fprintf_va1
_fprintf_va1:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #16
    str     x2, [sp]
    bl      _fprintf
    add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ret

// printf(fmt, arg1, arg2, arg3, arg4, arg5, arg6)
.global _printf_va6
_printf_va6:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #48
    stp     x1, x2, [sp]
    stp     x3, x4, [sp, #16]
    stp     x5, x6, [sp, #32]
    bl      _printf
    add     sp, sp, #48
    ldp     x29, x30, [sp], #16
    ret

// curl_easy_setopt(handle, option, arg1)
.global _curl_easy_setopt_va1
_curl_easy_setopt_va1:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #16
    str     x2, [sp]
    bl      _curl_easy_setopt
    add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ret

// curl_easy_getinfo(handle, info, arg1)
.global _curl_easy_getinfo_va1
_curl_easy_getinfo_va1:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #16
    str     x2, [sp]
    bl      _curl_easy_getinfo
    add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ret
