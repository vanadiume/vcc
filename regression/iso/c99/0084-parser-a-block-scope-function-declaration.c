/* 0084: a function declared in a body is a name the block calls

C99 6.2.1p4 makes the block a declaration's scope, and 6.2.2p5 gives a function
declared there the linkage an `extern` declaration would have, so a block-scope
`int f(char *);` declares the function the file declares outside it.  The
declaration was given a symbol built from the enclosing function's name instead,
`main.f`, which no declaration in the file provides, and the call to it was
refused with `main.f is used here and nothing in this file declares it`.
c-testsuite 00078.c is written with exactly that declaration and call.

The call has to be emitted against the name the declaration wrote: a symbol the
reader invented for the declaration would either fail the link or define the
function twice, and this program links and runs.  The declaration is recorded as
an ordinary identifier with the linkage of the function it names, in the
declaration reader in parser/statements.v.  Fixed in 3e99b40 ("parser: a function
declaration in a body is an ordinary one"). */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

struct pair {
    int first;
    int second;
};

static int shadowed = 7;

static int f(char *p)
{
    return *p + 1;
}

int later(char *);

int main(void)
{
    char s = 1;
    int shadowed = 3;
    struct pair p = {4, 5};
    struct pair *q = &p;

    /* The shape c-testsuite 00078.c is written with: a block-scope declaration
       of a file-scope function, then a call that has to reach it. */
    int f(char *);
    CHECK(f(&s) == 2);

    /* The same declaration with the storage class it has implicitly. */
    {
        extern int f(char *);
        CHECK(f(&s) == 2);
    }

    /* The declaration is in scope to the end of its block. */
    CHECK(f(&s) == 2);

    /* A declaration whose function the file defines after the call: the name is
       the external one the declaration wrote, and the link answers for it. */
    int later(char *);
    CHECK(later(&s) == 3);

    /* An object declared beside the function still hides the file-scope one,
       and sizeof and member lookup inside the block are unaffected. */
    CHECK(shadowed == 3);
    CHECK(sizeof(struct pair) == 2 * sizeof(int));
    CHECK(q->second == 5 && p.first == 4);
    return 0;
}

int later(char *p)
{
    return *p + 2;
}
