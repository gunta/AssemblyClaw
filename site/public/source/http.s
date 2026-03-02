// http.s — HTTPS client via libcurl FFI
// ARM64 macOS — Apple Silicon optimized
//
// Wraps libcurl for HTTPS POST requests to LLM APIs.
// Uses arena allocator for response buffers.
// libcurl ships with macOS — zero install needed.

.include "include/constants.inc"

.section __TEXT,__text,regular,pure_instructions
.p2align 4

// Response buffer structure (in .bss):
//   +0:  data pointer (arena-allocated)
//   +8:  length (current)
//   +16: capacity
.set RESP_DATA,     0
.set RESP_LEN,      8
.set RESP_CAP,      16
.set RESP_SIZE,     24

// ──────────────────────────────────────────────────────────────────
// _http_post: POST JSON to URL with auth header
//   x0 = URL (NUL-terminated)
//   x1 = JSON body (NUL-terminated)
//   x2 = auth header value (e.g., "Bearer sk-...")  (NUL-terminated)
//   Returns: x0 = response body pointer (NUL-terminated)
//            x1 = response body length
//            x0 = NULL on error
// ──────────────────────────────────────────────────────────────────
.global _http_post
_http_post:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    mov     x19, x0                     // URL
    mov     x20, x1                     // body
    mov     x21, x2                     // auth header value

    // Load libcurl lazily. This keeps --help/--version/status from mapping libcurl.
    bl      .Lhttp_curl_ensure
    cbz     x0, .Lhttp_error

    // Allocate response buffer from arena (8KB initial)
    mov     x0, #BUF_LARGE
    bl      _arena_alloc
    cbz     x0, .Lhttp_error
    mov     x22, x0                     // response buffer

    // Initialize response state
    adrp    x1, _g_http_resp@PAGE
    add     x1, x1, _g_http_resp@PAGEOFF
    str     x22, [x1, #RESP_DATA]
    str     xzr, [x1, #RESP_LEN]
    mov     x2, #BUF_LARGE
    str     x2, [x1, #RESP_CAP]

    // curl_easy_init()
    bl      _curl_easy_init
    cbz     x0, .Lhttp_error
    mov     x23, x0                     // curl handle

    // Set URL
    mov     x0, x23
    mov     x1, #CURLOPT_URL
    mov     x2, x19
    bl      _curl_easy_setopt_va1

    // Set POST body
    mov     x0, x23
    mov     x1, #CURLOPT_POSTFIELDS
    mov     x2, x20
    bl      _curl_easy_setopt_va1

    // Set POST method
    mov     x0, x23
    mov     x1, #CURLOPT_POST
    mov     x2, #1
    bl      _curl_easy_setopt_va1

    // Treat HTTP >= 400 as curl errors for clean propagation.
    mov     x0, x23
    mov     x1, #CURLOPT_FAILONERROR
    mov     x2, #1
    bl      _curl_easy_setopt_va1

    // Set write callback
    mov     x0, x23
    mov     x1, #CURLOPT_WRITEFUNCTION
    adrp    x2, _http_write_callback@PAGE
    add     x2, x2, _http_write_callback@PAGEOFF
    bl      _curl_easy_setopt_va1

    // Set write data (pointer to our response struct)
    mov     x0, x23
    mov     x1, #CURLOPT_WRITEDATA
    adrp    x2, _g_http_resp@PAGE
    add     x2, x2, _g_http_resp@PAGEOFF
    bl      _curl_easy_setopt_va1

    // Set timeout
    mov     x0, x23
    mov     x1, #CURLOPT_TIMEOUT
    mov     x2, #HTTP_TIMEOUT_SECS
    bl      _curl_easy_setopt_va1

    // Set user agent
    mov     x0, x23
    mov     x1, #CURLOPT_USERAGENT
    adrp    x2, _str_useragent@PAGE
    add     x2, x2, _str_useragent@PAGEOFF
    bl      _curl_easy_setopt_va1

    // Build headers list
    // Content-Type: application/json
    mov     x0, #0                      // slist = NULL
    adrp    x1, _str_content_type@PAGE
    add     x1, x1, _str_content_type@PAGEOFF
    bl      _curl_slist_append
    mov     x24, x0                     // save slist

    // Auth header:
    // - OpenAI-compatible: auth value is "Bearer ...", add "Authorization: ..."
    // - Anthropic: auth value is full "x-api-key: ...", append directly
    mov     x0, x21
    adrp    x1, _str_x_api_key_prefix@PAGE
    add     x1, x1, _str_x_api_key_prefix@PAGEOFF
    bl      _str_starts_with
    cbz     x0, .Lhttp_build_auth_bearer

    // Direct header mode (already "x-api-key: ...")
    mov     x0, x24
    mov     x1, x21
    bl      _curl_slist_append
    mov     x24, x0

    // Anthropic requires version header
    mov     x0, x24
    adrp    x1, _str_anthropic_version@PAGE
    add     x1, x1, _str_anthropic_version@PAGEOFF
    bl      _curl_slist_append
    mov     x24, x0
    b       .Lhttp_set_headers

.Lhttp_build_auth_bearer:
    sub     sp, sp, #512
    mov     x0, sp
    mov     x1, #512
    adrp    x2, _str_auth_fmt@PAGE
    add     x2, x2, _str_auth_fmt@PAGEOFF
    mov     x3, x21                     // auth value
    bl      _snprintf_va1

    mov     x0, x24                     // slist
    mov     x1, sp                      // auth header
    bl      _curl_slist_append
    mov     x24, x0
    add     sp, sp, #512

    // Set headers
.Lhttp_set_headers:
    mov     x0, x23
    mov     x1, #CURLOPT_HTTPHEADER
    mov     x2, x24
    bl      _curl_easy_setopt_va1

    // Perform request
    mov     x0, x23
    bl      _curl_easy_perform
    mov     x25, x0                     // save result code

    // Free headers
    mov     x0, x24
    bl      _curl_slist_free_all

    // Cleanup curl handle
    mov     x0, x23
    bl      _curl_easy_cleanup

    // Check result
    cmp     x25, #CURLE_OK
    b.ne    .Lhttp_error

    // NUL-terminate response
    adrp    x1, _g_http_resp@PAGE
    add     x1, x1, _g_http_resp@PAGEOFF
    ldr     x0, [x1, #RESP_DATA]
    ldr     x2, [x1, #RESP_LEN]
    strb    wzr, [x0, x2]              // NUL terminate

    // Return response
    mov     x1, x2                      // length
    // x0 already has data pointer

    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

.Lhttp_error:
    mov     x0, #0
    mov     x1, #0
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

// ──────────────────────────────────────────────────────────────────
// _http_write_callback: libcurl write callback
//   x0 = data pointer
//   x1 = size (always 1)
//   x2 = nmemb
//   x3 = userdata (pointer to response struct)
//   Returns: x0 = bytes consumed
// ──────────────────────────────────────────────────────────────────
.global _http_write_callback
_http_write_callback:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mul     x4, x1, x2                 // total bytes = size * nmemb
    mov     x19, x4                     // save total

    // Get response state
    ldr     x5, [x3, #RESP_DATA]       // data ptr
    ldr     x6, [x3, #RESP_LEN]        // current length
    ldr     x7, [x3, #RESP_CAP]        // capacity

    // Check if fits
    add     x8, x6, x4
    cmp     x8, x7
    b.ge    .Lcb_overflow               // doesn't fit, truncate

    // Copy data: memcpy(data + len, src, total)
    add     x9, x5, x6                 // dest = data + current len
    // Use our NEON memcpy
    mov     x10, x0                     // save src
    mov     x0, x9                      // dest
    mov     x1, x10                     // src
    mov     x2, x4                      // count
    bl      _memcpy_simd

    // Update length
    adrp    x3, _g_http_resp@PAGE
    add     x3, x3, _g_http_resp@PAGEOFF
    ldr     x6, [x3, #RESP_LEN]
    add     x6, x6, x19
    str     x6, [x3, #RESP_LEN]

    mov     x0, x19                     // return bytes consumed

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lcb_overflow:
    // Copy what fits
    sub     x4, x7, x6                 // remaining capacity
    add     x9, x5, x6
    mov     x10, x0
    mov     x0, x9
    mov     x1, x10
    mov     x2, x4
    bl      _memcpy_simd

    adrp    x3, _g_http_resp@PAGE
    add     x3, x3, _g_http_resp@PAGEOFF
    ldr     x7, [x3, #RESP_CAP]
    str     x7, [x3, #RESP_LEN]        // len = cap

    mov     x0, x19                     // still return total (curl expects this)
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ──────────────────────────────────────────────────────────────────
// .Lhttp_curl_ensure: lazy-resolve libcurl symbols via dlopen/dlsym
//   Returns: x0 = 1 if ready, 0 on failure
// ──────────────────────────────────────────────────────────────────
.Lhttp_curl_ensure:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    adrp    x19, _g_http_curl_loaded@PAGE
    add     x19, x19, _g_http_curl_loaded@PAGEOFF
    ldr     x0, [x19]
    cbnz    x0, .Lhttp_curl_ready

    adrp    x20, _g_http_curl_failed@PAGE
    add     x20, x20, _g_http_curl_failed@PAGEOFF
    ldr     x0, [x20]
    cbnz    x0, .Lhttp_curl_not_ready

    adrp    x0, _str_libcurl_path@PAGE
    add     x0, x0, _str_libcurl_path@PAGEOFF
    mov     x1, #5                      // RTLD_LAZY | RTLD_LOCAL
    bl      _dlopen
    cbz     x0, .Lhttp_curl_mark_failed
    mov     x21, x0

    adrp    x22, _g_http_curl_handle@PAGE
    add     x22, x22, _g_http_curl_handle@PAGEOFF
    str     x21, [x22]

    // curl_easy_init
    mov     x0, x21
    adrp    x1, _str_sym_curl_easy_init@PAGE
    add     x1, x1, _str_sym_curl_easy_init@PAGEOFF
    bl      _dlsym
    cbz     x0, .Lhttp_curl_bind_fail
    adrp    x8, _g_curl_easy_init_fn@PAGE
    add     x8, x8, _g_curl_easy_init_fn@PAGEOFF
    str     x0, [x8]

    // curl_easy_setopt
    mov     x0, x21
    adrp    x1, _str_sym_curl_easy_setopt@PAGE
    add     x1, x1, _str_sym_curl_easy_setopt@PAGEOFF
    bl      _dlsym
    cbz     x0, .Lhttp_curl_bind_fail
    adrp    x8, _g_curl_easy_setopt_fn@PAGE
    add     x8, x8, _g_curl_easy_setopt_fn@PAGEOFF
    str     x0, [x8]

    // curl_easy_perform
    mov     x0, x21
    adrp    x1, _str_sym_curl_easy_perform@PAGE
    add     x1, x1, _str_sym_curl_easy_perform@PAGEOFF
    bl      _dlsym
    cbz     x0, .Lhttp_curl_bind_fail
    adrp    x8, _g_curl_easy_perform_fn@PAGE
    add     x8, x8, _g_curl_easy_perform_fn@PAGEOFF
    str     x0, [x8]

    // curl_easy_cleanup
    mov     x0, x21
    adrp    x1, _str_sym_curl_easy_cleanup@PAGE
    add     x1, x1, _str_sym_curl_easy_cleanup@PAGEOFF
    bl      _dlsym
    cbz     x0, .Lhttp_curl_bind_fail
    adrp    x8, _g_curl_easy_cleanup_fn@PAGE
    add     x8, x8, _g_curl_easy_cleanup_fn@PAGEOFF
    str     x0, [x8]

    // curl_slist_append
    mov     x0, x21
    adrp    x1, _str_sym_curl_slist_append@PAGE
    add     x1, x1, _str_sym_curl_slist_append@PAGEOFF
    bl      _dlsym
    cbz     x0, .Lhttp_curl_bind_fail
    adrp    x8, _g_curl_slist_append_fn@PAGE
    add     x8, x8, _g_curl_slist_append_fn@PAGEOFF
    str     x0, [x8]

    // curl_slist_free_all
    mov     x0, x21
    adrp    x1, _str_sym_curl_slist_free_all@PAGE
    add     x1, x1, _str_sym_curl_slist_free_all@PAGEOFF
    bl      _dlsym
    cbz     x0, .Lhttp_curl_bind_fail
    adrp    x8, _g_curl_slist_free_all_fn@PAGE
    add     x8, x8, _g_curl_slist_free_all_fn@PAGEOFF
    str     x0, [x8]

    // curl_easy_getinfo (optional today, kept for completeness)
    mov     x0, x21
    adrp    x1, _str_sym_curl_easy_getinfo@PAGE
    add     x1, x1, _str_sym_curl_easy_getinfo@PAGEOFF
    bl      _dlsym
    cbz     x0, .Lhttp_curl_bind_fail
    adrp    x8, _g_curl_easy_getinfo_fn@PAGE
    add     x8, x8, _g_curl_easy_getinfo_fn@PAGEOFF
    str     x0, [x8]

    mov     x0, #1
    str     x0, [x19]
    b       .Lhttp_curl_ready

.Lhttp_curl_bind_fail:
    adrp    x22, _g_http_curl_handle@PAGE
    add     x22, x22, _g_http_curl_handle@PAGEOFF
    ldr     x0, [x22]
    cbz     x0, .Lhttp_curl_mark_failed
    bl      _dlclose
    str     xzr, [x22]

.Lhttp_curl_mark_failed:
    mov     x0, #1
    str     x0, [x20]

    // Clear any partially resolved symbols.
    adrp    x8, _g_curl_easy_init_fn@PAGE
    add     x8, x8, _g_curl_easy_init_fn@PAGEOFF
    str     xzr, [x8]
    adrp    x8, _g_curl_easy_setopt_fn@PAGE
    add     x8, x8, _g_curl_easy_setopt_fn@PAGEOFF
    str     xzr, [x8]
    adrp    x8, _g_curl_easy_perform_fn@PAGE
    add     x8, x8, _g_curl_easy_perform_fn@PAGEOFF
    str     xzr, [x8]
    adrp    x8, _g_curl_easy_cleanup_fn@PAGE
    add     x8, x8, _g_curl_easy_cleanup_fn@PAGEOFF
    str     xzr, [x8]
    adrp    x8, _g_curl_slist_append_fn@PAGE
    add     x8, x8, _g_curl_slist_append_fn@PAGEOFF
    str     xzr, [x8]
    adrp    x8, _g_curl_slist_free_all_fn@PAGE
    add     x8, x8, _g_curl_slist_free_all_fn@PAGEOFF
    str     xzr, [x8]
    adrp    x8, _g_curl_easy_getinfo_fn@PAGE
    add     x8, x8, _g_curl_easy_getinfo_fn@PAGEOFF
    str     xzr, [x8]

.Lhttp_curl_not_ready:
    mov     x0, #0
    b       .Lhttp_curl_done

.Lhttp_curl_ready:
    mov     x0, #1

.Lhttp_curl_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// ── BSS ──
.section __DATA,__bss
.p2align 4
_g_http_resp:
    .space  RESP_SIZE

.p2align 3
_g_http_curl_handle:
    .quad   0
_g_http_curl_loaded:
    .quad   0
_g_http_curl_failed:
    .quad   0

// ── Data ──
.section __DATA,__const
.p2align 3
_str_useragent:
    .asciz  "AssemblyClaw/0.1.0"
_str_content_type:
    .asciz  "Content-Type: application/json"
_str_auth_fmt:
    .asciz  "Authorization: %s"
_str_x_api_key_prefix:
    .asciz  "x-api-key:"
_str_anthropic_version:
    .asciz  "anthropic-version: 2023-06-01"
_str_libcurl_path:
    .asciz  "/usr/lib/libcurl.4.dylib"
_str_sym_curl_easy_init:
    .asciz  "curl_easy_init"
_str_sym_curl_easy_setopt:
    .asciz  "curl_easy_setopt"
_str_sym_curl_easy_perform:
    .asciz  "curl_easy_perform"
_str_sym_curl_easy_cleanup:
    .asciz  "curl_easy_cleanup"
_str_sym_curl_slist_append:
    .asciz  "curl_slist_append"
_str_sym_curl_slist_free_all:
    .asciz  "curl_slist_free_all"
_str_sym_curl_easy_getinfo:
    .asciz  "curl_easy_getinfo"
