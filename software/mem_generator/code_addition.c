#include <stdio.h>

int main(void) {
    volatile int a = 100;
    volatile int b = 2;
    int c = a+b;
    return c;
}
