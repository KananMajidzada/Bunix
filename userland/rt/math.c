// math.c - floating point without a libm.
//
// Everything here works in double. The x87 stack is not usable on this target,
// so nothing is allowed to reach for long double.

#include <stddef.h>
#include <math.h>
#include <ctype.h>

typedef union {
    double d;
    unsigned long u;
} dbl;

double fabs(double x) {
    dbl v; v.d = x;
    v.u &= 0x7FFFFFFFFFFFFFFFUL;
    return v.d;
}

double floor(double x) {
    dbl v; v.d = x;
    int e = (int)((v.u >> 52) & 0x7FF);
    if (e >= 0x7FF) return x;              // inf or nan
    if (e == 0) return v.d;                // already below one
    int exp = e - 1023;
    if (exp >= 0) return x;                // no fraction to drop
    int shift = 52 - exp;
    unsigned long mask = (1UL << shift) - 1;
    dbl w; w.d = x;
    if ((w.u & mask) == 0) return x;
    // Round toward minus infinity.
    dbl r; r.u = (w.u & ~mask);
    if (x < 0.0) r.d -= 1.0;
    return r.d;
}

double ceil(double x) {
    double f = floor(x);
    return (f == x) ? x : f + 1.0;
}

double trunc(double x) {
    dbl v; v.d = x;
    int e = (int)((v.u >> 52) & 0x7FF);
    if (e == 0x7FF || e == 0) return x;
    int exp = e - 1023;
    if (exp >= 0) return x;
    int shift = 52 - exp;
    dbl r; r.u = v.u & ~((1UL << shift) - 1);
    return r.d;
}

double round(double x) {
    double t = trunc(x);
    double d = x - t;
    if (d >= 0.5) return t + 1.0;
    if (d <= -0.5) return t - 1.0;
    return t;
}

double fmod(double x, double y) {
    if (y == 0.0 || x != x || y != y) return 0.0 / 0.0;
    double q = x / y;
    double t = trunc(q);
    double r = x - t * y;
    if (r < 0.0 && y > 0.0) r += y;
    if (r >= y && y < 0.0) r -= y;
    if (r < 0.0 && y < 0.0) r += y;
    return r;
}

double sqrt(double x) {
    if (x != x || x < 0.0) return 0.0 / 0.0;
    if (x == 0.0) return x;
    if (x > 1.7976931348623157e308) return 1.0 / 0.0;

    // Newton from a halving start, which converges in a dozen steps for the
    // whole range of doubles.
    dbl v; v.d = x;
    int e = (int)((v.u >> 52) & 0x7FF) - 1023;
    if (e & 1) e++;                 // make the exponent even
    dbl guess; guess.u = ((unsigned long)(e / 2 + 1023) << 52);
    double g = guess.d;
    for (int i = 0; i < 40; i++) {
        double n = 0.5 * (g + x / g);
        if (n == g) break;
        g = n;
    }
    return g;
}

float sqrtf(float x) { return (float)sqrt((double)x); }
float fabsf(float x) { return (float)fabs((double)x); }

double ldexp(double x, int n) {
    dbl v; v.d = x;
    int e = (int)((v.u >> 52) & 0x7FF);
    if (e == 0x7FF) return x;       // inf or nan
    if (e == 0 && (v.u & 0xFFFFFFFFFFFFFUL) == 0) return x;   // zero

    if (e == 0) {
        // Subnormal: scale up by a fixed step until it is normal, then again.
        v.d = x * 4503599627370496.0;   // 2^52
        return ldexp(v.d, n - 52);
    }

    long ne = (long)e + n;
    if (ne >= 0x7FF) {
        v.u = (v.u & 0x800FFFFFFFFFFFFFUL) | (0x7FFUL << 52);
        return v.d;
    }
    if (ne <= 0) {
        v.u = (v.u & 0x800FFFFFFFFFFFFFUL) | 1UL << 52;
        return ldexp(v.d, (int)ne - 1);
    }
    v.u = (v.u & 0x800FFFFFFFFFFFFFUL) | ((unsigned long)ne << 52);
    return v.d;
}

double frexp(double x, int *e) {
    dbl v; v.d = x;
    int ex = (int)((v.u >> 52) & 0x7FF);
    if (ex == 0x7FF) { *e = 0; return x; }
    if (ex == 0 && (v.u & 0xFFFFFFFFFFFFFUL) == 0) { *e = 0; return x; }
    int n;
    if (ex == 0) {
        v.d = x * 4503599627370496.0;
        n = (int)((v.u >> 52) & 0x7FF) - 1023 - 52;
    } else {
        n = ex - 1023;
        v.u = v.u & 0x800FFFFFFFFFFFFFUL;      // drop the exponent
    }
    *e = n;
    return v.d;
}

double modf(double x, double *ip) {
    double i = trunc(x);
    *ip = i;
    return x - i;
}

// --- transcendental functions ---

double exp(double x) {
    if (x != x) return x;
    if (x > 709.7) return 1.0 / 0.0;
    if (x < -745.0) return 0.0;

    // Reduce to exp(r) * 2^k with |r| small, so the series is short.
    double k = round(x / 0.69314718055994530942);
    double r = x - k * 0.69314718055994530942;
    if (r > 0.5) { r -= 0.69314718055994530942; k += 1.0; }
    if (r < -0.5) { r += 0.69314718055994530942; k -= 1.0; }

    double term = 1.0, sum = 1.0;
    for (int i = 1; i <= 16; i++) {
        term *= r / (double)i;
        sum += term;
    }
    return ldexp(sum, (int)k);
}

double log(double x) {
    if (x != x || x < 0.0) return 0.0 / 0.0;
    if (x == 0.0) return -1.0 / 0.0;

    int e;
    double m = frexp(x, &e);            // m in [0.5, 1)
    if (m < 0.70710678118654752440) { m *= 2.0; e -= 1; }
    // m is now close to one; the log series converges fast.
    double z = (m - 1.0) / (m + 1.0);
    double z2 = z * z;
    double sum = 0.0, p = z;
    for (int i = 1; i <= 31; i += 2) {
        sum += p / (double)i;
        p *= z2;
    }
    return 2.0 * sum + (double)e * 0.69314718055994530942;
}

double log2(double x) { return log(x) / 0.69314718055994530942; }
double log10(double x) { return log(x) / 2.30258509299404568402; }

double pow(double x, double y) {
    if (y == 0.0) return 1.0;
    if (y == 1.0) return x;
    if (y == 2.0) return x * x;
    if (y == 0.5) return sqrt(x);
    if (x < 0.0) {
        long n = (long)y;
        if ((double)n == y) {
            double r = exp((double)n * log(-x));
            return (n & 1) ? -r : r;
        }
        return 0.0 / 0.0;
    }
    return exp(y * log(x));
}

float powf(float x, float y) { return (float)pow((double)x, (double)y); }

double sin(double x) {
    int e;
    double m = frexp(x, &e);
    double r = x - (double)e * 1.57079632679489661923;
    double term = r, sum = r;
    double r2 = r * r;
    for (int i = 1; i <= 12; i++) {
        term *= -r2 / (double)((2 * i) * (2 * i + 1));
        sum += term;
    }
    // Fold back by quarters so the range stays small.
    switch (((e % 4) + 4) % 4) {
    case 0: return sum;
    case 1: return sum;
    case 2: return -sum;
    default: return -sum;
    }
}

double cos(double x) {
    double s = sin(x);
    double c = sqrt(1.0 - s * s);
    int e;
    frexp(x, &e);
    switch (((e % 4) + 4) % 4) {
    case 0: return c;
    case 1: return -s;
    case 2: return -c;
    default: return s;
    }
}

double tan(double x) { return sin(x) / cos(x); }

double atan(double x) {
    int e;
    double m = frexp(x, &e);            // m in [0.5, 1)
    int neg = m < 0.0;
    if (neg) m = -m;
    // Fold large values into [0, 1] with atan(x) = pi/2 - atan(1/x).
    if (m > 1.0) {
        m = 1.0 / m;
        e = -(e + 1);
    }
    double z = (m - 1.0) / (m + 1.0);
    double z2 = z * z;
    double term = z, sum = z;
    for (int i = 3; i <= 41; i += 2) {
        term *= -z2;
        sum += term / (double)i;
    }
    double r = sum;
    if (e > 0) r += (double)(e & 1 ? 2 : 1) * 1.57079632679489661923;
    return neg ? -r : r;
}

double atan2(double y, double x) {
    if (x == 0.0 && y == 0.0) return 0.0;
    double a = atan(y / x);
    if (x > 0.0) return a;
    if (x < 0.0) return y >= 0.0 ? a + 3.14159265358979323846
                                 : a - 3.14159265358979323846;
    return y > 0.0 ? 1.57079632679489661923 : -1.57079632679489661923;
}

// --- decimal to binary ---

// Powers of ten that are exact in double, so the scaling below is a single
// multiplication rather than an accumulated error.
static const double p10[] = {
    1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9,
    1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19,
    1e20, 1e21, 1e22,
};

double strtod(const char *s, char **end) {
    const char *p = s;
    while (*p == ' ' || (*p >= '\t' && *p <= '\r')) p++;

    int neg = 0;
    if (*p == '+' || *p == '-') {
        neg = (*p == '-');
        p++;
    }

    // inf and nan
    if ((p[0] == 'i' || p[0] == 'I') && (p[1] == 'n' || p[1] == 'N')) {
        if (end) *end = (char *)(p + 3);
        return neg ? -1.0 / 0.0 : 1.0 / 0.0;
    }
    if ((p[0] == 'n' || p[0] == 'N') && (p[1] == 'a' || p[1] == 'A') && p[2] == 'n') {
        if (end) *end = (char *)(p + 3);
        return 0.0 / 0.0;
    }

    // Collect the digits. The first nineteen fit a 64-bit word exactly, which
    // is as much as matters for the rounding.
    unsigned long long mant = 0;
    int ndig = 0;
    int exp10 = 0;
    int any = 0;

    while (*p >= '0' && *p <= '9') {
        any = 1;
        if (ndig < 19) {
            mant = mant * 10 + (unsigned long long)(*p - '0');
            ndig++;
        } else {
            exp10++;
        }
        p++;
    }
    if (*p == '.') {
        p++;
        while (*p >= '0' && *p <= '9') {
            any = 1;
            if (ndig < 19) {
                mant = mant * 10 + (unsigned long long)(*p - '0');
                ndig++;
                exp10--;
            }
            p++;
        }
    }
    if (!any) {
        if (end) *end = (char *)s;
        return 0.0;
    }

    if (*p == 'e' || *p == 'E') {
        const char *q = p + 1;
        int esign = 0;
        if (*q == '+' || *q == '-') {
            esign = (*q == '-');
            q++;
        }
        if (*q >= '0' && *q <= '9') {
            int ev = 0;
            while (*q >= '0' && *q <= '9') {
                if (ev < 100000) ev = ev * 10 + (*q - '0');
                q++;
            }
            exp10 += esign ? -ev : ev;
            p = q;
        }
    }

    if (end) *end = (char *)p;

    double v = (double)mant;
    if (exp10 > 0) {
        if (exp10 <= 22) v *= p10[exp10];
        else v *= 1e22, v *= pow(10.0, (double)(exp10 - 22));
    } else if (exp10 < 0) {
        int k = -exp10;
        if (k <= 22) v /= p10[k];
        else v /= 1e22, v /= pow(10.0, (double)(k - 22));
    }
    return neg ? -v : v;
}

// The x87 stack is not available, so a long double literal comes back as the
// nearest double. A ported compiler only uses this for an "L" suffix.
long double strtold(const char *s, char **end) { return (long double)strtod(s, end); }

float strtof(const char *s, char **end) { return (float)strtod(s, end); }

// The spelling of strtod for a caller that does not care where the number
// ended. A game reads its configuration file through this.
double atof(const char *s) { return strtod(s, NULL); }
