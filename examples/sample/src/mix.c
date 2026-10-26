#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* Profile S1: pure functions of uint64_t inputs using + - * (wrapping). */

uint64_t add3(uint64_t a, uint64_t b, uint64_t c) {
    return a + b + c;
}

uint64_t poly(uint64_t x, uint64_t y) {
    return x * x - y * x + y;
}

uint64_t zero(void) {
    return 0u;
}

uint64_t mix6(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f) {
    return a * b - c * d + e - f;
}

/* Outside S1: each of these must be refused with a reason, never approximated. */

uint64_t scale(uint64_t a, uint64_t b) {
    return a * 3u + b - 7u;
}

uint64_t pick(uint64_t a, uint64_t b) {
    if (a > b) {
        return a;
    }
    return b;
}

uint64_t counter = 0;

uint64_t bump(uint64_t a) {
    counter = counter + a;
    return counter;
}

struct pair {
    uint64_t lo;
    uint64_t hi;
};

uint64_t first(const uint64_t *p) {
    return p[0];
}

void hello(void) {
    printf("hello\n");
}

uint64_t *grab(uint64_t n) {
    return malloc(n * sizeof(uint64_t));
}
