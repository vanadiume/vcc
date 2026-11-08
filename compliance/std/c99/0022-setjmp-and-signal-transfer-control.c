/* 0022: setjmp-and-signal-transfer-control
 *
 * ISO/IEC 9899:1999 7.13: setjmp saves the state longjmp returns to, and the
 * second argument of longjmp is what setjmp returns, with zero becoming one;
 * 7.14: signal installs a handler and raise delivers a signal to the program.
 */

#include <setjmp.h>
#include <signal.h>
#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static jmp_buf escape;
static volatile sig_atomic_t delivered;

static void remember(int number)
{
    delivered = number;
}

static void jump_out(int value)
{
    longjmp(escape, value);
}

int main(void)
{
    int value;
    void (*previous)(int);

    /* 7.13.2.1p3: longjmp lands at setjmp, which returns its argument */
    value = setjmp(escape);
    if (value == 0) {
        jump_out(7);
        CHECK(0); /* longjmp does not return, so this is never reached */
    }
    CHECK(value == 7);

    /* and a zero argument arrives as one, so the first return is the only
     * zero setjmp reports */
    value = setjmp(escape);
    if (value == 0) {
        longjmp(escape, 0);
    }
    CHECK(value == 1);

    /* 7.14.1.1: a handler installed for a signal is called on delivery */
    previous = signal(SIGUSR1, remember);
    CHECK(previous != SIG_ERR);
    delivered = 0;
    CHECK(raise(SIGUSR1) == 0);
    CHECK(delivered == SIGUSR1);

    /* 7.14.1.1p3: whether delivery resets the disposition is
     * implementation-defined, so the handler goes back before it is replaced */
    CHECK(signal(SIGUSR1, remember) != SIG_ERR);

    /* SIG_IGN takes the signal without calling anything, and signal hands
     * back the handler it replaced */
    previous = signal(SIGUSR1, SIG_IGN);
    CHECK(previous == remember);
    delivered = 0;
    CHECK(raise(SIGUSR1) == 0);
    CHECK(delivered == 0);

    previous = signal(SIGUSR1, SIG_DFL);
    CHECK(previous == SIG_IGN);

    /* 7.14.1.1p3: a signal that cannot be caught is refused */
    CHECK(signal(SIGKILL, remember) == SIG_ERR);

    /* 7.14.2.1p2: raise reports a signal number it does not know */
    CHECK(raise(-1) != 0);
    return 0;
}
