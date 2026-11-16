/* 0075: a compound assignment to an element of a struct-member array

`s.a[0] += 1` and `p->a[0] += 1` were refused with `unsupported: the compound
assignment += to an element is not implemented`, for all ten operators.  The
statement reader had a path for a compound assignment whose target is an
element, and it accepted only `=`: an element of a plain array or of a pointer
reaches the name reader, which builds the expansion, while an element whose
base is a member reaches the subscript reader, which refused every compound
spelling.  The back end already computed the address of such a target once and
read and wrote through it, so the refusal was the only thing standing in the
way; `sqlite3.c:25403` writes `wsdStat.nowValue[op] += N`, and `nowValue` is an
array member.

Fixed in this commit ("parser: read a compound assignment to an element of a
member array").
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

struct S {
    int a[4];
    char c[4];
};

int main(void)
{
    struct S s;
    struct S *p = &s;

    /* All ten operators, on an element that is not index 0, through the
     * object: an offset that wrote the wrong slot leaves a[1] or a[3]
     * changed and this element not. */
    s.a[2] = 10;
    s.a[1] = 111;
    s.a[3] = -999;
    s.a[2] += 7;
    CHECK(s.a[2] == 17);
    s.a[2] -= 3;
    CHECK(s.a[2] == 14);
    s.a[2] *= 5;
    CHECK(s.a[2] == 70);
    s.a[2] /= 4;
    CHECK(s.a[2] == 17);
    s.a[2] %= 5;
    CHECK(s.a[2] == 2);
    s.a[2] <<= 6;
    CHECK(s.a[2] == 128);
    s.a[2] >>= 3;
    CHECK(s.a[2] == 16);
    s.a[2] &= 0x1c;
    CHECK(s.a[2] == 16);
    s.a[2] |= 0x03;
    CHECK(s.a[2] == 19);
    s.a[2] ^= 0x11;
    CHECK(s.a[2] == 2);
    CHECK(s.a[1] == 111 && s.a[3] == -999);

    /* The same ten through the pointer, on the last element. */
    p->a[3] = -40;
    p->a[3] += 9;
    CHECK(p->a[3] == -31);
    p->a[3] -= 4;
    CHECK(p->a[3] == -35);
    p->a[3] *= 3;
    CHECK(p->a[3] == -105);
    p->a[3] /= 2;
    CHECK(p->a[3] == -52);
    p->a[3] %= 10;
    CHECK(p->a[3] == -2);
    p->a[3] <<= 4;
    CHECK(p->a[3] == -32);
    p->a[3] >>= 1;
    CHECK(p->a[3] == -16);
    p->a[3] &= 0xf0;
    CHECK(p->a[3] == 240);
    p->a[3] |= 0x0f;
    CHECK(p->a[3] == 255);
    p->a[3] ^= 0x3c;
    CHECK(p->a[3] == 195);
    CHECK(s.a[2] == 2);

    /* An element whose type is one byte: the arithmetic is done at the width
     * of an int and the store is one byte, so the neighbour keeps its own
     * value. */
    s.c[0] = 60;
    s.c[1] = 60;
    s.c[2] = 60;
    s.c[3] = 60;
    s.c[3] += 5;
    CHECK(s.c[3] == 65);
    p->c[1] -= 10;
    CHECK(s.c[1] == 50);
    s.c[2] *= 2;
    CHECK(s.c[2] == 120);
    CHECK(s.c[0] == 60);

    /* An element whose index is computed and steps: the address is worked out
     * once, so the index moves by one and not by two. */
    {
        int i = 1;
        p->a[i++] += 40;
        CHECK(i == 2);
        CHECK(p->a[1] == 151);
    }
    return 0;
}
