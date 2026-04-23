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
    /* VMA definitions */
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    DMEM (rw)  : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS
{
    /* 1. INSTRUCTION MEMORY (.text) */
    .text : {
        *(.text.startup)  /* Forces Bootloader to 0x00 in IMEM */
        *(.text)
        *(.rodata)
    } > IMEM

    .data 0x00000000 : AT(0x1000) {
        *(.data)
        *(.sdata)
    } > DMEM

    .bss : {
        *(.bss)
        *(.sbss)
    } > DMEM
}