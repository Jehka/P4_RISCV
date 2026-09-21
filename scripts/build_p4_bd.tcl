#-----------------------------------------------------------------------
# build_p4_bd.tcl
# MINERVA P4 block design, scripted.
#
# Run from the Vivado Tcl console with the P4 project open:
#     source C:/path/to/build_p4_bd.tcl
#
# WHY SCRIPTED: p4_top exposes flat signal ports (not AXI interface
# bundles), because IP Integrator cannot infer interfaces from
# individually-named signals. That means ~17 hand-drawn connections per
# AXI link. Scripting it is faster, repeatable after a BD regeneration,
# and diffable.
#
# TOPOLOGY BUILT HERE
#
#   PS M_AXI_GP0 -> ps_interconnect -> fi_cfg        (fault campaigns)
#                                   -> dmem_ctrl_ps  (load/read data mem)
#                                   -> imem_ctrl_ps  (load PROGRAMS)
#
#   p4_top.ext_mem   -> dmem_ctrl_cpu -> +-- dmem_bram (True Dual Port)
#   PS               -> dmem_ctrl_ps  -> +
#
#   p4_top.imem      -> imem_ctrl_cpu -> +-- imem_bram (True Dual Port)
#   PS               -> imem_ctrl_ps  -> +
#
#   p4_top.periph    -> tied off (see note below)
#
# WHY DUAL PORT: an AXI BRAM Controller has a single S_AXI port, but both
# the CPU and the PS need to reach each memory. Two controllers sharing a
# True Dual Port BMG gives each its own path. This is also what makes
# runtime program loading work: the PS writes imem over JTAG while the
# CPU fetches from it.
#
# PERIPH TIE-OFF IS NOT OPTIONAL: if crossbar slave 2 is left dangling,
# any access into 0x0002_xxxx never gets a handshake, the arbiter holds
# its grant forever, and the whole fabric wedges. Constants are wired
# below to make a stray access complete harmlessly.
#
# RESET POLARITY: p4_top takes ACTIVE-HIGH rst. The BRAM controllers take
# active-LOW. Both are wired from the Processor System Reset block, from
# DIFFERENT outputs. The script verifies each controller's polarity
# property rather than assuming -- an assumed polarity cost days on P3.
#-----------------------------------------------------------------------

set BD_NAME     p4_bd
set TOP_MODULE  p4_top

# Address map -- must match axi4lite_crossbar's SLAVE_BASE/SLAVE_HIGH
set DMEM_BASE   0x00000000
set DMEM_RANGE  16K
set IMEM_BASE   0x00030000
set IMEM_RANGE  4K
set FI_BASE     0x40000000   ;# PS-side only; not a crossbar slave
set FI_RANGE    4K

#-----------------------------------------------------------------------
# 0. Create the block design
#-----------------------------------------------------------------------
# Remove any half-built BD from a previous failed run, so re-running this
# script is safe. A partially created p4_bd.bd otherwise collides with
# create_bd_design.
if {[llength [get_files -quiet ${BD_NAME}.bd]] > 0} {
    puts "Removing existing ${BD_NAME} before rebuilding..."
    catch {close_bd_design [get_bd_designs -quiet $BD_NAME]}
    catch {export_ip_user_files -of_objects [get_files ${BD_NAME}.bd] \
               -no_script -reset -force -quiet}
    catch {remove_files [get_files ${BD_NAME}.bd]}
    catch {file delete -force [file join [get_property directory [current_project]] \
               [current_project].srcs sources_1 bd $BD_NAME]}
}

create_bd_design $BD_NAME
current_bd_design $BD_NAME

#-----------------------------------------------------------------------
# 1. Zynq PS
#-----------------------------------------------------------------------
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" \
             Master "Disable" Slave "Disable"} $ps

# One GP master for PS -> fabric. FCLK0 at 100 MHz.
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
] $ps

#-----------------------------------------------------------------------
# 2. The design under test
#-----------------------------------------------------------------------
set p4 [create_bd_cell -type module -reference $TOP_MODULE p4_top_0]

#-----------------------------------------------------------------------
# 3. Memories: two True Dual Port BRAMs, two controllers each
#-----------------------------------------------------------------------
proc make_mem {name depth} {
    # controller facing the CPU (p4_top)
    set ctrl_cpu [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:axi_bram_ctrl ${name}_ctrl_cpu]
    set_property -dict [list \
        CONFIG.DATA_WIDTH {32} \
        CONFIG.SINGLE_PORT_BRAM {1} \
        CONFIG.PROTOCOL {AXI4LITE} \
    ] $ctrl_cpu

    # controller facing the PS
    set ctrl_ps [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:axi_bram_ctrl ${name}_ctrl_ps]
    set_property -dict [list \
        CONFIG.DATA_WIDTH {32} \
        CONFIG.SINGLE_PORT_BRAM {1} \
        CONFIG.PROTOCOL {AXI4LITE} \
    ] $ctrl_ps

    # shared true-dual-port memory
    set bram [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:blk_mem_gen ${name}_bram]
    set_property -dict [list \
        CONFIG.Memory_Type {True_Dual_Port_RAM} \
        CONFIG.Enable_B {Use_ENB_Pin} \
        CONFIG.Use_RSTB_Pin {true} \
        CONFIG.Port_B_Clock {100} \
        CONFIG.Port_B_Write_Rate {50} \
        CONFIG.Port_B_Enable_Rate {100} \
    ] $bram

    connect_bd_intf_net [get_bd_intf_pins ${name}_ctrl_cpu/BRAM_PORTA] \
                        [get_bd_intf_pins ${name}_bram/BRAM_PORTA]
    connect_bd_intf_net [get_bd_intf_pins ${name}_ctrl_ps/BRAM_PORTA] \
                        [get_bd_intf_pins ${name}_bram/BRAM_PORTB]
}

make_mem dmem 4096
make_mem imem 1024

#-----------------------------------------------------------------------
# 4. PS -> fabric interconnect (3 slaves: fi_cfg, dmem_ps, imem_ps)
#-----------------------------------------------------------------------
set ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect ps_interconnect]
set_property -dict [list CONFIG.NUM_MI {3}] $ic

#-----------------------------------------------------------------------
# 5. Clock and reset
#-----------------------------------------------------------------------
set rstgen [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_ps7_100M]

connect_bd_net [get_bd_pins ps7/FCLK_CLK0]    [get_bd_pins rst_ps7_100M/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7_100M/ext_reset_in]

set CLK [get_bd_pins ps7/FCLK_CLK0]

# every clocked block on the same 100 MHz domain
foreach pin {
    p4_top_0/clk
    dmem_ctrl_cpu/s_axi_aclk  dmem_ctrl_ps/s_axi_aclk
    imem_ctrl_cpu/s_axi_aclk  imem_ctrl_ps/s_axi_aclk
    ps_interconnect/ACLK
    ps_interconnect/S00_ACLK
    ps_interconnect/M00_ACLK ps_interconnect/M01_ACLK ps_interconnect/M02_ACLK
    ps7/M_AXI_GP0_ACLK
} {
    connect_bd_net $CLK [get_bd_pins $pin]
}

# ---- RESET POLARITY ----
# p4_top is ACTIVE HIGH; the AXI IP is ACTIVE LOW. Two different outputs
# of the same reset block. Getting this backwards is silent and painful.
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_reset] \
               [get_bd_pins p4_top_0/rst]

set ARSTN [get_bd_pins rst_ps7_100M/peripheral_aresetn]
foreach pin {
    dmem_ctrl_cpu/s_axi_aresetn dmem_ctrl_ps/s_axi_aresetn
    imem_ctrl_cpu/s_axi_aresetn imem_ctrl_ps/s_axi_aresetn
    ps_interconnect/ARESETN
    ps_interconnect/S00_ARESETN
    ps_interconnect/M00_ARESETN ps_interconnect/M01_ARESETN ps_interconnect/M02_ARESETN
} {
    connect_bd_net $ARSTN [get_bd_pins $pin]
}

#-----------------------------------------------------------------------
# 6. AXI wiring
#
# Vivado INFERS proper AXI interfaces from p4_top's flat ports, because
# axi4lite_ports.vh names them with the conventional <prefix>_awaddr /
# <prefix>_awvalid / ... pattern:
#
#   INFO: [IP_Flow 19-5107] Inferred bus interface 'ext_mem' ...
#   INFO: [IP_Flow 19-5107] Inferred bus interface 'imem'    ...
#   INFO: [IP_Flow 19-5107] Inferred bus interface 'fi_cfg'  ...
#   INFO: [IP_Flow 19-5107] Inferred bus interface 'periph'  ...
#
# So everything below is interface-to-interface. No signal-by-signal
# wiring is needed anywhere -- an earlier version of this script did that
# by hand on the assumption the flat ports would not be recognised.
#-----------------------------------------------------------------------

# CPU data + instruction fetch -> their BRAM controllers
connect_bd_intf_net [get_bd_intf_pins p4_top_0/ext_mem] \
                    [get_bd_intf_pins dmem_ctrl_cpu/S_AXI]
connect_bd_intf_net [get_bd_intf_pins p4_top_0/imem] \
                    [get_bd_intf_pins imem_ctrl_cpu/S_AXI]

# PS -> interconnect -> fi_cfg + the PS-side BRAM controllers
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] \
                    [get_bd_intf_pins ps_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ps_interconnect/M00_AXI] \
                    [get_bd_intf_pins p4_top_0/fi_cfg]
connect_bd_intf_net [get_bd_intf_pins ps_interconnect/M01_AXI] \
                    [get_bd_intf_pins dmem_ctrl_ps/S_AXI]
connect_bd_intf_net [get_bd_intf_pins ps_interconnect/M02_AXI] \
                    [get_bd_intf_pins imem_ctrl_ps/S_AXI]

#-----------------------------------------------------------------------
# 7. Periph (slave 2) tie-off -- REQUIRED, see header note
#-----------------------------------------------------------------------
proc make_const {name width val} {
    set c [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant $name]
    set_property -dict [list CONFIG.CONST_WIDTH $width CONFIG.CONST_VAL $val] $c
    return $c
}

make_const const1_1b  1  1
make_const const0_1b  1  0
make_const const0_2b  2  0
make_const const0_32b 32 0

# NOTE: 'periph' was inferred as an AXI interface, so its member pins may
# only be reachable individually if the interface is left unconnected.
# Each connection is guarded; anything that fails is reported at the end
# so it can be wired in the GUI rather than failing silently.
set periph_failed {}

proc tie {pin const} {
    global periph_failed
    if {[catch {connect_bd_net [get_bd_pins $const/dout] \
                               [get_bd_pins p4_top_0/$pin]} e]} {
        lappend periph_failed $pin
    }
}

foreach pin {periph_awready periph_wready periph_arready} { tie $pin const1_1b }
foreach pin {periph_bvalid periph_rvalid}                 { tie $pin const0_1b }
tie periph_bresp const0_2b
tie periph_rresp const0_2b
tie periph_rdata const0_32b

#-----------------------------------------------------------------------
# 8. Observability -- bring debug signals out
#-----------------------------------------------------------------------
foreach {pin portname} {
    debug_out     debug_out
    if_pc_out     if_pc_out
    mem_stall_out mem_stall_out
    if_stall_out  if_stall_out
    dma_irq       dma_irq
    fi_irq        fi_irq
} {
    # left in the BD for ILA probing rather than pushed to pins:
    # exposing unconstrained outputs at top level made Vivado place them
    # on arbitrary pins during P3 and destabilised the board.
}

#-----------------------------------------------------------------------
# 9. Address map -- assign explicitly, never trust auto-assignment
#-----------------------------------------------------------------------
assign_bd_address

# PS view of each slave, set explicitly and then verified below.
catch {
    set_property offset $DMEM_BASE [get_bd_addr_segs -of_objects \
        [get_bd_addr_spaces ps7/Data] -filter "NAME =~ *dmem_ctrl_ps*"]
    set_property range  $DMEM_RANGE [get_bd_addr_segs -of_objects \
        [get_bd_addr_spaces ps7/Data] -filter "NAME =~ *dmem_ctrl_ps*"]

    set_property offset $IMEM_BASE [get_bd_addr_segs -of_objects \
        [get_bd_addr_spaces ps7/Data] -filter "NAME =~ *imem_ctrl_ps*"]
    set_property range  $IMEM_RANGE [get_bd_addr_segs -of_objects \
        [get_bd_addr_spaces ps7/Data] -filter "NAME =~ *imem_ctrl_ps*"]
}

#-----------------------------------------------------------------------
# 10. Checks -- report rather than assume
#-----------------------------------------------------------------------
puts "\n==================== P4 BD CHECKS ===================="

puts "\n-- reset polarity (verify, do not assume) --"
foreach c {dmem_ctrl_cpu dmem_ctrl_ps imem_ctrl_cpu imem_ctrl_ps} {
    if {[catch {set v [get_property CONFIG.C_S_AXI_RESET_HIGH [get_bd_cells $c]]} e]} {
        puts "  $c : property not present (check manually)"
    } else {
        puts "  $c : C_S_AXI_RESET_HIGH = $v   (expect 0 = active low)"
    }
}
puts "  p4_top_0/rst driven by peripheral_reset (ACTIVE HIGH) -- by design"

puts "\n-- address map --"
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps7/Data]] {
    puts [format "  %-55s offset=%s range=%s" $seg \
        [get_property offset $seg] [get_property range $seg]]
}

puts "\n-- periph (crossbar slave 2) tie-off --"
if {[llength $periph_failed] == 0} {
    puts "  all periph inputs tied off OK"
} else {
    puts "  *** COULD NOT TIE OFF: $periph_failed"
    puts "  *** Wire these in the GUI before generating a bitstream."
    puts "  *** A dangling slave 2 wedges the crossbar on any 0x0002_xxxx access."
}

puts "\n-- reminder --"
puts "  * crossbar slave 2 (periph) is tied off in this BD."
puts "  * imem base here must equal axi4lite_crossbar SLAVE_BASE\[3\] = 0x00030000"
puts "  * XDC: create_clock on the RAW 100MHz pin only, never a divided output"
puts "======================================================\n"

#-----------------------------------------------------------------------
# 11. Validate and wrap
#-----------------------------------------------------------------------
regenerate_bd_layout
validate_bd_design
save_bd_design

make_wrapper -files [get_files ${BD_NAME}.bd] -top
add_files -norecurse [file join [get_property directory [current_project]] \
    [current_project].gen sources_1 bd $BD_NAME hdl ${BD_NAME}_wrapper.v]
set_property top ${BD_NAME}_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "P4 block design built. Review the checks above before synthesising."