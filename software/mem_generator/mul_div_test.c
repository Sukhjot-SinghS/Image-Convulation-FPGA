/**
 * mul_div_test.c
 * Author: Abhirup Paul
 * * Target: RV32M Extension (Shaurya's rv32m_alu.v)
 * This script verifies multiplication, division, and remainder 
 * operations using standard C, which the compiler will translate 
 * into RV32M instructions (mul, div, rem).
 */

#include <stdint.h>

// Mock UART/Display function for IIT Guwahati Lab testing
void print_result(char* op, int32_t a, int32_t b, int32_t res);

int main() {
    // 1. Test Multiplication (Single-Cycle DSP)
    int32_t a_mul = 500;
    int32_t b_mul = 40;
    int32_t res_mul = a_mul * b_mul; // Triggers 'is_mul' in Shaurya's RTL
    print_result("MUL", a_mul, b_mul, res_mul);

    // 2. Test Signed Division (32-Cycle Iterative)
    int32_t a_div = -100;
    int32_t b_div = 3;
    int32_t res_div = a_div / b_div; // Expecting -33
    print_result("DIV", a_div, b_div, res_div);

    // 3. Test Remainder (is_rem logic)
    int32_t res_rem = a_div % b_div; // Expecting -1
    print_result("REM", a_div, b_div, res_rem);

    // 4. Test Division by Zero (Hardcoded in Shaurya's FSM)
    // RTL returns 0xFFFFFFFF for quotient and operand1 for remainder
    int32_t zero = 0;
    int32_t res_dbz = a_div / zero; 
    print_result("DBZ", a_div, zero, res_dbz);

    return 0;
}

/**
 * In a real IITG lab scenario, this would write to a 
 * Memory Mapped I/O (MMIO) address to show values on 
 * the Nexys A7 Seven Segment Display or UART.
 */
void print_result(char* op, int32_t a, int32_t b, int32_t res) {
    // Placeholder for your UART_TX implementation
    // For now, these operations ensure the RV32M ALU is synthesized 
    // and exercised by the CPU.
}