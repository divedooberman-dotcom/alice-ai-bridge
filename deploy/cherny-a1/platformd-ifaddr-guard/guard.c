/* Narrow compatibility guard for maind build 28f5077683c648303e7ed932fc1ffcba57b8152f.
 * Preserve libc's original allocation and only filter the known faulty caller.
 * No network state, addresses, credentials or executable bytes are changed.
 */
#include <stddef.h>
#include <stdint.h>

/* Linux ABI declarations permit a freestanding ARM build without a device SDK. */
struct ifa {
    struct ifa *next;
    char *name;
    unsigned flags;
    void *addr, *netmask, *broadcast, *data;
};
#ifdef __arm__
_Static_assert(sizeof(struct ifa) == 28, "ARM ifaddrs ABI");
_Static_assert(offsetof(struct ifa, addr) == 12, "ARM ifa_addr offset");
#endif
extern void *malloc(size_t);
extern void free(void *);
extern void *dlsym(void *, const char *);
struct dl_info { const char *name; void *base; const char *symbol; void *address; };
extern int dladdr(const void *, struct dl_info *);
extern int pthread_once(int *, void (*)(void));
extern int *__errno_location(void);
extern void syslog(int, const char *, ...);

/* Return address of the confirmed faulty getifaddrs call, relative to the maind
 * image base, Thumb bit cleared. The default is the Cherny build named above;
 * another audited build passes its own value with -DGUARD_CALLSITE=0x... */
#ifndef GUARD_CALLSITE
#define GUARD_CALLSITE 0x14a7662
#endif

static int (*real_get)(struct ifa **);
static void (*real_free)(struct ifa *);
static int once;
static int lock;
static int reported;
struct owned {
    struct owned *next;
    struct ifa *original;
    struct ifa entries[];
};
static struct owned *allocations;

static void acquire(void) {
    while (__atomic_exchange_n(&lock, 1, __ATOMIC_ACQUIRE)) {}
}
static void release(void) { __atomic_store_n(&lock, 0, __ATOMIC_RELEASE); }
static void resolve(void) {
    real_get = (int (*)(struct ifa **))dlsym((void *)-1, "getifaddrs");
    real_free = (void (*)(struct ifa *))dlsym((void *)-1, "freeifaddrs");
}

static int matches(const char *name, uintptr_t base, uintptr_t caller) {
    if (!name) return 0;
    for (const char *p = name; *p; ++p) if (*p == '/') name = p + 1;
    const char expected[] = "maind";
    unsigned i = 0;
    while (expected[i] && name[i] == expected[i]) ++i;
    return !expected[i] && !name[i] &&
        ((caller & ~(uintptr_t)1) - base == GUARD_CALLSITE);
}
static int affected_caller(void *caller) {
    struct dl_info info;
    return dladdr(caller, &info) && matches(info.name, (uintptr_t)info.base, (uintptr_t)caller);
}

/* A shallow COPY keeps valid pointers alive in libc's untouched original list. */
static int filter(struct ifa **head) {
    size_t valid = 0, missing = 0;
    for (struct ifa *p = *head; p; p = p->next) {
        if (p->addr) ++valid; else ++missing;
    }
    if (!missing) return 0;
    syslog(6, "platformd-ifaddr-guard: filtering %u addressless entries", (unsigned)missing);
    if (!valid) {
        real_free(*head);
        *head = NULL;
        return 0;
    }
    if (valid > (SIZE_MAX - sizeof(struct owned)) / sizeof(struct ifa)) {
        real_free(*head); *head = NULL; *__errno_location() = 12; return -1;
    }
    struct owned *o = malloc(sizeof(*o) + valid * sizeof(struct ifa));
    if (!o) {
        real_free(*head); *head = NULL; *__errno_location() = 12; return -1;
    }
    o->original = *head;
    size_t n = 0;
    for (struct ifa *p = *head; p; p = p->next) {
        if (!p->addr) continue;
        o->entries[n] = *p;
        o->entries[n].next = n + 1 < valid ? &o->entries[n + 1] : NULL;
        ++n;
    }
    acquire();
    o->next = allocations;
    allocations = o;
    release();
    *head = o->entries;
    return 0;
}

int getifaddrs(struct ifa **head) {
    pthread_once(&once, resolve);
    if (!real_get || !real_free) { *__errno_location() = 38; return -1; }
    int result = real_get(head);
    if (result != 0 || !head || !*head) return result;
    int saved_errno = *__errno_location();
    if (affected_caller(__builtin_return_address(0))) {
        if (!__atomic_exchange_n(&reported, 1, __ATOMIC_RELAXED))
            syslog(6, "platformd-ifaddr-guard: matched target callsite");
        result = filter(head);
    }
    if (result == 0) *__errno_location() = saved_errno;
    return result;
}

void freeifaddrs(struct ifa *head) {
    pthread_once(&once, resolve);
    if (!head || !real_free) return;
    acquire();
    struct owned **link = &allocations, *found = NULL;
    while (*link) {
        if ((*link)->entries == head) { found = *link; *link = found->next; break; }
        link = &(*link)->next;
    }
    release();
    if (found) { real_free(found->original); free(found); }
    else real_free(head);
}
