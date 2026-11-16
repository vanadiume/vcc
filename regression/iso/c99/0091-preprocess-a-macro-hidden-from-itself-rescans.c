/* 0091: a macro hidden from itself stays hidden while its own replacement is read

`#define A B` beside `#define B A` has to stop somewhere.  The B that A's
replacement produces is hidden from A, and the A that B's replacement produces
is hidden from both, so the pair ends on the name A and A stays an ordinary
name from then on.  The hiding belongs to the token rather than to a stack of
the names being expanded, which is what keeps it true when the token is read
again later.

The other end of the same rule is a name that must expand once more: with
`#define F(x) G` beside `#define G F`, the F that G's replacement produces is a
use again as soon as G's own replacement is no longer the text being read.  That
needs the rescan of an object-like replacement with the text after the use
(0079), and the two together are #108; the `-E` output for `G(1)` and for the
standard's `f(2)(9)` example is in the issue.  What this case pins is the half
that must not change: every shape here that ends on a name still ends on it, and
the standard's pair still expands once where the file calls for it.

Checked against gcc and tcc, and each CHECK fails with the FAIL line when its
expectation is changed.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

/* Two object-like macros that name each other.  A expands to B and B back to
 * A, and the A that arrives during the pair's own replacement is not replaced
 * again, so the definition below defines A. */
#define A B
#define B A

/* Three of them, so the name that arrives has two expansions behind it. */
#define P Q
#define Q R
#define R P

/* A pair of function-like macros: M(int) is N(int) is M(int) again.  The
 * declaration's ( is the one the expansion sees, and the name it comes back to
 * is text, so this is a declaration of M and not an expansion forever. */
#define M(x) N(x)
#define N(x) M(x)

/* A name that expands to itself, one that expands to a call of itself, and one
 * that expands to a call of itself with an argument.  All three are painted
 * where they arrive: the first two leave the declarations they are written in
 * alone, and the third spells the G(int) that declares G as a function. */
#define F F
#define SELF(x) SELF(x)
#define G G(int)

/* The standard's f and g, used once: f(2) is `2*g`, and the g left standing is
 * the variable below, since a function-like macro's name with no ( after it is
 * not a use of it (C99 6.10.3p10). */
#define f(a) a*g
#define g(a) f(a)

/* A pair that does expand, so the file also checks the direction that moves. */
#define ONE(x) TWO(x)
#define TWO(x) ((x) + 1)

int A = 3;
int P = 4;
int F = 5;
int G;
int SELF(int);
int M(int);
int g = 10;

int main(void)
{
    /* Each pair ended on its first name, and that name is a variable. */
    CHECK(A == 3);
    CHECK(P == 4);
    CHECK(F == 5);

    /* f(2) expands the pair once and leaves the g as the variable. */
    CHECK(f(2) == 20);

    /* A pair the file calls for does expand. */
    CHECK(ONE(2) == 3);

    return 0;
}
