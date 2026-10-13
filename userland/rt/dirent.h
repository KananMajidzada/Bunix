// dirent.h - directory walking. Bunix directories hold no "." or ".." and are
// not seekable, so a DIR just remembers the listing it was handed.

#ifndef BUNIX_DIRENT_H
#define BUNIX_DIRENT_H

#include <stddef.h>
#include <sys/types.h>

#define NAME_MAX 64

typedef struct {
    ino_t d_ino;
    unsigned short d_reclen;
    char d_name[NAME_MAX];
} dirent_t;

typedef struct _DIR DIR;

DIR *opendir(const char *path);
dirent_t *readdir(DIR *d);
int closedir(DIR *d);
void rewinddir(DIR *d);
long telldir(DIR *d);
void seekdir(DIR *d, long pos);

#endif