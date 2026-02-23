// provider.s — LLM Provider (OpenAI-compatible + Anthropic API)
// ARM64 macOS
//
// - Sends chat requests using in-memory history.
// - Supports OpenAI-compatible endpoints and native Anthropic messages API.
// - Extracts tool calls and exposes them to the agent runtime.

.include "include/constants.inc"

.section __TEXT,__text,regular,pure_instructions
.p2align 4

// ──────────────────────────────────────────────────────────────────
// _provider_chat: send chat history and get response
//   x0 = latest user message (fallback when history is empty)
//   Returns: x0 = assistant content pointer, x1 = length, x0=NULL on error
// ──────────────────────────────────────────────────────────────────
.global _provider_chat
_provider_chat:
    stp     x29, x30, [sp, #-112]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]

    mov     x19, x0                     // latest user message
    bl      .Lprov_tool_clear

    bl      _config_get
    mov     x20, x0                     // config ptr
    ldr     x1, [x20, #72]              // CFG_LOADED
    cbz     x1, .Lprov_not_configured

    // provider branch: anthropic vs openai-compatible
    ldr     x0, [x20, #0]               // provider ptr
    ldr     x1, [x20, #8]               // provider len
    bl      .Lprov_is_anthropic
    mov     x28, x0                     // 1 if anthropic

    mov     x0, #BUF_LARGE
    bl      _arena_alloc
    cbz     x0, .Lprov_error
    mov     x21, x0                     // request buffer
    mov     x24, x21                    // cursor
    mov     x25, #BUF_LARGE             // bytes remaining
    strb    wzr, [x24]

    cbz     x28, .Lprov_build_openai
    b       .Lprov_build_anthropic

.Lprov_build_openai:
    // {"model":"...","messages":[
    mov     x0, x24
    mov     x1, x25
    adrp    x2, _str_openai_prefix_fmt@PAGE
    add     x2, x2, _str_openai_prefix_fmt@PAGEOFF
    ldr     x3, [x20, #40]              // model len
    ldr     x4, [x20, #32]              // model ptr
    bl      _snprintf_va2
    cmp     x0, #0
    b.lt    .Lprov_error
    cmp     x0, x25
    b.ge    .Lprov_error
    add     x24, x24, x0
    sub     x25, x25, x0

    mov     x26, #1                     // first message flag
    bl      _agent_history_count
    mov     x27, x0                     // history count
    cbz     x27, .Lprov_openai_fallback_single

    mov     x22, #0
    cmp     x27, #12
    b.le    .Lprov_openai_hist_loop
    sub     x22, x27, #12

.Lprov_openai_hist_loop:
    cmp     x22, x27
    b.ge    .Lprov_openai_after_hist
    mov     x0, x22
    bl      _agent_history_get          // x0=role x1=ptr x2=len
    cbz     x1, .Lprov_openai_hist_next
    mov     x3, x26
    bl      .Lprov_append_message_openai
    cbz     x0, .Lprov_error
    mov     x26, #0

.Lprov_openai_hist_next:
    add     x22, x22, #1
    b       .Lprov_openai_hist_loop

.Lprov_openai_fallback_single:
    mov     x0, x19
    bl      _strlen_simd
    mov     x2, x0
    mov     x0, #ROLE_USER
    mov     x1, x19
    mov     x3, x26
    bl      .Lprov_append_message_openai
    cbz     x0, .Lprov_error

.Lprov_openai_after_hist:
    // Add tools and temperature suffix.
    adrp    x0, _str_openai_tools_blob@PAGE
    add     x0, x0, _str_openai_tools_blob@PAGEOFF
    bl      .Lprov_append_cstr
    cbz     x0, .Lprov_error

    mov     x0, x24
    mov     x1, x25
    adrp    x2, _str_openai_suffix_fmt@PAGE
    add     x2, x2, _str_openai_suffix_fmt@PAGEOFF
    ldr     d0, [x20, #64]              // temperature
    fmov    x3, d0
    bl      _snprintf_va1
    cmp     x0, #0
    b.lt    .Lprov_error
    cmp     x0, x25
    b.ge    .Lprov_error
    add     x24, x24, x0
    sub     x25, x25, x0
    b       .Lprov_send

.Lprov_build_anthropic:
    // {"model":"...","max_tokens":1024,"messages":[
    mov     x0, x24
    mov     x1, x25
    adrp    x2, _str_anthropic_prefix_fmt@PAGE
    add     x2, x2, _str_anthropic_prefix_fmt@PAGEOFF
    ldr     x3, [x20, #40]              // model len
    ldr     x4, [x20, #32]              // model ptr
    bl      _snprintf_va2
    cmp     x0, #0
    b.lt    .Lprov_error
    cmp     x0, x25
    b.ge    .Lprov_error
    add     x24, x24, x0
    sub     x25, x25, x0

    mov     x26, #1                     // first message flag
    bl      _agent_history_count
    mov     x27, x0                     // history count
    cbz     x27, .Lprov_anthropic_fallback_single

    mov     x22, #0
    cmp     x27, #12
    b.le    .Lprov_anthropic_hist_loop
    sub     x22, x27, #12

.Lprov_anthropic_hist_loop:
    cmp     x22, x27
    b.ge    .Lprov_anthropic_after_hist
    mov     x0, x22
    bl      _agent_history_get          // x0=role x1=ptr x2=len
    cbz     x1, .Lprov_anthropic_hist_next
    mov     x3, x26
    bl      .Lprov_append_message_anthropic
    cbz     x0, .Lprov_error
    mov     x26, #0

.Lprov_anthropic_hist_next:
    add     x22, x22, #1
    b       .Lprov_anthropic_hist_loop

.Lprov_anthropic_fallback_single:
    mov     x0, x19
    bl      _strlen_simd
    mov     x2, x0
    mov     x0, #ROLE_USER
    mov     x1, x19
    mov     x3, x26
    bl      .Lprov_append_message_anthropic
    cbz     x0, .Lprov_error

.Lprov_anthropic_after_hist:
    // Add Anthropic tool schema and auto tool choice.
    adrp    x0, _str_anthropic_tools_blob@PAGE
    add     x0, x0, _str_anthropic_tools_blob@PAGEOFF
    bl      .Lprov_append_cstr
    cbz     x0, .Lprov_error

    mov     x0, x24
    mov     x1, x25
    adrp    x2, _str_anthropic_suffix_fmt@PAGE
    add     x2, x2, _str_anthropic_suffix_fmt@PAGEOFF
    ldr     d0, [x20, #64]              // temperature
    fmov    x3, d0
    bl      _snprintf_va1
    cmp     x0, #0
    b.lt    .Lprov_error
    cmp     x0, x25
    b.ge    .Lprov_error
    add     x24, x24, x0
    sub     x25, x25, x0

.Lprov_send:
    // Build auth header value.
    sub     sp, sp, #512
    mov     x0, sp
    mov     x1, #512
    cbz     x28, .Lprov_auth_bearer
    adrp    x2, _str_x_api_key_fmt@PAGE
    add     x2, x2, _str_x_api_key_fmt@PAGEOFF
    b       .Lprov_auth_build

.Lprov_auth_bearer:
    adrp    x2, _str_bearer_fmt@PAGE
    add     x2, x2, _str_bearer_fmt@PAGEOFF

.Lprov_auth_build:
    ldr     x3, [x20, #24]              // api_key len
    ldr     x4, [x20, #16]              // api_key ptr
    bl      _snprintf_va2

    // POST request.
    ldr     x0, [x20, #48]              // base_url
    mov     x1, x21                     // request body
    mov     x2, sp                      // auth value/header
    bl      _http_post
    add     sp, sp, #512
    cbz     x0, .Lprov_http_error

    mov     x22, x0                     // response ptr
    mov     x23, x1                     // response len

    cbz     x28, .Lprov_parse_openai
    mov     x0, x22
    bl      .Lprov_parse_anthropic
    cbz     x0, .Lprov_parse_error
    b       .Lprov_return

.Lprov_parse_openai:
    mov     x0, x22
    bl      .Lprov_parse_openai_content
    cbz     x0, .Lprov_parse_error
    b       .Lprov_return

.Lprov_not_configured:
    adrp    x0, _str_not_config_err@PAGE
    add     x0, x0, _str_not_config_err@PAGEOFF
    bl      _print_stderr
    mov     x0, #0
    mov     x1, #0
    b       .Lprov_return

.Lprov_error:
.Lprov_http_error:
    adrp    x0, _str_http_err@PAGE
    add     x0, x0, _str_http_err@PAGEOFF
    bl      _print_stderr
    mov     x0, #0
    mov     x1, #0
    b       .Lprov_return

.Lprov_parse_error:
    adrp    x0, _str_parse_err@PAGE
    add     x0, x0, _str_parse_err@PAGEOFF
    bl      _print_stderr
    mov     x0, x22
    mov     x1, x23

.Lprov_return:
    ldp     x27, x28, [sp, #80]
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #112
    ret

// ──────────────────────────────────────────────────────────────────
// _provider_tool_peek
//   Returns:
//     x0 = pending (0/1)
//     x1 = tool_name ptr
//     x2 = tool_name len
//     x3 = tool_args ptr
//     x4 = tool_args len
// ──────────────────────────────────────────────────────────────────
.global _provider_tool_peek
_provider_tool_peek:
    adrp    x8, _g_provider_tool_pending@PAGE
    add     x8, x8, _g_provider_tool_pending@PAGEOFF
    ldr     x0, [x8]
    ldr     x1, [x8, #8]
    ldr     x2, [x8, #16]
    ldr     x3, [x8, #24]
    ldr     x4, [x8, #32]
    ret

// ──────────────────────────────────────────────────────────────────
// Parsing helpers
// ──────────────────────────────────────────────────────────────────
.Lprov_parse_openai_content:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0                     // response json

    // SSE stream payload ("data: ..."): aggregate all content deltas first.
    mov     x0, x19
    adrp    x1, _str_sse_prefix@PAGE
    add     x1, x1, _str_sse_prefix@PAGEOFF
    bl      _str_starts_with
    cbz     x0, .Lprov_openai_parse_json
    mov     x0, x19
    adrp    x1, _str_pat_content_value@PAGE
    add     x1, x1, _str_pat_content_value@PAGEOFF
    mov     x2, #11
    bl      .Lprov_parse_stream_tokens
    cbnz    x0, .Lprov_openai_done

.Lprov_openai_parse_json:
    mov     x0, x19
    adrp    x1, _str_key_choices@PAGE
    add     x1, x1, _str_key_choices@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lprov_openai_top_content

    mov     x20, x0                     // choices array
    mov     x21, x1                     // choices len
    mov     x0, x20
    mov     x1, x21
    bl      _json_array_first_object
    cbz     x0, .Lprov_openai_top_content
    mov     x20, x0                     // first choice obj
    mov     x21, x1
    add     x8, x20, x21
    strb    wzr, [x8]

    mov     x0, x20
    adrp    x1, _str_key_message@PAGE
    add     x1, x1, _str_key_message@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lprov_openai_choice_content
    mov     x22, x0                     // message value
    mov     x21, x1
    ldrb    w8, [x22]
    cmp     w8, #'{'
    b.ne    .Lprov_openai_choice_content
    add     x9, x22, x21
    strb    wzr, [x9]
    mov     x0, x22
    adrp    x1, _str_key_content@PAGE
    add     x1, x1, _str_key_content@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lprov_openai_choice_content
    strb    wzr, [x0, x1]
    b       .Lprov_openai_done

.Lprov_openai_choice_content:
    mov     x0, x20
    adrp    x1, _str_key_content@PAGE
    add     x1, x1, _str_key_content@PAGEOFF
    bl      _json_find_key
    cbnz    x0, .Lprov_openai_content_ok
    b       .Lprov_openai_top_content

.Lprov_openai_content_ok:
    strb    wzr, [x0, x1]
    b       .Lprov_openai_done

.Lprov_openai_top_content:
    mov     x0, x19
    adrp    x1, _str_key_content@PAGE
    add     x1, x1, _str_key_content@PAGEOFF
    bl      _json_find_key
    cbnz    x0, .Lprov_openai_top_ok

    // Try tool call extraction.
    mov     x0, x19
    bl      .Lprov_set_tool_from_openai
    cbnz    x0, .Lprov_openai_done

    // Streaming fallback: collect all "content":"..." deltas from SSE payload.
    mov     x0, x19
    adrp    x1, _str_pat_content_value@PAGE
    add     x1, x1, _str_pat_content_value@PAGEOFF
    mov     x2, #11
    bl      .Lprov_parse_stream_tokens
    b       .Lprov_openai_done

.Lprov_openai_top_ok:
    strb    wzr, [x0, x1]

.Lprov_openai_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Lprov_parse_anthropic:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0                     // response json

    // SSE stream payload ("data: ..."): aggregate text deltas first.
    mov     x0, x19
    adrp    x1, _str_sse_prefix@PAGE
    add     x1, x1, _str_sse_prefix@PAGEOFF
    bl      _str_starts_with
    cbz     x0, .Lprov_anthropic_parse_json
    mov     x0, x19
    adrp    x1, _str_pat_text_value@PAGE
    add     x1, x1, _str_pat_text_value@PAGEOFF
    mov     x2, #8
    bl      .Lprov_parse_stream_tokens
    cbnz    x0, .Lprov_anthropic_done

.Lprov_anthropic_parse_json:
    // content[0]
    mov     x0, x19
    adrp    x1, _str_key_content@PAGE
    add     x1, x1, _str_key_content@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lprov_anthropic_fail
    mov     x20, x0
    mov     x21, x1
    mov     x0, x20
    mov     x1, x21
    bl      _json_array_first_object
    cbz     x0, .Lprov_anthropic_fail
    mov     x20, x0
    mov     x21, x1
    add     x8, x20, x21
    strb    wzr, [x8]

    // Prefer text.
    mov     x0, x20
    adrp    x1, _str_key_text@PAGE
    add     x1, x1, _str_key_text@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lprov_anthropic_tool
    strb    wzr, [x0, x1]
    b       .Lprov_anthropic_done

.Lprov_anthropic_tool:
    mov     x0, x20
    bl      .Lprov_set_tool_from_anthropic_obj
    b       .Lprov_anthropic_done

.Lprov_anthropic_fail:
    // Fallback: extract any "text" field from the full payload.
    mov     x0, x19
    adrp    x1, _str_key_text@PAGE
    add     x1, x1, _str_key_text@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lprov_anthropic_fail_zero
    strb    wzr, [x0, x1]
    b       .Lprov_anthropic_done

.Lprov_anthropic_fail_zero:
    // Streaming fallback: collect all "text":"..." deltas from SSE payload.
    mov     x0, x19
    adrp    x1, _str_pat_text_value@PAGE
    add     x1, x1, _str_pat_text_value@PAGEOFF
    mov     x2, #8
    bl      .Lprov_parse_stream_tokens

.Lprov_anthropic_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ──────────────────────────────────────────────────────────────────
// Tool extraction helpers
// ──────────────────────────────────────────────────────────────────
.Lprov_set_tool_from_openai:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    mov     x19, x0                     // response json

    mov     x0, x19
    adrp    x1, _str_key_tool_calls@PAGE
    add     x1, x1, _str_key_tool_calls@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lprov_tool_fail

    mov     x0, x19
    adrp    x1, _str_key_name@PAGE
    add     x1, x1, _str_key_name@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lprov_tool_fail
    bl      .Lprov_copy_substr
    cbz     x0, .Lprov_tool_fail
    mov     x21, x0                     // copied name ptr
    mov     x22, x1                     // name len

    mov     x0, x19
    adrp    x1, _str_key_arguments@PAGE
    add     x1, x1, _str_key_arguments@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lprov_tool_empty_args
    ldrb    w8, [x0]
    cmp     w8, #'{'
    b.eq    .Lprov_tool_copy_object_args
    cmp     w8, #'['
    b.eq    .Lprov_tool_copy_object_args
    bl      .Lprov_decode_json_string
    cbz     x0, .Lprov_tool_empty_args
    mov     x23, x0                     // args ptr
    mov     x24, x1                     // args len
    b       .Lprov_tool_store

.Lprov_tool_copy_object_args:
    bl      .Lprov_copy_substr
    cbz     x0, .Lprov_tool_empty_args
    mov     x23, x0
    mov     x24, x1
    b       .Lprov_tool_store

.Lprov_tool_empty_args:
    adrp    x23, _str_empty@PAGE
    add     x23, x23, _str_empty@PAGEOFF
    mov     x24, #0

.Lprov_tool_store:
    // Store pending call globals.
    adrp    x8, _g_provider_tool_pending@PAGE
    add     x8, x8, _g_provider_tool_pending@PAGEOFF
    mov     x9, #1
    str     x9, [x8]
    str     x21, [x8, #8]
    str     x22, [x8, #16]
    str     x23, [x8, #24]
    str     x24, [x8, #32]

    // Return summary text.
    mov     x0, #BUF_SMALL
    bl      _arena_alloc
    cbz     x0, .Lprov_tool_fail
    mov     x20, x0
    mov     x0, x20
    mov     x1, #BUF_SMALL
    adrp    x2, _str_tool_call_name_fmt@PAGE
    add     x2, x2, _str_tool_call_name_fmt@PAGEOFF
    mov     x3, x22
    mov     x4, x21
    bl      _snprintf_va2
    cmp     x0, #0
    b.lt    .Lprov_tool_fail
    cmp     x0, #BUF_SMALL
    b.lt    .Lprov_tool_ok
    mov     x0, x20
    mov     x1, #255
    b       .Lprov_tool_ret

.Lprov_tool_ok:
    mov     x1, x0
    mov     x0, x20
    b       .Lprov_tool_ret

.Lprov_tool_fail:
    mov     x0, #0
    mov     x1, #0

.Lprov_tool_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.Lprov_set_tool_from_anthropic_obj:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    mov     x19, x0                     // content object

    mov     x0, x19
    adrp    x1, _str_key_type@PAGE
    add     x1, x1, _str_key_type@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lprov_atool_fail
    mov     x2, x0
    mov     x3, x1
    adrp    x4, _str_tool_use@PAGE
    add     x4, x4, _str_tool_use@PAGEOFF
    mov     x0, x2
    mov     x1, x3
    mov     x2, x4
    bl      .Lprov_value_equals
    cbz     x0, .Lprov_atool_fail

    mov     x0, x19
    adrp    x1, _str_key_name@PAGE
    add     x1, x1, _str_key_name@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lprov_atool_fail
    bl      .Lprov_copy_substr
    cbz     x0, .Lprov_atool_fail
    mov     x21, x0
    mov     x22, x1

    mov     x0, x19
    adrp    x1, _str_key_input@PAGE
    add     x1, x1, _str_key_input@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lprov_atool_empty
    ldrb    w8, [x0]
    cmp     w8, #'{'
    b.eq    .Lprov_atool_copy
    cmp     w8, #'['
    b.eq    .Lprov_atool_copy
    bl      .Lprov_decode_json_string
    cbz     x0, .Lprov_atool_empty
    mov     x23, x0
    mov     x24, x1
    b       .Lprov_atool_store

.Lprov_atool_copy:
    bl      .Lprov_copy_substr
    cbz     x0, .Lprov_atool_empty
    mov     x23, x0
    mov     x24, x1
    b       .Lprov_atool_store

.Lprov_atool_empty:
    adrp    x23, _str_empty@PAGE
    add     x23, x23, _str_empty@PAGEOFF
    mov     x24, #0

.Lprov_atool_store:
    adrp    x8, _g_provider_tool_pending@PAGE
    add     x8, x8, _g_provider_tool_pending@PAGEOFF
    mov     x9, #1
    str     x9, [x8]
    str     x21, [x8, #8]
    str     x22, [x8, #16]
    str     x23, [x8, #24]
    str     x24, [x8, #32]

    mov     x0, #BUF_SMALL
    bl      _arena_alloc
    cbz     x0, .Lprov_atool_fail
    mov     x20, x0
    mov     x0, x20
    mov     x1, #BUF_SMALL
    adrp    x2, _str_tool_call_name_fmt@PAGE
    add     x2, x2, _str_tool_call_name_fmt@PAGEOFF
    mov     x3, x22
    mov     x4, x21
    bl      _snprintf_va2
    cmp     x0, #0
    b.lt    .Lprov_atool_fail
    cmp     x0, #BUF_SMALL
    b.lt    .Lprov_atool_ok
    mov     x0, x20
    mov     x1, #255
    b       .Lprov_atool_ret

.Lprov_atool_ok:
    mov     x1, x0
    mov     x0, x20
    b       .Lprov_atool_ret

.Lprov_atool_fail:
    mov     x0, #0
    mov     x1, #0

.Lprov_atool_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// ──────────────────────────────────────────────────────────────────
// Request builder helpers
// ──────────────────────────────────────────────────────────────────
.Lprov_append_message_openai:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0                     // role
    mov     x20, x1                     // msg ptr
    mov     x21, x2                     // msg len
    mov     x22, x3                     // first flag

    cbnz    x22, .Lprov_omsg_no_comma
    adrp    x0, _str_comma@PAGE
    add     x0, x0, _str_comma@PAGEOFF
    bl      .Lprov_append_cstr
    cbz     x0, .Lprov_omsg_fail

.Lprov_omsg_no_comma:
    adrp    x0, _str_openai_msg_prefix@PAGE
    add     x0, x0, _str_openai_msg_prefix@PAGEOFF
    bl      .Lprov_append_cstr
    cbz     x0, .Lprov_omsg_fail

    // Tool role is encoded as user to keep OpenAI-compatible payload valid
    // without requiring tool_call_id wiring.
    cmp     x19, #ROLE_ASSISTANT
    b.eq    .Lprov_omsg_role_assistant
    cmp     x19, #ROLE_SYSTEM
    b.eq    .Lprov_omsg_role_system
    adrp    x0, _str_role_user@PAGE
    add     x0, x0, _str_role_user@PAGEOFF
    b       .Lprov_omsg_role_set

.Lprov_omsg_role_assistant:
    adrp    x0, _str_role_assistant@PAGE
    add     x0, x0, _str_role_assistant@PAGEOFF
    b       .Lprov_omsg_role_set

.Lprov_omsg_role_system:
    adrp    x0, _str_role_system@PAGE
    add     x0, x0, _str_role_system@PAGEOFF

.Lprov_omsg_role_set:
    bl      .Lprov_append_cstr
    cbz     x0, .Lprov_omsg_fail

    adrp    x0, _str_openai_msg_mid@PAGE
    add     x0, x0, _str_openai_msg_mid@PAGEOFF
    bl      .Lprov_append_cstr
    cbz     x0, .Lprov_omsg_fail

    mov     x0, x20
    mov     x1, x21
    bl      .Lprov_append_escaped
    cbz     x0, .Lprov_omsg_fail

    adrp    x0, _str_openai_msg_suffix@PAGE
    add     x0, x0, _str_openai_msg_suffix@PAGEOFF
    bl      .Lprov_append_cstr
    cbz     x0, .Lprov_omsg_fail

    mov     x0, #1
    b       .Lprov_omsg_ret

.Lprov_omsg_fail:
    mov     x0, #0

.Lprov_omsg_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Lprov_append_message_anthropic:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0                     // role
    mov     x20, x1                     // msg ptr
    mov     x21, x2                     // msg len
    mov     x22, x3                     // first flag

    cbnz    x22, .Lprov_amsg_no_comma
    adrp    x0, _str_comma@PAGE
    add     x0, x0, _str_comma@PAGEOFF
    bl      .Lprov_append_cstr
    cbz     x0, .Lprov_amsg_fail

.Lprov_amsg_no_comma:
    adrp    x0, _str_anthropic_msg_prefix@PAGE
    add     x0, x0, _str_anthropic_msg_prefix@PAGEOFF
    bl      .Lprov_append_cstr
    cbz     x0, .Lprov_amsg_fail

    cmp     x19, #ROLE_ASSISTANT
    b.eq    .Lprov_amsg_role_assistant
    adrp    x0, _str_role_user@PAGE
    add     x0, x0, _str_role_user@PAGEOFF
    b       .Lprov_amsg_role_set

.Lprov_amsg_role_assistant:
    adrp    x0, _str_role_assistant@PAGE
    add     x0, x0, _str_role_assistant@PAGEOFF

.Lprov_amsg_role_set:
    bl      .Lprov_append_cstr
    cbz     x0, .Lprov_amsg_fail

    adrp    x0, _str_anthropic_msg_mid@PAGE
    add     x0, x0, _str_anthropic_msg_mid@PAGEOFF
    bl      .Lprov_append_cstr
    cbz     x0, .Lprov_amsg_fail

    mov     x0, x20
    mov     x1, x21
    bl      .Lprov_append_escaped
    cbz     x0, .Lprov_amsg_fail

    adrp    x0, _str_anthropic_msg_suffix@PAGE
    add     x0, x0, _str_anthropic_msg_suffix@PAGEOFF
    bl      .Lprov_append_cstr
    cbz     x0, .Lprov_amsg_fail

    mov     x0, #1
    b       .Lprov_amsg_ret

.Lprov_amsg_fail:
    mov     x0, #0

.Lprov_amsg_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ──────────────────────────────────────────────────────────────────
// Buffer utilities
// ──────────────────────────────────────────────────────────────────
.Lprov_append_cstr:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    mov     x19, x0
    mov     x0, x19
    bl      _strlen_simd
    mov     x20, x0
    cmp     x20, x25
    b.hs    .Lprov_append_cstr_fail
    mov     x0, x24
    mov     x1, x19
    mov     x2, x20
    bl      _memcpy_simd
    add     x24, x24, x20
    sub     x25, x25, x20
    strb    wzr, [x24]
    mov     x0, #1
    b       .Lprov_append_cstr_ret

.Lprov_append_cstr_fail:
    mov     x0, #0

.Lprov_append_cstr_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lprov_append_escaped:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0                     // src
    mov     x20, x1                     // len
    mov     x21, #0

.Lprov_esc_loop:
    cmp     x21, x20
    b.ge    .Lprov_esc_done
    ldrb    w22, [x19, x21]
    cmp     w22, #'"'
    b.eq    .Lprov_esc_quote
    cmp     w22, #'\\'
    b.eq    .Lprov_esc_backslash
    cmp     w22, #'\n'
    b.eq    .Lprov_esc_newline
    cmp     w22, #'\r'
    b.eq    .Lprov_esc_cr
    cmp     w22, #'\t'
    b.eq    .Lprov_esc_tab
    cmp     w22, #0x20
    b.lt    .Lprov_esc_control

    cmp     x25, #1
    b.ls    .Lprov_esc_fail
    strb    w22, [x24], #1
    sub     x25, x25, #1
    add     x21, x21, #1
    b       .Lprov_esc_loop

.Lprov_esc_quote:
    mov     w22, #'"'
    b       .Lprov_esc_two
.Lprov_esc_backslash:
    mov     w22, #'\\'
    b       .Lprov_esc_two
.Lprov_esc_newline:
    mov     w22, #'n'
    b       .Lprov_esc_two
.Lprov_esc_cr:
    mov     w22, #'r'
    b       .Lprov_esc_two
.Lprov_esc_tab:
    mov     w22, #'t'

.Lprov_esc_two:
    cmp     x25, #2
    b.ls    .Lprov_esc_fail
    mov     w8, #'\\'
    strb    w8, [x24], #1
    strb    w22, [x24], #1
    sub     x25, x25, #2
    add     x21, x21, #1
    b       .Lprov_esc_loop

.Lprov_esc_control:
    cmp     x25, #1
    b.ls    .Lprov_esc_fail
    mov     w8, #' '
    strb    w8, [x24], #1
    sub     x25, x25, #1
    add     x21, x21, #1
    b       .Lprov_esc_loop

.Lprov_esc_done:
    strb    wzr, [x24]
    mov     x0, #1
    b       .Lprov_esc_ret

.Lprov_esc_fail:
    mov     x0, #0

.Lprov_esc_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Lprov_copy_substr:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    mov     x19, x0
    mov     x20, x1
    add     x0, x20, #1
    bl      _arena_alloc
    cbz     x0, .Lprov_copy_fail
    mov     x8, x0
    mov     x0, x8
    mov     x1, x19
    mov     x2, x20
    bl      _memcpy_simd
    strb    wzr, [x8, x20]
    mov     x0, x8
    mov     x1, x20
    b       .Lprov_copy_ret

.Lprov_copy_fail:
    mov     x0, #0
    mov     x1, #0

.Lprov_copy_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lprov_decode_json_string:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0                     // src
    mov     x20, x1                     // len

    add     x0, x20, #1
    bl      _arena_alloc
    cbz     x0, .Lprov_decode_fail
    mov     x21, x0                     // dst
    mov     x22, #0                     // src idx
    mov     x8, #0                      // dst idx

.Lprov_decode_loop:
    cmp     x22, x20
    b.ge    .Lprov_decode_done
    ldrb    w9, [x19, x22]
    cmp     w9, #'\\'
    b.ne    .Lprov_decode_copy

    add     x22, x22, #1
    cmp     x22, x20
    b.ge    .Lprov_decode_done
    ldrb    w9, [x19, x22]
    cmp     w9, #'"'
    b.eq    .Lprov_decode_emit
    cmp     w9, #'\\'
    b.eq    .Lprov_decode_emit
    cmp     w9, #'/'
    b.eq    .Lprov_decode_emit
    cmp     w9, #'n'
    b.ne    .Lprov_decode_not_n
    mov     w9, #'\n'
    b       .Lprov_decode_emit
.Lprov_decode_not_n:
    cmp     w9, #'r'
    b.ne    .Lprov_decode_not_r
    mov     w9, #'\r'
    b       .Lprov_decode_emit
.Lprov_decode_not_r:
    cmp     w9, #'t'
    b.ne    .Lprov_decode_not_t
    mov     w9, #'\t'
    b       .Lprov_decode_emit
.Lprov_decode_not_t:
    cmp     w9, #'u'
    b.ne    .Lprov_decode_emit
    // Skip \uXXXX and emit '?'
    add     x22, x22, #4
    mov     w9, #'?'
    b       .Lprov_decode_emit

.Lprov_decode_copy:
    // fallthrough with current byte in w9
.Lprov_decode_emit:
    strb    w9, [x21, x8]
    add     x8, x8, #1
    add     x22, x22, #1
    b       .Lprov_decode_loop

.Lprov_decode_done:
    strb    wzr, [x21, x8]
    mov     x0, x21
    mov     x1, x8
    b       .Lprov_decode_ret

.Lprov_decode_fail:
    mov     x0, #0
    mov     x1, #0

.Lprov_decode_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// Parse stream payload by collecting all tokens matching:
//   <pattern><string-literal>
// Example pattern: "\"content\":\"" or "\"text\":\""
// x0=payload ptr, x1=pattern cstr, x2=pattern length
// Returns: x0=aggregated text ptr, x1=len (or 0,0 if not found)
.Lprov_parse_stream_tokens:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    mov     x19, x0                     // payload ptr
    mov     x20, x1                     // pattern ptr
    mov     x21, x2                     // pattern len

    mov     x0, #BUF_LARGE
    bl      _arena_alloc
    cbz     x0, .Lprov_stream_fail
    mov     x22, x0                     // out start
    mov     x23, x22                    // out cursor
    mov     x24, #BUF_LARGE             // out remaining
    mov     x25, #0                     // bytes written

.Lprov_stream_seek:
    ldrb    w8, [x19]
    cbz     w8, .Lprov_stream_done
    mov     x0, x19
    mov     x1, x20
    bl      _str_starts_with
    cbz     x0, .Lprov_stream_seek_next
    add     x19, x19, x21

.Lprov_stream_copy:
    ldrb    w8, [x19], #1
    cbz     w8, .Lprov_stream_done
    cmp     w8, #'"'
    b.eq    .Lprov_stream_seek
    cmp     w8, #'\\'
    b.ne    .Lprov_stream_emit

    // Decode JSON escape sequence.
    ldrb    w8, [x19], #1
    cbz     w8, .Lprov_stream_done
    cmp     w8, #'n'
    b.ne    .Lprov_stream_not_n
    mov     w8, #'\n'
    b       .Lprov_stream_emit
.Lprov_stream_not_n:
    cmp     w8, #'r'
    b.ne    .Lprov_stream_not_r
    mov     w8, #'\r'
    b       .Lprov_stream_emit
.Lprov_stream_not_r:
    cmp     w8, #'t'
    b.ne    .Lprov_stream_not_t
    mov     w8, #'\t'
    b       .Lprov_stream_emit
.Lprov_stream_not_t:
    cmp     w8, #'u'
    b.ne    .Lprov_stream_emit
    add     x19, x19, #4
    mov     w8, #'?'

.Lprov_stream_emit:
    cmp     x24, #1
    b.ls    .Lprov_stream_done
    strb    w8, [x23], #1
    sub     x24, x24, #1
    add     x25, x25, #1
    b       .Lprov_stream_copy

.Lprov_stream_seek_next:
    add     x19, x19, #1
    b       .Lprov_stream_seek

.Lprov_stream_done:
    cbz     x25, .Lprov_stream_fail
    strb    wzr, [x23]
    mov     x0, x22
    mov     x1, x25
    b       .Lprov_stream_ret

.Lprov_stream_fail:
    mov     x0, #0
    mov     x1, #0

.Lprov_stream_ret:
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

.Lprov_value_equals:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0                     // value ptr
    mov     x20, x1                     // value len
    mov     x21, x2                     // literal cstr
    mov     x0, x21
    bl      _strlen_simd
    cmp     x0, x20
    b.ne    .Lprov_ve_no
    mov     x0, x19
    mov     x1, x21
    mov     x2, x20
    bl      _json_match_key
    b       .Lprov_ve_ret

.Lprov_ve_no:
    mov     x0, #0

.Lprov_ve_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Lprov_is_anthropic:
    cmp     x1, #9
    b.lt    .Lprov_is_anthropic_no
    mov     x2, #9
    adrp    x3, _str_provider_anthropic@PAGE
    add     x3, x3, _str_provider_anthropic@PAGEOFF
    mov     x1, x3
    b       _json_match_key

.Lprov_is_anthropic_no:
    mov     x0, #0
    ret

.Lprov_tool_clear:
    adrp    x8, _g_provider_tool_pending@PAGE
    add     x8, x8, _g_provider_tool_pending@PAGEOFF
    stp     xzr, xzr, [x8]
    stp     xzr, xzr, [x8, #16]
    str     xzr, [x8, #32]
    ret

// ── BSS ──
.section __DATA,__bss
.p2align 4
_g_provider_tool_pending:
    .quad   0
    .quad   0
    .quad   0
    .quad   0
    .quad   0

// ── Data ──
.section __DATA,__const
.p2align 3

_str_openai_prefix_fmt:
    .asciz  "{\"model\":\"%.*s\",\"messages\":["
_str_openai_suffix_fmt:
    .asciz  ",\"temperature\":%.3f}"
_str_openai_tools_blob:
    .asciz  "],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"status\",\"description\":\"Show current status\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}},{\"type\":\"function\",\"function\":{\"name\":\"shell\",\"description\":\"Run a shell command\",\"parameters\":{\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"}},\"required\":[\"command\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"file_read\",\"description\":\"Read a file\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"file_write\",\"description\":\"Write a file\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"}},\"required\":[\"path\",\"content\"]}}}],\"tool_choice\":\"auto\""

_str_anthropic_prefix_fmt:
    .asciz  "{\"model\":\"%.*s\",\"max_tokens\":1024,\"messages\":["
_str_anthropic_suffix_fmt:
    .asciz  ",\"temperature\":%.3f}"
_str_anthropic_tools_blob:
    .asciz  "],\"tools\":[{\"name\":\"status\",\"description\":\"Show current status\",\"input_schema\":{\"type\":\"object\",\"properties\":{}}},{\"name\":\"shell\",\"description\":\"Run a shell command\",\"input_schema\":{\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"}},\"required\":[\"command\"]}},{\"name\":\"file_read\",\"description\":\"Read a file\",\"input_schema\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}},{\"name\":\"file_write\",\"description\":\"Write a file\",\"input_schema\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"}},\"required\":[\"path\",\"content\"]}}],\"tool_choice\":{\"type\":\"auto\"}"

_str_openai_msg_prefix:
    .asciz  "{\"role\":\""
_str_openai_msg_mid:
    .asciz  "\",\"content\":\""
_str_openai_msg_suffix:
    .asciz  "\"}"

_str_anthropic_msg_prefix:
    .asciz  "{\"role\":\""
_str_anthropic_msg_mid:
    .asciz  "\",\"content\":[{\"type\":\"text\",\"text\":\""
_str_anthropic_msg_suffix:
    .asciz  "\"}]}"

_str_bearer_fmt:
    .asciz  "Bearer %.*s"
_str_x_api_key_fmt:
    .asciz  "x-api-key: %.*s"

_str_comma:
    .asciz  ","
_str_empty:
    .asciz  ""

_str_role_system:
    .asciz  "system"
_str_role_user:
    .asciz  "user"
_str_role_assistant:
    .asciz  "assistant"

_str_key_choices:
    .asciz  "choices"
_str_key_message:
    .asciz  "message"
_str_key_content:
    .asciz  "content"
_str_key_text:
    .asciz  "text"
_str_key_type:
    .asciz  "type"
_str_key_tool_calls:
    .asciz  "tool_calls"
_str_key_name:
    .asciz  "name"
_str_key_arguments:
    .asciz  "arguments"
_str_key_input:
    .asciz  "input"
_str_pat_content_value:
    .asciz  "\"content\":\""
_str_pat_text_value:
    .asciz  "\"text\":\""
_str_sse_prefix:
    .asciz  "data:"

_str_tool_use:
    .asciz  "tool_use"
_str_tool_call_name_fmt:
    .asciz  "[tool_call] %.*s"

_str_provider_anthropic:
    .asciz  "anthropic"

_str_not_config_err:
    .asciz  "error: not configured. create ~/.assemblyclaw/config.json"
_str_http_err:
    .asciz  "error: HTTP request failed"
_str_parse_err:
    .asciz  "warning: could not parse response content field"
