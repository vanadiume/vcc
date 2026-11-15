/* 0082: an aggregate of eleven to fifteen bytes passed by value and returned

A structure of 11, 13, 14 or 15 bytes is two eightbytes, and the second one has a
tail of 3, 5, 6 or 7 bytes that no x86-64 move covers.  The argument path asked
the machine for a move at that width and the compiler refused with an internal
error: `x86_64: a value of 3 bytes is not one this machine moves through the
frame`.  The tail is now read and stored a chunk at a time, in the machine
encoders, out of and into the object's own bytes, which is the shape gcc emits
for the same argument.

Every byte is filled with a value that depends on its position, so a tail read
out of order or shifted changes the checksum the callee computes.  Each size is
passed as the first argument, as one argument among others that follow it, and
as the last argument after five integers, where the convention puts it on the
stack.  A fifteen-byte one is passed twice, each size is returned by value, and
a read-only object is passed the same way.
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

static unsigned int fnv(const unsigned char *p, unsigned int n)
{
    unsigned int h = 2166136261u;
    unsigned int i;
    for (i = 0; i < n; i++) {
        h ^= p[i];
        h *= 16777619u;
    }
    return h;
}

static unsigned char byte_at(unsigned int n, unsigned int i)
{
    return (unsigned char)(0x30 + ((i * 37u + n * 11u) & 0x7f));
}

struct S11 {
    unsigned char x[11];
};

struct S13 {
    unsigned char x[13];
};

struct S14 {
    unsigned char x[14];
};

struct S15 {
    unsigned char x[15];
};

static unsigned int arg_S11(struct S11 a);
static unsigned int after_S11(struct S11 a, int b, int c, int d, int e);
static unsigned int late_S11(int b, int c, int d, int e, int f, struct S11 a, int g);
static struct S11 echo_S11(struct S11 a);
static struct S11 make_S11(void);
static unsigned int arg_S13(struct S13 a);
static unsigned int after_S13(struct S13 a, int b, int c, int d, int e);
static unsigned int late_S13(int b, int c, int d, int e, int f, struct S13 a, int g);
static struct S13 echo_S13(struct S13 a);
static struct S13 make_S13(void);
static unsigned int arg_S14(struct S14 a);
static unsigned int after_S14(struct S14 a, int b, int c, int d, int e);
static unsigned int late_S14(int b, int c, int d, int e, int f, struct S14 a, int g);
static struct S14 echo_S14(struct S14 a);
static struct S14 make_S14(void);
static unsigned int arg_S15(struct S15 a);
static unsigned int after_S15(struct S15 a, int b, int c, int d, int e);
static unsigned int late_S15(int b, int c, int d, int e, int f, struct S15 a, int g);
static struct S15 echo_S15(struct S15 a);
static struct S15 make_S15(void);

static const struct S11 ro11 = { { 169, 78, 115, 152, 61, 98, 135, 172, 81, 118, 155 } };
static const struct S13 ro13 = { { 63, 100, 137, 174, 83, 120, 157, 66, 103, 140, 49, 86, 123 } };
static const struct S14 ro14 = { { 74, 111, 148, 57, 94, 131, 168, 77, 114, 151, 60, 97, 134, 171 } };
static const struct S15 ro15 = { { 85, 122, 159, 68, 105, 142, 51, 88, 125, 162, 71, 108, 145, 54, 91 } };

/* One set of functions per size: the callee reads the bytes the caller wrote, in
 * the order they were written, and every scalar argument after the structure is
 * part of the answer so that a clobbered argument register shows. */
#define DEFINE(N, S)                                                          \
    static unsigned int arg_##S(struct S a)                                   \
    {                                                                         \
        return fnv(a.x, N);                                                   \
    }                                                                         \
    static unsigned int after_##S(struct S a, int b, int c, int d, int e)     \
    {                                                                         \
        return fnv(a.x, N) ^ (unsigned int)b * 3u ^ (unsigned int)c * 5u      \
            ^ (unsigned int)d * 7u ^ (unsigned int)e * 11u;                   \
    }                                                                         \
    static unsigned int late_##S(int b, int c, int d, int e, int f,           \
                                 struct S a, int g)                           \
    {                                                                         \
        return fnv(a.x, N) ^ (unsigned int)b * 3u ^ (unsigned int)c * 5u      \
            ^ (unsigned int)d * 7u ^ (unsigned int)e * 11u                    \
            ^ (unsigned int)f * 13u ^ (unsigned int)g * 17u;                  \
    }                                                                         \
    static struct S echo_##S(struct S a)                                      \
    {                                                                         \
        return a;                                                             \
    }                                                                         \
    static struct S make_##S(void)                                            \
    {                                                                         \
        struct S s;                                                           \
        unsigned int i;                                                       \
        for (i = 0; i < N; i++)                                               \
            s.x[i] = byte_at(N, i);                                           \
        return s;                                                             \
    }

DEFINE(11, S11)
DEFINE(13, S13)
DEFINE(14, S14)
DEFINE(15, S15)

static unsigned int twice15(struct S15 a, struct S15 b)
{
    unsigned int h = 2166136261u;
    unsigned int i;
    for (i = 0; i < 15; i++) {
        h ^= a.x[i];
        h *= 16777619u;
    }
    for (i = 0; i < 15; i++) {
        h ^= b.x[i];
        h *= 16777619u;
    }
    return h;
}

#define CHECK_SIZE(N, S, RO)                                                 \
    do {                                                                      \
        struct S a;                                                           \
        unsigned int i;                                                       \
        for (i = 0; i < N; i++)                                               \
            a.x[i] = byte_at(N, i);                                           \
        CHECK(arg_##S(a) == fnv(a.x, N));                                     \
        CHECK(after_##S(a, 3, 5, 7, 11) == (fnv(a.x, N)                       \
               ^ 3u * 3u ^ 5u * 5u ^ 7u * 7u ^ 11u * 11u));                    \
        CHECK(late_##S(3, 5, 7, 11, 13, a, 17) == (fnv(a.x, N)                \
               ^ 3u * 3u ^ 5u * 5u ^ 7u * 7u ^ 11u * 11u                       \
               ^ 13u * 13u ^ 17u * 17u));                                      \
        {                                                                     \
            struct S r = echo_##S(a);                                         \
            struct S m = make_##S();                                          \
            for (i = 0; i < N; i++) {                                         \
                CHECK(r.x[i] == a.x[i]);                                      \
                CHECK(m.x[i] == a.x[i]);                                      \
            }                                                                 \
        }                                                                     \
        CHECK(arg_##S(RO) == fnv(a.x, N));                                    \
    } while (0)

int main(void)
{
    CHECK_SIZE(11, S11, ro11);
    CHECK_SIZE(13, S13, ro13);
    CHECK_SIZE(14, S14, ro14);
    CHECK_SIZE(15, S15, ro15);

    {
        struct S15 a;
        struct S15 b;
        unsigned int i;
        unsigned int h;
        for (i = 0; i < 15; i++) {
            a.x[i] = byte_at(15, i);
            b.x[i] = (unsigned char)(0x80 + ((i * 53u + 7u) & 0x3fu));
        }
        h = 2166136261u;
        for (i = 0; i < 15; i++) {
            h ^= a.x[i];
            h *= 16777619u;
        }
        for (i = 0; i < 15; i++) {
            h ^= a.x[i];
            h *= 16777619u;
        }
        CHECK(twice15(a, a) == h);
        h = 2166136261u;
        for (i = 0; i < 15; i++) {
            h ^= a.x[i];
            h *= 16777619u;
        }
        for (i = 0; i < 15; i++) {
            h ^= b.x[i];
            h *= 16777619u;
        }
        CHECK(twice15(a, b) == h);
    }
    return 0;
}
