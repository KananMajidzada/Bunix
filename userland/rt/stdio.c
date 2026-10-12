// stdio.c - minimal stdio for Bunix

#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include "syscalls.h"

void __stack_chk_fail(void) {
    bunix_write(1, "stack smashing detected\n", 24);
    bunix_exit(1);
}

static void putc(char c) {
    bunix_write(1, &c, 1);
}

void puts(const char *s) {
    while (*s) putc(*s++);
    putc('\n');
}

int putchar(int c) {
    putc(c);
    return c;
}

static void print_num(uint64_t n) {
    char buf[24];
    int i = 23;
    if (n == 0) {
        buf[i--] = '0';
    } else {
        while (n > 0) {
            buf[i--] = '0' + (n % 10);
            n /= 10;
        }
    }
    while (++i < 24) putc(buf[i]);
}

int printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    while (*fmt) {
        if (*fmt == '%') {
            fmt++;
            switch (*fmt) {
                case 's': puts(va_arg(ap, const char*)); break;
                case 'd': print_num(va_arg(ap, int)); break;
                case 'u': print_num(va_arg(ap, unsigned)); break;
                case 'x': {
                    uint64_t x = va_arg(ap, uint64_t);
                    char buf[18];
                    int i = 17;
                    if (x == 0) buf[i--] = '0';
                    while (x) {
                        int d = x & 15;
                        buf[i--] = d < 10 ? '0' + d : 'a' + d - 10;
                        x >>= 4;
                    }
                    while (++i < 18) putc(buf[i]);
                    break;
                }
                case 'p': {
                    uint64_t x = va_arg(ap, uint64_t);
                    putc('0'); putc('x');
                    char buf[18];
                    int i = 17;
                    if (x == 0) buf[i--] = '0';
                    while (x) {
                        int d = x & 15;
                        buf[i--] = d < 10 ? '0' + d : 'a' + d - 10;
                        x >>= 4;
                    }
                    while (++i < 18) putc(buf[i]);
                    break;
                }
                case 'c': putc(va_arg(ap, int)); break;
                case '%': putc('%'); break;
                default: putc('%'); putc(*fmt); break;
            }
        } else {
            putc(*fmt);
        }
        fmt++;
    }
    va_end(ap);
    return 0;
}

// POSIX-like wrappers
int open(const char *path, int flags, ...) {
    return -1;
}

ssize_t read(int fd, void *buf, size_t count) {
    if (fd == 0) {
        char *p = buf;
        size_t n = 0;
        while (n < count) {
            int c = bunix_readchr();
            if (c <= 0) { bunix_yield(); continue; }
            *p++ = c;
            n++;
            if (c == '\n') break;
        }
        return n;
    }
    return -1;
}

ssize_t write(int fd, const void *buf, size_t count) {
    if (fd == 1 || fd == 2) {
        return bunix_write(fd, buf, count);
    }
    return -1;
}

int close(int fd) {
    return 0;
}