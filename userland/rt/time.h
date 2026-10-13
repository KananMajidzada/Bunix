// time.h - clocks. Bunix has no hardware timer, so time comes from /proc/uptime,
// which the kernel derives from its tick counter.

#ifndef BUNIX_TIME_H
#define BUNIX_TIME_H

#include <stddef.h>

typedef long clock_t;
typedef long suseconds_t;

#define CLOCKS_PER_SEC 100

typedef struct {
    time_t tv_sec;
    suseconds_t tv_usec;
} timeval_t;

typedef struct {
    int tm_sec, tm_min, tm_hour;
    int tm_mday, tm_mon, tm_year;
    int tm_wday, tm_yday, tm_isdst;
} struct_tm;

time_t time(time_t *t);
int gettimeofday(timeval_t *tv, void *tz);
clock_t clock(void);
struct_tm *gmtime(const time_t *t);
struct_tm *localtime(const time_t *t);
size_t strftime(char *buf, size_t n, const char *fmt, const struct_tm *tm);

#endif