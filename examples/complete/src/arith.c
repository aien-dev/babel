#include <stdint.h>

uint64_t blend(uint64_t a, uint64_t b) {
    return a * b + a - b;
}

uint64_t cube(uint64_t x) {
    return x * x * x;
}

uint64_t spread(uint64_t a, uint64_t b, uint64_t c) {
    return a * b + b * c - c * a;
}
