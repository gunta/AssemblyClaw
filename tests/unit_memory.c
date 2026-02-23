#include <stdint.h>
#include <stdio.h>

extern int64_t arena_init(uint64_t size);
extern void *arena_alloc(uint64_t size);
extern void arena_reset(void);
extern int64_t arena_destroy(void);
extern uint64_t arena_used(void);

static int fail_count = 0;

static void check(int cond, const char *msg) {
  if (!cond) {
    fprintf(stderr, "FAIL: %s\n", msg);
    fail_count++;
  }
}

int main(void) {
  check(arena_init(65536) == 0, "arena_init");

  void *p1 = arena_alloc(16);
  check(p1 != NULL, "arena_alloc first");
  check((((uintptr_t)p1) & 0xf) == 0, "arena_alloc alignment");

  void *p2 = arena_alloc(65520);
  check(p2 != NULL, "arena_alloc near full page");

  void *p3 = arena_alloc(64);
  check(p3 != NULL, "arena auto-grow allocation");

  check(arena_used() >= 65536, "arena_used after growth");

  arena_reset();
  check(arena_used() == 0, "arena_reset");

  check(arena_destroy() == 0, "arena_destroy");

  if (fail_count == 0) {
    puts("PASS");
    return 0;
  }
  return 1;
}
