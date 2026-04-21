/* link.ld - Memory Map for RISC-V SoC */
/* Author: Abhirup Paul */

MEMORY
{
    /* VMA definitions */
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    DMEM (rw)  : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS
{
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