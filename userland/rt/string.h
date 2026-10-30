// string.h - C string and memory routines for the Bunix C runtime.

#ifndef BUNIX_STRING_H
#define BUNIX_STRING_H

#include <stddef.h>

void *memcpy(void *dst, const void *src, size_t n);
void *memmove(void *dst, const void *src, size_t n);
void *memset(void *dst, int c, size_t n);
int memcmp(const void *a, const void *b, size_t n);
void *memchr(const void *s, int c, size_t n);

char *strcpy(char *dst, const char *src);
char *strncpy(char *dst, const char *src, size_t n);
char *strcat(char *dst, const char *src);
char *strncat(char *dst, const char *src, size_t n);
int strcmp(const char *a, const char *b);
int strcasecmp(const char *a, const char *b);
int strncasecmp(const char *a, const char *b, size_t n);
int strncmp(const char *a, const char *b, size_t n);
int strcoll(const char *a, const char *b);
size_t strxfrm(char *dst, const char *src, size_t n);
char *strchr(const char *s, int c);
char *strrchr(const char *s, int c);
char *strstr(const char *hay, const char *needle);
size_t strspn(const char *s, const char *set);
size_t strcspn(const char *s, const char *set);
char *strpbrk(const char *s, const char *set);
char *strtok(char *s, const char *sep);
size_t strlen(const char *s);
char *strerror(int e);
char *strdup(const char *s);
char *strndup(const char *s, size_t n);

#endif