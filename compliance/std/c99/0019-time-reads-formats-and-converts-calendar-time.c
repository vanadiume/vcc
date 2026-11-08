/* 0019: time-reads-formats-and-converts-calendar-time
 *
 * ISO/IEC 9899:1999 7.23: time, clock and difftime, 7.23.3: mktime and the two
 * conversions, and 7.23.3.5: strftime formats a broken-down time. The tests
 * use the epoch for the fixed values, because that instant names the same
 * calendar date everywhere: 1970-01-01 was a Thursday.
 */

#include <stdio.h>
#include <string.h>
#include <time.h>

#define CHECK(...)                                                            \
    do {                                                                      \
        if (!(__VA_ARGS__)) {                                                 \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #__VA_ARGS__);     \
            return 1;                                                         \
        }                                                                     \
    } while (0)

int main(void)
{
    time_t now = 0;
    time_t epoch = 0;
    time_t back;
    time_t later;
    struct tm g;
    struct tm l;
    struct tm round;
    struct tm *pointer;
    char text[64];
    char *shaped;
    clock_t started;
    clock_t stopped;
    volatile long busy = 0;
    long i;

    CHECK(time(&now) != (time_t)-1);
    CHECK(now > 0);
    CHECK(time(NULL) != (time_t)-1);

    /* 7.23.3.3: gmtime answers in utc and needs no locale */
    pointer = gmtime(&epoch);
    CHECK(pointer != NULL);
    g = *pointer; /* the struct is shared, so it is copied at once */
    CHECK(g.tm_year == 70);
    CHECK(g.tm_mon == 0);
    CHECK(g.tm_mday == 1);
    CHECK(g.tm_hour == 0 && g.tm_min == 0 && g.tm_sec == 0);
    CHECK(g.tm_wday == 4);
    CHECK(g.tm_yday == 0);
    CHECK(g.tm_isdst == 0);
    CHECK(g.tm_sec >= 0 && g.tm_sec <= 60);

    /* 7.23.3.2: localtime is the same instant in the local zone, and mktime
     * takes it back to the instant it came from */
    pointer = localtime(&epoch);
    CHECK(pointer != NULL);
    l = *pointer;
    round = l;
    round.tm_isdst = -1;
    back = mktime(&round);
    CHECK(back == epoch);

    later = epoch + 3600;
    CHECK(difftime(later, epoch) == 3600.0);
    CHECK(difftime(epoch, later) == -3600.0);
    CHECK(difftime(epoch, epoch) == 0.0);

    /* 7.23.3.5: the format turns the struct into text */
    CHECK(strftime(text, sizeof text, "%Y-%m-%d", &g) == 10);
    CHECK(strcmp(text, "1970-01-01") == 0);
    CHECK(strftime(text, sizeof text, "%H:%M:%S", &g) == 8);
    CHECK(strcmp(text, "00:00:00") == 0);
    CHECK(strftime(text, sizeof text, "%%", &g) == 1);
    CHECK(strcmp(text, "%") == 0);
    CHECK(strftime(text, sizeof text, "%j", &g) == 3);
    CHECK(strcmp(text, "001") == 0);
    CHECK(strftime(text, sizeof text, "%a %b", &g) == 7);
    CHECK(strcmp(text, "Thu Jan") == 0);

    /* 7.23.3.5p3: a result that needs more room than there is returns zero */
    CHECK(strftime(text, 4, "%Y-%m-%d", &g) == 0);

    /* 7.23.3.1: asctime names the fields in a fixed 25-character shape */
    shaped = asctime(&g);
    CHECK(shaped != NULL);
    CHECK(strlen(shaped) == 25);
    CHECK(shaped[24] == '\n');
    CHECK(strncmp(shaped, "Thu Jan  1 00:00:00 1970", 24) == 0);

    /* and ctime is asctime of localtime, so only its shape is fixed */
    shaped = ctime(&epoch);
    CHECK(shaped != NULL);
    CHECK(strlen(shaped) == 25);
    CHECK(shaped[24] == '\n');

    /* 7.23.2.1: clock counts processor time since the program started */
    CHECK(CLOCKS_PER_SEC > 0);
    started = clock();
    CHECK(started != (clock_t)-1);
    for (i = 0; i < 1000000; i++) {
        busy += i;
    }
    stopped = clock();
    CHECK(stopped != (clock_t)-1);
    CHECK(stopped >= started);
    CHECK(busy > 0); /* the loop ran, so clock had something to count */
    return 0;
}
