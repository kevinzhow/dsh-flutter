#ifndef DEMO_H
#define DEMO_H
#include <stdint.h>
#define STR(x) #x
#define CAT(a, b) a##b
#define LONG_MACRO(x) \
    do { \
        foo(x); \
    } while (0)

struct node { struct node *next; union { int i; float f; } u; };
typedef int (*cb_t)(void *ctx, const char *msg);
extern const volatile uint32_t REG;

static const char *names[] = { "a\tb", "c\\d", "e\"f", "\x41\101\0" };
_Static_assert(sizeof(int) == 4, "int");

int main(void)
{
    int x = 0xdeadBEEF, y = 077, z = 1e10 > 0 ? 'a' : '\0';
    unsigned long long big = 18446744073709551615ULL;
    char *p = (char *)malloc(10 * sizeof *p);
    if (!p) goto fail;
    for (int i = 0, j = 10; i < j; i++, j--) { x += i << 2 | j >> 1 & ~0; }
    switch (x) { case 1: case 2: break; default: ; }
    do { x--; } while (x > 0);
    printf("%d%% %s %c %5.2f %lu\n", x, "s", 'c', 1.0f, (unsigned long)sizeof(x));
fail:
    free(p);
    return -1;
}
#endif /* DEMO_H */
