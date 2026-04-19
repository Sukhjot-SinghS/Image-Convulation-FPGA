<<<<<<< HEAD
// /**
//  * mul_div_test.c
//  * Author: Abhirup Paul
//  * * Target: RV32M Extension (Shaurya's rv32m_alu.v)
//  * This script verifies multiplication, division, and remainder 
//  * operations using standard C, which the compiler will translate 
//  * into RV32M instructions (mul, div, rem).
//  */

// // #include <stdint.h>

// // // Mock UART/Display function for IIT Guwahati Lab testing
// // void print_result(char* op, int32_t a, int32_t b, int32_t res);

// // int main() {
// //     // 1. Test Multiplication (Single-Cycle DSP)
// //     int32_t a_mul = 500;
// //     int32_t b_mul = 40;
// //     int32_t res_mul = a_mul * b_mul; // Triggers 'is_mul' in Shaurya's RTL
// //     print_result("MUL", a_mul, b_mul, res_mul);

// //     // 2. Test Signed Division (32-Cycle Iterative)
// //     int32_t a_div = -100;
// //     int32_t b_div = 3;
// //     int32_t res_div = a_div / b_div; // Expecting -33
// //     print_result("DIV", a_div, b_div, res_div);

// //     // 3. Test Remainder (is_rem logic)
// //     int32_t res_rem = a_div % b_div; // Expecting -1
// //     print_result("REM", a_div, b_div, res_rem);

// //     // 4. Test Division by Zero (Hardcoded in Shaurya's FSM)
// //     // RTL returns 0xFFFFFFFF for quotient and operand1 for remainder
// //     int32_t zero = 0;
// //     int32_t res_dbz = a_div / zero; 
// //     print_result("DBZ", a_div, zero, res_dbz);

// //     return 0;
// // }

// // /**
// //  * In a real IITG lab scenario, this would write to a 
// //  * Memory Mapped I/O (MMIO) address to show values on 
// //  * the Nexys A7 Seven Segment Display or UART.
// //  */
// // void print_result(char* op, int32_t a, int32_t b, int32_t res) {
// //     // Placeholder for your UART_TX implementation
// //     // For now, these operations ensure the RV32M ALU is synthesized 
// //     // and exercised by the CPU.
// // }













// /**
//  * mul_div_52_test.c
//  * Target: RV32M (Shaurya's ALU)
//  * Description: Exactly 52 distinct arithmetic operations covering
//  * all 8 RV32M instructions, signed/unsigned permutations, and all edge cases.
//  */

// #include <stdint.h>

// int main() {
//     // Inputs (marked volatile so the compiler doesn't skip the math)
//     volatile int32_t  pos_a    = 1500;
//     volatile int32_t  pos_b    = 42;
//     volatile int32_t  neg_a    = -800;
//     volatile int32_t  neg_b    = -15;
//     volatile uint32_t upos_a   = 3500000000; // Large unsigned
//     volatile uint32_t upos_b   = 77777;
    
//     // Edge case inputs
//     volatile int32_t  zero     = 0;
//     volatile int32_t  min_one  = -1;
//     volatile int32_t  int_min  = -2147483648; // 0x80000000

//     // Array to hold the 52 results
//     volatile int32_t res[52];

//     // ==========================================
//     // MULTIPLICATION (mul) - Lower 32 bits
//     // ==========================================
//     res[0] = pos_a * pos_b;       // 1. pos * pos
//     res[1] = neg_a * pos_b;       // 2. neg * pos
//     res[2] = pos_a * neg_b;       // 3. pos * neg
//     res[3] = neg_a * neg_b;       // 4. neg * neg
//     res[4] = pos_a * zero;        // 5. Multiply by zero
//     res[5] = zero  * neg_b;       // 6. Zero by negative
//     res[6] = int_min * 2;         // 7. Max negative * 2
//     res[7] = int_min * min_one;   // 8. Overflow mul (becomes 0x80000000)

//     // ==========================================
//     // MULTIPLICATION UPPER SIGNED (mulh) 
//     // ==========================================
//     res[8]  = (int32_t)(((int64_t)pos_a * (int64_t)pos_b) >> 32); // 9.
//     res[9]  = (int32_t)(((int64_t)neg_a * (int64_t)pos_b) >> 32); // 10.
//     res[10] = (int32_t)(((int64_t)pos_a * (int64_t)neg_b) >> 32); // 11.
//     res[11] = (int32_t)(((int64_t)neg_a * (int64_t)neg_b) >> 32); // 12.
//     res[12] = (int32_t)(((int64_t)int_min * (int64_t)pos_a) >> 32); // 13.
//     res[13] = (int32_t)(((int64_t)int_min * (int64_t)min_one) >> 32); // 14.

//     // ==========================================
//     // MULTIPLICATION UPPER SIGNED/UNSIGNED (mulhsu)
//     // ==========================================
//     res[14] = (int32_t)(((int64_t)pos_a * (uint64_t)upos_a) >> 32); // 15.
//     res[15] = (int32_t)(((int64_t)neg_a * (uint64_t)upos_b) >> 32); // 16.
//     res[16] = (int32_t)(((int64_t)min_one * (uint64_t)upos_a) >> 32); // 17.
//     res[17] = (int32_t)(((int64_t)zero * (uint64_t)upos_b) >> 32); // 18.
//     res[18] = (int32_t)(((int64_t)int_min * (uint64_t)upos_a) >> 32); // 19.
//     res[19] = (int32_t)(((int64_t)neg_a * (uint64_t)zero) >> 32); // 20.

//     // ==========================================
//     // MULTIPLICATION UPPER UNSIGNED (mulhu)
//     // ==========================================
//     res[20] = (uint32_t)(((uint64_t)upos_a * (uint64_t)upos_b) >> 32); // 21.
//     res[21] = (uint32_t)(((uint64_t)upos_b * (uint64_t)upos_a) >> 32); // 22.
//     res[22] = (uint32_t)(((uint64_t)upos_a * (uint64_t)zero) >> 32); // 23.
//     res[23] = (uint32_t)(((uint64_t)upos_a * (uint64_t)upos_a) >> 32); // 24.
//     res[24] = (uint32_t)(((uint64_t)upos_b * (uint64_t)upos_b) >> 32); // 25.
//     res[25] = (uint32_t)(((uint64_t)upos_a * (uint64_t)1) >> 32); // 26.

//     // ==========================================
//     // DIVISION SIGNED (div)
//     // ==========================================
//     res[26] = pos_a / pos_b;      // 27. pos / pos
//     res[27] = neg_a / pos_b;      // 28. neg / pos
//     res[28] = pos_a / neg_b;      // 29. pos / neg
//     res[29] = neg_a / neg_b;      // 30. neg / neg
//     res[30] = zero  / pos_a;      // 31. zero / pos
//     res[31] = pos_a / pos_a;      // 32. Divide by self
//     res[32] = pos_a / zero;       // 33. EDGE: Divide by Zero (Expect -1)
//     res[33] = int_min / min_one;  // 34. EDGE: Integer Overflow (Expect INT_MIN)

//     // ==========================================
//     // DIVISION UNSIGNED (divu)
//     // ==========================================
//     res[34] = upos_a / upos_b;    // 35. large / small
//     res[35] = upos_b / upos_a;    // 36. small / large (Expect 0)
//     res[36] = upos_a / upos_a;    // 37. Divide by self
//     res[37] = zero   / upos_a;    // 38. Zero / large
//     res[38] = upos_a / 1;         // 39. Divide by 1
//     res[39] = upos_a / zero;      // 40. EDGE: Unsigned Divide by Zero (Expect 0xFFFFFFFF)

//     // ==========================================
//     // REMAINDER SIGNED (rem)
//     // ==========================================
//     res[40] = pos_a % pos_b;      // 41. pos % pos
//     res[41] = neg_a % pos_b;      // 42. neg % pos (Expect negative result)
//     res[42] = pos_a % neg_b;      // 43. pos % neg (Expect positive result)
//     res[43] = neg_a % neg_b;      // 44. neg % neg (Expect negative result)
//     res[44] = zero  % pos_b;      // 45. Zero % pos
//     res[45] = pos_a % pos_a;      // 46. Modulo self (Expect 0)
//     res[46] = pos_a % zero;       // 47. EDGE: Modulo Zero (Expect dividend: pos_a)
//     res[47] = int_min % min_one;  // 48. EDGE: Overflow Remainder (Expect 0)

//     // ==========================================
//     // REMAINDER UNSIGNED (remu)
//     // ==========================================
//     res[48] = upos_a % upos_b;    // 49. large % small
//     res[49] = upos_b % upos_a;    // 50. small % large (Expect small: upos_b)
//     res[50] = zero   % upos_a;    // 51. Zero % large
//     res[51] = upos_a % zero;      // 52. EDGE: Unsigned Modulo Zero (Expect dividend: upos_a)

//     return 0;
// }

























=======
>>>>>>> origin/sukhjot

/**
 * mul_div_52_test.c
 * Target: RV32M (Shaurya's ALU)
 * Description: Exactly 52 distinct arithmetic operations covering
 * all 8 RV32M instructions, signed/unsigned permutations, and all edge cases.
 */

#include <stdint.h>

int main() {
    // Inputs (marked volatile so the compiler doesn't skip the math)
    volatile int32_t  pos_a    = 1500;
    volatile int32_t  pos_b    = 42;
    volatile int32_t  neg_a    = -800;
    volatile int32_t  neg_b    = -15;
    volatile uint32_t upos_a   = 3500000000; // Large unsigned
    volatile uint32_t upos_b   = 77777;
    
    // Edge case inputs
    volatile int32_t  zero     = 0;
    volatile int32_t  min_one  = -1;
    volatile int32_t  int_min  = -2147483648; // 0x80000000

    // Array to hold the 52 results
    volatile int32_t res[52];

    // ==========================================
    // MULTIPLICATION (mul) - Lower 32 bits
    // ==========================================
    res[0] = pos_a * pos_b;       // 1. pos * pos              1500 * 42 = 63000
    res[1] = neg_a * pos_b;       // 2. neg * pos              -800 * 42 = -33600
    res[2] = pos_a * neg_b;       // 3. pos * neg              1500 * -15 = -22500
    res[3] = neg_a * neg_b;       // 4. neg * neg              -800 * -15 = 12000
    res[4] = pos_a * zero;        // 5. Multiply by zero       1500 * 0 = 0
    res[5] = zero  * neg_b;       // 6. Zero by negative       0 * -15 = 0
    res[6] = int_min * 2;         // 7. Max negative * 2       -2147483648 * 2 = 0   (overflow in 32-bit, wraps to 0)
    res[7] = int_min * min_one;   // 8. Overflow mul (becomes 0x80000000) (-2147483648 * -1 = -2147483648, overflow)

    // ==========================================
    // MULTIPLICATION UPPER SIGNED (mulh) 
    // ==========================================
    res[8]  = (int32_t)(((int64_t)pos_a * (int64_t)pos_b) >> 32); // 9. (63000 >> 32) = 0
    res[9]  = (int32_t)(((int64_t)neg_a * (int64_t)pos_b) >> 32); // 10. (-33600 >> 32) = -1 (sign-extended, see logic below)
    res[10] = (int32_t)(((int64_t)pos_a * (int64_t)neg_b) >> 32); // 11. (-22500 >> 32) = -1
    res[11] = (int32_t)(((int64_t)neg_a * (int64_t)neg_b) >> 32); // 12. (12000 >> 32) = 0
    res[12] = (int32_t)(((int64_t)int_min * (int64_t)pos_a) >> 32); // 13. (-2147483648 * 1500 = -3221225472000, >>32 = -749)
    res[13] = (int32_t)(((int64_t)int_min * (int64_t)min_one) >> 32); // 14. (-2147483648 * -1 = 2147483648, >>32 = 0)

    // ==========================================
    // MULTIPLICATION UPPER SIGNED/UNSIGNED (mulhsu)
    // ==========================================
    res[14] = (int32_t)(((int64_t)pos_a * (uint64_t)upos_a) >> 32); // 15. (1500 * 3500000000ULL = 5250000000000, >>32 = 1222483)
    res[15] = (int32_t)(((int64_t)neg_a * (uint64_t)upos_b) >> 32); // 16. (-800 * 77777ULL = -62221600, >>32 = -15)
    res[16] = (int32_t)(((int64_t)min_one * (uint64_t)upos_a) >> 32); // 17. (-1 * 3500000000ULL = -3500000000, >>32 = -1)
    res[17] = (int32_t)(((int64_t)zero * (uint64_t)upos_b) >> 32); // 18. (0*77777 = 0, >>32 = 0)
    res[18] = (int32_t)(((int64_t)int_min * (uint64_t)upos_a) >> 32); // 19. (-2147483648 * 3500000000 = -7511200000000000000, >>32 = -1747567)
    res[19] = (int32_t)(((int64_t)neg_a * (uint64_t)zero) >> 32); // 20. (-800*0 = 0, >>32 = 0)

    // ==========================================
    // MULTIPLICATION UPPER UNSIGNED (mulhu)
    // ==========================================
    res[20] = (uint32_t)(((uint64_t)upos_a * (uint64_t)upos_b) >> 32); // 21. (3500000000*77777 = 272219500000000ULL, >>32 = 63395)
    res[21] = (uint32_t)(((uint64_t)upos_b * (uint64_t)upos_a) >> 32); // 22. Same as above: 63395
    res[22] = (uint32_t)(((uint64_t)upos_a * (uint64_t)zero) >> 32); // 23. 0
    res[23] = (uint32_t)(((uint64_t)upos_a * (uint64_t)upos_a) >> 32); // 24. (3500000000^2=1.225e19, >>32=284968)
    res[24] = (uint32_t)(((uint64_t)upos_b * (uint64_t)upos_b) >> 32); // 25. (77777^2=6059407729, >>32=1)
    res[25] = (uint32_t)(((uint64_t)upos_a * (uint64_t)1) >> 32); // 26. (3500000000>>32=0)

    // ==========================================
    // DIVISION SIGNED (div)
    // ==========================================
    res[26] = pos_a / pos_b;      // 27. pos / pos           1500/42 = 35
    res[27] = neg_a / pos_b;      // 28. neg / pos           -800/42 = -19
    res[28] = pos_a / neg_b;      // 29. pos / neg           1500/-15 = -100
    res[29] = neg_a / neg_b;      // 30. neg / neg           -800/-15 = 53
    res[30] = zero  / pos_a;      // 31. zero / pos          0/1500 = 0
    res[31] = pos_a / pos_a;      // 32. Divide by self      1500/1500 = 1
    res[32] = pos_a / zero;       // 33. EDGE: Divide by Zero (Expect -1)  // as per RISC-V spec, returns -1 (0xFFFFFFFF)
    res[33] = int_min / min_one;  // 34. EDGE: Integer Overflow (Expect INT_MIN)    // -2147483648 / -1 = -2147483648 (overflow)

    // ==========================================
    // DIVISION UNSIGNED (divu)
    // ==========================================
    res[34] = upos_a / upos_b;    // 35. large / small       3500000000/77777 = 45008
    res[35] = upos_b / upos_a;    // 36. small / large       77777/3500000000 = 0
    res[36] = upos_a / upos_a;    // 37. Divide by self      3500000000/3500000000 = 1
    res[37] = zero   / upos_a;    // 38. Zero / large        0/3500000000 = 0
    res[38] = upos_a / 1;         // 39. Divide by 1         3500000000/1 = 3500000000
    res[39] = upos_a / zero;      // 40. EDGE: Unsigned Divide by Zero (Expect 0xFFFFFFFF; 4294967295)

    // ==========================================
    // REMAINDER SIGNED (rem)
    // ==========================================
    res[40] = pos_a % pos_b;      // 41. pos % pos           1500%42 = 36
    res[41] = neg_a % pos_b;      // 42. neg % pos           -800%42 = -2
    res[42] = pos_a % neg_b;      // 43. pos % neg           1500%-15 = 0
    res[43] = neg_a % neg_b;      // 44. neg % neg           -800%-15 = -10
    res[44] = zero  % pos_b;      // 45. Zero % pos          0%42 = 0
    res[45] = pos_a % pos_a;      // 46. Modulo self         1500%1500 = 0
    res[46] = pos_a % zero;       // 47. EDGE: Modulo Zero (Expect dividend: pos_a = 1500)
    res[47] = int_min % min_one;  // 48. EDGE: Overflow Remainder (Expect 0)    // -2147483648 % -1 = 0

    // ==========================================
    // REMAINDER UNSIGNED (remu)
    // ==========================================
    res[48] = upos_a % upos_b;    // 49. large % small       3500000000%77777 = 45126
    res[49] = upos_b % upos_a;    // 50. small % large       77777%3500000000 = 77777
    res[50] = zero   % upos_a;    // 51. Zero % large        0%3500000000 = 0
    res[51] = upos_a % zero;      // 52. EDGE: Unsigned Modulo Zero (Expect dividend: upos_a = 3500000000)

    return 0;
}

/* EXPLANATIONS AND COMMENTS ON UNDEFINED CASES:
   - Any division by zero (signed): Should return -1 (0xFFFFFFFF), per RISC-V spec.
   - Any unsigned division by zero: Should return 0xFFFFFFFF (4294967295).
   - Any signed/unsigned remainder with divisor 0: Should return original dividend.
   - INT_MIN/-1 in signed division: returns INT_MIN due to 2's complement overflow.
   - Signed/unsigned upper multiplication results: check typecasting as C does not truncate by default!
   - Negative result right shift: arithmetic (sign-extending) right shift must be used.
<<<<<<< HEAD
*/








































/*
#include <stdint.h>

// Volatile arrays force the compiler to write these to Data Memory
// so we can see the results in the Vivado waveform.
volatile int32_t mul_tests[10];
volatile int32_t div_tests[10];
volatile int32_t rem_tests[10];
volatile int32_t edge_cases[10];

int main() {
    int32_t a, b;
    
    // ==========================================
    // 1. Basic Multiplication
    // ==========================================
    mul_tests[0] = 12 * 5;        // Expected: 60
    mul_tests[1] = -15 * 4;       // Expected: -60
    mul_tests[2] = -10 * -10;     // Expected: 100
    mul_tests[3] = 0 * 999;       // Expected: 0
    mul_tests[4] = 0x7FFFFFFF * 1; // Max positive

    // ==========================================
    // 2. Basic Division
    // ==========================================
    div_tests[0] = 100 / 4;       // Expected: 25
    div_tests[1] = -100 / 4;      // Expected: -25
    div_tests[2] = 100 / -4;      // Expected: -25
    div_tests[3] = -100 / -4;     // Expected: 25
    div_tests[4] = 0 / 50;        // Expected: 0

    // ==========================================
    // 3. Remainders
    // ==========================================
    // Note: In C (and RISC-V), the sign of the remainder matches the dividend
    rem_tests[0] = 10 % 3;        // Expected: 1
    rem_tests[1] = -10 % 3;       // Expected: -1
    rem_tests[2] = 10 % -3;       // Expected: 1
    rem_tests[3] = -10 % -3;      // Expected: -1

    // ==========================================
    // 4. Rigorous Edge Cases
    // ==========================================
    int32_t min_int = 0x80000000; // -2147483648
    int32_t minus_one = -1;
    int32_t zero = 0;
    int32_t positive_val = 55;

    // A. Sign Overflow: MIN_INT / -1
    // Expected: Quotient = MIN_INT, Remainder = 0
    edge_cases[0] = min_int / minus_one; 
    edge_cases[1] = min_int % minus_one;

    // B. Divide by Zero: Positive / 0
    // Expected: Quotient = -1 (0xFFFFFFFF), Remainder = Dividend (55)
    edge_cases[2] = positive_val / zero;
    edge_cases[3] = positive_val % zero;

    // C. Divide by Zero: Negative / 0
    // Expected: Quotient = -1, Remainder = Dividend (-55)
    edge_cases[4] = -positive_val / zero;
    edge_cases[5] = -positive_val % zero;

    // Infinite loop to safely halt the processor
    while(1) {
        // Wait forever
    }

    return 0;
}
=======
>>>>>>> origin/sukhjot
*/