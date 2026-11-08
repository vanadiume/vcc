/* 0070: a conditional whose arms are void is a statement

`a ? (void)0 : (void)0;` was refused with `unsupported: a void expression in a
statement is not one this back end evaluates for its side effects`.  A
conditional both of whose arms are void is worth nothing; it is written for
what the arm the condition selects does.  glibc's strict-ISO `assert` expands
to exactly this conditional, so `assert(1)` could not be compiled under
`-std=c99`.  Fixed in 59fc3b1 ("codegen: evaluate a void conditional statement
for its effect").
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static int order[8];
static int steps;

static int arm(int value)
{
    order[steps++] = value;
    return value;
}

int main(void)
{
    int flag = 0;

    /* Only the arm the condition selects runs. */
    flag ? (void)arm(1) : (void)arm(2);
    CHECK(steps == 1 && order[0] == 2);

    /* The condition is evaluated, side effect and all, and still selects the
     * false arm. */
    steps = 0;
    flag++ ? (void)arm(3) : (void)arm(4);
    CHECK(flag == 1 && steps == 1 && order[0] == 4);

    /* A condition the reader folds to a constant selects its arm on every run,
     * and the other arm is not written at all. */
    steps = 0;
    1 ? (void)arm(5) : (void)arm(6);
    CHECK(steps == 1 && order[0] == 5);
    steps = 0;
    0 ? (void)arm(7) : (void)arm(8);
    CHECK(steps == 1 && order[0] == 8);

    /* The shape glibc's strict-ISO assert is written with. */
    flag ? (void)0 : (void)0;
    return 0;
}
