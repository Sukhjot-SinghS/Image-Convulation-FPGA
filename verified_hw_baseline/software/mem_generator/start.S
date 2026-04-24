.section .text.startup
.global _start

_start:
    # Force the Stack Pointer to the top of your 4KB RAM
    # (If your RAM is bigger/smaller, change this hex address!)
    li sp, 0x00001000  

    # Jump to the C code
    call main          

end_loop:
    j end_loop
