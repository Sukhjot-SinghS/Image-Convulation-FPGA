.section .text.init
.global _start

_start:
    # ---------------------------------------------------------
    # Initialize the Stack Pointer (sp)
    # Your Data Memory (DMEM) is 4 KB (1024 words) in size.
    # 4 KB in hexadecimal is 0x1000.
    # The stack grows downward, so we point it to the very top!
    # ---------------------------------------------------------
    li sp, 0x1000 
    
    # Jump to the main C function
    call main

    # ---------------------------------------------------------
    # Infinite Halt Loop
    # If main() ever returns, we trap the CPU here so it doesn't
    # start executing random garbage memory.
    # ---------------------------------------------------------
halt:
    j halt