/* 0077: a case label is an integer constant expression

`case 1 + 1:`, `case (1 << 3):` and `case A + 1:`, with A an enumerator, were
refused with `unsupported: this case value is not one this reader reduces to an
integer constant, and only a written integer constant or one of those negated is
read`.  6.8.4.2p3 asks for an integer constant expression, and 6.6 makes all of
these one: gcc 16.2.1 accepts every label below under `-std=c99`.  Lua 5.4.8
writes `case LUA_VSHRSTR:`, whose macro is shifts and `|` over the tag, and
cJSON 1.7.18 writes `case cJSON_NULL:`, whose macro is `(1 << 2)`.  Fixed in
d849488 ("parser: fold a case label as a constant expression").
 */

#include <stdio.h>
#include <string.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);      \
            return 1;                                                         \
        }                                                                     \
    } while (0)

/* The shape Lua 5.4.8's lapi.c writes: makevariant(m, t) is a function-like
 * macro of shifts and `|`, and the labels are its expansions. */
#define VARIANT(m, t) (((m) << 4) | (t))
#define TSTRING 4
#define VSHRSTR VARIANT(TSTRING, 0)

/* The shape cJSON 1.7.18 writes: a parenthesized shift. */
#define CJSON_NULL (1 << 2)

enum kind { KNULL = 0, KFALSE, KTRUE };

static const char *taken;

static void label_of(int value)
{
    taken = "none";
    switch (value) {
    case VSHRSTR:
        taken = "VSHRSTR";
        break;
    case VARIANT(TSTRING, 1):
        taken = "VARIANT(TSTRING, 1)";
        break;
    case KNULL:
        taken = "KNULL";
        break;
    case KTRUE + 1:
        taken = "KTRUE + 1";
        break;
    case 1 + 1:
        taken = "1 + 1";
        break;
    case CJSON_NULL:
        taken = "CJSON_NULL";
        break;
    case (3 << 2) | 1:
        taken = "(3 << 2) | 1";
        break;
    case sizeof(int) * 3:
        taken = "sizeof(int) * 3";
        break;
    default:
        taken = "default";
        break;
    }
}

static int arm_is(const char *name)
{
    return strcmp(taken, name) == 0;
}

int main(void)
{
    /* Each label is the value its expression works out to: VARIANT(4, 0) is 64,
     * VARIANT(4, 1) is 65, KTRUE + 1 is 3, 1 + 1 is 2, (1 << 2) is 4,
     * (3 << 2) | 1 is 13, and sizeof(int) * 3 is 12. */
    label_of(VSHRSTR);
    CHECK(arm_is("VSHRSTR"));
    label_of(64);
    CHECK(arm_is("VSHRSTR"));
    label_of(VARIANT(TSTRING, 1));
    CHECK(arm_is("VARIANT(TSTRING, 1)"));
    label_of(KNULL);
    CHECK(arm_is("KNULL"));
    label_of(KTRUE + 1);
    CHECK(arm_is("KTRUE + 1"));
    label_of(1 + 1);
    CHECK(arm_is("1 + 1"));
    label_of(CJSON_NULL);
    CHECK(arm_is("CJSON_NULL"));
    label_of((3 << 2) | 1);
    CHECK(arm_is("(3 << 2) | 1"));
    label_of(sizeof(int) * 3);
    CHECK(arm_is("sizeof(int) * 3"));

    /* A value no label names falls through to the default arm, including one
     * beside an expanded label where a shift or a `|` could have gone wrong:
     * 66 is VARIANT(4, 2), 5 is between (1 << 2) and 1 + 1, 7 is between
     * KNULL + 1 and sizeof(int) * 3, and 14 is one above (3 << 2) | 1. */
    label_of(66);
    CHECK(arm_is("default"));
    label_of(5);
    CHECK(arm_is("default"));
    label_of(7);
    CHECK(arm_is("default"));
    label_of(14);
    CHECK(arm_is("default"));
    return 0;
}
