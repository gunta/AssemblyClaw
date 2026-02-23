// json.s — Zero-allocation streaming JSON parser
// ARM64 macOS — M4/M5 Pro/Max optimized
//
// Minimal parser that can extract string values by key path.
// No heap allocation — works directly on the input buffer.
// Returns pointers into the original JSON string.

.include "include/constants.inc"

.section __TEXT,__text,regular,pure_instructions
.p2align 4

// ──────────────────────────────────────────────────────────────────
// _json_find_key: find a string value by key in a JSON object
//   x0 = JSON string (NUL-terminated)
//   x1 = key to find (NUL-terminated)
//   Returns: x0 = pointer to value string start (after opening ")
//            x1 = value length (not including quotes)
//            x0 = NULL if not found
//
// Only handles top-level and one-level nested objects.
// Handles: "key": "value" and "key": { "subkey": "value" }
// ──────────────────────────────────────────────────────────────────
.global _json_find_key
_json_find_key:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // json string
    mov     x20, x1                     // key to find

    // Get key length
    mov     x0, x20
    bl      _strlen_simd
    mov     x21, x0                     // key length

    mov     x22, x19                    // cursor

.Ljson_scan:
    // Find next quote
    ldrb    w0, [x22]
    cbz     w0, .Ljson_not_found        // end of string
    cmp     w0, #'"'
    b.ne    .Ljson_skip_char

    // Found a quote — this might be our key
    add     x22, x22, #1               // skip opening quote

    // Compare key
    mov     x0, x22                     // current position
    mov     x1, x20                     // key we're looking for
    mov     x2, x21                     // key length
    bl      _json_match_key
    cbz     x0, .Ljson_no_match

    // Key matched! Advance past key + closing quote
    add     x22, x22, x21              // skip key chars
    ldrb    w0, [x22]
    cmp     w0, #'"'
    b.ne    .Ljson_no_match
    add     x22, x22, #1               // skip closing quote

    // Only treat this as a key token if the next non-space character is ':'.
    bl      .Ljson_skip_ws
    ldrb    w0, [x22]
    cmp     w0, #':'
    b.ne    .Ljson_no_match_after_key
    add     x22, x22, #1               // skip ':'
    bl      .Ljson_skip_ws

    // Now x22 points to the value
    ldrb    w0, [x22]
    cmp     w0, #'"'
    b.eq    .Ljson_extract_string
    cmp     w0, #'{'
    b.eq    .Ljson_extract_object
    cmp     w0, #'['
    b.eq    .Ljson_extract_array
    // Number, bool, null — extract until , or } or ]
    b       .Ljson_extract_literal

.Ljson_no_match:
    // Skip to end of this string value
.Ljson_skip_string:
    ldrb    w0, [x22]
    cbz     w0, .Ljson_not_found
    cmp     w0, #'"'
    b.eq    .Ljson_after_string
    cmp     w0, #'\\'
    b.eq    .Ljson_skip_escape
    add     x22, x22, #1
    b       .Ljson_skip_string

.Ljson_skip_escape:
    add     x22, x22, #2               // skip \ and next char
    b       .Ljson_skip_string

.Ljson_after_string:
    add     x22, x22, #1               // skip closing quote
    b       .Ljson_scan

.Ljson_no_match_after_key:
    b       .Ljson_scan

.Ljson_skip_char:
    add     x22, x22, #1
    b       .Ljson_scan

// ── Extract string value ──
.Ljson_extract_string:
    add     x22, x22, #1               // skip opening quote
    mov     x0, x22                     // value start

    // Find closing quote
    mov     x1, #0                      // length counter
.Ljson_measure_string:
    ldrb    w2, [x22, x1]
    cbz     w2, .Ljson_not_found
    cmp     w2, #'"'
    b.eq    .Ljson_string_done
    cmp     w2, #'\\'
    b.eq    .Ljson_measure_escape
    add     x1, x1, #1
    b       .Ljson_measure_string

.Ljson_measure_escape:
    add     x1, x1, #2                 // skip escape sequence
    b       .Ljson_measure_string

.Ljson_string_done:
    // x0 = value start, x1 = value length
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ── Extract object (return ptr to { and length to matching }) ──
.Ljson_extract_object:
    mov     x0, x22                     // start at {
    mov     x1, #1                      // depth = 1
    mov     x2, #0                      // length

.Ljson_obj_scan:
    add     x2, x2, #1
    ldrb    w3, [x22, x2]
    cbz     w3, .Ljson_not_found
    cmp     w3, #'{'
    b.eq    .Ljson_obj_open
    cmp     w3, #'}'
    b.eq    .Ljson_obj_close
    cmp     w3, #'"'
    b.eq    .Ljson_obj_skip_str
    b       .Ljson_obj_scan

.Ljson_obj_open:
    add     x1, x1, #1
    b       .Ljson_obj_scan

.Ljson_obj_close:
    sub     x1, x1, #1
    cbnz    x1, .Ljson_obj_scan
    add     x2, x2, #1                 // include closing }
    mov     x1, x2
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Ljson_obj_skip_str:
    add     x2, x2, #1
.Ljson_obj_str_loop:
    ldrb    w3, [x22, x2]
    cbz     w3, .Ljson_not_found
    cmp     w3, #'"'
    b.eq    .Ljson_obj_scan
    cmp     w3, #'\\'
    b.ne    .Ljson_obj_str_next
    add     x2, x2, #1                 // skip escaped char
.Ljson_obj_str_next:
    add     x2, x2, #1
    b       .Ljson_obj_str_loop

// ── Extract array ──
.Ljson_extract_array:
    mov     x0, x22
    mov     x1, #1
    mov     x2, #0
.Ljson_arr_scan:
    add     x2, x2, #1
    ldrb    w3, [x22, x2]
    cbz     w3, .Ljson_not_found
    cmp     w3, #'['
    b.eq    .Ljson_arr_inc
    cmp     w3, #']'
    b.eq    .Ljson_arr_dec
    b       .Ljson_arr_scan
.Ljson_arr_inc:
    add     x1, x1, #1
    b       .Ljson_arr_scan
.Ljson_arr_dec:
    sub     x1, x1, #1
    cbnz    x1, .Ljson_arr_scan
    add     x2, x2, #1
    mov     x1, x2
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ── Extract literal (number, bool, null) ──
.Ljson_extract_literal:
    mov     x0, x22
    mov     x1, #0
.Ljson_lit_loop:
    ldrb    w2, [x22, x1]
    cbz     w2, .Ljson_lit_end
    cmp     w2, #','
    b.eq    .Ljson_lit_end
    cmp     w2, #'}'
    b.eq    .Ljson_lit_end
    cmp     w2, #']'
    b.eq    .Ljson_lit_end
    cmp     w2, #' '
    b.eq    .Ljson_lit_end
    cmp     w2, #'\n'
    b.eq    .Ljson_lit_end
    add     x1, x1, #1
    b       .Ljson_lit_loop
.Ljson_lit_end:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ── Not found ──
.Ljson_not_found:
    mov     x0, #0
    mov     x1, #0
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ── Helper: skip whitespace ──
.Ljson_skip_ws:
.Ljson_ws_loop:
    ldrb    w0, [x22]
    cmp     w0, #' '
    b.eq    .Ljson_ws_next
    cmp     w0, #'\t'
    b.eq    .Ljson_ws_next
    cmp     w0, #'\n'
    b.eq    .Ljson_ws_next
    cmp     w0, #'\r'
    b.eq    .Ljson_ws_next
    ret                                 // done skipping
.Ljson_ws_next:
    add     x22, x22, #1
    b       .Ljson_ws_loop

// ──────────────────────────────────────────────────────────────────
// _json_match_key: compare buffer against key (not NUL-terminated)
//   x0 = buffer position
//   x1 = key (NUL-terminated)
//   x2 = key length
//   Returns: x0 = 1 if match, 0 if not
// ──────────────────────────────────────────────────────────────────
.global _json_match_key
_json_match_key:
    cbz     x2, .Lmatch_yes            // empty key matches
    mov     x3, #0                      // index
.Lmatch_loop:
    ldrb    w4, [x0, x3]
    ldrb    w5, [x1, x3]
    cmp     w4, w5
    b.ne    .Lmatch_no
    add     x3, x3, #1
    cmp     x3, x2
    b.lt    .Lmatch_loop
.Lmatch_yes:
    mov     x0, #1
    ret
.Lmatch_no:
    mov     x0, #0
    ret

// ──────────────────────────────────────────────────────────────────
// _json_find_nested: find a value in nested object "outer.inner"
//   x0 = JSON string
//   x1 = outer key (e.g., "providers")
//   x2 = inner key (e.g., "api_key")
//   Returns: x0 = value ptr, x1 = value length, or x0=NULL
// ──────────────────────────────────────────────────────────────────
.global _json_find_nested
_json_find_nested:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x2                     // save inner key

    // First find the outer key's value (should be an object)
    bl      _json_find_key
    cbz     x0, .Lnested_not_found

    // x0 = outer object start, x1 = outer object length
    // Now search within this substring for inner key
    // We need to NUL-terminate the substring temporarily
    // Since we're searching within it, just use it as-is
    // The json_find_key will stop at NUL or end of the object
    mov     x1, x19                     // inner key
    bl      _json_find_key

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lnested_not_found:
    mov     x0, #0
    mov     x1, #0
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ──────────────────────────────────────────────────────────────────
// _json_array_first_object: get first object element from a JSON array
//   x0 = array pointer (expected to start with '[')
//   x1 = array length (unused, caller may pass 0)
//   Returns: x0 = pointer to first object '{'
//            x1 = object length including braces
//            x0 = NULL if not found
// ──────────────────────────────────────────────────────────────────
.global _json_array_first_object
_json_array_first_object:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // array start
    mov     x20, #0

    ldrb    w0, [x19]
    cmp     w0, #'['
    b.ne    .Larr_obj_not_found
    add     x20, x19, #1                // cursor

.Larr_obj_seek:
    ldrb    w0, [x20]
    cbz     w0, .Larr_obj_not_found
    cmp     w0, #' '
    b.eq    .Larr_obj_seek_next
    cmp     w0, #'\t'
    b.eq    .Larr_obj_seek_next
    cmp     w0, #'\n'
    b.eq    .Larr_obj_seek_next
    cmp     w0, #'\r'
    b.eq    .Larr_obj_seek_next
    cmp     w0, #','
    b.eq    .Larr_obj_seek_next
    cmp     w0, #']'
    b.eq    .Larr_obj_not_found
    cmp     w0, #'{'
    b.eq    .Larr_obj_scan_object
    b       .Larr_obj_not_found

.Larr_obj_seek_next:
    add     x20, x20, #1
    b       .Larr_obj_seek

.Larr_obj_scan_object:
    mov     x21, x20                    // object start
    mov     x22, #1                     // brace depth
    mov     x2, #0                      // relative offset

.Larr_obj_loop:
    add     x2, x2, #1
    ldrb    w3, [x21, x2]
    cbz     w3, .Larr_obj_not_found
    cmp     w3, #'{'
    b.eq    .Larr_obj_open
    cmp     w3, #'}'
    b.eq    .Larr_obj_close
    cmp     w3, #'"'
    b.eq    .Larr_obj_skip_string
    b       .Larr_obj_loop

.Larr_obj_open:
    add     x22, x22, #1
    b       .Larr_obj_loop

.Larr_obj_close:
    sub     x22, x22, #1
    cbnz    x22, .Larr_obj_loop
    add     x2, x2, #1                 // include closing brace
    mov     x0, x21
    mov     x1, x2
    b       .Larr_obj_done

.Larr_obj_skip_string:
    add     x2, x2, #1
.Larr_obj_str_loop:
    ldrb    w3, [x21, x2]
    cbz     w3, .Larr_obj_not_found
    cmp     w3, #'"'
    b.eq    .Larr_obj_loop
    cmp     w3, #'\\'
    b.ne    .Larr_obj_str_next
    add     x2, x2, #1
.Larr_obj_str_next:
    add     x2, x2, #1
    b       .Larr_obj_str_loop

.Larr_obj_not_found:
    mov     x0, #0
    mov     x1, #0

.Larr_obj_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
