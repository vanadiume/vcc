/* 0014: CHECK(hook == 0); CHECK(&slot == 0); CHECK(beside() == 5);
 *
 * An undefined weak import is the address zero, and this program names two of
 * them without defining either: a function reached by `hook == 0` and an object
 * reached by `&slot`. The single file was already right; the same declarations
 * carried through a link of relocatable objects were not. The symbol table of
 * the object said WEAK UND, and the reference was then written as a distance to
 * the name, which the link answers with the call stub the name is also called
 * through: the address a program read was the stub's, so `if (hook) hook();`
 * tested true where nothing defines `hook`, made the call, and jumped through the
 * stub's slot to zero. An object writes the read of the global offset table's
 * slot now, as a program already did, and the slot is zero when nothing defines
 * the name.
 *
 * glibc's <sys/cdefs.h> is why the attribute has to be spelled in a GNU dialect
 * here: when the compiler claims no GNU identity the header defines
 * `__attribute__(xyz)` away, and the declaration becomes a plain import that a
 * link is right to refuse. The corpus compiles its gnu directory with
 * -std=gnu99, which is the mode this compiler answers the header's question in.
 *
 * The last line is the decision the fix must not cross: a weak import a unit of
 * the link defines binds to that definition, so its address is not zero and a
 * call through it reaches the definition's code. The name is a weak *import*
 * only while nothing answers it.
 *
 * gcc 16.2.1 links and runs the same file to exit 0 under -std=gnu99 -w. */

#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

extern int hook(void) __attribute__((weak));
extern int slot __attribute__((weak));

extern int beside(void) __attribute__((weak));
int beside(void) { return 5; }

int present(void) { return 3; }

/* Never called, and it has to be compiled anyway: a call to a name nothing
 * defines is a reference the link writes as the zero, and a program that calls
 * it without asking jumps there. The reference compiling is what this is for. */
static int call_it(void) { return hook(); }

int main(void)
{
    /* The address of an undefined weak function is zero, and the test a
     * feature-detection idiom is built from skips the call. */
    CHECK(hook == 0);
    if (hook) {
        return call_it();
    }

    /* The same for an object: the address is zero and no storage was copied. */
    CHECK(&slot == 0);

    /* The names the image does define are where they always were: the zero is
     * the undefined weak symbol's and not every address's. */
    CHECK(present != 0);
    CHECK(present() == 3);

    /* A weak declaration beside its definition is a definition, weak or not. */
    CHECK(beside != 0);
    CHECK(beside() == 5);
    return 0;
}
