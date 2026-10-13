/* A small program with a bit of everything a compiler has to handle: types,
   a struct, a loop, a function call, a pointer and a string. tcc compiles it
   inside Bunix and the result is compared against the host's. */

#include <stddef.h>

struct point {
    int x, y;
};

static int square(int n) {
    return n * n;
}

int sum_to(int n) {
    int total = 0;
    for (int i = 1; i <= n; i++) {
        total += square(i);
    }
    return total;
}

int main(void) {
    struct point p;
    p.x = 3;
    p.y = 4;

    const char *msg = "sum of squares";
    size_t len = 0;
    while (msg[len]) len++;

    int squares = sum_to(10);
    int product = p.x * p.y;

    return squares + product + (int)len;
}