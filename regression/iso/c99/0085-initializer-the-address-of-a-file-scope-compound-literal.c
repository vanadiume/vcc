/* 0085: the address of a file-scope compound literal is an address constant

`struct S *s = &(struct S){1, 2};` was refused with `unsupported: the operand of
& in a file-scope initializer has to be a name or a string literal`.  6.5.2.5p5
gives a compound literal outside the body of a function static storage duration,
and 6.6p9 makes the address of an object with static storage duration an address
constant, so the initializer is one a file-scope pointer may hold.  The reader
knew how to build the unnamed object for an array literal and for an aggregate
literal used as a value; the operand of `&` now reaches the same builder.
Fixed in b0af3d8 ("parser: the address of a file-scope compound literal").
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

struct S { int a; int b; };
struct P { struct S s; int n; };

/* The value the initializer holds, and the members the pointer reaches. */
static struct S *s = &(struct S){1, 2};

/* A scalar literal is one value, and its object is written the same way. */
static int *one = &(int){5};

/* The idiom the issue names: a static table of pointers into statically
 * initialized records, one positional, one designated, one with the members it
 * did not write left at the zeros 6.7.8p21 gives them. */
static struct S *table[3] = {
    &(struct S){3, 4},
    &(struct S){.a = 5, .b = 6},
    &(struct S){7}
};

/* An element that is itself a record, so the list is walked into the
 * sub-object. */
static struct P *p = &(struct P){{8, 9}, 10};

static void bump(void) { s->a = 11; }

int main(void)
{
    CHECK(s->a == 1 && s->b == 2);
    CHECK(*one == 5);
    CHECK(table[0]->a == 3 && table[0]->b == 4);
    CHECK(table[1]->a == 5 && table[1]->b == 6);
    CHECK(table[2]->a == 7 && table[2]->b == 0);
    CHECK(p->s.a == 8 && p->s.b == 9 && p->n == 10);

    /* The object is storage and not something rebuilt on each read: a write
     * through the pointer is read back through it, and the member beside it
     * keeps its value. */
    bump();
    CHECK(s->a == 11 && s->b == 2);

    /* Three literals are three objects, so the table's entries are three
     * distinct addresses. */
    CHECK(table[0] != table[1] && table[1] != table[2]);

    {
        /* The block-scope shape worked before this and still does, and the
         * object there is still one of its own. */
        struct S *local = &(struct S){12, 13};
        CHECK(local->a == 12 && local->b == 13);
        CHECK(&(int){0} != &(int){0});
    }
    return 0;
}
