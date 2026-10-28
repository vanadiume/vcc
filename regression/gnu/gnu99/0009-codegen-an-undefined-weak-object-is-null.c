/* 0009: an undefined weak object is the null address

The weak attribute (GCC 6.4.1) on an object this file declares and does not
define is an undefined weak symbol, which ELF gives the address zero. gcc links
`extern int slot __attribute__((weak));` and reads `&slot` through the global
offset table, so the program runs and the address is null; it writes
R_X86_64_GLOB_DAT against the name in a non-position-independent executable and
does it for a name a library does define as well, which is what says the table
is the answer and not a copy of the library's storage.

This compiler refused the same file instead:

    vcc: undefined reference to `slot`: no library the image names defines it

because an `extern` object took the copy-object path, and a copy asks a library
for the object's bytes and has the loader copy them in — a shape that needs a
definition to exist. The name never reached the table, so the weakness was never
consulted. Fixed by "codegen: an undefined weak object is read through the
table", with the reader keeping the attribute on an `extern` declaration and the
container naming the imported object as an object.

Every check returns non-zero and writes one line saying what it found, because
for a regression case a line of output is itself the regression; gcc runs this
file to exit 0 under -std=gnu99 -w, which is the half that says the answer is
C's rather than this tree's.

The three lines the fix has to keep apart are all here: the address of an
undefined weak object is null, a weak definition in this file is this file's
storage, and a weak declaration beside a definition is a definition. */

#include <stdio.h>

extern int slot __attribute__((weak));

static int *p = &slot;

int defined __attribute__((weak)) = 0;

extern int beside __attribute__((weak));

int beside = 4;

int main(void)
{
    if (&slot != 0) {
        fprintf(stderr, "the address of an undefined weak object was not null\n");
        return 1;
    }
    if (p != 0) {
        fprintf(stderr, "a file-scope pointer initialized to the address of an undefined weak object was not null\n");
        return 1;
    }
    if (&defined == 0) {
        fprintf(stderr, "a weak definition in this file has no address\n");
        return 1;
    }
    if (defined != 0) {
        fprintf(stderr, "a weak definition in this file did not hold its initializer\n");
        return 1;
    }
    if (&beside == 0) {
        fprintf(stderr, "a weak declaration beside its definition was read as undefined\n");
        return 1;
    }
    if (beside != 4) {
        fprintf(stderr, "a weak declaration beside its definition read %d\n", beside);
        return 1;
    }
    return 0;
}
