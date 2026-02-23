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
    adrp    x8, _g_curl_easy_setopt_fn@PAGE
    add     x8, x8, _g_curl_easy_setopt_fn@PAGEOFF
    ldr     x8, [x8]
    cbz     x8, .Lcurl_setopt_missing
    blr     x8
    b       .Lcurl_setopt_done
.Lcurl_setopt_missing:
    mov     x0, #1
.Lcurl_setopt_done:
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
    adrp    x8, _g_curl_easy_getinfo_fn@PAGE
    add     x8, x8, _g_curl_easy_getinfo_fn@PAGEOFF
    ldr     x8, [x8]
    cbz     x8, .Lcurl_getinfo_missing
    blr     x8
    b       .Lcurl_getinfo_done
.Lcurl_getinfo_missing:
    mov     x0, #1
.Lcurl_getinfo_done:
    add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ret

// curl_easy_init()
.global _curl_easy_init
_curl_easy_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adrp    x8, _g_curl_easy_init_fn@PAGE
    add     x8, x8, _g_curl_easy_init_fn@PAGEOFF
    ldr     x8, [x8]
    cbz     x8, .Lcurl_init_missing
    blr     x8
    b       .Lcurl_init_done
.Lcurl_init_missing:
    mov     x0, #0
.Lcurl_init_done:
    ldp     x29, x30, [sp], #16
    ret

// curl_easy_perform(handle)
.global _curl_easy_perform
_curl_easy_perform:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adrp    x8, _g_curl_easy_perform_fn@PAGE
    add     x8, x8, _g_curl_easy_perform_fn@PAGEOFF
    ldr     x8, [x8]
    cbz     x8, .Lcurl_perform_missing
    blr     x8
    b       .Lcurl_perform_done
.Lcurl_perform_missing:
    mov     x0, #1
.Lcurl_perform_done:
    ldp     x29, x30, [sp], #16
    ret

// curl_easy_cleanup(handle)
.global _curl_easy_cleanup
_curl_easy_cleanup:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adrp    x8, _g_curl_easy_cleanup_fn@PAGE
    add     x8, x8, _g_curl_easy_cleanup_fn@PAGEOFF
    ldr     x8, [x8]
    cbz     x8, .Lcurl_cleanup_done
    blr     x8
.Lcurl_cleanup_done:
    ldp     x29, x30, [sp], #16
    ret

// curl_slist_append(list, string)
.global _curl_slist_append
_curl_slist_append:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adrp    x8, _g_curl_slist_append_fn@PAGE
    add     x8, x8, _g_curl_slist_append_fn@PAGEOFF
    ldr     x8, [x8]
    cbz     x8, .Lcurl_slist_append_missing
    blr     x8
    b       .Lcurl_slist_append_done
.Lcurl_slist_append_missing:
    mov     x0, #0
.Lcurl_slist_append_done:
    ldp     x29, x30, [sp], #16
    ret

// curl_slist_free_all(list)
.global _curl_slist_free_all
_curl_slist_free_all:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adrp    x8, _g_curl_slist_free_all_fn@PAGE
    add     x8, x8, _g_curl_slist_free_all_fn@PAGEOFF
    ldr     x8, [x8]
    cbz     x8, .Lcurl_slist_free_done
    blr     x8
.Lcurl_slist_free_done:
    ldp     x29, x30, [sp], #16
    ret

.section __DATA,__bss
.p2align 3

.global _g_curl_easy_init_fn
_g_curl_easy_init_fn:
    .quad   0

.global _g_curl_easy_setopt_fn
_g_curl_easy_setopt_fn:
    .quad   0

.global _g_curl_easy_perform_fn
_g_curl_easy_perform_fn:
    .quad   0

.global _g_curl_easy_cleanup_fn
_g_curl_easy_cleanup_fn:
    .quad   0

.global _g_curl_slist_append_fn
_g_curl_slist_append_fn:
    .quad   0

.global _g_curl_slist_free_all_fn
_g_curl_slist_free_all_fn:
    .quad   0

.global _g_curl_easy_getinfo_fn
_g_curl_easy_getinfo_fn:
    .quad   0
