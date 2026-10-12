// C syscall wrappers for Bunix

#ifndef BUNIX_SYSCALLS_H
#define BUNIX_SYSCALLS_H

#include <stddef.h>
#include <stdint.h>

typedef long ssize_t;

#define SYS_EXIT       0
#define SYS_WRITE      1
#define SYS_READFILE   2
#define SYS_ALLOC      3
#define SYS_WRITEFILE  4
#define SYS_READCHR    5
#define SYS_YIELD      6
#define SYS_CREATE     7
#define SYS_REMOVE     8
#define SYS_READFILE   2
#define SYS_REaddir    9
#define SYS_HALT      10
#define SYS_SPAWN     11
#define SYS_ALIVE     12
#define SYS_FRESH     13
#define SYS_SPAWN_SHARED 14

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

static inline void bunix_exit(int code) {
    syscall1(SYS_EXIT, code);
}

static inline ssize_t bunix_write(int fd, const void *buf, size_t count) {
    return syscall3(SYS_WRITE, fd, (uint64_t)buf, count);
}

static inline ssize_t bunix_readfile(const char *path, void *buf, size_t count) {
    return syscall3(SYS_READFILE, (uint64_t)path, (uint64_t)buf, count);
}

static inline ssize_t bunix_writefile(const char *path, const void *buf, size_t count) {
    return syscall3(SYS_WRITEFILE, (uint64_t)path, (uint64_t)buf, count);
}

static inline int bunix_readchr(void) {
    return syscall0(SYS_READCHR);
}

static inline void bunix_yield(void) {
    syscall0(SYS_YIELD);
}

static inline int bunix_create(const char *path, int isdir) {
    return syscall2(SYS_CREATE, (uint64_t)path, isdir);
}

static inline int bunix_remove(const char *path) {
    return syscall1(SYS_REMOVE, (uint64_t)path);
}

static inline int bunix_readdir(const char *path, void *buf, size_t count) {
    return syscall3(SYS_REaddir, (uint64_t)path, (uint64_t)buf, count);
}

static inline uint64_t bunix_spawn(const char *path) {
    return syscall2(SYS_SPAWN, (uint64_t)path, 0);
}

static inline uint64_t bunix_spawn_shared(const char *path) {
    return syscall2(SYS_SPAWN_SHARED, (uint64_t)path, 0);
}

static inline int bunix_alive(uint64_t id) {
    return syscall1(SYS_ALIVE, id);
}

static inline int bunix_fresh(void) {
    return syscall0(SYS_FRESH);
}

static inline void bunix_halt(void) {
    syscall0(SYS_HALT);
}

#endif