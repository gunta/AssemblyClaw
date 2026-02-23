#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct {
  char *ptr;
  uint64_t len;
} slice_t;

extern slice_t json_find_key(char *json, const char *key);
extern slice_t json_array_first_object(char *arr, uint64_t len);

static int fail_count = 0;

static void check(int cond, const char *msg) {
  if (!cond) {
    fprintf(stderr, "FAIL: %s\n", msg);
    fail_count++;
  }
}

static int slice_eq(slice_t s, const char *lit) {
  size_t n = strlen(lit);
  return s.ptr && s.len == n && memcmp(s.ptr, lit, n) == 0;
}

int main(void) {
  char j_empty[] = "{}";
  slice_t s = json_find_key(j_empty, "x");
  check(s.ptr == NULL, "empty object");

  char j_kv[] = "{\"key\":\"value\"}";
  s = json_find_key(j_kv, "key");
  check(slice_eq(s, "value"), "simple key/value");

  char j_nested[] = "{\"a\":{\"b\":1}}";
  slice_t a = json_find_key(j_nested, "a");
  check(a.ptr != NULL, "nested outer");
  if (a.ptr) {
    char save = a.ptr[a.len];
    a.ptr[a.len] = '\0';
    slice_t b = json_find_key(a.ptr, "b");
    check(slice_eq(b, "1"), "nested inner");
    a.ptr[a.len] = save;
  }

  char j_arr[] = "{\"arr\":[{\"x\":1},{\"x\":2}]}";
  slice_t arr = json_find_key(j_arr, "arr");
  check(arr.ptr != NULL, "array key");
  if (arr.ptr) {
    slice_t obj = json_array_first_object(arr.ptr, arr.len);
    check(obj.ptr != NULL, "array first object");
    if (obj.ptr) {
      char save = obj.ptr[obj.len];
      obj.ptr[obj.len] = '\0';
      slice_t x = json_find_key(obj.ptr, "x");
      check(slice_eq(x, "1"), "array first object value");
      obj.ptr[obj.len] = save;
    }
  }

  char j_esc[] = "{\"esc\":\"a\\\\n\\\\t\"}";
  s = json_find_key(j_esc, "esc");
  check(slice_eq(s, "a\\\\n\\\\t"), "escaped string token");

  char j_lit[] = "{\"n\":123.45,\"t\":true,\"f\":false,\"z\":null}";
  check(slice_eq(json_find_key(j_lit, "n"), "123.45"), "number literal");
  check(slice_eq(json_find_key(j_lit, "t"), "true"), "true literal");
  check(slice_eq(json_find_key(j_lit, "f"), "false"), "false literal");
  check(slice_eq(json_find_key(j_lit, "z"), "null"), "null literal");

  char j_bad[] = "{\"a\":";
  s = json_find_key(j_bad, "a");
  check(s.ptr == NULL || s.len == 0, "malformed json");

  // Large config-like payload (~4KB+).
  char pad[4097];
  memset(pad, 'a', sizeof(pad) - 1);
  pad[sizeof(pad) - 1] = '\0';
  char j_large[4600];
  snprintf(j_large, sizeof(j_large), "{\"pad\":\"%s\",\"needle\":\"ok\"}", pad);
  s = json_find_key(j_large, "needle");
  check(slice_eq(s, "ok"), "large json parse");

  if (fail_count == 0) {
    puts("PASS");
    return 0;
  }
  return 1;
}
