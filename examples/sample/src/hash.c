#include <stdint.h>

uint64_t fold(uint64_t h, uint64_t k) {
    return h * k + h - k;
}

uint64_t square(uint64_t x) {
    return x * x;
}
