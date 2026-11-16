/* 0099: an empty parameter list is compatible with a (void) prototype

`void (*p)() = f;` for `void f(void)` was refused, and so was the reverse,
with `a constraint violation: void (void) * does not point to a type
compatible with what void () * points to`.  gcc 16.2.1 accepts both.  C99
6.7.5.3p15 makes a function type written with a parameter type list and one
written with an empty identifier list compatible when the list has no
ellipsis and every parameter type is compatible with its default-promoted
type, so `void()` and `void(void)` are one function type and `int()` and
`int(int)` are one, while `int()` and `int(char)` are not: a call through the
empty list hands over an int where the prototype names a char.

The call case is checked too, because the pair being compatible is only worth
something if an argument passed through the empty list is still promoted the
way the callee reads it.  `char` is promoted to int, so `r(c)` is `h(-3)`.
 */

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

#include <stdio.h>

void f(void) { }
void g() { }
int h(int x) { return x + 1; }

/* The declaration 8cc main.c:169 needs: the parameter is written `(void)` and
   the function registered with it is written `()`. */
int atexit(void (*)(void));

static void nothing(void) { }

int main(void)
{
    void (*p)() = f;
    void (*q)(void) = g;
    int (*r)() = h;
    int (*s)(int) = h;
    char c = -3;

    p();
    q();
    /* The empty list says nothing about the argument, so the call promotes the
       char to int and the callee reads -3, not the byte 0xfd. */
    CHECK(r(c) == -2);
    CHECK(s(c) == -2);
    CHECK(r(41) == 42);
    CHECK(s(41) == 42);

    atexit(nothing);
    atexit(g);
    return 0;
}
