/* * link.ld
 * Linker script for bare-metal RISC-V execution on Nexys4 DDR / Nexys A7.
 * Fits within the 4 KB (1024 words) memory bounds defined in memory.v.
 */

OUTPUT_ARCH( "riscv" )
ENTRY( _start )

/* * Define a single unified memory space.
 * Both IMEM and DMEM in the FPGA are 4 KB (0x1000 bytes) and mapped to base 0x0000.
 */
MEMORY
{
    /* Instruction Memory (mapped via Satish's MMIO logic) */
    RAM (xrw) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS
{
    /* 1. INSTRUCTION MEMORY (.text) */
    .text : {
        *(.text.startup)  /* <--- THIS IS THE MAGIC LINE. Forces Bootloader to 0x00 */
        *(.text)          /* Then puts main() and other functions after it */
    } > RAM

    /* 2. DATA MEMORY (.data) - Initialized variables */
    .data :
    {
        . = ALIGN(4);
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
    } > RAM

    /* 3. DATA MEMORY (.bss) - Uninitialized variables (zeroed out) */
    .bss :
    {
        . = ALIGN(4);
        __bss_start = .;
        
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    /* * The Stack grows downward from the top of RAM.
     * In start.s, we initialized `sp` to 0x1000 (4096).
     * This linker script ensures our code and variables stay safely at the bottom 
     * of the 4KB space, leaving the rest of the room for the stack!
     */
}