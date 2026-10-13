// sys/ucontext.h - the machine context a signal handler is handed.
//
// Bunix never delivers a signal, so nothing ever reads one of these. The
// header exists because a program that installs a handler includes it and
// names the type; the shape below is the Linux x86-64 one, so a caller that
// digs out a frame pointer finds the field where it expects.

#ifndef BUNIX_SYS_UCONTEXT_H
#define BUNIX_SYS_UCONTEXT_H

#include <stddef.h>

enum {
    REG_R8 = 0, REG_R9, REG_R10, REG_R11, REG_R12, REG_R13, REG_R14,
    REG_R15, REG_RDI, REG_RSI, REG_RBP, REG_RBX, REG_RDX, REG_RAX,
    REG_RCX, REG_RSP, REG_RIP, REG_EFL, REG_CSGSFS, REG_ERR, REG_TRAPNO,
    REG_OLDMASK, REG_CR2,
};

typedef unsigned long greg_t;

typedef struct {
    greg_t gregs[23];
    unsigned long long fpregs[312];
    unsigned long long __reserved1[8];
} mcontext_t;

typedef struct {
    unsigned long uc_flags;
    void *uc_link;
    unsigned long uc_stack[2];
    mcontext_t uc_mcontext;
} ucontext_t;

#endif