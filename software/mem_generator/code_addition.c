#include <stdio.h>

int main(void) {
    static int a = 100;
    static int b = 2;
    int c = a+b;
    return c;
}
