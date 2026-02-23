// config.s — Configuration loader
// ARM64 macOS — reads ~/.assemblyclaw/config.json
//
// Config structure (global, in .bss):
//   provider_name: ptr+len    (e.g., "openrouter")
//   api_key: ptr+len          (e.g., "sk-or-...")
//   model: ptr+len            (e.g., "anthropic/claude-sonnet-4")
//   base_url: ptr+len         (provider API URL)
//   temperature: double

.include "include/constants.inc"

.section __TEXT,__text,regular,pure_instructions
.p2align 4

// Config struct layout
.set CFG_PROVIDER,    0    // ptr (8) + len (8) = 16
.set CFG_API_KEY,     16   // ptr (8) + len (8) = 16
.set CFG_MODEL,       32   // ptr (8) + len (8) = 16
.set CFG_BASE_URL,    48   // ptr (8) + len (8) = 16
.set CFG_TEMP,        64   // double (8)
.set CFG_LOADED,      72   // bool (8)
.set CFG_SIZE,        80

// ──────────────────────────────────────────────────────────────────
// _config_load: load config from ~/.assemblyclaw/config.json
//   Returns: x0 = 0 on success, error code on failure
// ──────────────────────────────────────────────────────────────────
.global _config_load
_config_load:
    stp     x29, x30, [sp, #-96]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]
    sub     sp, sp, #256

    // Temp buffers:
    //   sp +   0: provider key C-string
    //   sp + 128: numeric literal C-string (temperature)
    mov     x26, sp
    add     x27, sp, #128

    adrp    x23, _g_config@PAGE
    add     x23, x23, _g_config@PAGEOFF
    str     xzr, [x23, #CFG_LOADED]

    // Read "~/.assemblyclaw/config.json" (auto-bootstrap on first run)
    adrp    x0, _str_cfg_home_path@PAGE
    add     x0, x0, _str_cfg_home_path@PAGEOFF
    bl      _path_expand_home
    mov     x25, x0
    mov     x0, x25
    bl      _read_file
    cbz     x0, .Lcfg_bootstrap_missing
    mov     x19, x0                     // JSON buffer
    mov     x20, x1                     // JSON length
    b       .Lcfg_parse_root

.Lcfg_bootstrap_missing:
    // Missing config: create template and retry load.
    mov     x0, x25
    bl      .Lcfg_bootstrap_default
    cbz     x0, .Lcfg_not_found

    mov     x0, x25
    bl      _read_file
    cbz     x0, .Lcfg_not_found
    mov     x19, x0
    mov     x20, x1

.Lcfg_parse_root:
    // Basic sanity: config must be a JSON object.
    mov     x0, x19
    bl      .Lcfg_is_object_json
    cbz     x0, .Lcfg_no_apikey

    // Parse default_provider
    mov     x0, x19
    adrp    x1, _str_key_provider@PAGE
    add     x1, x1, _str_key_provider@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lcfg_provider_default
    str     x0, [x23, #CFG_PROVIDER]
    str     x1, [x23, #(CFG_PROVIDER + 8)]
    b       .Lcfg_provider_ready

.Lcfg_provider_default:
    adrp    x0, _str_default_provider@PAGE
    add     x0, x0, _str_default_provider@PAGEOFF
    str     x0, [x23, #CFG_PROVIDER]
    bl      _strlen_simd
    str     x0, [x23, #(CFG_PROVIDER + 8)]

.Lcfg_provider_ready:
    // Copy provider name to temp buffer as NUL-terminated C string.
    ldr     x28, [x23, #CFG_PROVIDER]
    ldr     x24, [x23, #(CFG_PROVIDER + 8)]
    cmp     x24, #120
    b.gt    .Lcfg_no_apikey
    mov     x0, x26
    mov     x1, x28
    mov     x2, x24
    bl      _memcpy_simd
    strb    wzr, [x26, x24]

    // Find providers object and selected provider object.
    mov     x21, #0                     // selected provider object ptr
    mov     x22, #0                     // selected provider object len
    mov     x0, x19
    adrp    x1, _str_key_providers@PAGE
    add     x1, x1, _str_key_providers@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lcfg_parse_api_key

    // Limit nested key search to the providers object.
    add     x8, x0, x1
    strb    wzr, [x8]
    mov     x1, x26                     // selected provider key
    bl      _json_find_key
    mov     x21, x0
    mov     x22, x1

.Lcfg_parse_api_key:
    cbz     x21, .Lcfg_try_top_apikey
    mov     x0, x21
    adrp    x1, _str_key_api_key@PAGE
    add     x1, x1, _str_key_api_key@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lcfg_try_top_apikey
    str     x0, [x23, #CFG_API_KEY]
    str     x1, [x23, #(CFG_API_KEY + 8)]
    b       .Lcfg_parse_model

.Lcfg_try_top_apikey:
    mov     x0, x19
    adrp    x1, _str_key_api_key@PAGE
    add     x1, x1, _str_key_api_key@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lcfg_no_apikey
    str     x0, [x23, #CFG_API_KEY]
    str     x1, [x23, #(CFG_API_KEY + 8)]

.Lcfg_parse_model:
    cbz     x21, .Lcfg_model_top
    mov     x0, x21
    adrp    x1, _str_key_model@PAGE
    add     x1, x1, _str_key_model@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lcfg_model_top
    str     x0, [x23, #CFG_MODEL]
    str     x1, [x23, #(CFG_MODEL + 8)]
    b       .Lcfg_parse_base_url

.Lcfg_model_top:
    mov     x0, x19
    adrp    x1, _str_key_model@PAGE
    add     x1, x1, _str_key_model@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lcfg_model_default_map
    str     x0, [x23, #CFG_MODEL]
    str     x1, [x23, #(CFG_MODEL + 8)]
    b       .Lcfg_parse_base_url

.Lcfg_model_default_map:
    mov     x0, x26
    adrp    x1, _str_provider_anthropic@PAGE
    add     x1, x1, _str_provider_anthropic@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Lcfg_model_set_anthropic

    mov     x0, x26
    adrp    x1, _str_provider_openai@PAGE
    add     x1, x1, _str_provider_openai@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Lcfg_model_set_openai

    mov     x0, x26
    adrp    x1, _str_provider_deepseek@PAGE
    add     x1, x1, _str_provider_deepseek@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Lcfg_model_set_deepseek

    adrp    x0, _str_default_model@PAGE
    add     x0, x0, _str_default_model@PAGEOFF
    b       .Lcfg_model_store_default

.Lcfg_model_set_anthropic:
    adrp    x0, _str_default_model_anthropic@PAGE
    add     x0, x0, _str_default_model_anthropic@PAGEOFF
    b       .Lcfg_model_store_default

.Lcfg_model_set_openai:
    adrp    x0, _str_default_model_openai@PAGE
    add     x0, x0, _str_default_model_openai@PAGEOFF
    b       .Lcfg_model_store_default

.Lcfg_model_set_deepseek:
    adrp    x0, _str_default_model_deepseek@PAGE
    add     x0, x0, _str_default_model_deepseek@PAGEOFF

.Lcfg_model_store_default:
    str     x0, [x23, #CFG_MODEL]
    mov     x28, x0
    mov     x0, x28
    bl      _strlen_simd
    str     x0, [x23, #(CFG_MODEL + 8)]

.Lcfg_parse_base_url:
    cbz     x21, .Lcfg_base_url_top
    mov     x0, x21
    adrp    x1, _str_key_base_url@PAGE
    add     x1, x1, _str_key_base_url@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lcfg_base_url_top
    bl      .Lcfg_copy_string
    cbz     x0, .Lcfg_no_apikey
    str     x0, [x23, #CFG_BASE_URL]
    str     x1, [x23, #(CFG_BASE_URL + 8)]
    b       .Lcfg_parse_temperature

.Lcfg_base_url_top:
    mov     x0, x19
    adrp    x1, _str_key_base_url@PAGE
    add     x1, x1, _str_key_base_url@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lcfg_base_url_default_map
    bl      .Lcfg_copy_string
    cbz     x0, .Lcfg_no_apikey
    str     x0, [x23, #CFG_BASE_URL]
    str     x1, [x23, #(CFG_BASE_URL + 8)]
    b       .Lcfg_parse_temperature

.Lcfg_base_url_default_map:
    mov     x0, x26
    adrp    x1, _str_provider_anthropic@PAGE
    add     x1, x1, _str_provider_anthropic@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Lcfg_url_set_anthropic

    mov     x0, x26
    adrp    x1, _str_provider_openai@PAGE
    add     x1, x1, _str_provider_openai@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Lcfg_url_set_openai

    mov     x0, x26
    adrp    x1, _str_provider_deepseek@PAGE
    add     x1, x1, _str_provider_deepseek@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Lcfg_url_set_deepseek

    adrp    x0, _str_openrouter_url@PAGE
    add     x0, x0, _str_openrouter_url@PAGEOFF
    b       .Lcfg_url_store_default

.Lcfg_url_set_anthropic:
    adrp    x0, _str_anthropic_url@PAGE
    add     x0, x0, _str_anthropic_url@PAGEOFF
    b       .Lcfg_url_store_default

.Lcfg_url_set_openai:
    adrp    x0, _str_openai_url@PAGE
    add     x0, x0, _str_openai_url@PAGEOFF
    b       .Lcfg_url_store_default

.Lcfg_url_set_deepseek:
    adrp    x0, _str_deepseek_url@PAGE
    add     x0, x0, _str_deepseek_url@PAGEOFF

.Lcfg_url_store_default:
    str     x0, [x23, #CFG_BASE_URL]
    mov     x28, x0
    mov     x0, x28
    bl      _strlen_simd
    str     x0, [x23, #(CFG_BASE_URL + 8)]

.Lcfg_parse_temperature:
    // Default temperature = 0.7
    adrp    x0, _default_temp@PAGE
    add     x0, x0, _default_temp@PAGEOFF
    ldr     d0, [x0]
    str     d0, [x23, #CFG_TEMP]

    // Provider-specific temperature first.
    cbz     x21, .Lcfg_temp_top
    mov     x0, x21
    adrp    x1, _str_key_temperature@PAGE
    add     x1, x1, _str_key_temperature@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lcfg_temp_top
    b       .Lcfg_temp_parse_value

.Lcfg_temp_top:
    mov     x0, x19
    adrp    x1, _str_key_temperature@PAGE
    add     x1, x1, _str_key_temperature@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lcfg_validate_and_finish

.Lcfg_temp_parse_value:
    // x0 = temp literal ptr, x1 = temp literal len
    cmp     x1, #63
    b.gt    .Lcfg_validate_and_finish
    mov     x28, x1
    mov     x2, x1
    mov     x1, x0
    mov     x0, x27
    bl      _memcpy_simd
    strb    wzr, [x27, x28]
    mov     x0, x27
    bl      _atof
    str     d0, [x23, #CFG_TEMP]

.Lcfg_validate_and_finish:
    bl      .Lcfg_validate
    cbz     x0, .Lcfg_no_apikey

.Lcfg_loaded_ok:
    mov     x0, #1
    str     x0, [x23, #CFG_LOADED]
    mov     x0, #ERR_OK
    b       .Lcfg_ret

.Lcfg_not_found:
    mov     x0, #ERR_NOT_FOUND
    b       .Lcfg_ret

.Lcfg_no_apikey:
    mov     x0, #ERR_CONFIG
    b       .Lcfg_ret

// x0=config path ptr => x0=1 on success, 0 on failure.
.Lcfg_bootstrap_default:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    str     x25, [sp, #64]

    mov     x19, x0

    // Ensure ~/.assemblyclaw directory exists.
    adrp    x0, _str_cfg_home_dir@PAGE
    add     x0, x0, _str_cfg_home_dir@PAGEOFF
    bl      _path_expand_home
    cbz     x0, .Lcfg_bootstrap_fail
    mov     x20, x0
    mov     x0, x20
    mov     x1, #493                    // 0755
    bl      _mkdir

    // Open target config in write mode.
    mov     x0, x19
    adrp    x1, _str_file_mode_w@PAGE
    add     x1, x1, _str_file_mode_w@PAGEOFF
    bl      _fopen
    cbz     x0, .Lcfg_bootstrap_fail
    mov     x21, x0                     // FILE*

    // Write default template.
    adrp    x22, _str_cfg_template@PAGE
    add     x22, x22, _str_cfg_template@PAGEOFF
    mov     x0, x22
    bl      _strlen_simd
    mov     x23, x0

    mov     x0, x22
    mov     x1, #1
    mov     x2, x23
    mov     x3, x21
    bl      _fwrite
    cmp     x0, x23
    b.ne    .Lcfg_bootstrap_close_fail

    mov     x0, x21
    bl      _fclose
    cmp     x0, #0
    b.ne    .Lcfg_bootstrap_fail

    mov     x0, #1
    b       .Lcfg_bootstrap_done

.Lcfg_bootstrap_close_fail:
    mov     x0, x21
    bl      _fclose

.Lcfg_bootstrap_fail:
    mov     x0, #0

.Lcfg_bootstrap_done:
    ldr     x25, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

// x0=source ptr, x1=source len => x0=arena copy ptr, x1=len (or 0,0 on OOM)
.Lcfg_copy_string:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0
    mov     x20, x1
    add     x0, x20, #1
    bl      _arena_alloc
    cbz     x0, .Lcfg_copy_fail

    mov     x8, x0
    mov     x0, x8
    mov     x1, x19
    mov     x2, x20
    bl      _memcpy_simd
    strb    wzr, [x8, x20]
    mov     x0, x8
    mov     x1, x20
    b       .Lcfg_copy_done

.Lcfg_copy_fail:
    mov     x0, #0
    mov     x1, #0

.Lcfg_copy_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// x0=json buffer ptr => x0=1 if first non-space char is '{', else 0
.Lcfg_is_object_json:
    mov     x8, x0
.Lcfg_obj_scan:
    ldrb    w9, [x8]
    cbz     w9, .Lcfg_obj_no
    cmp     w9, #' '
    b.eq    .Lcfg_obj_next
    cmp     w9, #'\t'
    b.eq    .Lcfg_obj_next
    cmp     w9, #'\n'
    b.eq    .Lcfg_obj_next
    cmp     w9, #'\r'
    b.eq    .Lcfg_obj_next
    cmp     w9, #'{'
    b.eq    .Lcfg_obj_yes
    b       .Lcfg_obj_no
.Lcfg_obj_next:
    add     x8, x8, #1
    b       .Lcfg_obj_scan
.Lcfg_obj_yes:
    mov     x0, #1
    ret
.Lcfg_obj_no:
    mov     x0, #0
    ret

// Validate loaded config fields.
// Returns: x0=1 valid, x0=0 invalid
.Lcfg_validate:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    adrp    x19, _g_config@PAGE
    add     x19, x19, _g_config@PAGEOFF

    ldr     x0, [x19, #(CFG_PROVIDER + 8)]
    cbz     x0, .Lcfg_validate_no
    ldr     x0, [x19, #(CFG_API_KEY + 8)]
    cbz     x0, .Lcfg_validate_no
    ldr     x0, [x19, #(CFG_MODEL + 8)]
    cbz     x0, .Lcfg_validate_no
    ldr     x0, [x19, #(CFG_BASE_URL + 8)]
    cbz     x0, .Lcfg_validate_no

    ldr     x20, [x19, #CFG_BASE_URL]
    mov     x0, x20
    adrp    x1, _str_https_prefix@PAGE
    add     x1, x1, _str_https_prefix@PAGEOFF
    bl      _str_starts_with
    cbnz    x0, .Lcfg_validate_yes

    mov     x0, x20
    adrp    x1, _str_http_prefix@PAGE
    add     x1, x1, _str_http_prefix@PAGEOFF
    bl      _str_starts_with
    cbnz    x0, .Lcfg_validate_yes

.Lcfg_validate_no:
    mov     x0, #0
    b       .Lcfg_validate_ret

.Lcfg_validate_yes:
    mov     x0, #1

.Lcfg_validate_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lcfg_ret:
    add     sp, sp, #256
    ldp     x27, x28, [sp, #80]
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret

// ──────────────────────────────────────────────────────────────────
// _config_get: return pointer to global config struct
//   Returns: x0 = pointer to config
// ──────────────────────────────────────────────────────────────────
.global _config_get
_config_get:
    adrp    x0, _g_config@PAGE
    add     x0, x0, _g_config@PAGEOFF
    ret

// ──────────────────────────────────────────────────────────────────
// _config_print_status: print config summary
// ──────────────────────────────────────────────────────────────────
.global _config_print_status
_config_print_status:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, _g_config@PAGE
    add     x0, x0, _g_config@PAGEOFF
    ldr     x1, [x0, #CFG_LOADED]
    cbz     x1, .Lcfg_status_not_loaded

    // printf format uses: %.*s %.*s %.*s
    // args order: len, ptr pairs for provider/model/api_key
    ldr     x1, [x0, #(CFG_PROVIDER + 8)] // provider len
    ldr     x2, [x0, #CFG_PROVIDER]       // provider ptr
    ldr     x3, [x0, #(CFG_MODEL + 8)]    // model len
    ldr     x4, [x0, #CFG_MODEL]          // model ptr
    ldr     x5, [x0, #(CFG_API_KEY + 8)]  // api_key len
    ldr     x6, [x0, #CFG_API_KEY]        // api_key ptr
    // Limit displayed key prefix to at most 4 characters.
    mov     x7, #4
    cmp     x5, x7
    csel    x5, x5, x7, ls

    adrp    x0, _str_status_fmt@PAGE
    add     x0, x0, _str_status_fmt@PAGEOFF
    bl      _printf_va6
    b       .Lcfg_status_done

.Lcfg_status_not_loaded:
    adrp    x0, _str_not_configured@PAGE
    add     x0, x0, _str_not_configured@PAGEOFF
    bl      _puts

.Lcfg_status_done:
    ldp     x29, x30, [sp], #16
    ret

// ── BSS ──
.section __DATA,__bss
.p2align 4
.global _g_config
_g_config:
    .space  CFG_SIZE

// ── Data ──
.section __DATA,__const
.p2align 3

_str_cfg_home_path:
    .asciz  "~/.assemblyclaw/config.json"
_str_cfg_home_dir:
    .asciz  "~/.assemblyclaw"
_str_key_provider:
    .asciz  "default_provider"
_str_key_providers:
    .asciz  "providers"
_str_key_api_key:
    .asciz  "api_key"
_str_key_model:
    .asciz  "model"
_str_key_base_url:
    .asciz  "base_url"
_str_key_temperature:
    .asciz  "temperature"
_str_default_provider:
    .asciz  "openrouter"
_str_default_model:
    .asciz  "anthropic/claude-sonnet-4"
_str_default_model_anthropic:
    .asciz  "claude-sonnet-4-20250514"
_str_default_model_openai:
    .asciz  "gpt-4.1-mini"
_str_default_model_deepseek:
    .asciz  "deepseek-chat"
_str_openrouter_url:
    .asciz  "https://openrouter.ai/api/v1/chat/completions"
_str_anthropic_url:
    .asciz  "https://api.anthropic.com/v1/messages"
_str_openai_url:
    .asciz  "https://api.openai.com/v1/chat/completions"
_str_deepseek_url:
    .asciz  "https://api.deepseek.com/chat/completions"

_str_provider_anthropic:
    .asciz  "anthropic"
_str_provider_openai:
    .asciz  "openai"
_str_provider_deepseek:
    .asciz  "deepseek"
_str_http_prefix:
    .asciz  "http://"
_str_https_prefix:
    .asciz  "https://"

_str_status_fmt:
    .asciz  "assemblyclaw status\n  provider: %.*s\n  model:    %.*s\n  api_key:  %.*s...\n  config:   loaded\n"
_str_not_configured:
    .asciz  "assemblyclaw: not configured\n  edit: ~/.assemblyclaw/config.json (set providers.<name>.api_key)"
_str_file_mode_w:
    .asciz  "w"
_str_cfg_template:
    .ascii  "{\n"
    .ascii  "  \"default_provider\": \"openrouter\",\n"
    .ascii  "  \"providers\": {\n"
    .ascii  "    \"openrouter\": {\n"
    .ascii  "      \"api_key\": \"\",\n"
    .ascii  "      \"model\": \"anthropic/claude-sonnet-4\"\n"
    .ascii  "    }\n"
    .ascii  "  }\n"
    .ascii  "}\n"
    .asciz  ""

.p2align 3
_default_temp:
    .double 0.7
