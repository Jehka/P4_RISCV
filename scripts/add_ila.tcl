#-----------------------------------------------------------------------
# add_ila.tcl
# Adds a System ILA to the P4 block design for hardware bring-up.
#
# Run with the project open and p4_bd built:
#     source C:/Users/OSHIO/Verilog/RISC-V_P4/add_ila.tcl
#
# ================== WHY THESE PROBES ==================
# Three questions will come up at bring-up, and each needs a specific
# signal to answer:
#
#   "did the CPU run at all?"           -> if_pc_out
#       If the PC sits at 0x00030000 the CPU never left reset or never
#       completed a fetch. If it advances and then sticks at 0x00030030
#       the program ran to its spin, which is success.
#
#   "if it stalled, which side stalled?" -> if_stall_out / mem_stall_out
#       if_stall high forever  = instruction fetch is not completing
#                                (crossbar slave 3 / imem BRAM path)
#       mem_stall high forever = data access is not completing
#                                (crossbar slave 0 / dmem BRAM path)
#       This distinction is the single most useful thing on the list --
#       it splits the debug space in half immediately.
#
#   "did the injected instruction execute?" -> debug_out
#       Step 7 of the Vitis app rewrites the spin instruction with
#       "addi x10,x0,42". Nothing writes a0 to memory afterwards, so
#       software CANNOT observe the effect. debug_out (which is x10) is
#       the only way to see it. Without this probe that test is
#       unverifiable on hardware.
#
# Also probed: the crossbar's arbitration state (grant_valid / grant_idx
# for slave 0), because if two masters ever deadlock competing for data
# memory, the held grant is what shows it.
#
# ================== TRIGGERING ==================
# Default capture is "trigger immediately on arm", which is right for
# the first bring-up: arm before releasing the CPU and watch what
# happens. Once things are working, a more useful trigger is
#     debug_out == 42
# to catch the injected-instruction moment exactly.
#
# ================== NOTE ON TIMING ==================
# The ILA consumes BRAM and routing. The design currently closes at
# WNS +0.301 ns. If adding this pushes it negative, reduce
# CONFIG.C_DATA_DEPTH from 4096 to 1024 -- capture depth is the cheapest
# thing to give up.
#-----------------------------------------------------------------------

open_bd_design [get_files p4_bd.bd]
current_bd_design p4_bd

# Remove a previous ILA if this script is being re-run.
if {[llength [get_bd_cells -quiet ila_p4]] > 0} {
    puts "Removing existing ila_p4 before re-adding..."
    delete_bd_objs [get_bd_cells ila_p4]
}

#-----------------------------------------------------------------------
# 1. Create the ILA
#-----------------------------------------------------------------------
set ila [create_bd_cell -type ip -vlnv xilinx.com:ip:ila ila_p4]

# 6 probes, native (non-AXI) mode.
set_property -dict [list \
    CONFIG.C_MONITOR_TYPE     {Native} \
    CONFIG.C_NUM_OF_PROBES    {6}      \
    CONFIG.C_DATA_DEPTH       {4096}   \
    CONFIG.C_TRIGIN_EN        {false}  \
    CONFIG.C_ADV_TRIGGER      {true}   \
    CONFIG.C_EN_STRG_QUAL     {1}      \
    CONFIG.C_PROBE0_WIDTH     {32}     \
    CONFIG.C_PROBE1_WIDTH     {32}     \
    CONFIG.C_PROBE2_WIDTH     {1}      \
    CONFIG.C_PROBE3_WIDTH     {1}      \
    CONFIG.C_PROBE4_WIDTH     {1}      \
    CONFIG.C_PROBE5_WIDTH     {1}      \
] $ila

#-----------------------------------------------------------------------
# 2. Clock
#-----------------------------------------------------------------------
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ila_p4/clk]

#-----------------------------------------------------------------------
# 3. Probes
#
#   probe0  if_pc_out      did the CPU run / where is it
#   probe1  debug_out      x10 -- the ONLY way to see the injected
#                          instruction take effect
#   probe2  if_stall_out   fetch side stalled
#   probe3  mem_stall_out  data side stalled
#   probe4  dma_irq
#   probe5  fi_irq         fault-injection campaign completed
#-----------------------------------------------------------------------
connect_bd_net [get_bd_pins ila_p4/probe0] [get_bd_pins p4_top_0/if_pc_out]
connect_bd_net [get_bd_pins ila_p4/probe1] [get_bd_pins p4_top_0/debug_out]
connect_bd_net [get_bd_pins ila_p4/probe2] [get_bd_pins p4_top_0/if_stall_out]
connect_bd_net [get_bd_pins ila_p4/probe3] [get_bd_pins p4_top_0/mem_stall_out]
connect_bd_net [get_bd_pins ila_p4/probe4] [get_bd_pins p4_top_0/dma_irq]
connect_bd_net [get_bd_pins ila_p4/probe5] [get_bd_pins p4_top_0/fi_irq]

#-----------------------------------------------------------------------
# 4. Report
#-----------------------------------------------------------------------
puts "\n================= ILA PROBES ================="
puts "  probe0 \[31:0\]  if_pc_out      -- CPU program counter"
puts "  probe1 \[31:0\]  debug_out      -- x10 (a0)"
puts "  probe2         if_stall_out   -- fetch stalled"
puts "  probe3         mem_stall_out  -- data access stalled"
puts "  probe4         dma_irq"
puts "  probe5         fi_irq"
puts "=============================================="
puts "First bring-up: arm the ILA BEFORE the Vitis app releases the CPU."
puts "Expect if_pc_out to climb from 0x00030000 and settle at 0x00030030."
puts "If it never moves, read if_stall_out / mem_stall_out to see which"
puts "side is stuck.\n"

regenerate_bd_layout
validate_bd_design
save_bd_design

puts "ILA added. Now rebuild -- and remember to reset BOTH synth runs:"
puts "    reset_target all \[get_files p4_bd.bd\]"
puts "    generate_target all \[get_files p4_bd.bd\]"
puts "    create_ip_run \[get_files p4_bd.bd\]"
puts "    reset_run synth_1"
puts "    reset_run p4_bd_p4_top_0_0_synth_1"
puts "    launch_runs impl_1 -to_step write_bitstream -jobs 8"
puts "Then regenerate the .xsa -- the bitstream will have changed.\n"
