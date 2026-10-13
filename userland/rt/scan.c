// scan.c - the scanf family.
//
// Only the conversions a program is likely to lean on: the integers, the
// floating forms, %c, %s, %% and assignment suppression. Widths are honoured;
// the more exotic length modifiers are accepted and ignored, since what gets
// read does not depend on them.
//
// scanf reports how many values were assigned, not how much of the format
// matched, so a literal character and a suppressed conversion both have to be
// told apart from a conversion that stored something.

#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SCAN_STOP  0   // no match: stop here
#define SCAN_MATCH 1   // matched, nothing stored
#define SCAN_STORE 2   // matched and assigned

static void skipwhite(const char **pp) {
    const char *p = *pp;
    while (*p == ' ' || (*p >= '\t' && *p <= '\r')) p++;
    *pp = p;
}

static int iswhite(int c) {
    return c == ' ' || (c >= '\t' && c <= '\r');
}

static int scanint(const char **pp, int base, int width, unsigned long long *out) {
    const char *p = *pp;
    skipwhite(&p);

    int neg = 0;
    if (*p == '+' || *p == '-') {
        neg = (*p == '-');
        p++;
    }
    if (base == 16 && p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) p += 2;

    unsigned long long v = 0;
    int any = 0;
    for (; any < width; p++) {
        int c = *p;
        int d;
        if (c >= '0' && c <= '9') d = c - '0';
        else if (c >= 'a' && c <= 'z') d = c - 'a' + 10;
        else if (c >= 'A' && c <= 'Z') d = c - 'A' + 10;
        else break;
        if (d >= base) break;
        v = v * (unsigned long long)base + (unsigned long long)d;
        any++;
    }
    if (!any) return 0;
    *out = neg ? (unsigned long long)(-(long long)v) : v;
    *pp = p;
    return 1;
}

// Reads one conversion.
static int scanone(const char **fmtp, const char **sp, va_list ap) {
    const char *fmt = *fmtp;
    const char *str = *sp;

    if (*fmt == '\0') return SCAN_STOP;

    // Whitespace in the format matches any run of whitespace in the input.
    if (iswhite(*fmt)) {
        skipwhite(&str);
        while (iswhite(*fmt)) fmt++;
        *fmtp = fmt;
        *sp = str;
        return SCAN_MATCH;
    }

    if (*fmt != '%') {
        if (*str != *fmt) return SCAN_STOP;
        fmt++;
        str++;
        *fmtp = fmt;
        *sp = str;
        return SCAN_MATCH;
    }

    fmt++;
    int suppress = 0;
    if (*fmt == '*') {
        suppress = 1;
        fmt++;
    }

    int width = 0;
    while (*fmt >= '0' && *fmt <= '9') {
        width = width * 10 + (*fmt - '0');
        fmt++;
    }
    if (!width) width = 1 << 24;

    while (*fmt == 'h' || *fmt == 'l' || *fmt == 'z' || *fmt == 'j' ||
           *fmt == 't' || *fmt == 'L') fmt++;

    char c = *fmt;
    *fmtp = fmt + 1;

    if (c == '%') {
        if (*str != '%') return SCAN_STOP;
        *sp = str + 1;
        return SCAN_MATCH;
    }

    if (c == 'c') {
        skipwhite(&str);
        if (!*str) return SCAN_STOP;
        if (!suppress) {
            char *out = va_arg(ap, char *);
            for (int i = 0; i < width && *str; i++) *out++ = *str++;
            *out = 0;
        } else {
            for (int i = 0; i < width && *str; i++) str++;
        }
        *sp = str;
        return suppress ? SCAN_MATCH : SCAN_STORE;
    }

    if (c == 's') {
        skipwhite(&str);
        if (!*str) return SCAN_STOP;
        char *out = NULL;
        if (!suppress) out = va_arg(ap, char *);
        int n = 0;
        while (*str && n < width && !iswhite(*str)) {
            if (out) out[n] = *str;
            str++;
            n++;
        }
        if (out) out[n] = 0;
        *sp = str;
        return suppress ? SCAN_MATCH : SCAN_STORE;
    }

    if (c == 'd' || c == 'i' || c == 'u' || c == 'x' || c == 'X' ||
        c == 'o' || c == 'p') {
        int base = (c == 'd' || c == 'i') ? 10
                 : (c == 'x' || c == 'X' || c == 'p') ? 16
                 : (c == 'o') ? 8 : 10;
        unsigned long long v;
        if (!scanint(&str, base, width, &v)) return SCAN_STOP;
        if (!suppress) {
            void *out = va_arg(ap, void *);
            switch (c) {
            case 'd': case 'i': *(int *)out = (int)v; break;
            case 'u': *(unsigned *)out = (unsigned)v; break;
            case 'o': *(unsigned *)out = (unsigned)v; break;
            case 'p': *(void **)out = (void *)(uintptr_t)v; break;
            default:  *(unsigned *)out = (unsigned)v; break;
            }
        }
        *sp = str;
        return suppress ? SCAN_MATCH : SCAN_STORE;
    }

    if (c == 'f' || c == 'e' || c == 'g' || c == 'F' || c == 'E' || c == 'G') {
        skipwhite(&str);
        char tmp[64];
        int n = 0;
        const char *p = str;
        if (*p == '+' || *p == '-') tmp[n++] = *p++;
        while ((*p >= '0' && *p <= '9') || *p == '.' ||
               *p == 'e' || *p == 'E' || *p == '+' || *p == '-') {
            if (n < (int)sizeof(tmp) - 1 && n < width) tmp[n++] = *p;
            p++;
        }
        tmp[n] = 0;
        if (!n) return SCAN_STOP;
        char *tail;
        double v = strtod(tmp, &tail);
        if (tail == tmp) return SCAN_STOP;
        if (!suppress) {
            double *out = va_arg(ap, double *);
            *out = v;
        }
        *sp = p;
        return suppress ? SCAN_MATCH : SCAN_STORE;
    }

    return SCAN_STOP;
}

int vsscanf(const char *str, const char *fmt, va_list ap) {
    int stored = 0;
    for (;;) {
        int r = scanone(&fmt, &str, ap);
        if (r == SCAN_STOP) break;
        if (r == SCAN_STORE) stored++;
    }
    return stored;
}

int sscanf(const char *str, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int n = vsscanf(str, fmt, ap);
    va_end(ap);
    return n;
}