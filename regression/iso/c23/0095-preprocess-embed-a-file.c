/* 0095: #embed is the bytes of a file as an initializer

C23 6.10.3 makes the directive stand for a comma-separated list of integer
constants, one per byte, with limit, prefix, suffix and if_empty around it.
The payload beside this file holds 01 02 03 04, and the name is written the
way a program writes a resource: beside the source, not at an absolute path.
The directive was refused as unknown until #73 and is read in
preprocess/embed.v now. */

#include <stdio.h>

static const unsigned char bytes[] = {
#embed "0095-embed-data.bin"
};

static const unsigned char first_two[] = {
#embed "0095-embed-data.bin" limit(2)
};

static const unsigned char framed[] = {
#embed "0095-embed-data.bin" prefix(0xFF, ) suffix(, 0xEE)
};

static const unsigned char replaced[] = {
#embed "0095-embed-data.bin" limit(0) if_empty(0xAB, 0xCD)
};

int main(void)
{
    if (sizeof bytes != 4) { fprintf(stderr, "#embed did not read the four bytes of the payload\n"); return 1; }
    if (bytes[0] != 1 || bytes[1] != 2 || bytes[2] != 3 || bytes[3] != 4) { fprintf(stderr, "#embed read the bytes in the wrong order or as the wrong numbers\n"); return 2; }
    if (sizeof first_two != 2) { fprintf(stderr, "#embed limit did not stop after two bytes\n"); return 3; }
    if (first_two[0] != 1 || first_two[1] != 2) { fprintf(stderr, "#embed limit kept the wrong two bytes\n"); return 4; }
    if (sizeof framed != 6) { fprintf(stderr, "#embed prefix and suffix did not frame the list\n"); return 5; }
    if (framed[0] != 0xFF || framed[1] != 1 || framed[4] != 4 || framed[5] != 0xEE) { fprintf(stderr, "#embed prefix or suffix landed in the wrong place\n"); return 6; }
    if (sizeof replaced != 2) { fprintf(stderr, "#embed if_empty was not the whole of an empty list\n"); return 7; }
    if (replaced[0] != 0xAB || replaced[1] != 0xCD) { fprintf(stderr, "#embed if_empty wrote the wrong bytes\n"); return 8; }
    return 0;
}
