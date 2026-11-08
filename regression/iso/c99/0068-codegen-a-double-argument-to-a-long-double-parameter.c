/* 0068: a double argument reaches a long double parameter as its converted value
 *
 * An argument is converted to the type of the parameter it is handed to (C99
 * 6.5.2.2), and a double given to a `long double` parameter was not: the
 * argument was evaluated as a double, which leaves the value in the floating
 * register and nothing in the accumulator, and the accumulator was then parked
 * as though it held the address of the sixteen bytes the call pushes.  The
 * callee read whatever that address held.  For `ident(x)` below the value was a
 * NaN, and for `sqrtl(27.0)` it was whatever the earlier address left there;
 * both programs ran, exited 1, and reported nothing.
 *
 * Every value here is computed rather than written as a constant of the
 * parameter's type, because an argument that already is a long double was never
 * the shape that broke.  gcc 16.2.1 exits 0 on this program; the compiler from
 * before the change exits 1 on it, at the first check. */

#include <math.h>

static long double ident(long double v)
{
    return v;
}

static long double pair(int a, long double z, int b, long double w)
{
    return z + w;
}

int main(void)
{
    volatile double x = 27.0;
    double half = 0.5;
    float f = 2.5f;
    int i = -7;
    long double root;

    if (ident(x) != 27.0L)
        return 1;
    if (ident(27.0) != 27.0L)
        return 2;
    if (ident(f) != 2.5L)
        return 3;
    if (ident(i) != -7.0L)
        return 4;
    if (pair(1, half, 3, 4.75) != 5.25L)
        return 5;
    if (sqrtl(x) != sqrtl(27.0L))
        return 6;
    root = sqrtl(27.0);
    if (root * root < 26.999L || root * root > 27.001L)
        return 7;
    return 0;
}
