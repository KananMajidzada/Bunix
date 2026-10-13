// stdlib.c - conversions, sorting and the odds and ends of the C library.

#include <stddef.h>
#include <stdlib.h>

// --- whole number conversions ---

static int digitval(int c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'z') return c - 'a' + 10;
    if (c >= 'A' && c <= 'Z') return c - 'A' + 10;
    return -1;
}

static unsigned long long strtox(const char *s, char **end, int base,
                                 int *negp) {
    const char *p = s;
    while (*p == ' ' || (*p >= '\t' && *p <= '\r')) p++;

    int neg = 0;
    if (*p == '+' || *p == '-') {
        neg = (*p == '-');
        p++;
    }

    if ((base == 0 || base == 16) && p[0] == '0' && (p[1] == 'x' || p[1] == 'X') &&
        digitval(p[2]) >= 0 && digitval(p[2]) < 16) {
        p += 2;
        base = 16;
    } else if (base == 0) {
        base = (*p == '0') ? 8 : 10;
    }

    unsigned long long v = 0;
    int any = 0;
    for (;; p++) {
        int d = digitval(*p);
        if (d < 0 || d >= base) break;
        // Wrap rather than trap, which is what the standard asks for.
        v = v * (unsigned long long)base + (unsigned long long)d;
        any = 1;
    }

    if (end) *end = (char *)(any ? p : s);
    if (negp) *negp = neg;
    return v;
}

long strtol(const char *s, char **end, int base) {
    int neg;
    unsigned long long v = strtox(s, end, base, &neg);
    return neg ? -(long)v : (long)v;
}

unsigned long strtoul(const char *s, char **end, int base) {
    int neg;
    unsigned long long v = strtox(s, end, base, &neg);
    return neg ? (unsigned long)(-(long long)v) : (unsigned long)v;
}

unsigned long long strtoull(const char *s, char **end, int base) {
    int neg;
    unsigned long long v = strtox(s, end, base, &neg);
    return neg ? (unsigned long long)(-(long long)v) : v;
}

long long strtoll(const char *s, char **end, int base) {
    return (long long)strtoull(s, end, base);
}

int atoi(const char *s) { return (int)strtol(s, NULL, 10); }
long atol(const char *s) { return strtol(s, NULL, 10); }

// --- sorting ---

static void swapb(char *a, char *b, size_t n) {
    for (size_t i = 0; i < n; i++) {
        char t = a[i];
        a[i] = b[i];
        b[i] = t;
    }
}

void qsort(void *base, size_t n, size_t sz, int (*cmp)(const void *, const void *)) {
    char *b = (char *)base;
    if (n < 2 || sz == 0) return;

    // Insertion sort: simple, and it is stable, which qsort is not required
    // to be but callers here never mind either way.
    for (size_t i = 1; i < n; i++) {
        for (size_t j = i; j > 0; j--) {
            char *x = b + (j - 1) * sz;
            char *y = b + j * sz;
            if (cmp(x, y) <= 0) break;
            swapb(x, y, sz);
        }
    }
}

void *bsearch(const void *key, const void *base, size_t n, size_t sz,
              int (*cmp)(const void *, const void *)) {
    const char *b = (const char *)base;
    size_t lo = 0, hi = n;
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        const char *p = b + mid * sz;
        int c = cmp(key, p);
        if (c == 0) return (void *)p;
        if (c < 0) hi = mid;
        else lo = mid + 1;
    }
    return NULL;
}

// --- odds and ends ---

int abs(int n) { return n < 0 ? -n : n; }
long labs(long n) { return n < 0 ? -n : n; }

div_t div(int num, int den) {
    div_t r;
    r.quot = num / den;
    r.rem = num % den;
    return r;
}

ldiv_t ldiv(long num, long den) {
    ldiv_t r;
    r.quot = num / den;
    r.rem = num % den;
    return r;
}

static unsigned long rand_state = 1;

int rand(void) {
    // The example implementation from the standard.
    rand_state = rand_state * 1103515245 + 12345;
    return (int)((rand_state >> 16) & 0x7FFFFFFF);
}

void srand(unsigned seed) { rand_state = seed; }
