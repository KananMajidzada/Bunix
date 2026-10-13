// sys/mman.h - mapping memory.
//
// Bunix maps for a process by asking the kernel for pages, so mmap here is a
// plain allocation and the protection bits are not checked. That is enough
// for a program that maps a file and reads it, which is the common case.

#ifndef BUNIX_SYS_MMAN_H
#define BUNIX_SYS_MMAN_H

#include <stddef.h>
#include <sys/types.h>

#define PROT_NONE   0x0
#define PROT_READ   0x1
#define PROT_WRITE  0x2
#define PROT_EXEC   0x4

#define MAP_SHARED    0x01
#define MAP_PRIVATE   0x02
#define MAP_FIXED     0x10
#define MAP_ANONYMOUS 0x20
#define MAP_ANON      0x20
#define MAP_FAILED    ((void *) -1)
#define MAP_SUCCESS   0

#define MADV_NORMAL     0
#define MADV_RANDOM     1
#define MADV_SEQUENTIAL 2
#define MADV_WILLNEED   3
#define MADV_DONTNEED   4

void *mmap(void *addr, size_t len, int prot, int flags, int fd, off_t off);
int munmap(void *addr, size_t len);
int mprotect(void *addr, size_t len, int prot);
int madvise(void *addr, size_t len, int advice);

#endif
