// provider.s — LLM Provider (OpenAI-compatible API)
// ARM64 macOS — Apple Silicon optimized
//
// Builds OpenAI-compatible chat completion requests and parses responses.
// Supports: OpenRouter, OpenAI, Anthropic (via OpenRouter), DeepSeek.

.include "include/constants.inc"

.section __TEXT,__text,regular,pure_instructions
.p2align 4

// ──────────────────────────────────────────────────────────────────
// _provider_chat: send a chat message and get response
//   x0 = user message (NUL-terminated string)
//   Returns: x0 = response content pointer (NUL-terminated)
//            x1 = response content length
//            x0 = NULL on error
//
// Uses config for API key, model, base URL.
// Builds JSON request, POSTs via HTTP, parses response.
// ──────────────────────────────────────────────────────────────────
.global _provider_chat
_provider_chat:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]

    mov     x19, x0                     // save user message

    // Get config
    bl      _config_get
    mov     x20, x0                     // config pointer

    // Check if loaded
    ldr     x1, [x20, #72]             // CFG_LOADED
    cbz     x1, .Lprov_not_configured

    // Build request JSON
    // We need: model, messages array, temperature
    // Allocate buffer from arena for request body
    mov     x0, #BUF_LARGE             // 8KB should be plenty
    bl      _arena_alloc
    cbz     x0, .Lprov_error
    mov     x21, x0                     // request buffer

    // Get config fields
    ldr     x2, [x20, #32]             // CFG_MODEL ptr
    ldr     x3, [x20, #40]             // CFG_MODEL len

    // snprintf the request JSON
    mov     x0, x21                     // buffer
    mov     x1, #BUF_LARGE             // size
    adrp    x4, _str_req_fmt@PAGE
    add     x4, x4, _str_req_fmt@PAGEOFF
    // Args: fmt, model_len, model_ptr, message
    // printf format: %.*s for model, %s for message
    mov     x5, x3                      // model len (for %.*s)
    mov     x6, x2                      // model ptr
    mov     x7, x19                     // user message
    // Need to use stack for >8 args or rearrange
    // snprintf(buf, 8192, fmt, model_len, model_ptr, message)
    mov     x2, x4                      // fmt
    mov     x3, x5                      // model_len
    mov     x4, x6                      // model_ptr
    mov     x5, x7                      // message
    bl      _snprintf

    // Build auth header: "Bearer <api_key>"
    sub     sp, sp, #512
    mov     x0, sp
    mov     x1, #512
    adrp    x2, _str_bearer_fmt@PAGE
    add     x2, x2, _str_bearer_fmt@PAGEOFF
    ldr     x3, [x20, #16]             // CFG_API_KEY ptr
    ldr     x4, [x20, #24]             // CFG_API_KEY len
    // Use %.*s for the key
    bl      _snprintf

    // Get base URL
    ldr     x0, [x20, #48]             // CFG_BASE_URL ptr

    // Call http_post(url, body, auth)
    mov     x2, sp                      // auth header
    mov     x1, x21                     // request body
    // x0 already has URL
    bl      _http_post
    add     sp, sp, #512

    cbz     x0, .Lprov_http_error
    mov     x19, x0                     // response body
    mov     x20, x1                     // response length

    // Parse response: extract content from
    // {"choices":[{"message":{"content":"..."}}]}
    mov     x0, x19
    adrp    x1, _str_key_content@PAGE
    add     x1, x1, _str_key_content@PAGEOFF
    bl      _json_find_key

    cbz     x0, .Lprov_parse_error

    // x0 = content pointer, x1 = content length
    // NUL-terminate the content (write NUL after the string)
    // Content is inside the response buffer, we can modify it
    strb    wzr, [x0, x1]

    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Lprov_not_configured:
    adrp    x0, _str_not_config_err@PAGE
    add     x0, x0, _str_not_config_err@PAGEOFF
    bl      _print_stderr
    mov     x0, #0
    mov     x1, #0
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Lprov_error:
.Lprov_http_error:
    adrp    x0, _str_http_err@PAGE
    add     x0, x0, _str_http_err@PAGEOFF
    bl      _print_stderr
    mov     x0, #0
    mov     x1, #0
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Lprov_parse_error:
    // Couldn't extract content — print raw response for debugging
    adrp    x0, _str_parse_err@PAGE
    add     x0, x0, _str_parse_err@PAGEOFF
    bl      _print_stderr
    mov     x0, x19                     // return raw response
    mov     x1, x20
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ── Data ──
.section __DATA,__const
.p2align 3

// OpenAI-compatible chat request format
// Uses %.*s for model (len + ptr) and %s for message
_str_req_fmt:
    .asciz  "{\"model\":\"%.*s\",\"messages\":[{\"role\":\"user\",\"content\":\"%s\"}],\"temperature\":0.7}"

_str_bearer_fmt:
    .asciz  "Bearer %.*s"

_str_key_content:
    .asciz  "content"

_str_not_config_err:
    .asciz  "error: not configured. create ~/.assemblyclaw/config.json"
_str_http_err:
    .asciz  "error: HTTP request failed"
_str_parse_err:
    .asciz  "warning: could not parse response content field"
