// agent.s — Agent loop
// ARM64 macOS — Apple Silicon optimized
//
// Handles:
//   - Single message mode: agent -m "hello"
//   - Status display: status

.include "include/constants.inc"

.section __TEXT,__text,regular,pure_instructions
.p2align 4

// ──────────────────────────────────────────────────────────────────
// _agent_run: run agent with given arguments
//   x0 = argc (number of sub-arguments after "agent")
//   x1 = argv pointer (array of char* sub-arguments)
//   Returns: x0 = 0 on success
// ──────────────────────────────────────────────────────────────────
.global _agent_run
_agent_run:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // argc
    mov     x20, x1                     // argv

    // If no args, show usage for agent
    cbz     x19, .Lagent_usage

    // Check first arg
    ldr     x0, [x20]                   // argv[0]

    // Check for "-m" flag
    adrp    x1, _str_flag_m@PAGE
    add     x1, x1, _str_flag_m@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Lagent_message_mode

    // Unknown flag
    b       .Lagent_usage

.Lagent_message_mode:
    // Need at least 2 args: -m "message"
    cmp     x19, #2
    b.lt    .Lagent_no_message

    // Load config
    bl      _config_load
    cbnz    x0, .Lagent_config_error

    // Get the message (argv[1])
    ldr     x0, [x20, #8]              // argv[1]

    // Send to provider
    bl      _provider_chat
    cbz     x0, .Lagent_provider_error

    // Print response
    // x0 = content, x1 = length
    bl      _puts

    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lagent_usage:
    adrp    x0, _str_agent_usage@PAGE
    add     x0, x0, _str_agent_usage@PAGEOFF
    bl      _puts
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lagent_no_message:
    adrp    x0, _str_no_message@PAGE
    add     x0, x0, _str_no_message@PAGEOFF
    bl      _print_stderr
    mov     x0, #1
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lagent_config_error:
    adrp    x0, _str_config_err@PAGE
    add     x0, x0, _str_config_err@PAGEOFF
    bl      _print_stderr
    mov     x0, #1
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lagent_provider_error:
    // Error already printed by provider
    mov     x0, #1
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ──────────────────────────────────────────────────────────────────
// _status_run: show system status
//   Returns: x0 = 0
// ──────────────────────────────────────────────────────────────────
.global _status_run
_status_run:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Try to load config
    bl      _config_load
    // Print status regardless
    bl      _config_print_status

    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

// ── Data ──
.section __DATA,__const
.p2align 3

_str_flag_m:
    .asciz  "-m"
_str_agent_usage:
    .asciz  "usage: assemblyclaw agent -m \"message\"\n       assemblyclaw agent          (interactive mode — coming soon)"
_str_no_message:
    .asciz  "error: -m flag requires a message argument"
_str_config_err:
    .asciz  "error: could not load config. create ~/.assemblyclaw/config.json"
