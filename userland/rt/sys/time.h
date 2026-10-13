// sys/time.h - timeval and the calls that take one.

#ifndef BUNIX_SYS_TIME_H
#define BUNIX_SYS_TIME_H

#include <sys/types.h>

struct timeval {
    time_t tv_sec;
    suseconds_t tv_usec;
};

int gettimeofday(struct timeval *tv, void *tz);

#endif
