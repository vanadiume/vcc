/* 0081: a narrow store of a wide value

Assigning a 64-bit integer to a narrower lvalue was refused with `unsupported: a
value of 8 bytes is stored into an object that holds 4`, for a top-level object,
a member, an element and a write through a pointer. The conversion is the one
6.3.1.3 defines, and it was already made in an initializer, an argument, a
return and a cast; only the assignment refused it. What the store writes is the
low bytes of the value, read back at the type of the object: -1 into an unsigned
char is 255, 0x1_0000_0005 into an int is 5, and LONG_MIN into an int is 0.
Fixed in 1d95b80 ("codegen: narrow a wide integer into the object it is stored
into").

A narrowed store also has to leave the bytes beside its object alone, which each
group below checks with a neighbour. A bitfield is the same store cut to the
field's bits, and a top-level `_Bool` holds 0 or 1 afterwards whatever was
written into it (6.3.1.2), so `gb = 0x1_0000_0000` leaves 1.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

/* LONG_MIN is spelled out rather than read from limits.h, which these cases do
 * not otherwise need. */
#define LONG_MIN_VALUE (-9223372036854775807L - 1L)

struct Pair {
    int f;
    int tail;
};

struct Bits {
    unsigned f : 3;
    int tail;
};

static long wide;
static int gi;
static unsigned gu;
static short gs;
static char gc;
static _Bool gb;
static struct Pair gp;
static int ga[2];

static int take_int(int value)
{
    return value;
}

static int gives_back(void)
{
    long l = 0x100000005L;

    return l;
}

int main(void)
{
    int i;
    unsigned u;
    short s;
    char c;
    unsigned char uc;
    struct Pair p;
    struct Bits bits;
    int a[2];
    int *ip;
    struct Pair *pp;

    /* A plain object, read back signed: the low bytes are the value and the
     * read sign-extends them, so 0xFFFFFFFF reads as -1 and not 4294967295. */
    wide = 0x100000005L;
    i = 0;
    i = wide;
    CHECK(i == 5);
    wide = -1;
    i = 0;
    i = wide;
    CHECK(i == -1);
    wide = 0xFFFFFFFFL;
    i = 0;
    i = wide;
    CHECK(i == -1);
    wide = LONG_MIN_VALUE;
    i = 123;
    i = wide;
    CHECK(i == 0);
    wide = 0x7FFFFFFFL;
    i = 0;
    i = wide;
    CHECK(i == 2147483647);

    /* Unsigned and narrow destinations. */
    wide = -1;
    u = 0;
    u = wide;
    CHECK(u == 4294967295U);
    wide = 0x100000005L;
    u = 0;
    u = wide;
    CHECK(u == 5U);
    wide = -1;
    s = 0;
    s = wide;
    CHECK(s == -1);
    wide = 0x100018000L;
    s = 0;
    s = wide;
    CHECK(s == -32768);
    wide = -1;
    c = 0;
    c = wide;
    CHECK(c == -1);
    wide = 0x100000041L;
    c = 0;
    c = wide;
    CHECK(c == 'A');
    wide = -1;
    uc = 0;
    uc = wide;
    CHECK(uc == 255);
    wide = 0x100000041L;
    uc = 0;
    uc = wide;
    CHECK(uc == 65);

    /* The same four destinations at the top level. */
    wide = 0x100000005L;
    gi = 0;
    gi = wide;
    CHECK(gi == 5);
    wide = -1;
    gu = 0;
    gu = wide;
    CHECK(gu == 4294967295U);
    wide = -1;
    gs = 0;
    gs = wide;
    CHECK(gs == -1);
    wide = -1;
    gc = 0;
    gc = wide;
    CHECK(gc == -1);

    /* A compound assignment adds at the source's width and stores the sum
     * narrowed, so 10 + 0x1_0000_0000 is 10 in an int. */
    wide = 0x100000000L;
    i = 10;
    i += wide;
    CHECK(i == 10);
    wide = 0xFFFFFFFFL;
    i = -5;
    i += wide;
    CHECK(i == -6);
    wide = 0x100000000L;
    gi = 7;
    gi += wide;
    CHECK(gi == 7);
    wide = 0x100000000L;
    p.f = 1;
    p.f += wide;
    CHECK(p.f == 1);

    /* A member, and the member after it. */
    wide = 0x100000005L;
    p.f = 0;
    p.tail = 77;
    p.f = wide;
    CHECK(p.f == 5 && p.tail == 77);
    wide = -1;
    gp.f = 0;
    gp.tail = 66;
    gp.f = wide;
    CHECK(gp.f == -1 && gp.tail == 66);

    /* An element, and the element after it, in a local array and a top-level
     * one. */
    wide = 0x100000005L;
    a[0] = 0;
    a[1] = 99;
    a[0] = wide;
    CHECK(a[0] == 5 && a[1] == 99);
    ga[0] = 0;
    ga[1] = 98;
    ga[0] = wide;
    CHECK(ga[0] == 5 && ga[1] == 98);

    /* A write through a pointer, and through a pointer into a structure. */
    wide = -1;
    i = 0;
    ip = &i;
    *ip = wide;
    CHECK(i == -1);
    wide = 0x100000005L;
    i = 0;
    ip = &i;
    *ip = wide;
    CHECK(i == 5);
    wide = 0x100000000L;
    i = 3;
    ip = &i;
    *ip += wide;
    CHECK(i == 3);
    wide = -1;
    p.f = 0;
    p.tail = 55;
    pp = &p;
    pp->f = wide;
    CHECK(pp->f == -1 && pp->tail == 55);

    /* A bitfield is cut to its own bits after the narrowing conversion: 13 in
     * three bits is 5, and the member after it is not touched. */
    wide = 0x10000000DL;
    bits.f = 0;
    bits.tail = 44;
    bits.f = wide;
    CHECK(bits.f == 5 && bits.tail == 44);
    wide = -1;
    bits.f = wide;
    CHECK(bits.f == 7);

    /* A top-level `_Bool` holds 0 or 1 whatever was written into it, and the
     * test is of the whole value: 0x1_0000_0000 has a zero low byte. */
    wide = 0x100000000L;
    gb = 0;
    gb = wide;
    CHECK(gb == 1);

    /* The shapes that already worked still do. */
    wide = 0x100000005L;
    {
        int j = wide;

        CHECK(j == 5);
    }
    CHECK(take_int(wide) == 5);
    CHECK(gives_back() == 5);
    CHECK((int)wide == 5);
    return 0;
}
