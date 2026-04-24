/* link.ld - Memory Map for RISC-V SoC */
/* Author: Abhirup Paul */

MEMORY
{
    /* Harvard split: IMEM and DMEM are physically separate BRAMs,
       both addressed starting at 0x0 from the CPU's perspective. */
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    DMEM (rw)  : ORIGIN = 0x00004000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        *(.text.startup)  /* Forces bootloader / _start to 0x00 in IMEM */
        *(.text)
    } > IMEM

    .data : {
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
        *(.data)
        *(.sdata)
        *(.sdata.*)
    } > DMEM

    .bss : {
        *(.bss)
    } > DMEM
}