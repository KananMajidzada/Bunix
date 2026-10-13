// fcntl.h - open flags and the open call itself.

#ifndef BUNIX_FCNTL_H
#define BUNIX_FCNTL_H

#include <stddef.h>

#define O_RDONLY 0x0000
#define O_WRONLY 0x0001
#define O_RDWR   0x0002
#define O_CREAT  0x0040
#define O_TRUNC  0x0200
#define O_APPEND 0x0400
#define O_EXCL   0x0800

#define F_OK 0
#define X_OK 1
#define W_OK 2
#define R_OK 4

int open(const char *path, int flags, ...);
int creat(const char *path, int mode);

#endif