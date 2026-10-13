// time.h - clocks and calendar conversion.
//
// Bunix has no hardware timer. The kernel counts ticks and publishes them as
// /proc/uptime, so that decimal string is the only clock there is, and every
// time value here is seconds since boot.

#ifndef BUNIX_TIME_H
#define BUNIX_TIME_H

#include <stddef.h>
#include <sys/types.h>

typedef long clock_t;
typedef long suseconds_t;

#define CLOCKS_PER_SEC 100

struct tm {
    int tm_sec, tm_min, tm_hour;
    int tm_mday, tm_mon, tm_year;
    int tm_wday, tm_yday, tm_isdst;
    long tm_gmtoff;
    const char *tm_zone;
};

struct timeval {
    time_t tv_sec;
    suseconds_t tv_usec;
};

struct timespec {
    time_t tv_sec;
    long tv_nsec;
};

time_t time(time_t *t);
int gettimeofday(struct timeval *tv, void *tz);
clock_t clock(void);
struct tm *gmtime(const time_t *t);
struct tm *localtime(const time_t *t);
time_t mktime(struct tm *tm);
size_t strftime(char *buf, size_t n, const char *fmt, const struct tm *tm);

double difftime(time_t a, time_t b);

#endif
