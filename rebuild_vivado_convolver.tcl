# Vivado Project Creation Script
# Generated for: Image-Convulation-FPGA
# This script creates a Vivado project and adds all necessary RTL and constraints.

# Set project names and paths
set project_name "RV32_Image_Conv_System"
set project_dir "vivado_project"
set part "xc7a100tcsg324-1" ;# Nexys A7-100T

# Create project
create_project $project_name $project_dir -part $part -force

# Define base hardware path
set hw_path "./hardware"

# Add RTL source files
add_files [glob $hw_path/cpu/rtl/*.v]
add_files [glob $hw_path/coprocessor/rtl/*.v]
add_files [glob $hw_path/top/*.v]

# Add include files (like opcode.vh) and memory initialization files
add_files [glob $hw_path/cpu/*.hex]
set_property include_dirs [list \
    [file normalize "$hw_path/cpu/rtl"] \
    [file normalize "$hw_path/coprocessor/rtl"] \
] [get_filesets sources_1]

# Add constraints
if {[file exists "$hw_path/top/constraints/constraint.xdc"]} {
    add_files -fileset constrs_1 "$hw_path/top/constraints/constraint.xdc"
}

# Add testbenches to sim_1 fileset
add_files -fileset sim_1 [glob $hw_path/cpu/tb/*.v]
add_files -fileset sim_1 [glob $hw_path/coprocessor/tb/*.v]

# Set top module
set_property top top_fpga [get_filesets sources_1]
update_compile_order -fileset sources_1

# Set simulation top (example: tb_pipeline)
set_property top tb_top_fpga [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "============================================================"
puts "Project $project_name created successfully in $project_dir"
puts "Top Module: top_fpga"
puts "Target Part: $part"
puts "============================================================"
