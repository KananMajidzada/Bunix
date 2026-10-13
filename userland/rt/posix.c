// posix.c - POSIX file and directory calls for the Bunix C runtime.
//
// The kernel hands a whole file over in one read and takes it back in one
// write, so a descriptor here is a buffer plus a cursor: open slurps the file,
// read and lseek move over the buffer, close flushes it back if it is writable.
// Same trade as the Hare shim in userland/posix, kept so a ported program sees
// the ordinary open/read/write/close shape.

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <time.h>
#include <sys/mman.h>
#include <string.h>
#include <stdlib.h>
#include "syscalls.h"

#define NFD 16
#define PAGESZ 4096
#define BUFCAP 65536

typedef struct {
    int used;
    int wronly;
    int isdir;
    uint64_t base;
    size_t length;
    size_t cursor;
    char path[256];
} slot_t;

static slot_t slots[NFD];

// A descriptor is three small integers plus a fixed window of the file. The
// base is found by linear search, which is fine at NFD.
static int slot(void) {
    for (int i = 3; i < NFD; i++) {
        if (!slots[i].used) return i;
    }
    return -1;
}

static int valid(int fd) {
    return fd >= 0 && fd < NFD && slots[fd].used;
}

// Both /proc/uptime and directory listings are small, so a fixed page is
// enough for either.
static size_t small_read(const char *path, void *buf, size_t n) {
    long r = bunix_readfile(path, buf, n);
    return r < 0 ? 0 : (size_t)r;
}

int open(const char *p, int flags, ...) {
    int i = slot();
    if (i < 0) return -1;

    slots[i].used = 1;
    slots[i].wronly = (flags & (O_WRONLY | O_RDWR)) != 0;
    slots[i].isdir = 0;
    slots[i].cursor = 0;
    slots[i].length = 0;

    size_t n = strlen(p);
    if (n >= sizeof(slots[i].path)) {
        slots[i].used = 0;
        return -1;
    }
    memcpy(slots[i].path, p, n + 1);

    if (slots[i].wronly) {
        // A writer starts empty, except when it is appending to what is
        // already there.
        uint8_t *buf = malloc(BUFCAP);
        if (!buf) { slots[i].used = 0; return -1; }
        slots[i].base = (uint64_t)buf;
        slots[i].length = (flags & O_APPEND) ? small_read(p, buf, BUFCAP) : 0;
        slots[i].cursor = (flags & O_APPEND) ? slots[i].length : 0;
        if ((flags & O_CREAT) && !slots[i].length) {
            bunix_create(p, 0);
        }
        return i;
    }

    uint8_t *buf = malloc(BUFCAP);
    if (!buf) { slots[i].used = 0; return -1; }
    slots[i].base = (uint64_t)buf;
    slots[i].length = small_read(p, buf, BUFCAP);
    return i;
}

int creat(const char *p, int mode) {
    return open(p, O_WRONLY | O_CREAT | O_TRUNC, mode);
}

ssize_t read(int fd, void *buf, size_t count) {
    if (fd == STDIN_FILENO) {
        // Line at a time, the way the console hands characters over.
        char *p = (char *)buf;
        size_t n = 0;
        while (n < count) {
            int c = bunix_readchr();
            if (c <= 0) { bunix_yield(); continue; }
            p[n++] = (char)c;
            if (c == '\n') break;
        }
        return (ssize_t)n;
    }
    if (!valid(fd) || slots[fd].wronly) return -1;

    size_t n = slots[fd].length - slots[fd].cursor;
    if (n > count) n = count;
    memcpy(buf, (const void *)(slots[fd].base + slots[fd].cursor), n);
    slots[fd].cursor += n;
    return (ssize_t)n;
}

ssize_t write(int fd, const void *buf, size_t count) {
    if (fd == STDOUT_FILENO || fd == STDERR_FILENO) {
        return (ssize_t)bunix_write(buf, count);
    }
    if (!valid(fd) || !slots[fd].wronly) return -1;

    // A write lands at the cursor, not at the end. Seeking past the end and
    // writing there is how a program lays out a file with holes in it, which
    // is exactly what an ELF writer does; the gap reads back as zeroes.
    uint8_t *dst = (uint8_t *)slots[fd].base;
    if (slots[fd].cursor > slots[fd].length) {
        size_t gap = slots[fd].cursor - slots[fd].length;
        if (slots[fd].cursor > BUFCAP) return -1;
        memset(dst + slots[fd].length, 0, gap);
        slots[fd].length = slots[fd].cursor;
    }

    size_t n = 0;
    while (n < count && slots[fd].cursor < BUFCAP) {
        dst[slots[fd].cursor++] = ((const uint8_t *)buf)[n++];
    }
    if (slots[fd].cursor > slots[fd].length) slots[fd].length = slots[fd].cursor;
    return (ssize_t)n;
}

int close(int fd) {
    if (!valid(fd)) return -1;
    if (slots[fd].wronly) {
        bunix_writefile(slots[fd].path,
                        (const void *)slots[fd].base, slots[fd].length);
    }
    free((void *)slots[fd].base);
    slots[fd].used = 0;
    return 0;
}

long lseek(int fd, long off, int whence) {
    if (!valid(fd)) return -1;
    long n;
    if (whence == SEEK_SET) {
        n = off;
    } else if (whence == SEEK_CUR) {
        n = (long)slots[fd].cursor + off;
    } else if (whence == SEEK_END) {
        n = (long)slots[fd].length + off;
    } else {
        return -1;
    }
    if (n < 0) return -1;
    // Seeking past the end is allowed on a writer; the gap only becomes part
    // of the file once something is written there.
    if (!slots[fd].wronly && (size_t)n > slots[fd].length) {
        n = (long)slots[fd].length;
    }
    slots[fd].cursor = (size_t)n;
    return n;
}

int fstat(int fd, stat_t *st) {
    if (fd == STDIN_FILENO || fd == STDOUT_FILENO || fd == STDERR_FILENO) {
        memset(st, 0, sizeof(*st));
        st->st_mode = S_IFCHR;
        return 0;
    }
    if (!valid(fd)) return -1;
    memset(st, 0, sizeof(*st));
    st->st_mode = S_IFREG;
    st->st_size = (off_t)slots[fd].length;
    return 0;
}

int stat(const char *path, stat_t *st) {
    memset(st, 0, sizeof(*st));
    st->st_mode = S_IFREG;

    uint8_t probe[1];
    long n = bunix_readfile(path, probe, 1);
    if (n < 0) {
        // Not readable as a file; it may still be a directory.
        uint8_t names[512];
        long d = bunix_readdir(path, names, sizeof(names));
        if (d < 0) return -1;
        st->st_mode = S_IFDIR;
        return 0;
    }

    // Ask for the whole thing so the size comes out right.
    uint8_t *buf = malloc(BUFCAP);
    if (!buf) return -1;
    size_t len = small_read(path, buf, BUFCAP);
    free(buf);
    st->st_size = (off_t)len;
    return 0;
}

int ftruncate(int fd, off_t len) {
    if (!valid(fd)) return -1;
    if ((size_t)len < slots[fd].length) slots[fd].length = (size_t)len;
    return 0;
}

int unlink(const char *path) {
    return bunix_remove(path) ? 0 : -1;
}

// POSIX puts both spellings in circulation.
int remove(const char *path) { return unlink(path); }

int mkdir(const char *path, int mode) {
    return bunix_create(path, 1) ? 0 : -1;
}

int rmdir(const char *path) {
    return bunix_remove(path) ? 0 : -1;
}

int access(const char *path, int mode) {
    uint8_t probe[1];
    long n = bunix_readfile(path, probe, 1);
    if (n >= 0) return 0;
    uint8_t names[512];
    long d = bunix_readdir(path, names, sizeof(names));
    return d < 0 ? -1 : 0;
}

int isatty(int fd) {
    return (fd >= 0 && fd <= 2);
}

int dup(int fd) { return -1; }

char *getcwd(char *buf, size_t n) {
    // Every process sees one namespace rooted at /, so there is nowhere else
    // to be.
    const char *cwd = "/";
    size_t len = strlen(cwd);
    if (!buf || n < len + 1) return NULL;
    memcpy(buf, cwd, len + 1);
    return buf;
}

int chdir(const char *path) { return 0; }

pid_t getpid(void) { return 1; }

int sleep(unsigned secs) {
    unsigned i;
    for (i = 0; i < secs; i++) bunix_yield();
    return 0;
}

int usleep(unsigned usecs) {
    bunix_yield();
    return 0;
}

// Directories. The kernel lists names one per line, so readdir walks the
// string it was handed and hands back one line at a time.
struct _DIR {
    char *names;
    size_t length;
    size_t off;
    dirent_t ent;
};

DIR *opendir(const char *name) {
    char *names = malloc(4096);
    if (!names) return NULL;

    long n = bunix_readdir(name, names, 4095);
    if (n < 0) {
        free(names);
        return NULL;
    }
    names[n] = 0;

    DIR *d = malloc(sizeof(DIR));
    if (!d) { free(names); return NULL; }
    d->names = names;
    d->length = (size_t)n;
    d->off = 0;
    return d;
}

dirent_t *readdir(DIR *d) {
    if (!d || d->off >= d->length) return NULL;

    size_t start = d->off;
    size_t i = start;
    while (i < d->length && d->names[i] != '\n') i++;

    size_t len = i - start;
    size_t k = 0;
    while (k < len && k < NAME_MAX - 1) {
        d->ent.d_name[k] = d->names[start + k];
        k++;
    }
    d->ent.d_name[k] = 0;
    d->ent.d_ino = 0;
    d->ent.d_reclen = (unsigned short)len;

    d->off = (i < d->length) ? i + 1 : d->length;
    return &d->ent;
}

int closedir(DIR *d) {
    if (!d) return -1;
    free(d->names);
    free(d);
    return 0;
}

void rewinddir(DIR *d) {
    if (d) d->off = 0;
}

long telldir(DIR *d) {
    return d ? (long)d->off : -1;
}

void seekdir(DIR *d, long pos) {
    if (d && pos >= 0 && (size_t)pos <= d->length) d->off = (size_t)pos;
}

// Time. The kernel counts ticks and publishes them as /proc/uptime, so that
// decimal string is the only clock there is.
static uint64_t uptime_ticks(void) {
    char buf[32];
    size_t n = small_read("/proc/uptime", buf, sizeof(buf) - 1);
    uint64_t v = 0;
    size_t i = 0;
    while (i < n) {
        char c = buf[i];
        if (c < '0' || c > '9') break;
        v = v * 10 + (uint64_t)(c - '0');
        i++;
    }
    return v;
}

time_t time(time_t *t) {
    time_t v = (time_t)uptime_ticks();
    if (t) *t = v;
    return v;
}

int gettimeofday(struct timeval *tv, void *tz) {
    uint64_t v = uptime_ticks();
    if (tv) {
        tv->tv_sec = (time_t)v;
        tv->tv_usec = 0;
    }
    return 0;
}

clock_t clock(void) {
    return (clock_t)uptime_ticks();
}

struct tm *gmtime(const time_t *t) {
    static struct tm tm;
    time_t v = t ? *t : 0;
    long days = (long)v / 86400;
    long secs = (long)v % 86400;

    // Days since 1970-01-01 to a weekday and a day of the year.
    tm.tm_wday = (int)((days + 4) % 7);
    tm.tm_yday = (int)(days % 365);
    tm.tm_hour = (int)(secs / 3600);
    tm.tm_min = (int)((secs / 60) % 60);
    tm.tm_sec = (int)(secs % 60);
    tm.tm_mday = 1;
    tm.tm_mon = 0;
    tm.tm_year = 70;
    tm.tm_isdst = 0;
    return &tm;
}

struct tm *localtime(const time_t *t) {
    return gmtime(t);
}

size_t strftime(char *buf, size_t n, const char *fmt, const struct tm *tm) {
    size_t w = 0;
    const char *p = fmt;

    while (*p && w < n) {
        if (*p != '%') {
            buf[w++] = *p++;
            continue;
        }
        p++;
        if (*p == '\0') break;

        char tmp[32];
        size_t len = 0;
        switch (*p) {
        case 'Y': len = 0; tmp[len++] = (char)('0' + (tm->tm_year / 100) % 10);
                  tmp[len++] = (char)('0' + (tm->tm_year / 10) % 10);
                  tmp[len++] = (char)('0' + tm->tm_year % 10); break;
        case 'm': if (tm->tm_mon < 9) tmp[len++] = '0';
                  tmp[len++] = (char)('0' + (tm->tm_mon + 1) % 10); break;
        case 'd': if (tm->tm_mday < 10) tmp[len++] = '0';
                  tmp[len++] = (char)('0' + tm->tm_mday % 10); break;
        case 'H': if (tm->tm_hour < 10) tmp[len++] = '0';
                  tmp[len++] = (char)('0' + tm->tm_hour / 10 % 10);
                  tmp[len++] = (char)('0' + tm->tm_hour % 10); break;
        case 'M': if (tm->tm_min < 10) tmp[len++] = '0';
                  tmp[len++] = (char)('0' + tm->tm_min / 10 % 10);
                  tmp[len++] = (char)('0' + tm->tm_min % 10); break;
        case 'S': if (tm->tm_sec < 10) tmp[len++] = '0';
                  tmp[len++] = (char)('0' + tm->tm_sec / 10 % 10);
                  tmp[len++] = (char)('0' + tm->tm_sec % 10); break;
        case '%': tmp[len++] = '%'; break;
        default: tmp[len++] = *p; break;
        }

        for (size_t i = 0; i < len && w < n; i++) buf[w++] = tmp[i];
        p++;
    }
    if (w < n) buf[w] = 0;
    return w;
}

int system(const char *cmd) { return -1; }

// Mapping. The kernel hands out whole pages for a process, so a mapping is a
// request for them; the protection bits are not enforced because there is
// nothing to enforce them against.
void *mmap(void *addr, size_t len, int prot, int flags, int fd, off_t off) {
    (void)addr; (void)prot; (void)flags; (void)fd; (void)off;
    if (!len) return MAP_FAILED;
    size_t pages = (len + PAGESZ - 1) / PAGESZ;
    uint8_t *p = bunix_alloc(pages);
    return p ? (void *)p : MAP_FAILED;
}

int munmap(void *addr, size_t len) { (void)addr; (void)len; return 0; }

int madvise(void *addr, size_t len, int advice) {
    (void)addr; (void)len; (void)advice;
    return 0;
}

int mlock(void *addr, size_t len) { (void)addr; (void)len; return 0; }
int munlock(void *addr, size_t len) { (void)addr; (void)len; return 0; }