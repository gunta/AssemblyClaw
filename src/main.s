// main.s — AssemblyClaw entry point
// ARM64 macOS — M4/M5 Pro/Max optimized
//
// The world's smallest AI agent infrastructure.
// Pure ARM64 assembly. < 32 KB binary.
//
// CLI dispatch:
//   assemblyclaw --help / -h / help    → print usage
//   assemblyclaw --version             → print version
//   assemblyclaw status                → show config status
//   assemblyclaw agent -m "..."        → single message
//   assemblyclaw agent                 → interactive mode

.include "include/constants.inc"

.section __TEXT,__text,regular,pure_instructions
.p2align 4

// ──────────────────────────────────────────────────────────────────
// _main: program entry point
//   x0 = argc
//   x1 = argv (char**)
// ──────────────────────────────────────────────────────────────────
.global _main
_main:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // argc
    mov     x20, x1                     // argv

    // Initialize arena allocator (64KB)
    mov     x0, #ARENA_PAGE_SIZE
    bl      _arena_init
    cbnz    x0, .Lmain_arena_fail

    // If argc < 2, print usage
    cmp     x19, #2
    b.lt    .Lmain_help

    // Get argv[1] — the command
    ldr     x21, [x20, #8]             // argv[1]

    // ── Match commands ──
    // --help
    mov     x0, x21
    adrp    x1, _str_cmd_help@PAGE
    add     x1, x1, _str_cmd_help@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Lmain_help

    // -h
    mov     x0, x21
    adrp    x1, _str_cmd_h@PAGE
    add     x1, x1, _str_cmd_h@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Lmain_help

    // help
    mov     x0, x21
    adrp    x1, _str_cmd_help_word@PAGE
    add     x1, x1, _str_cmd_help_word@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Lmain_help

    // --version
    mov     x0, x21
    adrp    x1, _str_cmd_version@PAGE
    add     x1, x1, _str_cmd_version@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Lmain_version

    // status
    mov     x0, x21
    adrp    x1, _str_cmd_status@PAGE
    add     x1, x1, _str_cmd_status@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Lmain_status

    // agent
    mov     x0, x21
    adrp    x1, _str_cmd_agent@PAGE
    add     x1, x1, _str_cmd_agent@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Lmain_agent

    // Unknown command
    b       .Lmain_unknown

// ── Command handlers ──

.Lmain_help:
    adrp    x0, _str_usage@PAGE
    add     x0, x0, _str_usage@PAGEOFF
    bl      _puts
    mov     x0, #0
    b       .Lmain_exit

.Lmain_version:
    bl      _version_print
    mov     x0, #0
    b       .Lmain_exit

.Lmain_status:
    bl      _status_run
    b       .Lmain_exit

.Lmain_agent:
    // Pass remaining args to agent_run
    // argc = original argc - 2, argv = argv + 2
    sub     x0, x19, #2                // sub-argc
    add     x1, x20, #16              // sub-argv (skip program name + "agent")
    bl      _agent_run
    b       .Lmain_exit

.Lmain_unknown:
    // fprintf(stderr, "error: unknown command: %s\n", argv[1])
    adrp    x8, ___stderrp@GOTPAGE
    ldr     x8, [x8, ___stderrp@GOTPAGEOFF]
    ldr     x0, [x8]
    adrp    x1, _str_unknown_fmt@PAGE
    add     x1, x1, _str_unknown_fmt@PAGEOFF
    mov     x2, x21
    bl      _fprintf_va1
    mov     x0, #1
    b       .Lmain_exit

.Lmain_arena_fail:
    adrp    x0, _str_arena_fail@PAGE
    add     x0, x0, _str_arena_fail@PAGEOFF
    bl      _die
    // die never returns

.Lmain_exit:
    // Cleanup arena
    mov     x22, x0                     // save exit code
    bl      _arena_destroy
    mov     x0, x22                     // restore exit code

    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ── String Constants ──
.section __DATA,__const
.p2align 3

_str_cmd_help:
    .asciz  "--help"
_str_cmd_h:
    .asciz  "-h"
_str_cmd_help_word:
    .asciz  "help"
_str_cmd_version:
    .asciz  "--version"
_str_cmd_status:
    .asciz  "status"
_str_cmd_agent:
    .asciz  "agent"

_str_unknown_fmt:
    .asciz  "error: unknown command: %s\n"

_str_arena_fail:
    .asciz  "fatal: could not initialize memory arena"

_str_usage:
    .ascii  "assemblyclaw 0.1.0 — the world's smallest AI agent\n"
    .ascii  "\n"
    .ascii  "usage:\n"
    .ascii  "  assemblyclaw <command> [options]\n"
    .ascii  "\n"
    .ascii  "commands:\n"
    .ascii  "  agent -m \"msg\"   Send a message to the AI\n"
    .ascii  "  agent            Interactive chat mode\n"
    .ascii  "  status           Show configuration status\n"
    .ascii  "  help             Show this help message\n"
    .ascii  "\n"
    .ascii  "options:\n"
    .ascii  "  --help, -h       Show help\n"
    .ascii  "  --version        Show version\n"
    .ascii  "\n"
    .ascii  "config:\n"
    .ascii  "  ~/.assemblyclaw/config.json\n"
    .asciz  ""
