/* 0001: ctype-classifies-and-maps-characters
 *
 * ISO/IEC 9899:1999 7.4: the functions classify a character according to the
 * classification rules of the current locale, and the mapping functions
 * convert between upper and lower case.
 */

#include <ctype.h>
#include <stdio.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    CHECK(isalpha('a') && isalpha('z'));
    CHECK(isalpha('A') && isalpha('Z'));
    CHECK(!isalpha('0') && !isalpha(' '));

    CHECK(isdigit('0') && isdigit('9'));
    CHECK(!isdigit('a') && !isdigit('/'));

    CHECK(isalnum('a') && isalnum('7'));
    CHECK(!isalnum(' ') && !isalnum(','));

    CHECK(isspace(' ') && isspace('\t') && isspace('\n'));
    CHECK(isspace('\v') && isspace('\f') && isspace('\r'));
    CHECK(!isspace('a') && !isspace('\0'));

    CHECK(iscntrl('\0') && iscntrl('\n') && iscntrl('\a'));
    CHECK(!iscntrl(' ') && !iscntrl('a'));

    CHECK(islower('a') && islower('z'));
    CHECK(!islower('A') && !islower('0'));

    CHECK(isupper('A') && isupper('Z'));
    CHECK(!isupper('a') && !isupper('0'));

    CHECK(isblank(' ') && isblank('\t'));
    CHECK(!isblank('\n') && !isblank('a'));

    CHECK(isgraph('!') && isgraph('~') && isgraph('0'));
    CHECK(!isgraph(' ') && !isgraph('\n'));

    CHECK(isprint(' ') && isprint('~') && isprint('a'));
    CHECK(!isprint('\a') && !isprint('\n'));

    CHECK(ispunct('!') && ispunct('~') && ispunct(','));
    CHECK(!ispunct('a') && !ispunct('0') && !ispunct(' '));

    CHECK(isxdigit('0') && isxdigit('9'));
    CHECK(isxdigit('a') && isxdigit('f'));
    CHECK(isxdigit('A') && isxdigit('F'));
    CHECK(!isxdigit('g') && !isxdigit('G') && !isxdigit(' '));

    CHECK(toupper('a') == 'A' && toupper('z') == 'Z');
    CHECK(toupper('A') == 'A' && toupper('7') == '7');

    CHECK(tolower('A') == 'a' && tolower('Z') == 'z');
    CHECK(tolower('a') == 'a' && tolower('7') == '7');

    /* 7.4p1: EOF is an argument every function in this subclause accepts */
    CHECK(toupper(EOF) == EOF && tolower(EOF) == EOF);
    CHECK(isalpha(EOF) == 0 && isspace(EOF) == 0 && isxdigit(EOF) == 0);

    /* 7.4p1: a classifier returns zero or non-zero, never a bit mask */
    CHECK(isdigit('5') != 0);
    CHECK(isdigit('x') == 0);
    return 0;
}
