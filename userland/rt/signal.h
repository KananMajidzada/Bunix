// signal.h - signals.
//
// Bunix does not deliver signals: a fault kills the process. The names and the
// shapes are here so a program that installs a handler still builds, and so
// that one which merely checks the names gets the right answer.

#ifndef BUNIX_SIGNAL_H
#define BUNIX_SIGNAL_H

#include <stddef.h>

typedef void (*sighandler_t)(int);

// The set of signals a handler is asked to block. Nothing is ever delivered,
// so this only has to have the right shape.
typedef struct { unsigned long bits; } sigset_t;

typedef struct {
    int si_signo;
    int si_errno;
    int si_code;
} siginfo_t;

struct sigaction {
    union {
        void (*sa_handler)(int);
        void (*sa_sigaction)(int, siginfo_t *, void *);
    };
    unsigned long sa_flags;
    void (*sa_restorer)(void);
    sigset_t sa_mask;
};
typedef struct sigaction struct_sigaction;

#define SIGHUP  1
#define SIGINT  2
#define SIGQUIT 3
#define SIGILL  4
#define SIGTRAP 5
#define SIGABRT 6
#define SIGBUS  7
#define SIGFPE  8
#define SIGKILL 9
#define SIGUSR1 10
#define SIGSEGV 11
#define SIGUSR2 12
#define SIGPIPE 13
#define SIGALRM 14
#define SIGTERM 15
#define SIGCHLD 17
#define SIGCONT 18
#define SIGSTOP 19

#define SIG_ERR ((void (*)(int))-1)
#define SIG_DFL ((void (*)(int))0)
#define SIG_IGN ((void (*)(int))1)

#define SA_NOCLDSTOP  0x00000001
#define SA_NODEFER    0x40000000
#define SA_ONSTACK    0x08000000
#define SA_RESETHAND  0x10000000
#define SA_RESTART    0x10000000
#define SA_SIGINFO    0x00000004

#define SIG_BLOCK   0
#define SIG_UNBLOCK 1
#define SIG_SETMASK 2

int sigemptyset(sigset_t *set);
int sigfillset(sigset_t *set);
int sigaddset(sigset_t *set, int n);
int sigdelset(sigset_t *set, int n);
int sigismember(const sigset_t *set, int n);
int sigprocmask(int how, const sigset_t *set, sigset_t *old);
int sigaction(int sig, const struct sigaction *act, struct sigaction *old);
sighandler_t signal(int sig, sighandler_t handler);
int kill(int pid, int sig);

#endif
