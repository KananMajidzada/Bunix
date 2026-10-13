// heap.c - malloc/free for Bunix C programs
//
// A bump allocator over pages handed out by the kernel, with freed blocks
// threaded onto a free list. Blocks keep their size, so free is O(1) and
// realloc can tell whether the block is already big enough.

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include "syscalls.h"

#define ALIGN 16
#define CHUNK (256 * 1024)
#define PAGESZ 4096

typedef struct block {
    size_t sz;
    struct block *next;
} block_t;

static block_t *free_head;
static uint8_t *cur;
static uint8_t *end;

static size_t align_up(size_t n) {
    return (n + ALIGN - 1) & ~(size_t)(ALIGN - 1);
}

static int grow(size_t min) {
    size_t want = min < CHUNK ? CHUNK : min;
    size_t pages = (want + PAGESZ - 1) / PAGESZ;
    uint8_t *base = bunix_alloc(pages);
    if (!base) return 0;
    cur = base;
    end = base + pages * PAGESZ;
    return 1;
}

void *malloc(size_t n) {
    if (!n) n = ALIGN;
    size_t need = align_up(n) + sizeof(block_t);

    // Reuse the first free block that is large enough, splitting it if there
    // is a worthwhile remainder.
    block_t **prev = &free_head;
    block_t *b = free_head;
    while (b) {
        if (b->sz >= n) {
            *prev = b->next;
            return (void *)(b + 1);
        }
        block_t *next = b->next;
        if (b->sz >= n + sizeof(block_t) + ALIGN) {
            // Cut the tail off as a new free block.
            block_t *rest = (block_t *)((char *)b + sizeof(block_t) + align_up(n));
            rest->sz = b->sz - align_up(n) - sizeof(block_t);
            rest->next = b->next;
            *prev = rest;
            b->sz = align_up(n);
            return (void *)(b + 1);
        }
        prev = &b->next;
        b = next;
    }

    if (!cur || cur + need > end) {
        if (!grow(need)) return NULL;
    }

    b = (block_t *)cur;
    b->sz = need - sizeof(block_t);
    cur += need;
    return (void *)(b + 1);
}

void free(void *p) {
    if (!p) return;
    block_t *b = (block_t *)p - 1;
    b->next = free_head;
    free_head = b;
}

void *calloc(size_t nmemb, size_t sz) {
    size_t total = nmemb * sz;
    if (nmemb && total / nmemb != sz) return NULL;   // overflow
    void *p = malloc(total);
    if (p) memset(p, 0, total);
    return p;
}

void *realloc(void *p, size_t n) {
    if (!p) return malloc(n);
    if (!n) { free(p); return NULL; }

    block_t *b = (block_t *)p - 1;
    if (b->sz >= n) return p;

    void *np = malloc(n);
    if (!np) return NULL;
    memcpy(np, p, b->sz);
    free(p);
    return np;
}

char *getenv(const char *name) { return NULL; }