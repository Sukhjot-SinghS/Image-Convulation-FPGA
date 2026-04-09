/* link.ld - Memory Map for RISC-V SoC */
/* Author: Abhirup Paul */

MEMORY
{
    /* Instruction Memory (mapped via Satish's MMIO logic) */
    RAM (xrw) : ORIGIN = 0x00000000, LENGTH = 16K
}

SECTIONS
{
    .text : {
        *(.text)
    } > RAM

    .data : {
        *(.data)
    } > RAM

    .bss : {
        *(.bss)
    } > RAM
}