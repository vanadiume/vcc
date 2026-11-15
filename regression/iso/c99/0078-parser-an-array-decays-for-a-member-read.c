/* 0078: an array of struct is read through -> after decaying to a pointer

`p->x` was refused with `unsupported: p is read through ->, and it is declared
struct P[1] rather than a pointer`, although 6.3.2.1p3 converts an array to a
pointer to its first element everywhere except the operand of `sizeof`,
`_Alignof` or `&`, and the left operand of `->` is none of those.  The refusal
blocked cJSON 1.7.18, which declares its handle as `struct { ... } buffer[1]`
and then writes `buffer->buffer` and `buffer->length`, so cJSON.c stopped at
its first use.  Fixed by decaying the array before the pointer is asked for.

The values are checked rather than the compile: a reader that added the member
offset to the array's own address without reading through the first element
would compile and answer from the wrong bytes wherever the member is not at
offset zero.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

struct P {
    int x;
    int y;
};

struct P global[1] = {{ 11, 12 }};

int main(void)
{
    /* The cJSON shape: a one-element array of an anonymous struct, written
     * and read through ->, with the pointer member first and the count after
     * it. */
    int value = 41;
    struct {
        unsigned char *buffer;
        size_t length;
    } handle[1];

    handle->buffer = (unsigned char *)&value;
    handle->length = 7;
    CHECK(handle->length == 7);
    CHECK(*handle->buffer == 41);
    CHECK(handle[0].length == 7);
    CHECK((*handle).length == 7);

    /* A named array of struct, read and written through ->.  Both members sit
     * at a non-zero offset in the element, so a store at the array's own
     * address would not pass these checks. */
    struct P p[1] = {{ 3, 4 }};
    CHECK(p->x == 3);
    CHECK(p->y == 4);
    p->x = 5;
    p->y = 6;
    CHECK(p->x == 5 && p->y == 6);
    CHECK(p[0].x == 5 && p[0].y == 6);

    /* The same access on a top-level array. */
    CHECK(global->x == 11 && global->y == 12);
    global->x = 13;
    CHECK(global[0].x == 13);

    /* A row of an array of arrays decays after the subscript. */
    struct P rows[2][1] = {{{ 21, 22 }}, {{ 23, 24 }}};
    CHECK(rows[1]->x == 23 && rows[1]->y == 24);
    rows[1]->y = 25;
    CHECK(rows[1][0].y == 25);

    /* A real pointer reads and writes the same member through -> as before. */
    struct P q = { 8, 9 };
    struct P *real = &q;
    CHECK(real->x == 8 && real->y == 9);
    real->x = 10;
    CHECK(q.x == 10 && real->x == 10);

    return 0;
}
