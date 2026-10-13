// stddef.h - the types every C program expects.

#ifndef BUNIX_STDDEF_H
#define BUNIX_STDDEF_H

typedef unsigned long size_t;
typedef long ptrdiff_t;
typedef int wchar_t;
typedef long double max_align_t;

#define NULL ((void *)0)

#define offsetof(type, member) ((size_t) & (((type *)0)->member))

#endif
