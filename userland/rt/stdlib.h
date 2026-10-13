// stdlib.h - allocation, conversion and process control.

#ifndef BUNIX_STDLIB_H
#define BUNIX_STDLIB_H

#include <stddef.h>

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1

#define RAND_MAX 0x7fffffff

typedef struct { int quot; int rem; } div_t;
typedef struct { long quot; long rem; } ldiv_t;

void *malloc(size_t n);
void *calloc(size_t nmemb, size_t sz);
void *realloc(void *p, size_t n);
void free(void *p);

void exit(int code) __attribute__((noreturn));
void _Exit(int code) __attribute__((noreturn));
void abort(void) __attribute__((noreturn));

int atoi(const char *s);
long atol(const char *s);
long strtol(const char *s, char **end, int base);
unsigned long strtoul(const char *s, char **end, int base);

int abs(int n);
long labs(long n);
div_t div(int num, int den);

int rand(void);
void srand(unsigned seed);

char *getenv(const char *name);
int system(const char *cmd);

void qsort(void *base, size_t n, size_t sz, int (*cmp)(const void *, const void *));
void *bsearch(const void *key, const void *base, size_t n, size_t sz,
              int (*cmp)(const void *, const void *));

#endif