// sys/stat.h - the stat family. Bunix files are flat and untyped on disk, so
// only the size and the directory bit are real; the rest is filled with
// something plausible so callers see a sane struct.

#ifndef BUNIX_SYS_STAT_H
#define BUNIX_SYS_STAT_H

#include <stddef.h>
#include <sys/types.h>
#include <unistd.h>

#define S_IFMT   0170000
#define S_IFREG  0100000
#define S_IFDIR  0040000
#define S_IFCHR  0020000
#define S_IFBLK  0060000
#define S_IFIFO  0010000
#define S_IFLNK  0120000
#define S_IFSOCK 0140000

#define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
#define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)

typedef struct {
    ino_t st_ino;
    mode_t st_mode;
    nlink_t st_nlink;
    uid_t st_uid;
    gid_t st_gid;
    off_t st_size;
    time_t st_atime;
    time_t st_mtime;
    time_t st_ctime;
} stat_t;

typedef stat_t struct_stat;

int stat(const char *path, stat_t *st);
int fstat(int fd, stat_t *st);
int mkdir(const char *path, int mode);

#endif