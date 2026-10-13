// cstart.c - C runtime start.
//
// The loader leaves one argument string in %rdi and its length in %rsi.
// argv[0] is not in there: the shell strips the program name before the call,
// so it is reconstructed as the program path the shell used. The rest is split
// on spaces the ordinary way.

#include <stddef.h>
#include <stdlib.h>
#include "syscalls.h"

extern int main(int argc, char **argv);

// atexit handlers, so a program can register cleanup before it starts.
#define MAXEXIT 32
static void (*exits[MAXEXIT])(void);
static int nexits;

int atexit(void (*fn)(void)) {
    if (nexits >= MAXEXIT) return -1;
    exits[nexits++] = fn;
    return 0;
}

void exit(int code) {
    // Run handlers innermost first, as C requires.
    while (nexits > 0) {
        nexits--;
        exits[nexits]();
    }
    bunix_exit(code);
    for (;;) {
    }
}

void _Exit(int code) {
    bunix_exit(code);
    for (;;) {
    }
}

void abort(void) {
    bunix_write("abort\n", 6);
    _Exit(134);
}

#define MAXARGS 64

void __libc_start(char *buf, size_t len) {
    static char *argv[MAXARGS];
    int argc = 1;
    argv[0] = "bunix";

    size_t i = 0;
    while (i < len && argc < MAXARGS - 1) {
        while (i < len && buf[i] == ' ') i++;
        if (i >= len) break;
        argv[argc++] = &buf[i];
        while (i < len && buf[i] != ' ') i++;
        if (i < len) buf[i++] = 0;
    }
    argv[argc] = NULL;

    exit(main(argc, argv));
}