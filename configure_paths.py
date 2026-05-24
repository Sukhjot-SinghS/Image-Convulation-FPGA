import os
import re

def main():
    print("==========================================================")
    print("  RISC-V FPGA Coprocessor Memory Path Configurator")
    print("==========================================================")
    
    # Automatically detect the current directory as default
    default_path = os.getcwd().replace('\\', '/')
    print(f"Detected repository root: {default_path}\n")
    
    # Prompt the user for input
    user_path = input("Enter the absolute path to your repository root\n"
                      f"(Or press ENTER to use default '{default_path}'): ").strip()
    
    if not user_path:
        user_path = default_path
        
    # Standardize backslashes to forward slashes for Verilog compliance
    user_path = user_path.replace('\\', '/').rstrip('/')
    
    memory_v_path = os.path.join("hardware", "cpu", "rtl", "memory.v")
    
    if not os.path.exists(memory_v_path):
        print(f"\n[ERROR] '{memory_v_path}' could not be found.")
        print("Please make sure you are running this script from the root of the repository!")
        input("\nPress ENTER to exit...")
        return

    with open(memory_v_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Define regex patterns matching $readmemh("...", imem) and $readmemh("...", dmem)
    # This pattern matches any absolute path containing 'hardware/cpu/imem.hex' or 'hardware/cpu/dmem.hex'
    imem_pattern = r'\$readmemh\("[^"]*hardware/cpu/imem\.hex",\s*imem\);'
    dmem_pattern = r'\$readmemh\("[^"]*hardware/cpu/dmem\.hex",\s*dmem\);'

    new_imem = f'$readmemh("{user_path}/hardware/cpu/imem.hex", imem);'
    new_dmem = f'$readmemh("{user_path}/hardware/cpu/dmem.hex", dmem);'

    # Perform regex replacements
    content, count_imem = re.subn(imem_pattern, new_imem, content)
    content, count_dmem = re.subn(dmem_pattern, new_dmem, content)

    if count_imem == 0 or count_dmem == 0:
        # Fallback if someone has edited the template or relative paths were present
        imem_fallback_pattern = r'\$readmemh\("[^"]*imem\.hex",\s*imem\);'
        dmem_fallback_pattern = r'\$readmemh\("[^"]*dmem\.hex",\s*dmem\);'
        content, count_imem = re.subn(imem_fallback_pattern, new_imem, content)
        content, count_dmem = re.subn(dmem_fallback_pattern, new_dmem, content)

    # Write the modified content back
    with open(memory_v_path, 'w', encoding='utf-8') as f:
        f.write(content)

    print("\n==========================================================")
    print("  CONFIGURATION COMPLETED SUCCESSFULY!")
    print("==========================================================")
    print(f"File updated: {memory_v_path}")
    print(f"  -> IMEM Path: {user_path}/hardware/cpu/imem.hex")
    print(f"  -> DMEM Path: {user_path}/hardware/cpu/dmem.hex")
    print("==========================================================")
    print("You can now build and synthesize your Vivado project safely!")
    print("==========================================================")

if __name__ == "__main__":
    main()
