/* 0069: an expression statement is a full expression, comma operators and all

`(void)sizeof(1), (void)0;` was refused with `expected ;, found ','`.  The
statement reader stopped at the comma, so the comma operator was read only
inside parentheses, and glibc's strict-ISO `assert` -- which expands to
`((void) sizeof ((expr) ? 1 : 0), __extension__ ({ ... }))` -- could not be
compiled under `-std=c99`.  The statement reader reads the commas now, and a
statement that starts with an assignment is put back together as the expression
it is before the comma is read over it.  Fixed in 1fb7c81 ("parser: read the
comma operators of an expression statement").
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

static int note(int value)
{
    order[steps++] = value;
    return value;
}

int main(void)
{
    int a = 0;
    int b = 0;

    /* The left operand runs first and its value is thrown away. */
    a = note(1), b = note(2);
    CHECK(a == 1 && b == 2);
    CHECK(steps == 2 && order[0] == 1 && order[1] == 2);

    /* Three operands, left to right. */
    steps = 0;
    note(3), note(4), note(5);
    CHECK(steps == 3 && order[0] == 3 && order[1] == 4 && order[2] == 5);

    /* The shape glibc's strict-ISO assert is written with. */
    (void)sizeof(1), (void)0;

    /* A call on the right, and a step on the left. */
    steps = 0;
    b++, note(6);
    CHECK(b == 3 && steps == 1 && order[0] == 6);
    return 0;
}
