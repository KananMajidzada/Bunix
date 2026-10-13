// string.c - C string functions for Bunix

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

void *memcpy(void *dst, const void *src, size_t n) {
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    while (n--) *d++ = *s++;
    return dst;
}

void *memmove(void *dst, const void *src, size_t n) {
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    if (d == s || !n) return dst;
    if (d < s) {
        while (n--) *d++ = *s++;
    } else {
        d += n;
        s += n;
        while (n--) *--d = *--s;
    }
    return dst;
}

void *memset(void *dst, int c, size_t n) {
    unsigned char *d = (unsigned char *)dst;
    while (n--) *d++ = (unsigned char)c;
    return dst;
}

int memcmp(const void *a, const void *b, size_t n) {
    const unsigned char *x = (const unsigned char *)a;
    const unsigned char *y = (const unsigned char *)b;
    while (n--) {
        if (*x != *y) return *x - *y;
        x++;
        y++;
    }
    return 0;
}

void *memchr(const void *s, int c, size_t n) {
    const unsigned char *p = (const unsigned char *)s;
    for (size_t i = 0; i < n; i++) {
        if (p[i] == (unsigned char)c) return (void *)(p + i);
    }
    return NULL;
}

size_t strlen(const char *s) {
    size_t n = 0;
    while (s[n]) n++;
    return n;
}

int strcmp(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return (int)(unsigned char)*a - (int)(unsigned char)*b;
}

int strncmp(const char *a, const char *b, size_t n) {
    while (n && *a && *a == *b) { a++; b++; n--; }
    if (!n) return 0;
    return (int)(unsigned char)*a - (int)(unsigned char)*b;
}

int strcoll(const char *a, const char *b) {
    return strcmp(a, b);
}

size_t strxfrm(char *dst, const char *src, size_t n) {
    size_t len = strlen(src);
    if (n) {
        size_t k = len < n - 1 ? len : n - 1;
        memcpy(dst, src, k);
        dst[k] = 0;
    }
    return len;
}

char *strcpy(char *dst, const char *src) {
    char *d = dst;
    while ((*d++ = *src++));
    return dst;
}

char *strncpy(char *dst, const char *src, size_t n) {
    char *d = dst;
    while (n && *src) { *d++ = *src++; n--; }
    while (n--) *d++ = 0;
    return dst;
}

char *strcat(char *dst, const char *src) {
    strcpy(dst + strlen(dst), src);
    return dst;
}

char *strncat(char *dst, const char *src, size_t n) {
    char *d = dst + strlen(dst);
    while (n-- && *src) *d++ = *src++;
    *d = 0;
    return dst;
}

char *strchr(const char *s, int c) {
    char ch = (char)c;
    for (;; s++) {
        if (*s == ch) return (char *)s;
        if (!*s) return NULL;
    }
}

char *strrchr(const char *s, int c) {
    char ch = (char)c;
    const char *last = NULL;
    for (;; s++) {
        if (*s == ch) last = s;
        if (!*s) break;
    }
    return (char *)last;
}

char *strstr(const char *hay, const char *needle) {
    if (!*needle) return (char *)hay;
    size_t n = strlen(needle);
    for (; *hay; hay++) {
        if (*hay == *needle && !strncmp(hay, needle, n)) return (char *)hay;
    }
    return NULL;
}

size_t strspn(const char *s, const char *set) {
    size_t n = 0;
    for (; s[n]; n++) {
        if (!strchr(set, s[n])) break;
    }
    return n;
}

size_t strcspn(const char *s, const char *set) {
    size_t n = 0;
    for (; s[n]; n++) {
        if (strchr(set, s[n])) break;
    }
    return n;
}

char *strpbrk(const char *s, const char *set) {
    for (; *s; s++) {
        if (strchr(set, *s)) return (char *)s;
    }
    return NULL;
}

// strtok keeps its cursor in a static; that is the old behaviour and the only
// one a caller can port to without a rewrite.
static char *tok_state;

char *strtok(char *s, const char *sep) {
    if (s) tok_state = s;
    if (!tok_state) return NULL;

    tok_state += strspn(tok_state, sep);
    if (!*tok_state) {
        tok_state = NULL;
        return NULL;
    }

    char *start = tok_state;
    size_t n = strcspn(start, sep);
    if (start[n]) {
        start[n] = 0;
        tok_state = start + n + 1;
    } else {
        tok_state = NULL;
    }
    return start;
}

char *strerror(int e) {
    return (char *)"error";
}

char *strdup(const char *s) {
    size_t n = strlen(s) + 1;
    char *p = (char *)malloc(n);
    if (p) memcpy(p, s, n);
    return p;
}

char *strndup(const char *s, size_t n) {
    size_t len = 0;
    while (len < n && s[len]) len++;
    char *p = (char *)malloc(len + 1);
    if (!p) return NULL;
    memcpy(p, s, len);
    p[len] = 0;
    return p;
}