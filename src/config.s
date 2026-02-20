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
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]

    // Build config path: $HOME/.assemblyclaw/config.json
    adrp    x0, _str_home_env@PAGE
    add     x0, x0, _str_home_env@PAGEOFF
    bl      _getenv
    cbz     x0, .Lcfg_no_home
    mov     x19, x0                     // HOME path

    // snprintf(buf, 256, "%s/.assemblyclaw/config.json", home)
    sub     sp, sp, #256
    mov     x0, sp                      // buffer
    mov     x1, #256                    // size
    adrp    x2, _str_cfg_path_fmt@PAGE
    add     x2, x2, _str_cfg_path_fmt@PAGEOFF
    mov     x3, x19                     // home
    bl      _snprintf_va1

    // Read the file
    mov     x0, sp                      // path
    bl      _read_file
    add     sp, sp, #256

    cbz     x0, .Lcfg_not_found
    mov     x19, x0                     // JSON buffer
    mov     x20, x1                     // JSON length

    // Parse: extract "default_provider"
    mov     x0, x19
    adrp    x1, _str_key_provider@PAGE
    add     x1, x1, _str_key_provider@PAGEOFF
    bl      _json_find_key

    adrp    x2, _g_config@PAGE
    add     x2, x2, _g_config@PAGEOFF
    cbz     x0, .Lcfg_default_provider
    str     x0, [x2, #CFG_PROVIDER]
    str     x1, [x2, #(CFG_PROVIDER + 8)]
    b       .Lcfg_parse_providers

.Lcfg_default_provider:
    // Default to "openrouter"
    adrp    x0, _str_default_provider@PAGE
    add     x0, x0, _str_default_provider@PAGEOFF
    str     x0, [x2, #CFG_PROVIDER]
    mov     x1, #10                     // "openrouter" length
    str     x1, [x2, #(CFG_PROVIDER + 8)]

.Lcfg_parse_providers:
    // Find the "providers" object
    mov     x0, x19
    adrp    x1, _str_key_providers@PAGE
    add     x1, x1, _str_key_providers@PAGEOFF
    bl      _json_find_key
    cbz     x0, .Lcfg_try_apikey       // no providers object, try flat api_key

    mov     x21, x0                     // providers JSON object

    // Within providers, find the configured provider's object
    // Then within that, find "api_key"
    mov     x0, x21
    adrp    x1, _str_key_api_key@PAGE
    add     x1, x1, _str_key_api_key@PAGEOFF
    bl      _json_find_key

    adrp    x2, _g_config@PAGE
    add     x2, x2, _g_config@PAGEOFF
    cbz     x0, .Lcfg_try_apikey
    str     x0, [x2, #CFG_API_KEY]
    str     x1, [x2, #(CFG_API_KEY + 8)]
    b       .Lcfg_parse_model

.Lcfg_try_apikey:
    // Try top-level "api_key"
    mov     x0, x19
    adrp    x1, _str_key_api_key@PAGE
    add     x1, x1, _str_key_api_key@PAGEOFF
    bl      _json_find_key

    adrp    x2, _g_config@PAGE
    add     x2, x2, _g_config@PAGEOFF
    cbz     x0, .Lcfg_no_apikey
    str     x0, [x2, #CFG_API_KEY]
    str     x1, [x2, #(CFG_API_KEY + 8)]

.Lcfg_parse_model:
    // Try to find "model" in providers object or top-level
    mov     x0, x19
    adrp    x1, _str_key_model@PAGE
    add     x1, x1, _str_key_model@PAGEOFF
    bl      _json_find_key

    adrp    x2, _g_config@PAGE
    add     x2, x2, _g_config@PAGEOFF
    cbz     x0, .Lcfg_default_model
    str     x0, [x2, #CFG_MODEL]
    str     x1, [x2, #(CFG_MODEL + 8)]
    b       .Lcfg_set_base_url

.Lcfg_default_model:
    adrp    x0, _str_default_model@PAGE
    add     x0, x0, _str_default_model@PAGEOFF
    str     x0, [x2, #CFG_MODEL]
    mov     x1, #27                     // length of default model
    str     x1, [x2, #(CFG_MODEL + 8)]

.Lcfg_set_base_url:
    // Set base URL based on provider name
    adrp    x2, _g_config@PAGE
    add     x2, x2, _g_config@PAGEOFF

    // Default: OpenRouter
    adrp    x0, _str_openrouter_url@PAGE
    add     x0, x0, _str_openrouter_url@PAGEOFF
    str     x0, [x2, #CFG_BASE_URL]
    mov     x1, #35
    str     x1, [x2, #(CFG_BASE_URL + 8)]

    // Set default temperature (0.7)
    adrp    x0, _default_temp@PAGE
    add     x0, x0, _default_temp@PAGEOFF
    ldr     d0, [x0]
    str     d0, [x2, #CFG_TEMP]

    // Mark as loaded
    mov     x0, #1
    str     x0, [x2, #CFG_LOADED]

    mov     x0, #ERR_OK
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Lcfg_no_home:
    mov     x0, #ERR_CONFIG
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Lcfg_not_found:
    mov     x0, #ERR_NOT_FOUND
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Lcfg_no_apikey:
    mov     x0, #ERR_CONFIG
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
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

_str_home_env:
    .asciz  "HOME"
_str_cfg_path_fmt:
    .asciz  "%s/.assemblyclaw/config.json"
_str_key_provider:
    .asciz  "default_provider"
_str_key_providers:
    .asciz  "providers"
_str_key_api_key:
    .asciz  "api_key"
_str_key_model:
    .asciz  "model"
_str_default_provider:
    .asciz  "openrouter"
_str_default_model:
    .asciz  "anthropic/claude-sonnet-4"
_str_openrouter_url:
    .asciz  "https://openrouter.ai/api/v1/chat/completions"
_str_anthropic_url:
    .asciz  "https://api.anthropic.com/v1/messages"
_str_openai_url:
    .asciz  "https://api.openai.com/v1/chat/completions"

_str_status_fmt:
    .asciz  "assemblyclaw status\n  provider: %.*s\n  model:    %.*s\n  api_key:  %.*s...\n  config:   loaded\n"
_str_not_configured:
    .asciz  "assemblyclaw: not configured\n  run: mkdir -p ~/.assemblyclaw && edit ~/.assemblyclaw/config.json"

.p2align 3
_default_temp:
    .double 0.7
