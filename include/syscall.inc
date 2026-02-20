// syscall.inc — macOS ARM64 syscall numbers
// On macOS ARM64, syscalls go through libSystem wrappers.
// We call C functions directly (bl _write, bl _read, etc.)
// These constants are for reference / direct syscall if needed.

// macOS ARM64 syscall convention:
//   x16 = syscall number
//   x0-x5 = arguments
//   svc #0x80
//   x0 = return value (negative = error)

.set SYS_exit,       1
.set SYS_read,       3
.set SYS_write,      4
.set SYS_open,       5
.set SYS_close,      6
.set SYS_mmap,       197
.set SYS_munmap,     73
.set SYS_stat64,     338
.set SYS_fstat64,    339
