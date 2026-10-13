// assert.h - assertions that compile out under NDEBUG.

#ifndef BUNIX_ASSERT_H
#define BUNIX_ASSERT_H

void __assert_fail(const char *expr, const char *file, int line);

#ifdef NDEBUG
#define assert(e) ((void)0)
#else
#define assert(e) ((e) ? (void)0 : __assert_fail(#e, __FILE__, __LINE__))
#endif

#endif
