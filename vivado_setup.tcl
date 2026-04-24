# Project configuration
set project_name "fpga_conv_soc"
set project_dir  "vivado_project"
set target_part  "xc7a100tcsg324-1" ;# Nexys A7-100T

# 1. Create Project
create_project $project_name $project_dir -part $target_part -force

# 2. Add Source Files
# RISC-V CPU RTL
add_files [glob hardware/cpu/rtl/*.v]

# Convolution Coprocessor RTL
add_files [glob hardware/coprocessor/rtl/*.v]

# Top-Level Wrappers & FSM
add_files [glob hardware/top/*.v]

# UART RTL
add_files [glob uart/*.v]

# 3. Add Memory Initialization Files (.hex)
catch {add_files hardware/cpu/imem.hex}
catch {add_files hardware/cpu/dmem.hex}

# 4. Add Constraints
if {[file exists "hardware/top/NexysA7.xdc"]} {
    add_files -fileset constrs_1 -norecurse "hardware/top/NexysA7.xdc"
} else {
    catch {add_files -fileset constrs_1 -norecurse "hardware/top/constraints/constraint.xdc"}
}

# 5. Set Top Level
set_property top top_fpga [current_fileset]
update_compile_order -fileset sources_1

puts "=========================================================="
puts " ✅ Project $project_name created successfully in IMGCONVDUMMY!"
puts " To synthesize, run: launch_runs synth_1 -jobs 4"
puts " To generate bitstream, run: launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "=========================================================="
