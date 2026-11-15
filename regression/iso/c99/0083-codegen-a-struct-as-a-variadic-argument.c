/* 0083: a structure as a variadic argument and through va_arg

A structure written past the named parameters of a variadic call was refused
with `unsupported: <name> is an object of an aggregate type`, and reading one
in the callee with `__builtin_va_arg` was refused as an object handed over by
value that is not a name, an element or a member.  C99 6.5.2.2p6-7 passes a
structure as an argument of its own type, and 7.15.1.1 allows `va_arg` with a
type compatible with the argument.  Issue #41.  */

#include <stdio.h>
#include <stdarg.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

struct small {
    int a;
};

struct pair {
    int a;
    int b;
};

struct wide {
    long a;
    long b;
};

/* The structure is the first unnamed argument: it travels in a register. */
static int register_small(int n, ...)
{
    va_list ap;
    struct small s;
    int after;

    va_start(ap, n);
    s = va_arg(ap, struct small);
    after = va_arg(ap, int);
    va_end(ap);
    CHECK(n == 1);
    CHECK(s.a == 4);
    CHECK(after == 40);
    return 0;
}

static int register_pair(int n, ...)
{
    va_list ap;
    struct pair s;
    int after;

    va_start(ap, n);
    s = va_arg(ap, struct pair);
    after = va_arg(ap, int);
    va_end(ap);
    CHECK(n == 2);
    CHECK(s.a == 8 && s.b == 9);
    CHECK(after == 41);
    return 0;
}

static int register_wide(int n, ...)
{
    va_list ap;
    struct wide s;
    int after;

    va_start(ap, n);
    s = va_arg(ap, struct wide);
    after = va_arg(ap, int);
    va_end(ap);
    CHECK(n == 3);
    CHECK(s.a == 16 && s.b == 17);
    CHECK(after == 42);
    return 0;
}

/* Four unnamed ints fill the general register file, so the structure and the
 * int after it are passed on the stack. */
static int stack_small(int a, int b, ...)
{
    va_list ap;
    struct small s;
    int after;

    va_start(ap, b);
    CHECK(va_arg(ap, int) == 3);
    CHECK(va_arg(ap, int) == 4);
    CHECK(va_arg(ap, int) == 5);
    CHECK(va_arg(ap, int) == 6);
    s = va_arg(ap, struct small);
    after = va_arg(ap, int);
    va_end(ap);
    CHECK(a == 10 && b == 11);
    CHECK(s.a == 4);
    CHECK(after == 43);
    return 0;
}

static int stack_pair(int a, int b, ...)
{
    va_list ap;
    struct pair s;
    int after;

    va_start(ap, b);
    CHECK(va_arg(ap, int) == 3);
    CHECK(va_arg(ap, int) == 4);
    CHECK(va_arg(ap, int) == 5);
    CHECK(va_arg(ap, int) == 6);
    s = va_arg(ap, struct pair);
    after = va_arg(ap, int);
    va_end(ap);
    CHECK(a == 12 && b == 13);
    CHECK(s.a == 8 && s.b == 9);
    CHECK(after == 44);
    return 0;
}

static int stack_wide(int a, int b, ...)
{
    va_list ap;
    struct wide s;
    int after;

    va_start(ap, b);
    CHECK(va_arg(ap, int) == 3);
    CHECK(va_arg(ap, int) == 4);
    CHECK(va_arg(ap, int) == 5);
    CHECK(va_arg(ap, int) == 6);
    s = va_arg(ap, struct wide);
    after = va_arg(ap, int);
    va_end(ap);
    CHECK(a == 14 && b == 15);
    CHECK(s.a == 16 && s.b == 17);
    CHECK(after == 45);
    return 0;
}

/* A printf-shaped walk: an int, a structure, a double and an int, so the
 * structure is read out of the general file between two scalar arguments. */
static int mixed(const char *tag, ...)
{
    va_list ap;
    int first;
    struct pair s;
    double d;
    int last;

    va_start(ap, tag);
    first = va_arg(ap, int);
    s = va_arg(ap, struct pair);
    d = va_arg(ap, double);
    last = va_arg(ap, int);
    va_end(ap);
    CHECK(tag[0] == 'm');
    CHECK(first == 7);
    CHECK(s.a == 8 && s.b == 9);
    CHECK(d == 2.5);
    CHECK(last == 46);
    return 0;
}

/* A variadic call with no object in it keeps the walk it had. */
static int only_scalars(int n, ...)
{
    va_list ap;
    int a;
    double b;
    int c;

    va_start(ap, n);
    a = va_arg(ap, int);
    b = va_arg(ap, double);
    c = va_arg(ap, int);
    va_end(ap);
    CHECK(n == 50);
    CHECK(a == 51);
    CHECK(b == 3.25);
    CHECK(c == 52);
    return 0;
}

int main(void)
{
    struct small sm = { 4 };
    struct pair pr = { 8, 9 };
    struct wide wd = { 16, 17 };

    CHECK(register_small(1, sm, 40) == 0);
    CHECK(register_pair(2, pr, 41) == 0);
    CHECK(register_wide(3, wd, 42) == 0);

    CHECK(stack_small(10, 11, 3, 4, 5, 6, sm, 43) == 0);
    CHECK(stack_pair(12, 13, 3, 4, 5, 6, pr, 44) == 0);
    CHECK(stack_wide(14, 15, 3, 4, 5, 6, wd, 45) == 0);

    CHECK(mixed("mix", 7, pr, 2.5, 46) == 0);
    CHECK(only_scalars(50, 51, 3.25, 52) == 0);
    return 0;
}
