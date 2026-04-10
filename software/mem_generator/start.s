/* start.S - Bare-metal bootloader for RISC-V */

.section .text
.global _start

_start:
    # 1. Initialize the Stack Pointer (sp) to the top of 16KB RAM
    # 16KB = 0x4000 in hex.
    lui sp, %hi(0x4000)
    addi sp, sp, %lo(0x4000)

    # 2. Jump to your C code
    call main

inf_loop:
    # 3. Safety Net: If main() finishes, trap the CPU in an infinite loop
    # so it doesn't wander off into empty memory and crash.
    j inf_loop