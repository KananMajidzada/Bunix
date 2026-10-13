// Exercises the C runtime: formatted output, allocation, and file I/O.
// Anything that prints WRONG: is a runtime bug, so the strings are checked
// against what is expected rather than just being printed.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <time.h>

static int fails;

static void check(const char *what, long got, long want) {
    if (got != want) {
        printf("WRONG: %s got %d want %d\n", what, (int)got, (int)want);
        fails++;
    }
}

static void checkstr(const char *what, const char *got, const char *want) {
    if (strcmp(got, want) != 0) {
        printf("WRONG: %s\n  got  [%s]\n  want [%s]\n", what, got, want);
        fails++;
    }
}

int main(int argc, char **argv) {
    printf("test_c: hello from C\n");
    printf("argc=%d\n", argc);
    for (int i = 0; i < argc; i++) {
        printf("argv[%d]=%s\n", i, argv[i]);
    }

    // printf conversion coverage
    printf("d=%d neg=%d u=%u hex=%x HEX=%X oct=%o c=%c s=%s p=%p pct=%%\n",
           42, -7, 4294967295u, 255, 255, 017, 'Z', "str", (void *)0x1234);
    printf("wide: [%5d] [%-5d] [%05d] [%5s] [%-5s]\n",
           7, 7, 7, "ab", "ab");
    printf("long: %ld %lu %lx  size:%zu  ptrdiff:%zd\n",
           1234567890123L, 18446744073709551615UL, 4096UL,
           (size_t)7, (ssize_t)-5);

    // string functions
    printf("-- strings\n");
    char buf[64];
    strcpy(buf, "hello");
    check("strlen", (long)strlen(buf), 5);
    checkstr("strcat", (strcat(buf, " world"), buf), "hello world");
    check("strcmp eq", strcmp("abc", "abc"), 0);
    check("strcmp lt", strcmp("abc", "abd") < 0, 1);
    checkstr("strchr", strchr(buf, 'w'), "world");
    check("strrchr", (long)(strrchr("aXbXc", 'X') - "aXbXc"), 3);
    checkstr("strstr", strstr(buf, "lo w"), "lo world");
    printf("-- strings done\n");

    // malloc and free
    for (int round = 0; round < 64; round++) {
        printf("-- malloc round %d\n", round);
        char *p = malloc(1024 + round);
        if (!p) { printf("WRONG: malloc returned NULL\n"); fails++; break; }
        memset(p, round & 0x7f, 1024 + round);
        if ((unsigned char)p[0] != (unsigned char)(round & 0x7f)) {
            printf("WRONG: malloc memory clobbered\n"); fails++; break;
        }
        strcpy(p, "ok");
        checkstr("malloc content", p, "ok");
        free(p);
    }
    printf("-- malloc done\n");

    printf("-- calloc\n");
    char *z = calloc(64, 4);
    int nonzero = 0;
    for (int i = 0; i < 256; i++) if (z[i]) nonzero++;
    check("calloc zeroed", nonzero, 0);
    free(z);
    printf("-- calloc done\n");

    printf("-- realloc\n");
    char *r = malloc(16);
    strcpy(r, "grow");
    r = realloc(r, 4096);
    checkstr("realloc kept", r, "grow");
    free(r);
    printf("-- realloc done\n");

    // file round trip
    const char *path = "/tmp/c_test.txt";
    printf("-- unlink\n");
    unlink(path);
    printf("-- fopen w\n");
    FILE *f = fopen(path, "w");
    printf("-- fopen w done, f=%s\n", f ? "ok" : "NULL");
    if (!f) { printf("WRONG: fopen(w) failed\n"); fails++; }
    else {
        fprintf(f, "line one\nline two\n");
        fputs("line three\n", f);
        fwrite("xy", 1, 2, f);
        fclose(f);
        printf("-- fclose done\n");
    }

    printf("-- fopen r\n");
    f = fopen(path, "r");
    printf("-- fopen r done, f=%s\n", f ? "ok" : "NULL");
    if (!f) { printf("WRONG: fopen(r) failed\n"); fails++; }
    else {
        char line[64];
        printf("-- fgets\n");
        if (!fgets(line, sizeof(line), f)) printf("WRONG: fgets eof\n");
        else checkstr("read l1", line, "line one\n");
        printf("-- fgets2\n");
        fgets(line, sizeof(line), f);
        checkstr("read l2", line, "line two\n");

        // seek back and read again
        printf("-- fseek\n");
        fseek(f, 0, SEEK_SET);
        printf("-- fread\n");
        char raw[64];
        memset(raw, 0, sizeof(raw));
        size_t n = fread(raw, 1, 8, f);
        check("fread count", (long)n, 8);
        checkstr("fread data", raw, "line one");

        printf("-- stat\n");
        stat_t st;
        check("stat", stat(path, &st), 0);
        check("stat size", (long)st.st_size, 31);
        check("is regular", S_ISREG(st.st_mode), 1);
        fclose(f);
    }
    printf("-- file section done\n");

    // directory listing
    DIR *d = opendir("/");
    if (!d) { printf("WRONG: opendir(/) failed\n"); fails++; }
    else {
        int names = 0;
        int sawdev = 0;
        dirent_t *e;
        while ((e = readdir(d))) {
            names++;
            if (strcmp(e->d_name, "dev") == 0) sawdev = 1;
        }
        check("readdir found something", names > 0, 1);
        check("readdir saw dev", sawdev, 1);
        closedir(d);
    }

    // time
    time_t now = time(NULL);
    check("time nonzero", now > 0, 1);

    // raw descriptors
    int fd = open("/tmp/c_test.txt", O_RDONLY);
    check("open raw", fd >= 0, 1);
    char rb[16];
    ssize_t got = read(fd, rb, 9);
    check("read raw count", (long)got, 9);
    rb[9] = 0;
    checkstr("read raw data", rb, "line one\n");
    check("lseek", lseek(fd, 0, SEEK_SET), 0);
    close(fd);

    unlink(path);

    if (fails) {
        printf("test_c: %d FAILURES\n", fails);
        return 1;
    }
    printf("test_c: all ok\n");
    return 0;
}