/* 0076: a comma expression whose first operand is a compound assignment

`a += 2, b++;` was refused with `unsupported: expected ;, found ','`.  The
statement reader read the commas of an expression statement after an
assignment, but returned a compound assignment unchanged, because the
expression it would have been put back as computes the target's address a
second time.  The commas after one are read as statement separators instead,
one statement per operand in the order written, which is the same effects in
the same order for a value that is thrown away.  zlib 1.3.1's
`scan += 2, match++;` (deflate.c:1452) is this shape.
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
static int evaluations;

static int note(int value)
{
    order[steps++] = value;
    return value;
}

static int next_index(void)
{
    evaluations++;
    return 0;
}

int main(void)
{
    int a = 0;
    int b = 0;
    int arr[2] = {10, 20};
    int i, j;

    /* Both sides have an effect and the left one happens first. */
    a += 2, b++;
    CHECK(a == 2 && b == 1);

    /* A call on each side, left before right. */
    steps = 0;
    note(1), note(2);
    CHECK(steps == 2 && order[0] == 1 && order[1] == 2);

    /* Three operands. */
    steps = 0;
    note(3), note(4), note(5);
    CHECK(steps == 3 && order[0] == 3 && order[1] == 4 && order[2] == 5);

    /* The compound assignment's target is addressed once, so a side effect in
     * its subscript runs once. */
    evaluations = 0;
    steps = 0;
    arr[next_index()] += 5, note(6);
    CHECK(arr[0] == 15 && evaluations == 1 && steps == 1 && order[0] == 6);

    /* The comma in a declaration still declares two objects. */
    {
        int c = 1, d = 2;
        CHECK(c == 1 && d == 2);
    }

    /* The comma in a for clause still separates its statements. */
    for (i = 0, j = 3; i < j; i++, j--) {
    }
    CHECK(i == 2 && j == 1);

    /* A comma inside parentheses is still the comma operator. */
    CHECK((a = 1, a + 4) == 5 && a == 1);
    return 0;
}
