#include <stdio.h>
#include "local.h"

#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define VERSION "1.2"

typedef struct {
    int id;
    const char *name;
    unsigned flags : 3;
} Item;

enum Mode { MODE_A = 1, MODE_B = 1 << 2 };

static inline int clamp(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

/* multi-line
 * comment */
int main(int argc, char **argv) {
    Item items[] = { {1, "one", 0}, {2, "two\n", 1} };
    char c = '\'';
    float f = 3.14f;
    long n = 0xFFUL;
    for (size_t i = 0; i < sizeof(items) / sizeof(items[0]); ++i) {
        printf("%d: %s (%5.2f)\n", items[i].id, items[i].name, f);
    }
#ifdef DEBUG
    fprintf(stderr, "debug\n");
#endif
    return argc > 1 ? atoi(argv[1]) : 0; // trailing
}
