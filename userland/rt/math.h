// math.h - the floating point routines a ported program reaches for.
//
// Bunix has no libm. These are the ones that can be written without one; the
// transcendental functions below are series that are good to a few ulp, which
// is plenty for a compiler's constant folding.

#ifndef BUNIX_MATH_H
#define BUNIX_MATH_H

#define M_PI     3.14159265358979323846
#define M_E      2.7182818284590452354
#define M_LN2    0.69314718055994530942
#define M_LN10   2.30258509299404568402
#define M_SQRT2  1.41421356237309504880

#define FPE_INTDIV 1
#define FPE_INTOVF 2
#define FPE_FLTDIV 3
#define FPE_FLTOVF 4
#define FPE_FLTUND 5
#define FPE_FLTRES 6
#define FPE_FLTINV 7
#define FPE_FLTSUB 8

#define FE_INVALID   1
#define FE_DIVBYZERO 4
#define FE_OVERFLOW  8
#define FE_UNDERFLOW 16
#define FE_INEXACT   32
#define FE_ALL_EXCEPT 61

#define HUGE_VAL (__builtin_huge_val())
#define INFINITY (__builtin_inff())
#define NAN      (__builtin_nanf(""))

double fabs(double x);
double floor(double x);
double ceil(double x);
double round(double x);
double trunc(double x);
double fmod(double x, double y);
double sqrt(double x);
double pow(double x, double y);
double exp(double x);
double log(double x);
double log2(double x);
double log10(double x);
double sin(double x);
double cos(double x);
double tan(double x);
double atan(double x);
double atan2(double y, double x);
double ldexp(double x, int e);
double frexp(double x, int *e);
double modf(double x, double *ip);

float fabsf(float x);
float sqrtf(float x);
float powf(float x, float y);
float strtof(const char *s, char **end);

double strtod(const char *s, char **end);
long double strtold(const char *s, char **end);

#endif
