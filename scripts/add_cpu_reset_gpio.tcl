#-----------------------------------------------------------------------
# add_cpu_reset_gpio.tcl
# Adds software-controlled CPU reset to the P4 block design.
#
# Run with the project open and p4_bd already built:
#     source C:/path/to/add_cpu_reset_gpio.tcl
#
# ================== WHY THIS IS NEEDED ==================
# p4_top.rst is driven only by the Processor System Reset block, which
# asserts once at power-up and never again. That makes bring-up
# impossible:
#
#   1. bitstream loads; the CPU leaves reset immediately
#   2. imem BRAM is uninitialised -- the CPU fetches zeros, which are not
#      valid RV32I, and wanders off executing garbage
#   3. the Vitis app then loads the real program to 0x4002_0000
#   4. too late: the CPU is already lost and nothing can restart it
#
# The GPIO below lets software HOLD the CPU in reset, load a program,
# then RELEASE it. It also matters for P5: a fault campaign wants to
# reset / load / run / observe many times, and doing that through a
# global PL reset each iteration would also reset the BRAM controllers
# and the crossbar.
#
# ================== RESULTING BEHAVIOUR ==================
#   cpu_reset_gpio bit 0 = 1  -> CPU held in reset
#   cpu_reset_gpio bit 0 = 0  -> CPU runs
#
# The GPIO output is OR'd with the Processor System Reset block's
# peripheral_reset, so power-on reset still works AND software can assert
# reset independently. p4_top.rst is ACTIVE HIGH, so OR is the correct
# combining function: either source asserting holds the CPU in reset.
#
# IMPORTANT: the GPIO powers up with its output at 0. To hold the CPU at
# power-on, set CONFIG.C_DOUT_DEFAULT below to 0x00000001 -- done here,
# so the CPU is held until software explicitly releases it. Without that,
# the CPU still runs garbage in the window between bitstream load and the
# app's first write.
#-----------------------------------------------------------------------

open_bd_design [get_files p4_bd.bd]
current_bd_design p4_bd

#-----------------------------------------------------------------------
# 1. AXI GPIO, single output bit, defaulting to RESET ASSERTED
#-----------------------------------------------------------------------
set gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio cpu_reset_gpio]
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH      {1}          \
    CONFIG.C_ALL_OUTPUTS     {1}          \
    CONFIG.C_IS_DUAL         {0}          \
    CONFIG.C_DOUT_DEFAULT    {0x00000001} \
] $gpio

#-----------------------------------------------------------------------
# 2. OR the GPIO bit with the power-on reset
#-----------------------------------------------------------------------
set orgate [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic cpu_rst_or]
set_property -dict [list \
    CONFIG.C_SIZE {1} \
    CONFIG.C_OPERATION {or} \
] $orgate

# disconnect the direct peripheral_reset -> p4_top.rst link
if {[llength [get_bd_nets -quiet -of_objects [get_bd_pins p4_top_0/rst]]] > 0} {
    delete_bd_objs [get_bd_nets -of_objects [get_bd_pins p4_top_0/rst]]
}

connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_reset] \
               [get_bd_pins cpu_rst_or/Op1]
connect_bd_net [get_bd_pins cpu_reset_gpio/gpio_io_o] \
               [get_bd_pins cpu_rst_or/Op2]
connect_bd_net [get_bd_pins cpu_rst_or/Res] \
               [get_bd_pins p4_top_0/rst]

#-----------------------------------------------------------------------
# 3. Hang the GPIO off the PS interconnect (needs a 4th master port)
#-----------------------------------------------------------------------
set_property CONFIG.NUM_MI {4} [get_bd_cells ps_interconnect]

connect_bd_net [get_bd_pins ps7/FCLK_CLK0]  [get_bd_pins ps_interconnect/M03_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0]  [get_bd_pins cpu_reset_gpio/s_axi_aclk]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] \
               [get_bd_pins ps_interconnect/M03_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] \
               [get_bd_pins cpu_reset_gpio/s_axi_aresetn]

connect_bd_intf_net [get_bd_intf_pins ps_interconnect/M03_AXI] \
                    [get_bd_intf_pins cpu_reset_gpio/S_AXI]

#-----------------------------------------------------------------------
# 4. Address it inside the PS GP0 aperture (0x4000_0000 - 0x7FFF_FFFF)
#-----------------------------------------------------------------------
create_bd_addr_seg -range 4K -offset 0x40030000 \
    [get_bd_addr_spaces ps7/Data] \
    [get_bd_addr_segs cpu_reset_gpio/S_AXI/Reg] SEG_cpu_reset_gpio

#-----------------------------------------------------------------------
# 5. Report the full map -- verify, never assume
#-----------------------------------------------------------------------
puts "\n============ PS ADDRESS MAP ============"
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps7/Data]] {
    puts [format "  %-50s offset=%s range=%s" $seg \
        [get_property offset $seg] [get_property range $seg]]
}
puts "\n============ CPU ADDRESS MAP ============"
foreach sp {p4_top_0/ext_mem p4_top_0/imem} {
    foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces $sp]] {
        puts [format "  %-50s offset=%s range=%s" $seg \
            [get_property offset $seg] [get_property range $seg]]
    }
}
puts "========================================\n"
puts "cpu_reset_gpio bit0: 1 = CPU held in reset, 0 = CPU runs"
puts "Powers up at 1, so the CPU stays halted until software releases it.\n"

regenerate_bd_layout
validate_bd_design
save_bd_design
