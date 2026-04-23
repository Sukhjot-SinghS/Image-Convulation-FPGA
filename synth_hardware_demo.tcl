# ==============================================================================
#  synth_hardware_demo.tcl
#  Full Vivado Synthesis → Implementation → Bitstream Script
#  Target: Nexys A7-100T (xc7a100tcsg324-1)
#  Top Module: top_fpga
#
#  Usage (from repo root in Vivado Tcl console):
#    source synth_hardware_demo.tcl
#
#  Or from command line:
#    vivado -mode batch -source synth_hardware_demo.tcl
# ==============================================================================

# ── Step 0: Configuration ────────────────────────────────────────────────────
set project_name "HW_Demo"
set project_dir  "vivado_project/${project_name}"
set part         "xc7a100tcsg324-1"
set top_module   "top_fpga"
set num_jobs     4

# Base paths (relative to repo root where this script lives)
set hw_path      "./hardware"
set cpu_rtl      "${hw_path}/cpu/rtl"
set coproc_rtl   "${hw_path}/coprocessor/rtl"
set top_rtl      "${hw_path}/top"
set constraints  "${hw_path}/top/constraints/constraint.xdc"

puts "============================================================"
puts " Starting Hardware Demo Synthesis Flow"
puts " Project : $project_name"
puts " Part    : $part"
puts " Top     : $top_module"
puts "============================================================"

# ── Step 1: Create Project ───────────────────────────────────────────────────
#   -force overwrites any existing project with the same name
create_project $project_name $project_dir -part $part -force
set_property target_language Verilog [current_project]

puts "\n>>> Step 1: Project created."

# ── Step 2: Add RTL Source Files ─────────────────────────────────────────────
# CPU pipeline + RV32M
add_files [list \
    ${cpu_rtl}/pipeline.v    \
    ${cpu_rtl}/IF_ID.v       \
    ${cpu_rtl}/execute.v     \
    ${cpu_rtl}/wb.v          \
    ${cpu_rtl}/hazard_unit.v \
    ${cpu_rtl}/rv32m_alu.v   \
    ${cpu_rtl}/memory.v      \
]

# Coprocessor island
add_files [list \
    ${coproc_rtl}/conv_engine.v    \
    ${coproc_rtl}/line_buffer.v    \
    ${coproc_rtl}/img_bram_in.v    \
    ${coproc_rtl}/img_bram_out.v   \
    ${coproc_rtl}/kernel_regfile.v \
    ${coproc_rtl}/mmio_decoder.v   \
    ${coproc_rtl}/uart_rx.v        \
    ${coproc_rtl}/uart_tx.v        \
]

# Top level
add_files [list \
    ${top_rtl}/top_fpga.v \
    ${top_rtl}/top_fsm.v  \
]

puts ">>> Step 2: RTL source files added."

# ── Step 3: Add Include Directories ─────────────────────────────────────────
#   opcode.vh lives in cpu/rtl and is `included by IF_ID.v, execute.v, wb.v
set_property include_dirs [list \
    [file normalize $cpu_rtl]    \
    [file normalize $coproc_rtl] \
] [get_filesets sources_1]

puts ">>> Step 3: Include directories set."

# ── Step 4: Add Memory Initialization Files (.hex) ───────────────────────────
#   These are read by $readmemh in memory.v
catch {add_files ${hw_path}/cpu/imem.hex}
catch {add_files ${hw_path}/cpu/dmem.hex}

puts ">>> Step 4: Memory hex files added."

# ── Step 5: Add Constraints ─────────────────────────────────────────────────
if {[file exists $constraints]} {
    add_files -fileset constrs_1 -norecurse $constraints
    puts ">>> Step 5: Constraints file added ($constraints)."
} else {
    puts ">>> Step 5: WARNING — Constraints file not found at $constraints!"
}

# ── Step 6: Set Top Module ───────────────────────────────────────────────────
set_property top $top_module [get_filesets sources_1]
update_compile_order -fileset sources_1

puts ">>> Step 6: Top module set to $top_module."

# ── Step 7: Synthesis ────────────────────────────────────────────────────────
puts "\n============================================================"
puts " Running Synthesis..."
puts "============================================================"

# Configure synthesis settings
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]

launch_runs synth_1 -jobs $num_jobs
wait_on_run synth_1

# Check synthesis status
set synth_status [get_property STATUS [get_runs synth_1]]
puts ">>> Step 7: Synthesis complete — Status: $synth_status"

if {$synth_status ne "synth_design Complete!"} {
    puts ">>> ERROR: Synthesis failed! Check vivado.log for details."
    puts ">>> Open the project in GUI: vivado ${project_dir}/${project_name}.xpr"
    return
}

# ── Step 8: Implementation ───────────────────────────────────────────────────
puts "\n============================================================"
puts " Running Implementation (Place & Route)..."
puts "============================================================"

launch_runs impl_1 -jobs $num_jobs
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts ">>> Step 8: Implementation complete — Status: $impl_status"

if {$impl_status ne "route_design Complete!"} {
    puts ">>> ERROR: Implementation failed! Check vivado.log for details."
    puts ">>> Open the project in GUI: vivado ${project_dir}/${project_name}.xpr"
    return
}

# ── Step 9: Generate Bitstream ───────────────────────────────────────────────
puts "\n============================================================"
puts " Generating Bitstream..."
puts "============================================================"

launch_runs impl_1 -to_step write_bitstream -jobs $num_jobs
wait_on_run impl_1

puts ">>> Step 9: Bitstream generation complete."

# ── Step 10: Report Utilization & Timing ─────────────────────────────────────
open_run impl_1

# Save utilization report
set util_report "${project_dir}/utilization_report.txt"
report_utilization -file $util_report
puts ">>> Utilization report saved to: $util_report"

# Save timing summary
set timing_report "${project_dir}/timing_report.txt"
report_timing_summary -file $timing_report
puts ">>> Timing report saved to: $timing_report"

# Print key utilization numbers
puts "\n============================================================"
puts " RESOURCE UTILIZATION SUMMARY"
puts "============================================================"
report_utilization -hierarchical -hierarchical_depth 2

# ── Step 11: Locate Bitstream ────────────────────────────────────────────────
set bitstream_path "${project_dir}/${project_name}.runs/impl_1/${top_module}.bit"
if {[file exists $bitstream_path]} {
    puts "\n============================================================"
    puts " ✅ BITSTREAM READY"
    puts " File: $bitstream_path"
    puts "============================================================"
    puts ""
    puts " To program the FPGA, run these commands in Vivado Tcl:"
    puts "   open_hw_manager"
    puts "   connect_hw_server"
    puts "   open_hw_target"
    puts "   set_property PROGRAM.FILE {$bitstream_path} \[current_hw_device\]"
    puts "   program_hw_devices \[current_hw_device\]"
    puts ""
} else {
    puts "\n>>> WARNING: Bitstream file not found at expected path."
    puts ">>> Check: ${project_dir}/${project_name}.runs/impl_1/"
}

puts "============================================================"
puts " Hardware Demo Synthesis Flow Complete!"
puts "============================================================"
