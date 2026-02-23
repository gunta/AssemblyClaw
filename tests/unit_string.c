#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern uint64_t strlen_simd(const char *s);
extern int64_t strcmp_simd(const char *a, const char *b);
extern void *memcpy_simd(void *dst, const void *src, uint64_t n);

static int fail_count = 0;

static void check(int cond, const char *msg) {
  if (!cond) {
    fprintf(stderr, "FAIL: %s\n", msg);
    fail_count++;
  }
}

int main(void) {
  check(strlen_simd("") == 0, "strlen empty");
  check(strlen_simd("hello") == 5, "strlen hello");

  char long_buf[257];
  memset(long_buf, 'a', 256);
  long_buf[256] = '\0';
  check(strlen_simd(long_buf) == 256, "strlen 256");

  char unaligned[] = "xunaligned";
  check(strlen_simd(unaligned + 1) == 9, "strlen unaligned");

  check(strcmp_simd("abc", "abc") == 0, "strcmp equal");
  check(strcmp_simd("abc", "abd") < 0, "strcmp less");
  check(strcmp_simd("abd", "abc") > 0, "strcmp greater");
  check(strcmp_simd("", "") == 0, "strcmp empty");

  char src16[16];
  char dst16[16];
  for (int i = 0; i < 16; i++) src16[i] = (char)i;
  memcpy_simd(dst16, src16, 16);
  check(memcmp(src16, dst16, 16) == 0, "memcpy 16-byte");

  char src4k[4096];
  char dst4k[4096];
  for (int i = 0; i < 4096; i++) src4k[i] = (char)(i & 0x7f);
  memcpy_simd(dst4k, src4k, 4096);
  check(memcmp(src4k, dst4k, 4096) == 0, "memcpy 4KB");

  if (fail_count == 0) {
    puts("PASS");
    return 0;
  }
  return 1;
}
