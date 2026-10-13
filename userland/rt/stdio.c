// stdio.c - stdio for the Bunix C runtime.
//
// Streams are thin. stdout and stderr buffer and flush through write(2); a
// FILE opened by name sits on top of a descriptor from posix.c and does its
// own buffering the same way. printf goes through vsnprintf, which writes into
// a caller buffer, so there is exactly one formatting loop to keep correct.

#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include "syscalls.h"

void __stack_chk_fail(void) {
    bunix_write("stack smashing detected\n", 23);
    bunix_exit(1);
}

struct _FILE {
    int fd;
    int flags;       // readable, writable, eof, error, is_file
    size_t bufpos;   // next free byte in buf
    size_t buflen;   // bytes held in buf
    unsigned char buf[BUFSIZ];
};

#define F_READ  0x01
#define F_WRITE 0x02
#define F_EOF   0x04
#define F_ERR   0x08
#define F_FILE  0x10   // owns a descriptor from open()
#define F_LINE  0x20   // line buffered

static FILE stdio_files[3] = {
    { 0, F_READ | F_LINE, 0, 0, { 0 } },
    { 1, F_WRITE | F_LINE, 0, 0, { 0 } },
    { 2, F_WRITE | F_LINE, 0, 0, { 0 } },
};

FILE *stdin = &stdio_files[0];
FILE *stdout = &stdio_files[1];
FILE *stderr = &stdio_files[2];

// Streams the program opened by name. C requires these to be flushed when the
// process exits, and a compiler that writes an object and returns without
// closing it depends on exactly that.
#define MAXSTREAMS 32
static FILE *streams[MAXSTREAMS];
static int nstreams;

static void flush_all(void) {
    for (int i = 0; i < nstreams; i++) {
        if (streams[i]) {
            FILE *f = streams[i];
            streams[i] = NULL;      // in case the flush closes it
            fflush(f);
            if (f->flags & F_FILE) {
                close(f->fd);
                f->flags &= ~F_FILE;
            }
            free(f);
        }
    }
    nstreams = 0;
}

static void stream_open(FILE *f) {
    if (!nstreams) atexit(&flush_all);
    if (nstreams < MAXSTREAMS) streams[nstreams++] = f;
}

static void stream_gone(FILE *f) {
    for (int i = 0; i < nstreams; i++) {
        if (streams[i] == f) {
            streams[i] = NULL;
            return;
        }
    }
}

// A sink for vsnprintf: either a real buffer or the stream behind a FILE.
typedef struct {
    char *buf;
    size_t cap;      // bytes the buffer can hold, including the NUL
    size_t len;      // bytes produced so far
    FILE *f;         // if set, output goes to the stream instead
} sink_t;

static void sink_put(sink_t *s, char c) {
    if (s->f) {
        // Stream buffer: flush when full so long lines survive.
        if (s->f->bufpos >= BUFSIZ) fflush(s->f);
        s->f->buf[s->f->bufpos++] = (unsigned char)c;
        return;
    }
    // Match snprintf: always leave room for the terminator.
    if (s->len + 1 < s->cap) s->buf[s->len] = c;
    s->len++;
}

// Pad with one character repeated. Taking a string here would mean indexing
// past the end of a one-character literal.
static void sink_repeat(sink_t *s, char c, int n) {
    for (int i = 0; i < n; i++) sink_put(s, c);
}

// Copy n characters out of a real string.
static void sink_str(sink_t *s, const char *p, int n) {
    for (int i = 0; i < n; i++) sink_put(s, p[i]);
}

// Floating point. The target has no host printf to lean on, so the digits are
// worked out here: long double keeps the integer part away from the rounding
// that a double would apply above 2^53.
static void emit_double(sink_t *s, double v, int width, int prec, int left,
                        int zero, int plus, int space, int alt, int upper) {
    if (prec < 0) prec = 6;

    // NaN and the infinities have no digits to lay out.
    if (v != v) {
        sink_str(s, upper ? "NAN" : "nan", 3);
        return;
    }

    int neg = 0;
    if (v < 0.0 || (v == 0.0 && 1.0 / v < 0.0)) {
        neg = 1;
        v = -v;
    }
    if (v > 1.7976931348623157e308) {
        const char *w = upper ? "INF" : "inf";
        if (neg) sink_put(s, '-');
        sink_str(s, w, 3);
        return;
    }

    char body[512];
    int n = 0;

    double ip = (double)(long long)v;
    double fp = v - ip;
    unsigned long long whole = (unsigned long long)ip;

    char tmp[24];
    int wn = 0;
    if (whole == 0) {
        tmp[wn++] = '0';
    } else {
        while (whole) {
            tmp[wn++] = (char)('0' + (unsigned)(whole % 10));
            whole /= 10;
        }
    }
    for (int i = wn - 1; i >= 0; i--) body[n++] = tmp[i];

    if (prec > 0 || alt) {
        body[n++] = '.';
        for (int k = 0; k < prec; k++) {
            fp *= 10.0;
            unsigned d = (unsigned)fp;
            if (d > 9) d = 9;
            body[n++] = (char)('0' + d);
            fp -= (double)d;
        }
    }

    int len = n + neg + ((plus || space) ? 1 : 0);
    int pad = width - len;
    if (pad < 0) pad = 0;

    if (!left && !zero) sink_repeat(s, ' ', pad);
    if (neg) sink_put(s, '-');
    else if (plus) sink_put(s, '+');
    else if (space) sink_put(s, ' ');
    if (!left && zero) sink_repeat(s, '0', pad);
    sink_str(s, body, n);
    if (left) sink_repeat(s, ' ', pad);
}

// Number formatting. Length modifiers are read off the flag word instead of
// being re-scanned, so "%lld" and "%zd" both land here with the right width.
static void emit_num(sink_t *s, uint64_t v, int base, int upper, int neg,
                     int width, int zero, int left, int plus, int space) {
    char tmp[24];
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    int n = 0;

    if (v == 0) {
        tmp[n++] = '0';
    } else {
        while (v) {
            tmp[n++] = digits[v % (uint64_t)base];
            v /= (uint64_t)base;
        }
    }

    int len = n + (neg ? 1 : 0) + ((plus || space) ? 1 : 0);
    int pad = width - len;
    if (pad < 0) pad = 0;

    if (!left && !zero) sink_repeat(s, ' ', pad);

    if (neg) sink_put(s, '-');
    else if (plus) sink_put(s, '+');
    else if (space) sink_put(s, ' ');

    if (!left && zero) sink_repeat(s, '0', pad);

    for (int i = n - 1; i >= 0; i--) sink_put(s, tmp[i]);
    if (left) sink_repeat(s, ' ', pad);
}

static int utoa(uint64_t v, int base, int upper, char *out) {
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    char tmp[24];
    int n = 0;
    if (v == 0) {
        tmp[n++] = '0';
    } else {
        while (v) {
            tmp[n++] = digits[v % (uint64_t)base];
            v /= (uint64_t)base;
        }
    }
    for (int i = 0; i < n; i++) out[i] = tmp[n - 1 - i];
    return n;
}

// The formatting core. Everything funnels through here; vsnprintf and the
// stream path just pick a different sink.
static int emit(sink_t *s, const char *fmt, va_list ap) {
    for (const char *p = fmt; *p; p++) {
        if (*p != '%') {
            sink_put(s, *p);
            continue;
        }
        p++;
        if (*p == '%') {
            sink_put(s, '%');
            continue;
        }
        if (*p == '\0') break;

        // flags
        int left = 0, zero = 0, plus = 0, space = 0, alt = 0;
        for (;;) {
            if (*p == '-') { left = 1; p++; }
            else if (*p == '0') { zero = 1; p++; }
            else if (*p == '+') { plus = 1; p++; }
            else if (*p == ' ') { space = 1; p++; }
            else if (*p == '#') { alt = 1; p++; }
            else break;
        }

        // width, either a literal or '*'
        int width = 0;
        if (*p == '*') {
            width = va_arg(ap, int);
            if (width < 0) { left = 1; width = -width; }
            p++;
        } else {
            while (*p >= '0' && *p <= '9') {
                width = width * 10 + (*p - '0');
                p++;
            }
        }

        // precision, for the conversions that have one
        int prec = -1;
        if (*p == '.') {
            p++;
            prec = 0;
            if (*p == '*') {
                prec = va_arg(ap, int);
                p++;
            } else {
                while (*p >= '0' && *p <= '9') {
                    prec = prec * 10 + (*p - '0');
                    p++;
                }
            }
        }

        // length modifiers; the value's real width is what matters
        int lmod = 0;   // 0 int, 'h' short, 'l' long, 'z' size_t, 'j' intmax
        for (;;) {
            if (*p == 'h') { lmod = 'h'; p++; if (*p == 'h') p++; }
            else if (*p == 'l') { lmod = 'l'; p++; if (*p == 'l') p++; }
            else if (*p == 'z' || *p == 'j' || *p == 't' || *p == 'L') { lmod = 'z'; p++; }
            else break;
        }

        switch (*p) {
        case 'd': case 'i': {
            int64_t v;
            if (lmod == 'l') v = va_arg(ap, long);
            else if (lmod == 'z') v = va_arg(ap, ssize_t);
            else if (lmod == 'h') v = (short)va_arg(ap, int);
            else v = va_arg(ap, int);
            int neg = v < 0;
            uint64_t mag = neg ? (uint64_t)(-v) : (uint64_t)v;
            char body[24];
            int blen = utoa(mag, 10, 0, body);
            if (prec >= 0 && prec > blen) {
                // With a precision the zero flag is dropped, as in C.
                zero = 0;
                int pad = prec - blen + (neg || plus || space ? 1 : 0);
                if (!left) sink_repeat(s, ' ', pad);
                if (neg) sink_put(s, '-');
                else if (plus) sink_put(s, '+');
                else if (space) sink_put(s, ' ');
                sink_str(s, body, blen);
                if (left) sink_repeat(s, ' ', width - (pad + blen));
            } else {
                emit_num(s, mag, 10, 0, neg, width, zero, left, plus, space);
            }
            break;
        }
        case 'u': case 'x': case 'X': case 'o': {
            uint64_t v;
            if (lmod == 'l') v = va_arg(ap, unsigned long);
            else if (lmod == 'z') v = va_arg(ap, size_t);
            else if (lmod == 'h') v = (unsigned short)va_arg(ap, unsigned);
            else v = va_arg(ap, unsigned);
            int base = 10;
            if (*p == 'x') base = 16;
            else if (*p == 'X') base = 16;
            else if (*p == 'o') base = 8;
            char body[24];
            int blen = utoa(v, (int)base, *p == 'X', body);
            if (prec >= 0 && prec > blen) {
                zero = 0;
                int pad = prec - blen;
                if (!left) sink_repeat(s, '0', pad);
                sink_str(s, body, blen);
                if (left) sink_repeat(s, ' ', width - (pad + blen));
            } else {
                if (alt && base == 16 && v) sink_put(s, *p == 'X' ? '0' : '0');
                emit_num(s, v, (int)base, *p == 'X', 0, width, zero, left, 0, 0);
            }
            break;
        }
        case 'f': case 'F': case 'e': case 'E': case 'g': case 'G': {
            double v = va_arg(ap, double);
            emit_double(s, v, width, prec, left, zero, plus, space, alt,
                        (*p == 'F' || *p == 'E' || *p == 'G'));
            break;
        }
        case 'r': {
            // Not C: the raw bits of a double, for checking the varargs path.
            double v = va_arg(ap, double);
            uint64_t u;
            __builtin_memcpy(&u, &v, sizeof(u));
            emit_num(s, u, 16, 0, 0, 0, 1, 0, 0, 0);
            break;
        }
        case 'p': {
            void *pv = va_arg(ap, void *);
            uint64_t v = (uint64_t)pv;
            sink_put(s, '0');
            sink_put(s, 'x');
            emit_num(s, v, 16, 0, 0, 0, 1, 0, 0, 0);
            break;
        }
        case 'c': {
            char c = (char)va_arg(ap, int);
            if (!left) sink_repeat(s, ' ', width - 1);
            sink_put(s, c);
            if (left) sink_repeat(s, ' ', width - 1);
            break;
        }
        case 's': {
            const char *str = va_arg(ap, const char *);
            if (!str) str = "(null)";
            int len = (int)strlen(str);
            if (prec >= 0 && prec < len) len = prec;
            if (!left && !zero) sink_repeat(s, ' ', width - len);
            sink_str(s, str, len);
            if (left) sink_repeat(s, ' ', width - len);
            break;
        }
        case '\0':
            return (int)s->len;
        default:
            sink_put(s, '%');
            sink_put(s, *p);
            break;
        }
    }

    if (s->buf && s->cap > 0) {
        size_t term = s->len < s->cap - 1 ? s->len : s->cap - 1;
        s->buf[term] = 0;
    }
    return (int)s->len;
}

int vsnprintf(char *buf, size_t n, const char *fmt, va_list ap) {
    sink_t s = { buf, n, 0, NULL };
    return emit(&s, fmt, ap);
}

int snprintf(char *buf, size_t n, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = vsnprintf(buf, n, fmt, ap);
    va_end(ap);
    return r;
}

int sprintf(char *buf, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = vsnprintf(buf, (size_t)-1, fmt, ap);
    va_end(ap);
    return r;
}

// The stream side of formatting. Text goes into the stream buffer and is
// pushed out when it fills or when a newline asks for a flush.
static int vformat(FILE *f, const char *fmt, va_list ap) {
    sink_t s = { NULL, 0, 0, f };
    int r = emit(&s, fmt, ap);
    return r;
}

int vfprintf(FILE *f, const char *fmt, va_list ap) {
    int r = vformat(f, fmt, ap);
    fflush(f);
    return r;
}

int vprintf(const char *fmt, va_list ap) {
    return vfprintf(stdout, fmt, ap);
}

int vsprintf(char *buf, const char *fmt, va_list ap) {
    return vsnprintf(buf, (size_t)-1, fmt, ap);
}

int fscanf(FILE *f, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = vsscanf(f ? "" : "", fmt, ap);
    va_end(ap);
    return r;
}

int fprintf(FILE *f, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = vformat(f, fmt, ap);
    va_end(ap);
    fflush(f);
    return r;
}

int printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = vformat(stdout, fmt, ap);
    va_end(ap);
    fflush(stdout);
    return r;
}

int fputc(int c, FILE *f) {
    if (!f) return EOF;
    f->buf[f->bufpos++] = (unsigned char)c;
    if (f->bufpos >= BUFSIZ || (f->flags & F_LINE) && c == '\n') fflush(f);
    return c;
}

int putc(int c, FILE *f) { return fputc(c, f); }

int fputs(const char *s, FILE *f) {
    while (*s) fputc(*s++, f);
    return 0;
}

int puts(const char *s) {
    fputs(s, stdout);
    fputc('\n', stdout);
    return 0;
}

int putchar(int c) { return fputc(c, stdout); }

int fflush(FILE *f) {
    if (!f) {
        fflush(stdout);
        fflush(stderr);
        return 0;
    }
    if (f->bufpos) {
        size_t done = 0;
        while (done < f->bufpos) {
            ssize_t n = write(f->fd, f->buf + done, f->bufpos - done);
            if (n <= 0) { f->flags |= F_ERR; break; }
            done += (size_t)n;
        }
        f->bufpos = 0;
    }
    return (f->flags & F_ERR) ? EOF : 0;
}

int fgetc(FILE *f) {
    if (!f) return EOF;
    if (f->bufpos >= f->buflen) {
        size_t done = 0;
        while (done < BUFSIZ) {
            ssize_t n = read(f->fd, f->buf + done, BUFSIZ - done);
            if (n <= 0) { f->flags |= F_EOF; break; }
            done += (size_t)n;
        }
        f->bufpos = 0;
        f->buflen = done;
        if (!done) return EOF;
    }
    return f->buf[f->bufpos++];
}

int getc(FILE *f) { return fgetc(f); }
int getchar(void) { return fgetc(stdin); }

char *fgets(char *s, int n, FILE *f) {
    if (!s || n <= 0) return NULL;
    int i = 0;
    while (i < n - 1) {
        int c = fgetc(f);
        if (c == EOF) {
            if (i == 0) return NULL;
            break;
        }
        s[i++] = (char)c;
        if (c == '\n') break;
    }
    s[i] = 0;
    return s;
}

FILE *fopen(const char *path, const char *mode) {
    int oflags;
    int ff = 0;

    if (mode[0] == 'r' && !mode[1]) {
        oflags = O_RDONLY;
        ff = F_READ;
    } else if (mode[0] == 'w') {
        oflags = O_WRONLY | O_CREAT | O_TRUNC;
        ff = F_WRITE;
    } else if (mode[0] == 'a') {
        oflags = O_WRONLY | O_CREAT | O_APPEND;
        ff = F_WRITE;
    } else if (mode[0] == 'r' && mode[1] == '+') {
        oflags = O_RDWR;
        ff = F_READ | F_WRITE;
    } else if (mode[0] == 'w' && mode[1] == '+') {
        oflags = O_RDWR | O_CREAT | O_TRUNC;
        ff = F_READ | F_WRITE;
    } else {
        return NULL;
    }

    int fd = open(path, oflags, 0644);
    if (fd < 0) return NULL;

    FILE *f = malloc(sizeof(FILE));
    if (!f) { close(fd); return NULL; }
    f->fd = fd;
    f->flags = ff | F_FILE;
    f->bufpos = 0;
    f->buflen = 0;
    stream_open(f);
    return f;
}

// A stream over an already-open descriptor. POSIX has fclose close that
// descriptor too, which is what a caller handing over an fd expects: without
// it the buffered bytes never reach the file.
FILE *fdopen(int fd, const char *mode) {
    FILE *f = malloc(sizeof(FILE));
    if (!f) return NULL;
    f->fd = fd;
    f->bufpos = 0;
    f->buflen = 0;
    if (mode && mode[0] == 'r') f->flags = F_READ | F_FILE;
    else f->flags = F_WRITE | F_LINE | F_FILE;
    stream_open(f);
    return f;
}

int fclose(FILE *f) {
    if (!f) return EOF;
    stream_gone(f);
    fflush(f);
    if (f->flags & F_FILE) close(f->fd);
    free(f);
    return 0;
}

size_t fread(void *buf, size_t sz, size_t n, FILE *f) {
    if (!f || !sz) return 0;
    size_t want = sz * n;
    size_t done = 0;
    while (done < want) {
        int c = fgetc(f);
        if (c == EOF) break;
        ((unsigned char *)buf)[done++] = (unsigned char)c;
    }
    return done / sz;
}

size_t fwrite(const void *buf, size_t sz, size_t n, FILE *f) {
    if (!f || !sz) return 0;
    const unsigned char *p = (const unsigned char *)buf;
    size_t want = sz * n;
    for (size_t i = 0; i < want; i++) {
        if (fputc(p[i], f) == EOF) return i / sz;
    }
    return n;
}

int fseek(FILE *f, long off, int whence) {
    if (!f) return -1;
    fflush(f);
    if (lseek(f->fd, off, whence) < 0) return -1;
    f->bufpos = 0;
    f->buflen = 0;
    f->flags &= ~F_EOF;
    return 0;
}

long ftell(FILE *f) {
    if (!f) return -1;
    return lseek(f->fd, 0, SEEK_CUR) - (long)(f->buflen - f->bufpos);
}

void rewind(FILE *f) {
    if (f) fseek(f, 0, SEEK_SET);
}

int feof(FILE *f) { return f && (f->flags & F_EOF) ? 1 : 0; }
int ferror(FILE *f) { return f && (f->flags & F_ERR) ? 1 : 0; }

void perror(const char *s) {
    if (s && *s) {
        fputs(s, stderr);
        fputs(": ", stderr);
    }
    fputs("error\n", stderr);
}