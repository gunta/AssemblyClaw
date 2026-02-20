// constants.inc — AssemblyClaw global constants
// ARM64 macOS

// ── Version ──
.set VERSION_MAJOR, 0
.set VERSION_MINOR, 1
.set VERSION_PATCH, 0

// ── Buffer Sizes ──
.set BUF_TINY,      64          // small temp buffers
.set BUF_SMALL,     256         // path buffers
.set BUF_MEDIUM,    4096        // config, JSON
.set BUF_LARGE,     8192        // HTTP responses
.set BUF_HUGE,      65536       // arena page size (64KB)

// ── Arena Allocator ──
.set ARENA_PAGE_SIZE, 65536     // 64KB pages via mmap
.set ARENA_ALIGN,     16        // minimum allocation alignment

// ── Error Codes ──
.set ERR_OK,               0
.set ERR_FAILED,           1
.set ERR_OUT_OF_MEMORY,    2
.set ERR_INVALID_ARG,      3
.set ERR_NOT_FOUND,        4
.set ERR_IO,               5
.set ERR_PARSE,            6
.set ERR_NETWORK,          7
.set ERR_PROVIDER,         8
.set ERR_CONFIG,           9
.set ERR_HTTP,             10

// ── JSON Token Types ──
.set JSON_NONE,      0
.set JSON_OBJECT,    1
.set JSON_ARRAY,     2
.set JSON_STRING,    3
.set JSON_NUMBER,    4
.set JSON_TRUE,      5
.set JSON_FALSE,     6
.set JSON_NULL,      7
.set JSON_KEY,       8

// ── Chat Roles ──
.set ROLE_SYSTEM,    0
.set ROLE_USER,      1
.set ROLE_ASSISTANT, 2
.set ROLE_TOOL,      3

// ── HTTP ──
.set HTTP_TIMEOUT_SECS, 30

// ── libcurl constants ──
.set CURLOPT_URL,            10002
.set CURLOPT_WRITEFUNCTION,  20011
.set CURLOPT_WRITEDATA,      10001
.set CURLOPT_HTTPHEADER,     10023
.set CURLOPT_POSTFIELDS,     10015
.set CURLOPT_POST,           47
.set CURLOPT_TIMEOUT,        13
.set CURLOPT_USERAGENT,      10018

.set CURLE_OK,               0

// ── System ──
.set STDOUT,  1
.set STDERR,  2
.set STDIN,   0

// ── mmap flags (macOS) ──
.set MAP_ANON,    0x1000
.set MAP_PRIVATE, 0x0002
.set PROT_READ,   0x01
.set PROT_WRITE,  0x02
