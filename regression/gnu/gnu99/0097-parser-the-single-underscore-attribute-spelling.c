/* 0097: the single-underscore attribute spelling

GNU C reads `__attribute` as the same keyword as `__attribute__`, and gcc
16.2.1, clang and tcc accept both. libgc's `gc.h` writes the single-underscore
form, which is how V's build reached it. vcc compared the exact spelling
`__attribute__` in the two places that recognize an attribute, so a declaration
that opened with `__attribute` was refused with

    unsupported: expected a declaration, found '__attribute'

before anything else in the file was read. Fixed by "parser: read the
single-underscore __attribute spelling".

The shapes below are the positions the keyword can take: in front of a prototype
and a definition, between the declaration specifiers and the declarator, after a
declarator, and twice in a run of specifiers. Each check returns non-zero on the
shape that stopped being read, and the case prints nothing on purpose: for a
regression case a line of output is itself the regression. */

__attribute ((weak)) int weak_prefix(void);
__attribute ((weak)) int weak_prefix(void) { return 1; }

__attribute ((noreturn)) void spin(void)
{
    for (;;) {
    }
}

__attribute ((noinline)) int noinline_prefix(void) { return 2; }

__attribute ((weak)) __attribute ((noinline)) int two_specifiers(void) { return 3; }

int __attribute ((noinline)) between_specifiers(void) { return 4; }

int after_declarator(void) __attribute ((weak));
int after_declarator(void) { return 5; }

int main(void)
{
    if (weak_prefix() != 1)
        return 1;
    if (noinline_prefix() != 2)
        return 2;
    if (two_specifiers() != 3)
        return 3;
    if (between_specifiers() != 4)
        return 4;
    if (after_declarator() != 5)
        return 5;
    return 0;
}
