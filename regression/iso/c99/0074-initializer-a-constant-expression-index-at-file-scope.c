/* 0074: a constant-expression index in a file-scope address initializer

`int *p = &a[1 + 1];` was refused with `unsupported: expected ], found '+'`,
while `&a[2]` and `&a[(1 + 1)]` were accepted.  The subscript reader took a
written constant as the whole subscript and stopped at the number, so anything
that began with one and went on with an operator never reached the folder that
reads it.  It answers with the written number only when the bracket closes
straight after it now, and every other expression goes to the folder, which is
what `&sqlite3UpperToLower[256-OP_Ne]` needs.  Fixes #26.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

enum { OP_Ne = 69 };

static unsigned char table[512];
static int a[8];

/* The three shapes SQLite 3.54.1 writes at sqlite3.c:24210-24212. */
static const unsigned char *lt = &table[256 - OP_Ne];
static const unsigned char *eq = &table[256 + 6 - OP_Ne];
static const unsigned char *gt = &table[256 + 12 - OP_Ne];

/* An index that starts with a written number and goes on with an operator. */
static int *two = &a[1 + 1];

/* The same expression inside parentheses, which the folder read already. */
static int *five = &a[(2 + 3)];

/* A negative term, and a prefix minus inside the brackets. */
static int *three = &a[-1 + 4];
static int *minus_two = &a[-(-2)];

/* A product, so the value is a fold and not a sum of two written numbers. */
static int *six = &a[2 * 3];

/* A string literal is read by the same subscript reader. */
static const char *tail = &"abcdef"[1 + 1];

int main(void)
{
    /* The byte each pointer names is the byte the index scales to, so an
     * offset that was dropped or never scaled answers a different address. */
    CHECK(lt == &table[187]);
    CHECK(eq == &table[193]);
    CHECK(gt == &table[199]);
    CHECK(lt < gt && eq - lt == 6 && gt - lt == 12);

    CHECK(two == &a[2]);
    CHECK(*two == a[2]);
    CHECK(five == &a[5]);
    CHECK(three == &a[3]);
    CHECK(minus_two == &a[2]);
    CHECK(six == &a[6]);
    CHECK(two - &a[0] == 2);
    CHECK(six - &a[0] == 6);

    CHECK(tail[0] == 'c' && tail[1] == 'd' && tail[2] == 'e');
    return 0;
}
