// syscalls.h - direct interface to Bunix's native system calls.
//
// The native calls do not follow POSIX. In particular a path always arrives as
// a pointer and a separate length, because the kernel reads the length out of
// the register rather than walking for a NUL. These wrappers take that shape
// and hide it, so callers can hand over an ordinary C string.
//
// Register use is rax for the call number, rdi/rsi/rdx/rcx for the arguments,
// and rax for the result.

#ifndef BUNIX_SYSCALLS_H
#define BUNIX_SYSCALLS_H

#include <stddef.h>
#include <stdint.h>

typedef long ssize_t;

#define SYS_EXIT        0
#define SYS_WRITE       1
#define SYS_READFILE    2
#define SYS_ALLOC       3
#define SYS_WRITEFILE   4
#define SYS_READCHR     5
#define SYS_YIELD       6
#define SYS_CREATE      7
#define SYS_REMOVE      8
#define SYS_REaddir     9
#define SYS_HALT        10
#define SYS_SPAWN       11
#define SYS_ALIVE       12
#define SYS_FRESH       13
#define SYS_SPAWN_SHARED 14
#define SYS_APPEND      15
#define SYS_STAT        16
#define SYS_SCREEN      17
#define SYS_CHDIR       18
#define SYS_PWD         19
#define SYS_PS          20
#define SYS_KILL        21
#define SYS_READAT      22
#define SYS_WRITEAT     23
#define SYS_REDIRECT    24

static inline uint64_t syscall0(uint64_t n) {
    uint64_t ret;
    __asm__ volatile ("int $0x80" : "=a"(ret) : "a"(n) : "rcx", "r11", "memory");
    return ret;
}

static inline uint64_t syscall1(uint64_t n, uint64_t a1) {
    uint64_t ret;
    __asm__ volatile ("int $0x80" : "=a"(ret) : "a"(n), "D"(a1) : "rcx", "r11", "memory");
    return ret;
}

static inline uint64_t syscall2(uint64_t n, uint64_t a1, uint64_t a2) {
    uint64_t ret;
    __asm__ volatile ("int $0x80" : "=a"(ret) : "a"(n), "D"(a1), "S"(a2) : "rcx", "r11", "memory");
    return ret;
}

static inline uint64_t syscall3(uint64_t n, uint64_t a1, uint64_t a2, uint64_t a3) {
    uint64_t ret;
    __asm__ volatile ("int $0x80" : "=a"(ret) : "a"(n), "D"(a1), "S"(a2), "d"(a3) : "rcx", "r11", "memory");
    return ret;
}

static inline uint64_t syscall4(uint64_t n, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4) {
    uint64_t ret;
    __asm__ volatile ("int $0x80" : "=a"(ret) : "a"(n), "D"(a1), "S"(a2), "d"(a3), "c"(a4) : "r11", "memory");
    return ret;
}

// The fifth argument rides in r8, which no constraint names, so a register
// variable pins it there.
static inline uint64_t syscall5(uint64_t n, uint64_t a1, uint64_t a2,
                                uint64_t a3, uint64_t a4, uint64_t a5) {
    register uint64_t r8 __asm__("r8") = a5;
    uint64_t ret;
    __asm__ volatile ("int $0x80" : "=a"(ret)
                      : "a"(n), "D"(a1), "S"(a2), "d"(a3), "c"(a4), "r"(r8)
                      : "r11", "memory");
    return ret;
}

// Paths cross the boundary as (pointer, length), so the wrappers need the
// length without depending on the C library.
static inline uint64_t path_len(const char *p) {
    uint64_t n = 0;
    while (p[n]) n++;
    return n;
}

static inline void bunix_exit(int code) {
    syscall1(SYS_EXIT, code);
}

// To the console. There is no descriptor on the native side.
static inline ssize_t bunix_write(const void *buf, size_t len) {
    return (ssize_t)syscall2(SYS_WRITE, (uint64_t)buf, len);
}

static inline ssize_t bunix_readfile(const char *path, void *buf, size_t count) {
    uint64_t n = path_len(path);
    return (ssize_t)syscall4(SYS_READFILE, (uint64_t)path, n, (uint64_t)buf, count);
}

static inline ssize_t bunix_writefile(const char *path, const void *buf, size_t count) {
    uint64_t n = path_len(path);
    return (ssize_t)syscall4(SYS_WRITEFILE, (uint64_t)path, n, (uint64_t)buf, count);
}

static inline ssize_t bunix_appendfile(const char *path, const void *buf, size_t count) {
    uint64_t n = path_len(path);
    return (ssize_t)syscall4(SYS_APPEND, (uint64_t)path, n, (uint64_t)buf, count);
}

// Reads count bytes of a file starting at byte offset off. What a file makes
// of the offset is the file's own business: /dev/fb takes it as a pixel
// position, and /dev/kbd is a queue and goes no further.
static inline ssize_t bunix_readat(const char *path, uint64_t off,
                                   void *buf, size_t count) {
    uint64_t n = path_len(path);
    return (ssize_t)syscall5(SYS_READAT, (uint64_t)path, n, (uint64_t)buf, count, off);
}

// Writes count bytes at byte offset off.
static inline ssize_t bunix_writeat(const char *path, uint64_t off,
                                    const void *buf, size_t count) {
    uint64_t n = path_len(path);
    return (ssize_t)syscall5(SYS_WRITEAT, (uint64_t)path, n, (uint64_t)buf, count, off);
}

// Sends the output of this process to a file instead of the console. Mode 1
// empties the file first, mode 2 adds to it, and mode 0 puts the output
// back on the console.
static inline int bunix_redirect(const char *path, int mode) {
    uint64_t n = path_len(path);
    return (int)syscall3(SYS_REDIRECT, (uint64_t)path, n, (uint64_t)mode);
}

// Size and type of a path without reading it: mode 1 means a directory.
struct bunix_stat {
    uint64_t size;
    uint32_t mode;
};

// The console size, so a program can fit itself to the screen.
static inline int bunix_screen(uint32_t *rows, uint32_t *cols) {
    return (int)syscall2(SYS_SCREEN, (uint64_t)rows, (uint64_t)cols);
}

static inline int bunix_stat(const char *path, struct bunix_stat *st) {
    uint64_t n = path_len(path);
    return (int)syscall4(SYS_STAT, (uint64_t)path, n,
                         (uint64_t)&st->size, (uint64_t)&st->mode);
}

static inline int bunix_readdir(const char *path, void *buf, size_t count) {
    uint64_t n = path_len(path);
    return (int)syscall4(SYS_REaddir, (uint64_t)path, n, (uint64_t)buf, count);
}

static inline int bunix_create(const char *path, int isdir) {
    uint64_t n = path_len(path);
    return (int)syscall3(SYS_CREATE, (uint64_t)path, n, isdir);
}

static inline int bunix_remove(const char *path) {
    uint64_t n = path_len(path);
    return (int)syscall2(SYS_REMOVE, (uint64_t)path, n);
}

static inline int bunix_readchr(void) {
    return (int)syscall0(SYS_READCHR);
}

static inline void bunix_yield(void) {
    syscall0(SYS_YIELD);
}

static inline uint8_t *bunix_alloc(uint64_t pages) {
    return (uint8_t *)syscall1(SYS_ALLOC, pages);
}

static inline uint64_t bunix_spawn(const char *path) {
    uint64_t n = path_len(path);
    return syscall2(SYS_SPAWN, (uint64_t)path, n);
}

static inline uint64_t bunix_spawn_shared(const char *path) {
    uint64_t n = path_len(path);
    return syscall2(SYS_SPAWN_SHARED, (uint64_t)path, n);
}

static inline int bunix_alive(uint64_t id) {
    return (int)syscall1(SYS_ALIVE, id);
}

static inline int bunix_fresh(void) {
    return (int)syscall0(SYS_FRESH);
}

static inline void bunix_halt(void) {
    syscall0(SYS_HALT);
}

// The directory the process is in. A relative path is taken from there.
static inline int bunix_chdir(const char *path) {
    uint64_t n = path_len(path);
    return (int)syscall2(SYS_CHDIR, (uint64_t)path, n);
}

// Where the process is. The path is written into the buffer and its length
// is returned, or zero when it does not fit.
static inline size_t bunix_pwd(char *buf, size_t count) {
    return (size_t)syscall2(SYS_PWD, (uint64_t)buf, count);
}

// The processes that are running, one per line.
static inline size_t bunix_ps(char *buf, size_t count) {
    return (size_t)syscall2(SYS_PS, (uint64_t)buf, count);
}

// Stops a process.
static inline int bunix_kill(uint64_t id) {
    return (int)syscall1(SYS_KILL, id);
}

#endif