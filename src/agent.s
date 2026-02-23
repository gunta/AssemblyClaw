// agent.s — Agent loop
// ARM64 macOS — Apple Silicon optimized
//
// Handles:
//   - Single message mode: agent -m "hello"
//   - Interactive mode: agent
//   - Status display: status
//   - Basic conversation history capture in arena memory

.include "include/constants.inc"

.section __TEXT,__text,regular,pure_instructions
.p2align 4

// Conversation history entry layout.
.set HIST_ROLE,  0
.set HIST_PTR,   8
.set HIST_LEN,   16
.set HIST_SIZE,  24
.set HIST_MAX,   64
.set TOOL_MAX_ITERS, 8

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

    // No args => interactive mode.
    cbz     x19, .Lagent_interactive_mode

    // Check first arg.
    ldr     x0, [x20]                   // argv[0]

    // Check for "-m" flag.
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

    // Get message (argv[1]) and store in history.
    ldr     x0, [x20, #8]               // argv[1]
    mov     x19, x0
    mov     x0, #ROLE_USER
    mov     x1, x19
    bl      _agent_history_append

    // Send to provider.
    mov     x0, x19
    bl      _agent_process_with_tools
    cbz     x0, .Lagent_provider_error

    mov     x19, x0
    mov     x0, x19
    bl      _puts

    mov     x0, #0
    b       .Lagent_done

.Lagent_interactive_mode:
    bl      _agent_run_interactive
    b       .Lagent_done

.Lagent_usage:
    adrp    x0, _str_agent_usage@PAGE
    add     x0, x0, _str_agent_usage@PAGEOFF
    bl      _puts
    mov     x0, #0
    b       .Lagent_done

.Lagent_no_message:
    adrp    x0, _str_no_message@PAGE
    add     x0, x0, _str_no_message@PAGEOFF
    bl      _print_stderr
    mov     x0, #1
    b       .Lagent_done

.Lagent_config_error:
    adrp    x0, _str_config_err@PAGE
    add     x0, x0, _str_config_err@PAGEOFF
    bl      _print_stderr
    mov     x0, #1
    b       .Lagent_done

.Lagent_provider_error:
    // Error already printed by provider
    mov     x0, #1

.Lagent_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ──────────────────────────────────────────────────────────────────
// _agent_run_interactive: interactive chat loop
//   Returns: x0 = 0 on success, 1 on config failure
// ──────────────────────────────────────────────────────────────────
_agent_run_interactive:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    sub     sp, sp, #BUF_MEDIUM         // input buffer

    // Load config once.
    bl      _config_load
    cbnz    x0, .Linteractive_cfg_error

    // Install basic signal handlers for graceful interactive shutdown.
    adrp    x8, _g_agent_signal_exit@PAGE
    add     x8, x8, _g_agent_signal_exit@PAGEOFF
    str     xzr, [x8]
    mov     x0, #2                      // SIGINT
    adrp    x1, _agent_signal_handler@PAGE
    add     x1, x1, _agent_signal_handler@PAGEOFF
    bl      _signal
    mov     x0, #15                     // SIGTERM
    adrp    x1, _agent_signal_handler@PAGE
    add     x1, x1, _agent_signal_handler@PAGEOFF
    bl      _signal

    adrp    x19, _str_interactive_banner@PAGE
    add     x19, x19, _str_interactive_banner@PAGEOFF
    mov     x0, x19
    bl      _strlen_simd
    mov     x1, x0
    mov     x0, x19
    mov     x2, #STDOUT
    bl      _write_fd

.Linteractive_loop:
    adrp    x8, _g_agent_signal_exit@PAGE
    add     x8, x8, _g_agent_signal_exit@PAGEOFF
    ldr     x9, [x8]
    cbnz    x9, .Linteractive_done

    // Print prompt without newline: "> "
    adrp    x0, _str_prompt@PAGE
    add     x0, x0, _str_prompt@PAGEOFF
    mov     x1, #2
    mov     x2, #STDOUT
    bl      _write_fd

    // fgets(buf, BUF_MEDIUM, stdin)
    mov     x0, sp
    mov     x1, #BUF_MEDIUM
    adrp    x8, ___stdinp@GOTPAGE
    ldr     x8, [x8, ___stdinp@GOTPAGEOFF]
    ldr     x2, [x8]
    bl      _fgets
    cbz     x0, .Linteractive_done      // EOF / stdin closed

    // Trim trailing newline and optional trailing '\r'.
    mov     x0, sp
    bl      _strlen_simd
    mov     x19, x0
    cbz     x19, .Linteractive_loop

    sub     x20, x19, #1
    ldrb    w21, [sp, x20]
    cmp     w21, #'\n'
    b.ne    .Linteractive_trim_cr
    strb    wzr, [sp, x20]
    mov     x19, x20
    cbz     x19, .Linteractive_loop

.Linteractive_trim_cr:
    sub     x20, x19, #1
    ldrb    w21, [sp, x20]
    cmp     w21, #'\r'
    b.ne    .Linteractive_dispatch
    strb    wzr, [sp, x20]
    mov     x19, x20
    cbz     x19, .Linteractive_loop

.Linteractive_dispatch:
    // exit / quit commands.
    mov     x0, sp
    adrp    x1, _str_cmd_exit@PAGE
    add     x1, x1, _str_cmd_exit@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Linteractive_done

    mov     x0, sp
    adrp    x1, _str_cmd_quit@PAGE
    add     x1, x1, _str_cmd_quit@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Linteractive_done

    // Inline status command for quick checks.
    mov     x0, sp
    adrp    x1, _str_cmd_status@PAGE
    add     x1, x1, _str_cmd_status@PAGEOFF
    bl      _str_equal
    cbz     x0, .Linteractive_send
    bl      _config_print_status
    b       .Linteractive_loop

.Linteractive_send:
    mov     x0, #ROLE_USER
    mov     x1, sp
    bl      _agent_history_append

    mov     x0, sp
    bl      _agent_process_with_tools
    cbz     x0, .Linteractive_loop      // provider prints error

    mov     x0, x0
    bl      _puts
    b       .Linteractive_loop

.Linteractive_cfg_error:
    adrp    x0, _str_config_err@PAGE
    add     x0, x0, _str_config_err@PAGEOFF
    bl      _print_stderr
    mov     x0, #1
    b       .Linteractive_return

.Linteractive_done:
    mov     x0, #0

.Linteractive_return:
    add     sp, sp, #BUF_MEDIUM
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ──────────────────────────────────────────────────────────────────
// _agent_signal_handler: set exit flag for interactive loop
//   x0 = signal number (unused)
// ──────────────────────────────────────────────────────────────────
_agent_signal_handler:
    adrp    x8, _g_agent_signal_exit@PAGE
    add     x8, x8, _g_agent_signal_exit@PAGEOFF
    mov     x9, #1
    str     x9, [x8]
    mov     x0, #0
    bl      _exit
    ret

// ──────────────────────────────────────────────────────────────────
// _agent_history_count: return number of history entries
//   Returns: x0 = count
// ──────────────────────────────────────────────────────────────────
.global _agent_history_count
_agent_history_count:
    adrp    x0, _g_hist_count@PAGE
    add     x0, x0, _g_hist_count@PAGEOFF
    ldr     x0, [x0]
    ret

// ──────────────────────────────────────────────────────────────────
// _agent_history_get: get history entry by index
//   x0 = index
//   Returns: x0 = role, x1 = message ptr, x2 = message len
//            (all zero on invalid index)
// ──────────────────────────────────────────────────────────────────
.global _agent_history_get
_agent_history_get:
    adrp    x3, _g_hist_count@PAGE
    add     x3, x3, _g_hist_count@PAGEOFF
    ldr     x4, [x3]
    cmp     x0, x4
    b.hs    .Lhist_get_invalid

    adrp    x5, _g_hist_entries@PAGE
    add     x5, x5, _g_hist_entries@PAGEOFF
    mov     x6, #HIST_SIZE
    mul     x7, x0, x6
    add     x5, x5, x7

    ldr     x0, [x5, #HIST_ROLE]
    ldr     x1, [x5, #HIST_PTR]
    ldr     x2, [x5, #HIST_LEN]
    ret

.Lhist_get_invalid:
    mov     x0, #0
    mov     x1, #0
    mov     x2, #0
    ret

// ──────────────────────────────────────────────────────────────────
// _agent_process_with_tools
//   x0 = latest user message pointer
//   Returns: x0 = final assistant content pointer, or NULL on error
// ──────────────────────────────────────────────────────────────────
_agent_process_with_tools:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // latest user msg
    mov     x20, #0                     // tool iteration count

.Lagent_tool_loop:
    mov     x0, x19
    bl      _provider_chat
    cbz     x0, .Lagent_tool_fail
    mov     x21, x0                     // provider response

    bl      _provider_tool_peek
    cbz     x0, .Lagent_tool_final      // no pending tool call

    mov     x22, x1                     // tool name ptr
    mov     x23, x3                     // tool args ptr
    mov     x24, x4                     // tool args len

    // Keep assistant tool-call marker in history for context continuity.
    mov     x0, #ROLE_ASSISTANT
    mov     x1, x21
    bl      _agent_history_append

    // Execute tool.
    mov     x0, x22
    mov     x1, x23
    mov     x2, x24
    bl      _agent_execute_tool
    cbz     x0, .Lagent_tool_exec_fail

    // Append tool result to history as ROLE_TOOL.
    mov     x23, x0
    mov     x0, #ROLE_TOOL
    mov     x1, x23
    bl      _agent_history_append

    add     x20, x20, #1
    cmp     x20, #TOOL_MAX_ITERS
    b.lt    .Lagent_tool_loop

    adrp    x0, _str_tool_iter_limit@PAGE
    add     x0, x0, _str_tool_iter_limit@PAGEOFF
    b       .Lagent_tool_fail

.Lagent_tool_exec_fail:
    adrp    x23, _str_tool_exec_fail@PAGE
    add     x23, x23, _str_tool_exec_fail@PAGEOFF
    mov     x0, #ROLE_TOOL
    mov     x1, x23
    bl      _agent_history_append
    add     x20, x20, #1
    cmp     x20, #TOOL_MAX_ITERS
    b.lt    .Lagent_tool_loop
    adrp    x0, _str_tool_iter_limit@PAGE
    add     x0, x0, _str_tool_iter_limit@PAGEOFF
    b       .Lagent_tool_fail

.Lagent_tool_final:
    // Final assistant content.
    mov     x0, #ROLE_ASSISTANT
    mov     x1, x21
    bl      _agent_history_append
    mov     x0, x21
    b       .Lagent_tool_ret

.Lagent_tool_fail:
    cbz     x0, .Lagent_tool_fail_default
    // x0 already has error string
    bl      _print_stderr
    mov     x0, #0
    b       .Lagent_tool_ret

.Lagent_tool_fail_default:
    adrp    x0, _str_tool_exec_fail@PAGE
    add     x0, x0, _str_tool_exec_fail@PAGEOFF
    bl      _print_stderr
    mov     x0, #0

.Lagent_tool_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// ──────────────────────────────────────────────────────────────────
// _agent_execute_tool
//   x0 = tool name ptr (NUL-terminated)
//   x1 = tool args JSON ptr (NUL-terminated; may be empty)
//   x2 = tool args len (unused)
//   Returns: x0 = result string pointer (NUL-terminated), or NULL on error
// ──────────────────────────────────────────────────────────────────
_agent_execute_tool:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    str     x25, [sp, #64]

    mov     x19, x0                     // tool name
    mov     x20, x1                     // args json

    mov     x0, x19
    adrp    x1, _str_tool_status@PAGE
    add     x1, x1, _str_tool_status@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Ltool_status

    mov     x0, x19
    adrp    x1, _str_tool_shell@PAGE
    add     x1, x1, _str_tool_shell@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Ltool_shell

    mov     x0, x19
    adrp    x1, _str_tool_file_read@PAGE
    add     x1, x1, _str_tool_file_read@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Ltool_file_read

    mov     x0, x19
    adrp    x1, _str_tool_file_write@PAGE
    add     x1, x1, _str_tool_file_write@PAGEOFF
    bl      _str_equal
    cbnz    x0, .Ltool_file_write

    adrp    x0, _str_tool_unknown@PAGE
    add     x0, x0, _str_tool_unknown@PAGEOFF
    b       .Ltool_ret

.Ltool_status:
    bl      _config_get
    mov     x21, x0
    mov     x0, #BUF_SMALL
    bl      _arena_alloc
    cbz     x0, .Ltool_fail
    mov     x22, x0
    mov     x0, x22
    mov     x1, #BUF_SMALL
    adrp    x2, _str_tool_status_fmt@PAGE
    add     x2, x2, _str_tool_status_fmt@PAGEOFF
    ldr     x3, [x21, #8]               // provider len
    ldr     x4, [x21, #0]               // provider ptr
    ldr     x5, [x21, #40]              // model len
    ldr     x6, [x21, #32]              // model ptr
    bl      _snprintf_va4
    mov     x0, x22
    b       .Ltool_ret

.Ltool_shell:
    mov     x0, x20
    adrp    x1, _str_key_command@PAGE
    add     x1, x1, _str_key_command@PAGEOFF
    bl      .Lagent_find_key_with_decode
    cbz     x0, .Ltool_fail
    bl      .Lagent_copy_slice
    cbz     x0, .Ltool_fail
    mov     x21, x0                     // command string

    // Silence command stdout/stderr; report exit code via tool result only.
    mov     x0, x21
    bl      _strlen_simd
    mov     x22, x0
    adrp    x0, _str_shell_silence_suffix@PAGE
    add     x0, x0, _str_shell_silence_suffix@PAGEOFF
    bl      _strlen_simd
    mov     x23, x0
    add     x0, x22, x23
    add     x0, x0, #1
    bl      _arena_alloc
    cbz     x0, .Ltool_fail
    mov     x24, x0
    mov     x0, x24
    mov     x1, x21
    mov     x2, x22
    bl      _memcpy_simd
    add     x0, x24, x22
    adrp    x1, _str_shell_silence_suffix@PAGE
    add     x1, x1, _str_shell_silence_suffix@PAGEOFF
    mov     x2, x23
    bl      _memcpy_simd
    add     x8, x24, x22
    add     x8, x8, x23
    strb    wzr, [x8]

    mov     x0, x24
    bl      _system
    mov     x21, x0                     // exit code

    mov     x0, #BUF_SMALL
    bl      _arena_alloc
    cbz     x0, .Ltool_fail
    mov     x22, x0
    mov     x0, x22
    mov     x1, #BUF_SMALL
    adrp    x2, _str_shell_result_fmt@PAGE
    add     x2, x2, _str_shell_result_fmt@PAGEOFF
    mov     x3, x21
    bl      _snprintf_va1
    mov     x0, x22
    b       .Ltool_ret

.Ltool_file_read:
    mov     x0, x20
    adrp    x1, _str_key_path@PAGE
    add     x1, x1, _str_key_path@PAGEOFF
    bl      .Lagent_find_key_with_decode
    cbz     x0, .Ltool_fail
    bl      .Lagent_copy_slice
    cbz     x0, .Ltool_fail
    mov     x21, x0                     // path string
    mov     x0, x21
    bl      _read_file
    cbz     x0, .Ltool_fail
    b       .Ltool_ret

.Ltool_file_write:
    // path
    mov     x0, x20
    adrp    x1, _str_key_path@PAGE
    add     x1, x1, _str_key_path@PAGEOFF
    bl      .Lagent_find_key_with_decode
    cbz     x0, .Ltool_fail
    bl      .Lagent_copy_slice
    cbz     x0, .Ltool_fail
    mov     x21, x0                     // path

    // content
    mov     x0, x20
    adrp    x1, _str_key_content@PAGE
    add     x1, x1, _str_key_content@PAGEOFF
    bl      .Lagent_find_key_with_decode
    cbz     x0, .Ltool_fail
    mov     x22, x0                     // content ptr
    mov     x23, x1                     // content len

    mov     x0, x21
    adrp    x1, _str_file_mode_w@PAGE
    add     x1, x1, _str_file_mode_w@PAGEOFF
    bl      _fopen
    cbz     x0, .Ltool_fail
    mov     x24, x0                     // FILE*

    mov     x0, x22                     // ptr
    mov     x1, #1                      // size
    mov     x2, x23                     // nmemb
    mov     x3, x24                     // stream
    bl      _fwrite

    mov     x0, x24
    bl      _fclose

    adrp    x0, _str_file_write_ok@PAGE
    add     x0, x0, _str_file_write_ok@PAGEOFF
    b       .Ltool_ret

.Ltool_fail:
    mov     x0, #0

.Ltool_ret:
    ldr     x25, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

// x0=ptr, x1=len => x0=arena NUL copy or NULL
.Lagent_copy_slice:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    mov     x19, x0
    mov     x20, x1
    add     x0, x20, #1
    bl      _arena_alloc
    cbz     x0, .Lagent_copy_fail
    mov     x8, x0
    mov     x0, x8
    mov     x1, x19
    mov     x2, x20
    bl      _memcpy_simd
    strb    wzr, [x8, x20]
    mov     x0, x8
    b       .Lagent_copy_ret

.Lagent_copy_fail:
    mov     x0, #0

.Lagent_copy_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// x0=args json ptr, x1=key cstr => x0=value ptr, x1=value len (or 0,0)
.Lagent_find_key_with_decode:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0                     // args ptr
    mov     x20, x1                     // key ptr

    mov     x0, x19
    mov     x1, x20
    bl      _json_find_key
    cbnz    x0, .Lagent_find_key_done

    // Fallback: decode escaped JSON string once, then retry.
    mov     x0, x19
    bl      _strlen_simd
    mov     x1, x0
    mov     x0, x19
    bl      .Lagent_decode_json_string
    cbz     x0, .Lagent_find_key_done
    mov     x21, x0
    mov     x0, x21
    mov     x1, x20
    bl      _json_find_key

.Lagent_find_key_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// x0=src ptr, x1=src len => x0=decoded ptr, x1=decoded len (or 0,0)
.Lagent_decode_json_string:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0                     // src
    mov     x20, x1                     // len

    add     x0, x20, #1
    bl      _arena_alloc
    cbz     x0, .Lagent_decode_fail
    mov     x21, x0                     // dst
    mov     x22, #0                     // src idx
    mov     x8, #0                      // dst idx

.Lagent_decode_loop:
    cmp     x22, x20
    b.ge    .Lagent_decode_done
    ldrb    w9, [x19, x22]
    cmp     w9, #'\\'
    b.ne    .Lagent_decode_emit

    add     x22, x22, #1
    cmp     x22, x20
    b.ge    .Lagent_decode_done
    ldrb    w9, [x19, x22]
    cmp     w9, #'"'
    b.eq    .Lagent_decode_emit
    cmp     w9, #'\\'
    b.eq    .Lagent_decode_emit
    cmp     w9, #'/'
    b.eq    .Lagent_decode_emit
    cmp     w9, #'n'
    b.ne    .Lagent_decode_not_n
    mov     w9, #'\n'
    b       .Lagent_decode_emit
.Lagent_decode_not_n:
    cmp     w9, #'r'
    b.ne    .Lagent_decode_not_r
    mov     w9, #'\r'
    b       .Lagent_decode_emit
.Lagent_decode_not_r:
    cmp     w9, #'t'
    b.ne    .Lagent_decode_not_t
    mov     w9, #'\t'
    b       .Lagent_decode_emit
.Lagent_decode_not_t:
    cmp     w9, #'u'
    b.ne    .Lagent_decode_emit
    add     x22, x22, #4
    mov     w9, #'?'

.Lagent_decode_emit:
    strb    w9, [x21, x8]
    add     x8, x8, #1
    add     x22, x22, #1
    b       .Lagent_decode_loop

.Lagent_decode_done:
    strb    wzr, [x21, x8]
    mov     x0, x21
    mov     x1, x8
    b       .Lagent_decode_ret

.Lagent_decode_fail:
    mov     x0, #0
    mov     x1, #0

.Lagent_decode_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ──────────────────────────────────────────────────────────────────
// _agent_history_append: append message text to in-memory history
//   x0 = role (ROLE_USER / ROLE_ASSISTANT / ...)
//   x1 = message pointer (NUL-terminated)
// ──────────────────────────────────────────────────────────────────
_agent_history_append:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // role
    mov     x20, x1                     // source message
    cbz     x20, .Lhist_done

    // len = strlen(message)
    mov     x0, x20
    bl      _strlen_simd
    mov     x21, x0

    // Duplicate into arena: len + 1
    add     x0, x21, #1
    bl      _arena_alloc
    cbz     x0, .Lhist_done
    mov     x22, x0                     // copied message

    mov     x0, x22
    mov     x1, x20
    mov     x2, x21
    bl      _memcpy_simd
    strb    wzr, [x22, x21]

    // Persist history to file-backed memory backend.
    mov     x0, x19
    mov     x1, x22
    mov     x2, x21
    bl      .Lhist_persist_file

    adrp    x8, _g_hist_count@PAGE
    add     x8, x8, _g_hist_count@PAGEOFF
    ldr     x9, [x8]
    cmp     x9, #HIST_MAX
    b.ge    .Lhist_done

    adrp    x10, _g_hist_entries@PAGE
    add     x10, x10, _g_hist_entries@PAGEOFF
    mov     x11, #HIST_SIZE
    mul     x12, x9, x11
    add     x10, x10, x12

    str     x19, [x10, #HIST_ROLE]
    str     x22, [x10, #HIST_PTR]
    str     x21, [x10, #HIST_LEN]

    add     x9, x9, #1
    str     x9, [x8]

.Lhist_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// x0=role, x1=msg ptr, x2=msg len
.Lhist_persist_file:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    mov     x19, x0                     // role
    mov     x20, x1                     // msg ptr
    mov     x21, x2                     // msg len
    cbz     x20, .Lhist_pf_done

    // Ensure ~/.assemblyclaw exists.
    adrp    x0, _str_memory_dir@PAGE
    add     x0, x0, _str_memory_dir@PAGEOFF
    bl      _path_expand_home
    cbz     x0, .Lhist_pf_done
    mov     x22, x0
    mov     x0, x22
    mov     x1, #493                    // 0755
    bl      _mkdir

    // Open memory log in append mode.
    adrp    x0, _str_memory_log_path@PAGE
    add     x0, x0, _str_memory_log_path@PAGEOFF
    bl      _path_expand_home
    cbz     x0, .Lhist_pf_done
    mov     x23, x0
    mov     x0, x23
    adrp    x1, _str_file_mode_a@PAGE
    add     x1, x1, _str_file_mode_a@PAGEOFF
    bl      _fopen
    cbz     x0, .Lhist_pf_done
    mov     x24, x0                     // FILE*

    // Role prefix.
    cmp     x19, #ROLE_ASSISTANT
    b.eq    .Lhist_pf_role_assistant
    cmp     x19, #ROLE_TOOL
    b.eq    .Lhist_pf_role_tool
    cmp     x19, #ROLE_SYSTEM
    b.eq    .Lhist_pf_role_system
    adrp    x25, _str_mem_role_user@PAGE
    add     x25, x25, _str_mem_role_user@PAGEOFF
    b       .Lhist_pf_role_set

.Lhist_pf_role_assistant:
    adrp    x25, _str_mem_role_assistant@PAGE
    add     x25, x25, _str_mem_role_assistant@PAGEOFF
    b       .Lhist_pf_role_set

.Lhist_pf_role_tool:
    adrp    x25, _str_mem_role_tool@PAGE
    add     x25, x25, _str_mem_role_tool@PAGEOFF
    b       .Lhist_pf_role_set

.Lhist_pf_role_system:
    adrp    x25, _str_mem_role_system@PAGE
    add     x25, x25, _str_mem_role_system@PAGEOFF

.Lhist_pf_role_set:
    mov     x0, x25
    bl      _strlen_simd
    mov     x26, x0

    // fwrite(role, 1, role_len, file)
    mov     x0, x25
    mov     x1, #1
    mov     x2, x26
    mov     x3, x24
    bl      _fwrite

    // fwrite("\t", 1, 1, file)
    adrp    x0, _str_tab@PAGE
    add     x0, x0, _str_tab@PAGEOFF
    mov     x1, #1
    mov     x2, #1
    mov     x3, x24
    bl      _fwrite

    // fwrite(message, 1, msg_len, file)
    mov     x0, x20
    mov     x1, #1
    mov     x2, x21
    mov     x3, x24
    bl      _fwrite

    // fwrite("\n", 1, 1, file)
    adrp    x0, _str_newline@PAGE
    add     x0, x0, _str_newline@PAGEOFF
    mov     x1, #1
    mov     x2, #1
    mov     x3, x24
    bl      _fwrite

    mov     x0, x24
    bl      _fclose

.Lhist_pf_done:
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
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

// ── BSS ──
.section __DATA,__bss
.p2align 4
_g_hist_count:
    .quad   0
_g_hist_entries:
    .space  1536                          // HIST_MAX * HIST_SIZE
_g_agent_signal_exit:
    .quad   0

// ── Data ──
.section __DATA,__const
.p2align 3

_str_flag_m:
    .asciz  "-m"
_str_agent_usage:
    .asciz  "usage: assemblyclaw agent -m \"message\"\n       assemblyclaw agent"
_str_no_message:
    .asciz  "error: -m flag requires a message argument"
_str_config_err:
    .asciz  "error: could not load config. create ~/.assemblyclaw/config.json"

_str_prompt:
    .asciz  "> "
_str_interactive_banner:
    .asciz  "assemblyclaw interactive mode (type 'exit' to quit)\n"
_str_cmd_exit:
    .asciz  "exit"
_str_cmd_quit:
    .asciz  "quit"
_str_cmd_status:
    .asciz  "status"

_str_tool_iter_limit:
    .asciz  "error: tool iteration limit reached"
_str_tool_exec_fail:
    .asciz  "error: tool execution failed"
_str_tool_unknown:
    .asciz  "tool error: unknown tool"

_str_tool_status:
    .asciz  "status"
_str_tool_shell:
    .asciz  "shell"
_str_tool_file_read:
    .asciz  "file_read"
_str_tool_file_write:
    .asciz  "file_write"

_str_key_command:
    .asciz  "command"
_str_key_path:
    .asciz  "path"
_str_key_content:
    .asciz  "content"

_str_tool_status_fmt:
    .asciz  "status: provider=%.*s model=%.*s"
_str_shell_result_fmt:
    .asciz  "shell exit %d"
_str_shell_silence_suffix:
    .asciz  " >/dev/null 2>&1"
_str_file_mode_w:
    .asciz  "w"
_str_file_mode_a:
    .asciz  "a"
_str_file_write_ok:
    .asciz  "ok"
_str_memory_dir:
    .asciz  "~/.assemblyclaw"
_str_memory_log_path:
    .asciz  "~/.assemblyclaw/memory.log"
_str_mem_role_system:
    .asciz  "system"
_str_mem_role_user:
    .asciz  "user"
_str_mem_role_assistant:
    .asciz  "assistant"
_str_mem_role_tool:
    .asciz  "tool"
_str_tab:
    .asciz  "\t"
_str_newline:
    .asciz  "\n"
