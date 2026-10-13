// unistd.h - the POSIX calls the Bunix C runtime provides.

#ifndef BUNIX_UNISTD_H
#define BUNIX_UNISTD_H

#include <stddef.h>
#include <stdint.h>

#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2

typedef long ssize_t;
typedef int pid_t;

ssize_t read(int fd, void *buf, size_t n);
ssize_t write(int fd, const void *buf, size_t n);
int close(int fd);
long lseek(int fd, long off, int whence);
int unlink(const char *path);
int rmdir(const char *path);
int access(const char *path, int mode);
int execvp(const char *file, char *const argv[]);
char *getenv(const char *name);
int isatty(int fd);
int dup(int fd);
char *getcwd(char *buf, size_t n);
int chdir(const char *path);
void _exit(int code) __attribute__((noreturn));
pid_t getpid(void);
int sleep(unsigned secs);
int usleep(unsigned usecs);
void *sbrk(intptr_t inc);

#endif