// Test program for bcc cross-compiler

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "syscalls.h"

int main(int argc, char **argv) {
    printf("Hello from C on Bunix!\n");
    printf("argc = %d\n", argc);
    for (int i = 0; i < argc; i++) {
        printf("argv[%d] = %s\n", i, argv[i]);
    }

    // Test file I/O
    char buf[256];
    ssize_t n = bunix_readfile("/hello", buf, sizeof(buf) - 1);
    if (n > 0) {
        buf[n] = 0;
        printf("Read %zd bytes from /hello:\n%s", n, buf);
    } else {
        printf("Failed to read /hello\n");
    }

    // Test write
    const char *msg = "Written from C program\n";
    bunix_writefile("/dev/cons", msg, strlen(msg));

    // Test malloc
    char *p = malloc(100);
    if (p) {
        strcpy(p, "malloc works!");
        printf("malloc: %s\n", p);
        free(p);
    }

    return 42;
}