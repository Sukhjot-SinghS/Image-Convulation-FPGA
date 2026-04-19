/* link.ld - Memory Map for RISC-V SoC */
/* Author: Abhirup Paul */

MEMORY
{
    /* Instruction Memory (mapped via Satish's MMIO logic) */
    RAM (xrw) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        *(.text.startup)  /* <--- THIS IS THE MAGIC LINE. Forces Bootloader to 0x00 */
        *(.text)          /* Then puts main() and other functions after it */
    } > RAM

    .data : {
        *(.data)
    } > RAM

    .bss : {
        *(.bss)
    } > RAM
}