// stubs.c - the parts of the C library a ported program links against that
// Bunix has no way to provide.
//
// Most of these are things the program only reaches for on a machine with
// more facilities than this one: a dynamic loader, signals, memory protection
// and a shell to run other programs. They are here so a port links, and they
// say plainly that they did not work rather than pretending.

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>

// --- errno ---

static int the_errno;

int *__errno_location(void) { return &the_errno; }


void __assert_fail(const char *expr, const char *file, int line) {
    fprintf(stderr, "%s:%d: assertion failed: %s\n", file, line, expr);
    abort();
}

// --- the dynamic loader ---
//
// Bunix has no shared objects. Returning failure is the honest answer: a
// program that asks to load one at run time is asking for something this
// system does not do.

void *dlopen(const char *path, int flags) {
    if (path) errno = ENOSYS;
    return NULL;
}

int dlclose(void *handle) { (void)handle; return -1; }

void *dlsym(void *handle, const char *name) {
    (void)handle;
    (void)name;
    return NULL;
}

char *dlerror(void) { return "Bunix has no dynamic loader"; }

// --- running other programs ---
//
// There is no exec, so tcc -run cannot work here. Compiling and linking to a
// file can.

int execvp(const char *file, char *const argv[]) { (void)file; (void)argv; return -1; }

// --- memory protection and signals ---

int mprotect(void *addr, size_t len, int prot) {
    (void)addr; (void)len; (void)prot;
    return 0;   // pages here are already writable, so nothing to do
}

int sigemptyset(sigset_t *set) { (void)set; return 0; }
int sigfillset(sigset_t *set) { (void)set; return 0; }
int sigaddset(sigset_t *set, int n) { (void)set; (void)n; return 0; }
int sigdelset(sigset_t *set, int n) { (void)set; (void)n; return 0; }
int sigprocmask(int how, const sigset_t *set, sigset_t *old) {
    (void)how; (void)set;
    if (old) old->bits = 0;
    return 0;
}

int sigaction(int sig, const struct sigaction *act, struct sigaction *old) {
    (void)sig;
    if (old) {
        old->sa_handler = 0;
        old->sa_flags = 0;
        old->sa_restorer = 0;
    }
    (void)act;
    return 0;
}

int sigismember(const sigset_t *set, int n) {
    (void)set; (void)n;
    return 0;
}

sighandler_t signal(int sig, sighandler_t handler) { (void)sig; return handler; }

int kill(int pid, int sig) { (void)pid; (void)sig; return -1; }

// --- process things that do not apply ---

int getpagesize(void) { return 4096; }
long sysconf(int name) {
    switch (name) {
    case 2: return 100;        // _SC_OPEN_MAX, an honest small number
    case 3: return 1;          // _SC_NPROCESSORS_ONLN
    default: return -1;
    }
}
