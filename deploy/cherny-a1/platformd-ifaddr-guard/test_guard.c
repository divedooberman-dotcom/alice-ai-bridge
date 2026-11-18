#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

static int fail_alloc;
static int test_error;
static void *test_malloc(size_t n) { return fail_alloc ? NULL : malloc(n); }
static int *test_errno(void) { return &test_error; }
static int test_once(int *unused, void (*fn)(void)) { (void)unused; (void)fn; return 0; }
static void test_syslog(int priority, const char *format, ...) { (void)priority; (void)format; }
#define syslog test_syslog
#define malloc test_malloc
#define __errno_location test_errno
#define pthread_once test_once
#define getifaddrs guarded_getifaddrs
#define freeifaddrs guarded_freeifaddrs
#include "guard.c"
#undef malloc
#undef pthread_once

static unsigned frees;
static struct ifa *expected;
static void fake_free(struct ifa *p) { assert(p == expected); ++frees; }
static int fake_error(struct ifa **p) { (void)p; test_error = 5; return -1; }
static int fake_get(struct ifa **p) { *p = expected; return 0; }

/* Models the original reader's precondition without deliberately crashing. */
static int reader_safe(struct ifa *p) {
    for (; p; p = p->next) if (!p->addr) return 0;
    return 1;
}
static void ignore_free(struct ifa *p) { (void)p; }
static void *stress(void *unused) {
    (void)unused;
    for (int i = 0; i < 10000; ++i) {
        int addr = 2;
        struct ifa good = {.name="wlan0", .addr=&addr};
        struct ifa bad = {.name="wlan0", .next=&good};
        struct ifa *head = &bad;
        assert(filter(&head) == 0 && head->addr == &addr && !head->next);
        guarded_freeifaddrs(head);
        assert(!bad.addr && bad.next == &good);
    }
    return NULL;
}

int main(void) {
    assert(matches("/system/vendor/quasar/maind", 0x10000, 0x10000 + GUARD_CALLSITE + 1));
    assert(matches("maind", 0x10000, 0x10000 + GUARD_CALLSITE));
    assert(!matches("other", 0x10000, 0x10000 + GUARD_CALLSITE + 1));
    assert(!matches("maind", 0x10000, 0x10000 + GUARD_CALLSITE + 3));
    assert(!matches(NULL, 0x10000, 0x10000 + GUARD_CALLSITE + 1));
    real_free = fake_free; real_get = fake_get;
    int addr = 2, addr6 = 10;
    struct ifa tail = {.name="wlan0"};
    struct ifa v6 = {.name="wlan0", .addr=&addr6, .next=&tail};
    struct ifa middle = {.name="wlan0", .next=&v6};
    struct ifa v4 = {.name="wlan0", .addr=&addr, .next=&middle};
    struct ifa start = {.name="wlan0", .next=&v4};
    struct ifa *head = expected = &start;
    assert(!reader_safe(head)); /* Before fix: demonstrably unsafe input. */
    assert(filter(&head) == 0 && reader_safe(head));
    assert(head->addr == &addr && head->next->addr == &addr6 && !head->next->next);
    assert(start.next == &v4 && v4.next == &middle && middle.next == &v6);
    guarded_freeifaddrs(head); assert(frees == 1 && !allocations);

    head = expected = &tail;
    assert(filter(&head) == 0 && !head && frees == 2);
    guarded_freeifaddrs(NULL); assert(frees == 2);
    struct ifa only = {.name="lo", .addr=&addr};
    head = expected = &only;
    assert(filter(&head) == 0 && head == &only);
    guarded_freeifaddrs(head); assert(frees == 3);

    head = expected = &start; fail_alloc = 1;
    assert(filter(&head) == -1 && !head && test_error == 12 && frees == 4);
    fail_alloc = 0;
    head = expected = &start;
    assert(guarded_getifaddrs(&head) == 0 && head == expected); /* Other caller untouched. */
    guarded_freeifaddrs(head); assert(frees == 5);
    real_get = fake_error;
    assert(guarded_getifaddrs(&head) == -1 && test_error == 5);
    real_free = ignore_free;
    pthread_t threads[4];
    for (int i = 0; i < 4; ++i) assert(!pthread_create(&threads[i], NULL, stress, NULL));
    for (int i = 0; i < 4; ++i) assert(!pthread_join(threads[i], NULL));
    assert(!allocations);
    puts("PASS: null entries, ownership, empty lists, errors, unaffected caller, 40000 concurrent lifecycles");
}
