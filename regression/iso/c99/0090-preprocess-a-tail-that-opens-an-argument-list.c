/* 0090: a replacement that opens an argument list reads it from the file

`#define A F(` beside the function-like `F` was refused with `the arguments of
F have no closing )`, where gcc expands `A 1)` to `F(1)`.  C99 6.10.3p4
rescans a replacement together with the rest of the file, so the `(` the
replacement ends with opens a list whose arguments are the tokens after the
use.  An alias between the use and the macro is the same shape, and so is a
replacement a call produced.  Fixed in 7a0ef96 ("preprocess: a replacement that
opens an argument list reads it from the file").
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

#define INC(x) ((x) + 1)
#define ADD(a, b) ((a) + (b))
#define ID(x) x

/* The replacement ends with the ( that opens the list. */
#define OPEN_INC INC(
#define OPEN_ADD ADD(
#define OPEN_ID ID(

/* The list is complete in the replacement, so nothing follows the use. */
#define COMPLETE INC(6)

/* The replacement a call produces ends with the (. */
#define OPEN_VIA(y) INC(

/* An alias stands between the use and the macro whose replacement opens it. */
#define ALIAS_INC OPEN_INC

int main(void)
{
    int value;

    /* The source finishes the list the replacement opened. */
    value = OPEN_INC 4);
    CHECK(value == 5);
    value = OPEN_ADD 2, 3);
    CHECK(value == 5);

    /* The text after the closing ) is read where it stands, once. */
    value = OPEN_ID 3) + 4;
    CHECK(value == 7);

    /* A replacement whose list is complete needs nothing after the use. */
    value = COMPLETE;
    CHECK(value == 7);

    /* The replacement a call produced opens the list the same way. */
    value = OPEN_VIA(1) 9);
    CHECK(value == 10);

    /* The same shape through an alias. */
    value = ALIAS_INC 11);
    CHECK(value == 12);

    return 0;
}
