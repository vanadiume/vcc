/* 0021: fenv-rounds-and-reports-floating-point-exceptions
 *
 * ISO/IEC 9899:1999 7.6: the floating-point environment holds the rounding
 * direction and the exception flags; the functions read it, save it and put it
 * back.
 */

#include <fenv.h>
#include <math.h>
#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    fenv_t saved;
    fenv_t held;
    fexcept_t flags;
    volatile double one = 1.0;
    volatile double zero = 0.0;
    volatile double third;
    double nearest;
    double upward;
    double downward = 0.0;
    double infinite;

    CHECK(fegetround() == FE_TONEAREST);
    CHECK(feclearexcept(FE_ALL_EXCEPT) == 0);
    CHECK(fetestexcept(FE_ALL_EXCEPT) == 0);

    /* 7.6.2: the rounding direction is a property of the environment and a
     * division under it rounds that way */
    third = 1.0 / 3.0;
    nearest = third;
    CHECK(fesetround(FE_UPWARD) == 0);
    CHECK(fegetround() == FE_UPWARD);
    third = one / 3.0;
    upward = third;
    CHECK(upward >= nearest);

    CHECK(fesetround(FE_DOWNWARD) == 0);
    CHECK(fegetround() == FE_DOWNWARD);
    third = one / 3.0;
    downward = third;
    CHECK(downward <= nearest);
    CHECK(upward > downward);

    CHECK(fesetround(FE_TOWARDZERO) == 0);
    CHECK(fegetround() == FE_TOWARDZERO);
    CHECK(fesetround(FE_TONEAREST) == 0);
    CHECK(fegetround() == FE_TONEAREST);

    /* 7.6.2.2 and 7.6.2.3: a raised exception is recorded and readable */
    CHECK(feclearexcept(FE_ALL_EXCEPT) == 0);
    infinite = one / zero;
    CHECK(isinf(infinite));
    CHECK(fetestexcept(FE_DIVBYZERO) != 0);
    CHECK(fetestexcept(FE_INVALID) == 0);

    CHECK(feclearexcept(FE_ALL_EXCEPT) == 0);
    CHECK(fetestexcept(FE_ALL_EXCEPT) == 0);

    /* 7.6.4: the environment can be saved, held and put back */
    CHECK(fegetenv(&saved) == 0);
    CHECK(feholdexcept(&held) == 0);
    CHECK(fetestexcept(FE_ALL_EXCEPT) == 0);
    CHECK(feraiseexcept(FE_INVALID) == 0);
    CHECK(fetestexcept(FE_INVALID) != 0);
    CHECK(fesetenv(&held) == 0);
    CHECK(fetestexcept(FE_ALL_EXCEPT) == 0);

    /* 7.6.2.4: an except flags object saves and restores the flags */
    CHECK(fegetexceptflag(&flags, FE_ALL_EXCEPT) == 0);
    CHECK(feraiseexcept(FE_DIVBYZERO) == 0);
    CHECK(fesetexceptflag(&flags, FE_ALL_EXCEPT) == 0);
    CHECK(fetestexcept(FE_DIVBYZERO) == 0);

    /* 7.6.4.4: feupdateenv restores the environment and then re-raises the
     * flags that were set when it was called */
    CHECK(fegetenv(&saved) == 0);
    CHECK(feraiseexcept(FE_INVALID) == 0);
    CHECK(feupdateenv(&saved) == 0);
    CHECK(fetestexcept(FE_INVALID) != 0);
    CHECK(fesetenv(&saved) == 0);
    CHECK(fetestexcept(FE_ALL_EXCEPT) == 0);

    CHECK(fesetround(FE_TONEAREST) == 0);
    return 0;
}
