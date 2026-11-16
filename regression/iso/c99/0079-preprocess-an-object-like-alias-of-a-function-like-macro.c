/* 0079: an object-like alias of a function-like macro is a call

`#define G F` beside `#define F(x) ...` left `G(1)` as the name `F` followed
by `(1)`, and the parser then refused `F` as an undeclared name.  C99 6.10.3p4
rescans a replacement together with the rest of the source file, so a name an
expansion ends with is read with the `(` that follows the use and is a call.
An alias chain and a name a function-like expansion ends with are the same
rule.  `#define F F` and `#define G G(x)` are the guard: a name that arrives
during its own expansion is not replaced again.  Lua 5.4.8 writes
`#define setobj2n setobj` beside the function-like `setobj`.  Fixed in 9bdde26
("preprocess: rescan an object-like replacement with the text after it").
 */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

#define INC(x) ((x) + 1)
#define ALIAS INC
#define ALIAS_TWICE ALIAS
#define CHAIN_A CHAIN_B
#define CHAIN_B CHAIN_C
#define CHAIN_C INC
#define PRODUCE(x) ALIAS
#define SELF SELF
#define SELF_CALL SELF_CALL(void)
#define SELF_APPLY(x) SELF_APPLY(x)

/* The alias used without a `(` is the name `INC` and not a call, so a
 * variable of that name can stand where it is written. */
static int INC = 7;

/* SELF_CALL's replacement is a call to SELF_CALL, and SELF_APPLY's is an
 * invocation of itself.  Both names are painted where they arrive, so these
 * are declarations and not expansions. */
int SELF_CALL;
int SELF_APPLY(int);

int SELF = 1;

int main(void)
{
    /* The alias is a use of INC, and the ( after the use holds its argument. */
    CHECK(ALIAS(1) == 2);

    /* Three aliases stand between the use and the function-like macro. */
    CHECK(CHAIN_A(4) == 5);

    /* The name a function-like macro expands to takes the next ( as well. */
    CHECK(PRODUCE(0)(8) == 9);

    /* No `(` after the use: ALIAS_TWICE expands to the variable INC. */
    CHECK(ALIAS_TWICE + 1 == 8);

    /* The self-referential names above are a variable and declarations. */
    CHECK(SELF == 1);

    return 0;
}
