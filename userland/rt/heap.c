// heap.c - malloc/free for Bunix C programs

#include <stddef.h>
#include <stdint.h>
#include "syscalls.h"

#define ALIGN 16
#define CHUNK (256 * 1024)
#define PAGESZ 4096

typedef struct block {
    size_t sz;
    struct block *next;
} block_t;

static block_t *free_head = NULL;
static uint8_t *cur = NULL;
static uint8_t *end = NULL;

static size_t align_up(size_t n) {
    return (n + ALIGN - 1) & ~(ALIGN - 1);
}

static int grow(size_t min) {
    size_t want = min < CHUNK ? CHUNK : min;
    size_t pages = (want + PAGESZ - 1) / PAGESZ;
    uint8_t *base = (uint8_t*)syscall1(SYS_ALLOC, pages);
    if (!base) return 0;
    cur = base;
    end = base + pages * PAGESZ;
    return 1;
}

void *malloc(size_t n) {
    if (n == 0) n = ALIGN;
    size_t need = align_up(n) + sizeof(block_t);

    block_t **prev = &free_head;
    block_t *b = free_head;
    while (b) {
        if (b->sz >= need - sizeof(block_t)) {
            *prev = b->next;
            return (void*)(b + 1);
        }
        prev = &b->next;
        b = b->next;
    }

    if (!cur || cur + need > end) {
        if (!grow(need)) return NULL;
    }

    b = (block_t*)cur;
    b->sz = need - sizeof(block_t);
    cur += need;
    return (void*)(b + 1);
}

void free(void *p) {
    if (!p) return;
    block_t *b = (block_t*)p - 1;
    b->next = free_head;
    free_head = b;
}

void *realloc(void *p, size_t n) {
    if (!p) return malloc(n);
    if (n == 0) { free(p); return NULL; }
    block_t *b = (block_t*)p - 1;
    if (b->sz >= n) return p;
    void *np = malloc(n);
    if (!np) return NULL;
    // simple memcpy
    char *dst = np, *src = p;
    for (size_t i = 0; i < b->sz; i++) dst[i] = src[i];
    free(p);
    return np;
}