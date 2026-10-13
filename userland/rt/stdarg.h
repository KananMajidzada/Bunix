// stdarg.h - variable argument lists.
//
// The target is x86-64, where the compiler's own builtin has the right shape,
// so this only has to hand it through. A compiler built for Bunix (tcc) ships
// its own copy of this header for the code it compiles; this one is for code
// compiled by bcc.

#ifndef BUNIX_STDARG_H
#define BUNIX_STDARG_H

typedef __builtin_va_list va_list;
typedef va_list __gnuc_va_list;

#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_end(ap)         __builtin_va_end(ap)
#define va_arg(ap, type)   __builtin_va_arg(ap, type)
#define va_copy(dst, src)  __builtin_va_copy(dst, src)

#define _VA_LIST_DEFINED
#define __GNUC_VA_LIST

#endif
