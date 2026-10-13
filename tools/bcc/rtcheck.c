// Checks the runtime pieces that only exist for a ported program.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <setjmp.h>
#include <errno.h>

static int bad, total;
static void want(const char *tag, const char *got, const char *exp) {
    total++;
    if (strcmp(got, exp) != 0) { printf("FAIL %-14s got [%s] want [%s]\n", tag, got, exp); bad++; }
}
static void wanth(const char *tag, long got, long exp) {
    total++;
    if (got != exp) { printf("FAIL %-14s got %ld want %ld\n", tag, got, exp); bad++; }
}
static int near(const char *tag, double got, double exp, double tol) {
    total++;
    double d = got - exp;
    if (d < 0) d = -d;
    if (d > tol) { printf("FAIL %-14s got %f want %f\n", tag, got, exp); bad++; return 0; }
    return 1;
}

static jmp_buf jb;
static int jumped;
static void thrower(void) { jumped = 1; longjmp(jb, 7); }

static int cmpint(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    return x < y ? -1 : (x > y ? 1 : 0);
}

int main(void) {
    char b[64];

    /* strtol family */
    want("strtol", (sprintf(b, "%ld", strtol("  -42abc", NULL, 10)), b), "-42");
    want("strtol16", (sprintf(b, "%ld", strtol("0x1f", NULL, 0)), b), "31");
    want("strtol8", (sprintf(b, "%ld", strtol("0755", NULL, 0)), b), "493");
    { char *e; strtol("123xyz", &e, 10); wanth("strtol end", (long)(*e == 'x'), 1); }
    want("strtoul", (sprintf(b, "%lu", strtoul("ffffffff", NULL, 16)), b), "4294967295");
    want("strtoull", (sprintf(b, "%llu", strtoull("18446744073709551615", NULL, 10)), b), "18446744073709551615");
    want("atoi", (sprintf(b, "%d", atoi("123")), b), "123");

    /* strtod is what a compiler leans on hardest */
    near("strtod 1.5", strtod("1.5", NULL), 1.5, 0);
    near("strtod pi", strtod("3.14159265358979", NULL), 3.14159265358979, 1e-14);
    near("strtod neg", strtod("-2.5e3", NULL), -2500.0, 0);
    near("strtod tiny", strtod("1e-10", NULL), 1e-10, 1e-22);
    near("strodot huge", strtod("1.7976931348623157e308", NULL), 1.7976931348623157e308, 1e290);
    { char *e; strtod("12.5abc", &e); wanth("strtod end", (long)(*e == 'a'), 1); }
    want("strtof", (sprintf(b, "%.2f", (double)strtof("2.5", NULL)), b), "2.50");

    /* math */
    near("sqrt", sqrt(2.0), 1.4142135623730951, 1e-15);
    near("sqrt 1e8", sqrt(1e8), 10000.0, 1e-9);
    near("fabs", fabs(-3.5), 3.5, 0);
    near("floor", floor(-1.5), -2.0, 0);
    near("ceil", ceil(-1.5), -1.0, 0);
    near("trunc", trunc(-1.9), -1.0, 0);
    near("round", round(-1.5), -2.0, 0);
    near("round 2.5", round(2.5), 3.0, 0);
    near("fmod", fmod(7.5, 2.0), 1.5, 1e-15);
    near("exp", exp(1.0), 2.718281828459045, 1e-14);
    near("exp 5", exp(5.0), 148.4131591025766, 1e-10);
    near("log", log(100.0), 4.605170185988092, 1e-14);
    near("log10", log10(1000.0), 3.0, 1e-14);
    near("pow", pow(2.0, 10.0), 1024.0, 1e-12);
    near("pow frac", pow(2.0, 0.5), 1.4142135623730951, 1e-14);
    { int e; double m = frexp(12.0, &e); near("frexp", m, 0.75, 0); wanth("frexp exp", e, 4); }
    near("ldexp", ldexp(1.5, 10), 1536.0, 0);
    near("ldexp -3", ldexp(8.0, -3), 1.0, 0);
    { double ip; double fr = modf(3.75, &ip); near("modf ip", ip, 3.0, 0); near("modf fr", fr, 0.75, 1e-14); }

    /* setjmp / longjmp */
    jumped = 0;
    if (setjmp(jb) == 0) thrower();
    wanth("longjmp ran", jumped, 1);

    /* sscanf, which tcc uses on its own version string */
    { int a = 0, c = 0, d = 0;
      wanth("sscanf n", sscanf("0.9.27", "%d.%d.%d", &a, &c, &d), 3);
      wanth("sscanf a", a, 0); wanth("sscanf b", c, 9); wanth("sscanf c", d, 27); }
    { char s[32]; int n = 0;
      sscanf("  hello   42 ", "%s %d", s, &n);
      want("sscanf s", s, "hello"); wanth("sscanf d", n, 42); }
    { double v; sscanf("3.5", "%lf", &v); near("sscanf f", v, 3.5, 0); }

    /* qsort and bsearch */
    { int a[9] = {5, 3, 9, 1, 7, 2, 8, 6, 4};
      qsort(a, 9, sizeof(int), cmpint);
      want("qsort", (sprintf(b, "%d%d%d%d%d%d%d%d%d", a[0],a[1],a[2],a[3],a[4],a[5],a[6],a[7],a[8]), b), "123456789");
      int key = 7;
      int *f = bsearch(&key, a, 9, sizeof(int), cmpint);
      wanth("bsearch", f ? *f : -1, 7); }

    /* errno */
    errno = 0;
    wanth("errno clear", errno, 0);

    printf("\n%d/%d runtime checks pass\n", total - bad, total);
    return bad != 0;
}
