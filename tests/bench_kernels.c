#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  char *ptr;
  uint64_t len;
} slice_t;

extern uint64_t strlen_simd(const char *s);
extern slice_t json_find_key(char *json, const char *key);

static volatile uint64_t g_sink = 0;

#if defined(__clang__)
#define OPTNONE __attribute__((optnone))
#else
#define OPTNONE
#endif

static const char *skip_ws(const char *p) {
  while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
  return p;
}

__attribute__((noinline)) OPTNONE
static uint64_t strlen_scalar(const char *s) {
  const char *p = s;
  while (*p) p++;
  return (uint64_t)(p - s);
}

__attribute__((noinline)) OPTNONE
static slice_t json_find_key_scalar(char *json, const char *key) {
  const uint64_t key_len = strlen_scalar(key);
  for (char *p = json; *p; p++) {
    if (*p != '"') continue;

    char *key_start = p + 1;
    uint64_t i = 0;
    while (i < key_len && key_start[i] && key_start[i] == key[i]) i++;
    if (i != key_len || key_start[i] != '"') continue;

    const char *q = (const char *)(key_start + i + 1);
    q = skip_ws(q);
    if (*q != ':') continue;
    q++;
    q = skip_ws(q);
    if (*q != '"') continue;
    q++;

    char *value_start = (char *)q;
    while (*q) {
      if (*q == '"') break;
      if (*q == '\\' && q[1]) {
        q += 2;
      } else {
        q++;
      }
    }
    if (*q != '"') return (slice_t){0, 0};
    return (slice_t){value_start, (uint64_t)(q - (const char *)value_start)};
  }

  return (slice_t){0, 0};
}

__attribute__((noinline))
static int run_strlen_simd(void) {
  enum { STR_LEN = 32768, ITERS = 5000 };
  static char s[STR_LEN];
  memset(s, 'a', STR_LEN - 1);
  s[STR_LEN - 1] = '\0';

  uint64_t acc = 0;
  for (uint64_t i = 0; i < ITERS; i++) {
    acc += strlen_simd(s);
  }
  g_sink = acc;

  const uint64_t expected = (uint64_t)(STR_LEN - 1) * (uint64_t)ITERS;
  return acc == expected ? 0 : 2;
}

__attribute__((noinline)) OPTNONE
static int run_strlen_scalar(void) {
  enum { STR_LEN = 32768, ITERS = 5000 };
  static char s[STR_LEN];
  memset(s, 'a', STR_LEN - 1);
  s[STR_LEN - 1] = '\0';

  uint64_t acc = 0;
  for (uint64_t i = 0; i < ITERS; i++) {
    acc += strlen_scalar(s);
  }
  g_sink = acc;

  const uint64_t expected = (uint64_t)(STR_LEN - 1) * (uint64_t)ITERS;
  return acc == expected ? 0 : 2;
}

__attribute__((noinline))
static int run_json_simd(void) {
  enum { PAD_LEN = 4096, ITERS = 25000 };
  static char json[PAD_LEN + 128];
  static char pad[PAD_LEN + 1];

  memset(pad, 'a', PAD_LEN);
  pad[PAD_LEN] = '\0';
  snprintf(json, sizeof(json), "{\"pad\":\"%s\",\"needle\":\"ok\",\"tail\":1}", pad);

  uint64_t acc = 0;
  for (uint64_t i = 0; i < ITERS; i++) {
    slice_t s = json_find_key(json, "needle");
    if (!s.ptr || s.len != 2) return 3;
    acc += s.len;
  }
  g_sink = acc;

  return acc == (uint64_t)ITERS * 2u ? 0 : 3;
}

__attribute__((noinline)) OPTNONE
static int run_json_scalar(void) {
  enum { PAD_LEN = 4096, ITERS = 25000 };
  static char json[PAD_LEN + 128];
  static char pad[PAD_LEN + 1];

  memset(pad, 'a', PAD_LEN);
  pad[PAD_LEN] = '\0';
  snprintf(json, sizeof(json), "{\"pad\":\"%s\",\"needle\":\"ok\",\"tail\":1}", pad);

  uint64_t acc = 0;
  for (uint64_t i = 0; i < ITERS; i++) {
    slice_t s = json_find_key_scalar(json, "needle");
    if (!s.ptr || s.len != 2) return 3;
    acc += s.len;
  }
  g_sink = acc;

  return acc == (uint64_t)ITERS * 2u ? 0 : 3;
}

static void usage(const char *argv0) {
  fprintf(stderr,
          "usage: %s <strlen-simd|strlen-scalar|json-simd|json-scalar>\n",
          argv0);
}

int main(int argc, char **argv) {
  if (argc != 2) {
    usage(argv[0]);
    return 1;
  }

  if (strcmp(argv[1], "strlen-simd") == 0) return run_strlen_simd();
  if (strcmp(argv[1], "strlen-scalar") == 0) return run_strlen_scalar();
  if (strcmp(argv[1], "json-simd") == 0) return run_json_simd();
  if (strcmp(argv[1], "json-scalar") == 0) return run_json_scalar();

  usage(argv[0]);
  return 1;
}
