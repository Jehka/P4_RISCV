
################################################################
# This is a generated script based on design: p4_bd
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2025.2
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   if { [string compare $scripts_vivado_version $current_vivado_version] > 0 } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2042 -severity "ERROR" " This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Sourcing the script failed since it was created with a future version of Vivado."}

   } else {
     catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   }

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source p4_bd_script.tcl


# The design that will be created by this Tcl script contains the following 
# module references:
# p4_top

# Please add the sources of those modules before sourcing this Tcl script.

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xc7z020clg484-1
   set_property BOARD_PART digilentinc.com:zedboard:part0:1.1 [current_project]
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name p4_bd

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:processing_system7:5.5\
xilinx.com:ip:axi_bram_ctrl:4.1\
xilinx.com:ip:blk_mem_gen:8.4\
xilinx.com:ip:proc_sys_reset:5.0\
xilinx.com:ip:xlconstant:1.1\
xilinx.com:ip:axi_gpio:2.0\
xilinx.com:ip:util_vector_logic:2.0\
xilinx.com:ip:ila:6.2\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

##################################################################
# CHECK Modules
##################################################################
set bCheckModules 1
if { $bCheckModules == 1 } {
   set list_check_mods "\ 
p4_top\
"

   set list_mods_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2020 -severity "INFO" "Checking if the following modules exist in the project's sources: $list_check_mods ."

   foreach mod_vlnv $list_check_mods {
      if { [can_resolve_reference $mod_vlnv] == 0 } {
         lappend list_mods_missing $mod_vlnv
      }
   }

   if { $list_mods_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2021 -severity "ERROR" "The following module(s) are not found in the project: $list_mods_missing" }
      common::send_gid_msg -ssname BD::TCL -id 2022 -severity "INFO" "Please add source files for the missing module(s) above."
      set bCheckIPsPassed 0
   }
}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set DDR [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR ]

  set FIXED_IO [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO ]


  # Create ports

  # Create instance: ps7, and set properties
  set ps7 [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7 ]
  set_property -dict [list \
    CONFIG.PCW_ACT_APU_PERIPHERAL_FREQMHZ {666.666687} \
    CONFIG.PCW_ACT_CAN_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_DCI_PERIPHERAL_FREQMHZ {10.158730} \
    CONFIG.PCW_ACT_ENET0_PERIPHERAL_FREQMHZ {125.000000} \
    CONFIG.PCW_ACT_ENET1_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ {100.000000} \
    CONFIG.PCW_ACT_FPGA1_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA2_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA3_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_PCAP_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_QSPI_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_SDIO_PERIPHERAL_FREQMHZ {50.000000} \
    CONFIG.PCW_ACT_SMC_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_SPI_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_TPIU_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_TTC0_CLK0_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC0_CLK1_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC0_CLK2_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK0_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK1_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK2_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_UART_PERIPHERAL_FREQMHZ {50.000000} \
    CONFIG.PCW_ACT_WDT_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_APU_PERIPHERAL_FREQMHZ {666.666667} \
    CONFIG.PCW_CLK0_FREQ {100000000} \
    CONFIG.PCW_CLK1_FREQ {10000000} \
    CONFIG.PCW_CLK2_FREQ {10000000} \
    CONFIG.PCW_CLK3_FREQ {10000000} \
    CONFIG.PCW_DDR_RAM_HIGHADDR {0x1FFFFFFF} \
    CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
    CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_PERIPHERAL_FREQMHZ {1000 Mbps} \
    CONFIG.PCW_ENET0_RESET_ENABLE {0} \
    CONFIG.PCW_ENET_RESET_ENABLE {1} \
    CONFIG.PCW_ENET_RESET_SELECT {Share reset pin} \
    CONFIG.PCW_EN_EMIO_TTC0 {1} \
    CONFIG.PCW_EN_ENET0 {1} \
    CONFIG.PCW_EN_GPIO {1} \
    CONFIG.PCW_EN_QSPI {1} \
    CONFIG.PCW_EN_SDIO0 {1} \
    CONFIG.PCW_EN_TTC0 {1} \
    CONFIG.PCW_EN_UART1 {1} \
    CONFIG.PCW_EN_USB0 {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {150.000000} \
    CONFIG.PCW_FPGA2_PERIPHERAL_FREQMHZ {50.000000} \
    CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
    CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {1} \
    CONFIG.PCW_GPIO_MIO_GPIO_IO {MIO} \
    CONFIG.PCW_I2C0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_I2C_RESET_ENABLE {1} \
    CONFIG.PCW_MIO_0_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_0_PULLUP {disabled} \
    CONFIG.PCW_MIO_0_SLEW {slow} \
    CONFIG.PCW_MIO_10_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_10_PULLUP {disabled} \
    CONFIG.PCW_MIO_10_SLEW {slow} \
    CONFIG.PCW_MIO_11_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_11_PULLUP {disabled} \
    CONFIG.PCW_MIO_11_SLEW {slow} \
    CONFIG.PCW_MIO_12_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_12_PULLUP {disabled} \
    CONFIG.PCW_MIO_12_SLEW {slow} \
    CONFIG.PCW_MIO_13_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_13_PULLUP {disabled} \
    CONFIG.PCW_MIO_13_SLEW {slow} \
    CONFIG.PCW_MIO_14_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_14_PULLUP {disabled} \
    CONFIG.PCW_MIO_14_SLEW {slow} \
    CONFIG.PCW_MIO_15_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_15_PULLUP {disabled} \
    CONFIG.PCW_MIO_15_SLEW {slow} \
    CONFIG.PCW_MIO_16_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_16_PULLUP {disabled} \
    CONFIG.PCW_MIO_16_SLEW {fast} \
    CONFIG.PCW_MIO_17_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_17_PULLUP {disabled} \
    CONFIG.PCW_MIO_17_SLEW {fast} \
    CONFIG.PCW_MIO_18_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_18_PULLUP {disabled} \
    CONFIG.PCW_MIO_18_SLEW {fast} \
    CONFIG.PCW_MIO_19_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_19_PULLUP {disabled} \
    CONFIG.PCW_MIO_19_SLEW {fast} \
    CONFIG.PCW_MIO_1_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_1_PULLUP {disabled} \
    CONFIG.PCW_MIO_1_SLEW {fast} \
    CONFIG.PCW_MIO_20_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_20_PULLUP {disabled} \
    CONFIG.PCW_MIO_20_SLEW {fast} \
    CONFIG.PCW_MIO_21_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_21_PULLUP {disabled} \
    CONFIG.PCW_MIO_21_SLEW {fast} \
    CONFIG.PCW_MIO_22_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_22_PULLUP {disabled} \
    CONFIG.PCW_MIO_22_SLEW {fast} \
    CONFIG.PCW_MIO_23_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_23_PULLUP {disabled} \
    CONFIG.PCW_MIO_23_SLEW {fast} \
    CONFIG.PCW_MIO_24_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_24_PULLUP {disabled} \
    CONFIG.PCW_MIO_24_SLEW {fast} \
    CONFIG.PCW_MIO_25_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_25_PULLUP {disabled} \
    CONFIG.PCW_MIO_25_SLEW {fast} \
    CONFIG.PCW_MIO_26_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_26_PULLUP {disabled} \
    CONFIG.PCW_MIO_26_SLEW {fast} \
    CONFIG.PCW_MIO_27_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_27_PULLUP {disabled} \
    CONFIG.PCW_MIO_27_SLEW {fast} \
    CONFIG.PCW_MIO_28_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_28_PULLUP {disabled} \
    CONFIG.PCW_MIO_28_SLEW {fast} \
    CONFIG.PCW_MIO_29_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_29_PULLUP {disabled} \
    CONFIG.PCW_MIO_29_SLEW {fast} \
    CONFIG.PCW_MIO_2_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_2_SLEW {fast} \
    CONFIG.PCW_MIO_30_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_30_PULLUP {disabled} \
    CONFIG.PCW_MIO_30_SLEW {fast} \
    CONFIG.PCW_MIO_31_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_31_PULLUP {disabled} \
    CONFIG.PCW_MIO_31_SLEW {fast} \
    CONFIG.PCW_MIO_32_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_32_PULLUP {disabled} \
    CONFIG.PCW_MIO_32_SLEW {fast} \
    CONFIG.PCW_MIO_33_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_33_PULLUP {disabled} \
    CONFIG.PCW_MIO_33_SLEW {fast} \
    CONFIG.PCW_MIO_34_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_34_PULLUP {disabled} \
    CONFIG.PCW_MIO_34_SLEW {fast} \
    CONFIG.PCW_MIO_35_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_35_PULLUP {disabled} \
    CONFIG.PCW_MIO_35_SLEW {fast} \
    CONFIG.PCW_MIO_36_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_36_PULLUP {disabled} \
    CONFIG.PCW_MIO_36_SLEW {fast} \
    CONFIG.PCW_MIO_37_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_37_PULLUP {disabled} \
    CONFIG.PCW_MIO_37_SLEW {fast} \
    CONFIG.PCW_MIO_38_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_38_PULLUP {disabled} \
    CONFIG.PCW_MIO_38_SLEW {fast} \
    CONFIG.PCW_MIO_39_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_39_PULLUP {disabled} \
    CONFIG.PCW_MIO_39_SLEW {fast} \
    CONFIG.PCW_MIO_3_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_3_SLEW {fast} \
    CONFIG.PCW_MIO_40_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_40_PULLUP {disabled} \
    CONFIG.PCW_MIO_40_SLEW {fast} \
    CONFIG.PCW_MIO_41_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_41_PULLUP {disabled} \
    CONFIG.PCW_MIO_41_SLEW {fast} \
    CONFIG.PCW_MIO_42_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_42_PULLUP {disabled} \
    CONFIG.PCW_MIO_42_SLEW {fast} \
    CONFIG.PCW_MIO_43_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_43_PULLUP {disabled} \
    CONFIG.PCW_MIO_43_SLEW {fast} \
    CONFIG.PCW_MIO_44_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_44_PULLUP {disabled} \
    CONFIG.PCW_MIO_44_SLEW {fast} \
    CONFIG.PCW_MIO_45_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_45_PULLUP {disabled} \
    CONFIG.PCW_MIO_45_SLEW {fast} \
    CONFIG.PCW_MIO_46_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_46_PULLUP {disabled} \
    CONFIG.PCW_MIO_46_SLEW {slow} \
    CONFIG.PCW_MIO_47_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_47_PULLUP {disabled} \
    CONFIG.PCW_MIO_47_SLEW {slow} \
    CONFIG.PCW_MIO_48_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_48_PULLUP {disabled} \
    CONFIG.PCW_MIO_48_SLEW {slow} \
    CONFIG.PCW_MIO_49_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_49_PULLUP {disabled} \
    CONFIG.PCW_MIO_49_SLEW {slow} \
    CONFIG.PCW_MIO_4_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_4_SLEW {fast} \
    CONFIG.PCW_MIO_50_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_50_PULLUP {disabled} \
    CONFIG.PCW_MIO_50_SLEW {slow} \
    CONFIG.PCW_MIO_51_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_51_PULLUP {disabled} \
    CONFIG.PCW_MIO_51_SLEW {slow} \
    CONFIG.PCW_MIO_52_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_52_PULLUP {disabled} \
    CONFIG.PCW_MIO_52_SLEW {slow} \
    CONFIG.PCW_MIO_53_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_53_PULLUP {disabled} \
    CONFIG.PCW_MIO_53_SLEW {slow} \
    CONFIG.PCW_MIO_5_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_5_SLEW {fast} \
    CONFIG.PCW_MIO_6_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_6_SLEW {fast} \
    CONFIG.PCW_MIO_7_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_7_SLEW {slow} \
    CONFIG.PCW_MIO_8_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_8_SLEW {fast} \
    CONFIG.PCW_MIO_9_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_9_PULLUP {disabled} \
    CONFIG.PCW_MIO_9_SLEW {slow} \
    CONFIG.PCW_MIO_TREE_PERIPHERALS {GPIO#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#Enet 0#Enet 0#Enet 0#Enet\
0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#SD 0#SD 0#SD 0#SD 0#SD 0#SD 0#SD 0#SD 0#UART 1#UART 1#GPIO#GPIO#Enet 0#Enet\
0} \
    CONFIG.PCW_MIO_TREE_SIGNALS {gpio[0]#qspi0_ss_b#qspi0_io[0]#qspi0_io[1]#qspi0_io[2]#qspi0_io[3]/HOLD_B#qspi0_sclk#gpio[7]#gpio[8]#gpio[9]#gpio[10]#gpio[11]#gpio[12]#gpio[13]#gpio[14]#gpio[15]#tx_clk#txd[0]#txd[1]#txd[2]#txd[3]#tx_ctl#rx_clk#rxd[0]#rxd[1]#rxd[2]#rxd[3]#rx_ctl#data[4]#dir#stp#nxt#data[0]#data[1]#data[2]#data[3]#clk#data[5]#data[6]#data[7]#clk#cmd#data[0]#data[1]#data[2]#data[3]#wp#cd#tx#rx#gpio[50]#gpio[51]#mdc#mdio}\
\
    CONFIG.PCW_PJTAG_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
    CONFIG.PCW_QSPI_GRP_FBCLK_ENABLE {0} \
    CONFIG.PCW_QSPI_GRP_IO1_ENABLE {0} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_IO {MIO 1 .. 6} \
    CONFIG.PCW_QSPI_GRP_SS1_ENABLE {0} \
    CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_QSPI_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_QSPI_QSPI_IO {MIO 1 .. 6} \
    CONFIG.PCW_SD0_GRP_CD_ENABLE {1} \
    CONFIG.PCW_SD0_GRP_CD_IO {MIO 47} \
    CONFIG.PCW_SD0_GRP_POW_ENABLE {0} \
    CONFIG.PCW_SD0_GRP_WP_ENABLE {1} \
    CONFIG.PCW_SD0_GRP_WP_IO {MIO 46} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
    CONFIG.PCW_SDIO_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_SDIO_PERIPHERAL_VALID {1} \
    CONFIG.PCW_SINGLE_QSPI_DATA_MODE {x4} \
    CONFIG.PCW_TTC0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_TTC0_TTC0_IO {EMIO} \
    CONFIG.PCW_TTC_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_UART1_GRP_FULL_ENABLE {0} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
    CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_UART_PERIPHERAL_VALID {1} \
    CONFIG.PCW_UIPARAM_ACT_DDR_FREQ_MHZ {533.333374} \
    CONFIG.PCW_UIPARAM_DDR_BL {8} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY0 {0.41} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY1 {0.411} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY2 {0.341} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY3 {0.358} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 {0.025} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 {0.028} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {0.001} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {0.001} \
    CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333313} \
    CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J128M16 HA-15E} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_DATA_EYE {1} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_READ_GATE {1} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_WRITE_LEVEL {1} \
    CONFIG.PCW_UIPARAM_DDR_USE_INTERNAL_VREF {1} \
    CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_USB0_RESET_ENABLE {0} \
    CONFIG.PCW_USB0_USB0_IO {MIO 28 .. 39} \
    CONFIG.PCW_USB_RESET_ENABLE {1} \
    CONFIG.PCW_USB_RESET_SELECT {Share reset pin} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.preset {ZedBoard} \
  ] $ps7


  # Create instance: p4_top_0, and set properties
  set block_name p4_top
  set block_cell_name p4_top_0
  if { [catch {set p4_top_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $p4_top_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: dmem_ctrl_cpu, and set properties
  set dmem_ctrl_cpu [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 dmem_ctrl_cpu ]
  set_property -dict [list \
    CONFIG.PROTOCOL {AXI4LITE} \
    CONFIG.SINGLE_PORT_BRAM {1} \
  ] $dmem_ctrl_cpu


  # Create instance: dmem_ctrl_ps, and set properties
  set dmem_ctrl_ps [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 dmem_ctrl_ps ]
  set_property -dict [list \
    CONFIG.PROTOCOL {AXI4LITE} \
    CONFIG.SINGLE_PORT_BRAM {1} \
  ] $dmem_ctrl_ps


  # Create instance: dmem_bram, and set properties
  set dmem_bram [ create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 dmem_bram ]
  set_property -dict [list \
    CONFIG.Enable_B {Use_ENB_Pin} \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Port_B_Clock {100} \
    CONFIG.Port_B_Enable_Rate {100} \
    CONFIG.Port_B_Write_Rate {50} \
    CONFIG.Use_RSTB_Pin {true} \
  ] $dmem_bram


  # Create instance: imem_ctrl_cpu, and set properties
  set imem_ctrl_cpu [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 imem_ctrl_cpu ]
  set_property -dict [list \
    CONFIG.PROTOCOL {AXI4LITE} \
    CONFIG.SINGLE_PORT_BRAM {1} \
  ] $imem_ctrl_cpu


  # Create instance: imem_ctrl_ps, and set properties
  set imem_ctrl_ps [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 imem_ctrl_ps ]
  set_property -dict [list \
    CONFIG.PROTOCOL {AXI4LITE} \
    CONFIG.SINGLE_PORT_BRAM {1} \
  ] $imem_ctrl_ps


  # Create instance: imem_bram, and set properties
  set imem_bram [ create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 imem_bram ]
  set_property -dict [list \
    CONFIG.Enable_B {Use_ENB_Pin} \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Port_B_Clock {100} \
    CONFIG.Port_B_Enable_Rate {100} \
    CONFIG.Port_B_Write_Rate {50} \
    CONFIG.Use_RSTB_Pin {true} \
  ] $imem_bram


  # Create instance: ps_interconnect, and set properties
  set ps_interconnect [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps_interconnect ]
  set_property CONFIG.NUM_MI {4} $ps_interconnect


  # Create instance: rst_ps7_100M, and set properties
  set rst_ps7_100M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_100M ]

  # Create instance: const1_1b, and set properties
  set const1_1b [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const1_1b ]
  set_property -dict [list \
    CONFIG.CONST_VAL {1} \
    CONFIG.CONST_WIDTH {1} \
  ] $const1_1b


  # Create instance: const0_1b, and set properties
  set const0_1b [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const0_1b ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0} \
    CONFIG.CONST_WIDTH {1} \
  ] $const0_1b


  # Create instance: const0_2b, and set properties
  set const0_2b [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const0_2b ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0} \
    CONFIG.CONST_WIDTH {2} \
  ] $const0_2b


  # Create instance: const0_32b, and set properties
  set const0_32b [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const0_32b ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0} \
    CONFIG.CONST_WIDTH {32} \
  ] $const0_32b


  # Create instance: const1_aux, and set properties
  set const1_aux [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const1_aux ]
  set_property -dict [list \
    CONFIG.CONST_VAL {1} \
    CONFIG.CONST_WIDTH {1} \
  ] $const1_aux


  # Create instance: cpu_reset_gpio, and set properties
  set cpu_reset_gpio [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 cpu_reset_gpio ]
  set_property -dict [list \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_DOUT_DEFAULT {0x00000001} \
    CONFIG.C_GPIO_WIDTH {1} \
    CONFIG.C_IS_DUAL {0} \
  ] $cpu_reset_gpio


  # Create instance: cpu_rst_or, and set properties
  set cpu_rst_or [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 cpu_rst_or ]
  set_property -dict [list \
    CONFIG.C_OPERATION {or} \
    CONFIG.C_SIZE {1} \
  ] $cpu_rst_or


  # Create instance: ila_p4, and set properties
  set ila_p4 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ila:6.2 ila_p4 ]
  set_property -dict [list \
    CONFIG.C_ADV_TRIGGER {true} \
    CONFIG.C_DATA_DEPTH {4096} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_MONITOR_TYPE {Native} \
    CONFIG.C_NUM_OF_PROBES {6} \
    CONFIG.C_PROBE0_WIDTH {32} \
    CONFIG.C_PROBE1_WIDTH {32} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_TRIGIN_EN {false} \
  ] $ila_p4


  # Create interface connections
  connect_bd_intf_net -intf_net dmem_ctrl_cpu_BRAM_PORTA [get_bd_intf_pins dmem_ctrl_cpu/BRAM_PORTA] [get_bd_intf_pins dmem_bram/BRAM_PORTA]
  connect_bd_intf_net -intf_net dmem_ctrl_ps_BRAM_PORTA [get_bd_intf_pins dmem_ctrl_ps/BRAM_PORTA] [get_bd_intf_pins dmem_bram/BRAM_PORTB]
  connect_bd_intf_net -intf_net imem_ctrl_cpu_BRAM_PORTA [get_bd_intf_pins imem_ctrl_cpu/BRAM_PORTA] [get_bd_intf_pins imem_bram/BRAM_PORTA]
  connect_bd_intf_net -intf_net imem_ctrl_ps_BRAM_PORTA [get_bd_intf_pins imem_ctrl_ps/BRAM_PORTA] [get_bd_intf_pins imem_bram/BRAM_PORTB]
  connect_bd_intf_net -intf_net p4_top_0_ext_mem [get_bd_intf_pins p4_top_0/ext_mem] [get_bd_intf_pins dmem_ctrl_cpu/S_AXI]
  connect_bd_intf_net -intf_net p4_top_0_imem [get_bd_intf_pins p4_top_0/imem] [get_bd_intf_pins imem_ctrl_cpu/S_AXI]
  connect_bd_intf_net -intf_net ps7_DDR [get_bd_intf_ports DDR] [get_bd_intf_pins ps7/DDR]
  connect_bd_intf_net -intf_net ps7_FIXED_IO [get_bd_intf_ports FIXED_IO] [get_bd_intf_pins ps7/FIXED_IO]
  connect_bd_intf_net -intf_net ps7_M_AXI_GP0 [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins ps_interconnect/S00_AXI]
  connect_bd_intf_net -intf_net ps_interconnect_M00_AXI [get_bd_intf_pins ps_interconnect/M00_AXI] [get_bd_intf_pins p4_top_0/fi_cfg]
  connect_bd_intf_net -intf_net ps_interconnect_M01_AXI [get_bd_intf_pins ps_interconnect/M01_AXI] [get_bd_intf_pins dmem_ctrl_ps/S_AXI]
  connect_bd_intf_net -intf_net ps_interconnect_M02_AXI [get_bd_intf_pins ps_interconnect/M02_AXI] [get_bd_intf_pins imem_ctrl_ps/S_AXI]
  connect_bd_intf_net -intf_net ps_interconnect_M03_AXI [get_bd_intf_pins ps_interconnect/M03_AXI] [get_bd_intf_pins cpu_reset_gpio/S_AXI]

  # Create port connections
  connect_bd_net -net const0_1b_dout  [get_bd_pins const0_1b/dout] \
  [get_bd_pins p4_top_0/periph_bvalid] \
  [get_bd_pins p4_top_0/periph_rvalid]
  connect_bd_net -net const0_2b_dout  [get_bd_pins const0_2b/dout] \
  [get_bd_pins p4_top_0/periph_bresp] \
  [get_bd_pins p4_top_0/periph_rresp]
  connect_bd_net -net const0_32b_dout  [get_bd_pins const0_32b/dout] \
  [get_bd_pins p4_top_0/periph_rdata]
  connect_bd_net -net const1_1b_dout  [get_bd_pins const1_1b/dout] \
  [get_bd_pins p4_top_0/periph_awready] \
  [get_bd_pins p4_top_0/periph_wready] \
  [get_bd_pins p4_top_0/periph_arready]
  connect_bd_net -net const1_aux_dout  [get_bd_pins const1_aux/dout] \
  [get_bd_pins rst_ps7_100M/aux_reset_in]
  connect_bd_net -net cpu_reset_gpio_gpio_io_o  [get_bd_pins cpu_reset_gpio/gpio_io_o] \
  [get_bd_pins cpu_rst_or/Op2]
  connect_bd_net -net cpu_rst_or_Res  [get_bd_pins cpu_rst_or/Res] \
  [get_bd_pins p4_top_0/rst]
  connect_bd_net -net p4_top_0_debug_out  [get_bd_pins p4_top_0/debug_out] \
  [get_bd_pins ila_p4/probe1]
  connect_bd_net -net p4_top_0_dma_irq  [get_bd_pins p4_top_0/dma_irq] \
  [get_bd_pins ila_p4/probe4]
  connect_bd_net -net p4_top_0_fi_irq  [get_bd_pins p4_top_0/fi_irq] \
  [get_bd_pins ila_p4/probe5]
  connect_bd_net -net p4_top_0_if_pc_out  [get_bd_pins p4_top_0/if_pc_out] \
  [get_bd_pins ila_p4/probe0]
  connect_bd_net -net p4_top_0_if_stall_out  [get_bd_pins p4_top_0/if_stall_out] \
  [get_bd_pins ila_p4/probe2]
  connect_bd_net -net p4_top_0_mem_stall_out  [get_bd_pins p4_top_0/mem_stall_out] \
  [get_bd_pins ila_p4/probe3]
  connect_bd_net -net ps7_FCLK_CLK0  [get_bd_pins ps7/FCLK_CLK0] \
  [get_bd_pins rst_ps7_100M/slowest_sync_clk] \
  [get_bd_pins p4_top_0/clk] \
  [get_bd_pins dmem_ctrl_cpu/s_axi_aclk] \
  [get_bd_pins dmem_ctrl_ps/s_axi_aclk] \
  [get_bd_pins imem_ctrl_cpu/s_axi_aclk] \
  [get_bd_pins imem_ctrl_ps/s_axi_aclk] \
  [get_bd_pins ps7/M_AXI_GP0_ACLK] \
  [get_bd_pins ps_interconnect/ACLK] \
  [get_bd_pins ps_interconnect/S00_ACLK] \
  [get_bd_pins ps_interconnect/M00_ACLK] \
  [get_bd_pins ps_interconnect/M01_ACLK] \
  [get_bd_pins ps_interconnect/M02_ACLK] \
  [get_bd_pins ps_interconnect/M03_ACLK] \
  [get_bd_pins cpu_reset_gpio/s_axi_aclk] \
  [get_bd_pins ila_p4/clk]
  connect_bd_net -net ps7_FCLK_RESET0_N  [get_bd_pins ps7/FCLK_RESET0_N] \
  [get_bd_pins rst_ps7_100M/ext_reset_in]
  connect_bd_net -net rst_ps7_100M_peripheral_aresetn  [get_bd_pins rst_ps7_100M/peripheral_aresetn] \
  [get_bd_pins dmem_ctrl_cpu/s_axi_aresetn] \
  [get_bd_pins dmem_ctrl_ps/s_axi_aresetn] \
  [get_bd_pins imem_ctrl_cpu/s_axi_aresetn] \
  [get_bd_pins imem_ctrl_ps/s_axi_aresetn] \
  [get_bd_pins ps_interconnect/ARESETN] \
  [get_bd_pins ps_interconnect/S00_ARESETN] \
  [get_bd_pins ps_interconnect/M00_ARESETN] \
  [get_bd_pins ps_interconnect/M01_ARESETN] \
  [get_bd_pins ps_interconnect/M02_ARESETN] \
  [get_bd_pins ps_interconnect/M03_ARESETN] \
  [get_bd_pins cpu_reset_gpio/s_axi_aresetn]
  connect_bd_net -net rst_ps7_100M_peripheral_reset  [get_bd_pins rst_ps7_100M/peripheral_reset] \
  [get_bd_pins cpu_rst_or/Op1]

  # Create address segments
  assign_bd_address -offset 0x40030000 -range 0x00001000 -with_name SEG_cpu_reset_gpio -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs cpu_reset_gpio/S_AXI/Reg] -force
  assign_bd_address -offset 0x40010000 -range 0x00004000 -with_name SEG_dmem_ps -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs dmem_ctrl_ps/S_AXI/Mem0] -force
  assign_bd_address -offset 0x40020000 -range 0x00001000 -with_name SEG_imem_ps -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs imem_ctrl_ps/S_AXI/Mem0] -force
  assign_bd_address -offset 0x40000000 -range 0x00001000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs p4_top_0/fi_cfg/reg0] -force
  assign_bd_address -offset 0x00000000 -range 0x00004000 -with_name SEG_dmem_cpu -target_address_space [get_bd_addr_spaces p4_top_0/ext_mem] [get_bd_addr_segs dmem_ctrl_cpu/S_AXI/Mem0] -force
  assign_bd_address -offset 0x00030000 -range 0x00001000 -with_name SEG_imem_cpu -target_address_space [get_bd_addr_spaces p4_top_0/imem] [get_bd_addr_segs imem_ctrl_cpu/S_AXI/Mem0] -force

  # Perform GUI Layout
  regenerate_bd_layout -layout_string {
   "ActiveEmotionalView":"Default View",
   "Default View_ScaleFactor":"0.573711",
   "Default View_TopLeft":"-303,3",
   "ExpandedHierarchyInLayout":"",
   "guistr":"# # String gsaved with Nlview 7.8.0 2024-04-26 e1825d835c VDI=44 GEI=38 GUI=JA:21.0
#  -string -flagsOSRD
preplace port DDR -pg 1 -lvl 7 -x 1990 -y 1140 -defaultsOSRD
preplace port FIXED_IO -pg 1 -lvl 7 -x 1990 -y 1170 -defaultsOSRD
preplace inst ps7 -pg 1 -lvl 2 -x 410 -y 1230 -defaultsOSRD
preplace inst p4_top_0 -pg 1 -lvl 4 -x 1140 -y 460 -defaultsOSRD
preplace inst dmem_ctrl_cpu -pg 1 -lvl 5 -x 1530 -y 320 -defaultsOSRD
preplace inst dmem_ctrl_ps -pg 1 -lvl 4 -x 1140 -y 770 -defaultsOSRD
preplace inst dmem_bram -pg 1 -lvl 6 -x 1840 -y 760 -defaultsOSRD
preplace inst imem_ctrl_cpu -pg 1 -lvl 5 -x 1530 -y 570 -defaultsOSRD
preplace inst imem_ctrl_ps -pg 1 -lvl 4 -x 1140 -y 910 -defaultsOSRD
preplace inst imem_bram -pg 1 -lvl 6 -x 1840 -y 900 -defaultsOSRD
preplace inst ps_interconnect -pg 1 -lvl 3 -x 790 -y 760 -defaultsOSRD
preplace inst rst_ps7_100M -pg 1 -lvl 2 -x 410 -y 1010 -defaultsOSRD
preplace inst const1_1b -pg 1 -lvl 6 -x 1840 -y 60 -defaultsOSRD
preplace inst const0_1b -pg 1 -lvl 6 -x 1840 -y 180 -defaultsOSRD
preplace inst const0_2b -pg 1 -lvl 6 -x 1840 -y 650 -defaultsOSRD
preplace inst const0_32b -pg 1 -lvl 6 -x 1840 -y 310 -defaultsOSRD
preplace inst const1_aux -pg 1 -lvl 1 -x 100 -y 1010 -defaultsOSRD
preplace inst cpu_reset_gpio -pg 1 -lvl 4 -x 1140 -y 1050 -defaultsOSRD
preplace inst cpu_rst_or -pg 1 -lvl 3 -x 790 -y 1020 -defaultsOSRD
preplace inst ila_p4 -pg 1 -lvl 6 -x 1840 -y 470 -defaultsOSRD
preplace netloc const0_1b_dout 1 4 3 1320 120 NJ 120 1960
preplace netloc const0_2b_dout 1 4 3 1400 490 1670J 590 1960
preplace netloc const0_32b_dout 1 4 3 1370J 240 1690J 250 1960
preplace netloc const1_1b_dout 1 4 3 1310 230 1720J 240 1970
preplace netloc const1_aux_dout 1 1 1 N 1010
preplace netloc cpu_reset_gpio_gpio_io_o 1 2 3 640 1130 NJ 1130 1300
preplace netloc cpu_rst_or_Res 1 3 1 970 480n
preplace netloc p4_top_0_debug_out 1 4 2 1340J 680 1700
preplace netloc p4_top_0_dma_irq 1 4 2 1320 670 1710J
preplace netloc p4_top_0_fi_irq 1 4 2 1310J 660 1720
preplace netloc p4_top_0_if_pc_out 1 4 2 1380J 430 N
preplace netloc p4_top_0_if_stall_out 1 4 2 1390J 470 N
preplace netloc p4_top_0_mem_stall_out 1 4 2 1350J 650 1680
preplace netloc ps7_FCLK_CLK0 1 1 5 220 1370 620 570 980 680 1330 410 N
preplace netloc ps7_FCLK_RESET0_N 1 1 2 210 910 600
preplace netloc rst_ps7_100M_peripheral_aresetn 1 2 3 610 580 950 240 1360
preplace netloc rst_ps7_100M_peripheral_reset 1 2 1 N 1010
preplace netloc dmem_ctrl_cpu_BRAM_PORTA 1 5 1 1690 320n
preplace netloc dmem_ctrl_ps_BRAM_PORTA 1 4 2 N 770 NJ
preplace netloc imem_ctrl_cpu_BRAM_PORTA 1 5 1 1660 570n
preplace netloc imem_ctrl_ps_BRAM_PORTA 1 4 2 N 910 NJ
preplace netloc p4_top_0_ext_mem 1 4 1 N 300
preplace netloc p4_top_0_imem 1 4 1 1300 320n
preplace netloc ps7_DDR 1 2 5 NJ 1150 NJ 1150 1400J 1140 NJ 1140 NJ
preplace netloc ps7_FIXED_IO 1 2 5 NJ 1170 NJ 1170 NJ 1170 NJ 1170 NJ
preplace netloc ps7_M_AXI_GP0 1 2 1 630 640n
preplace netloc ps_interconnect_M00_AXI 1 3 1 940 440n
preplace netloc ps_interconnect_M01_AXI 1 3 1 N 750
preplace netloc ps_interconnect_M02_AXI 1 3 1 960 770n
preplace netloc ps_interconnect_M03_AXI 1 3 1 940 790n
levelinfo -pg 1 0 100 410 790 1140 1530 1840 1990
pagesize -pg 1 -db -bbox -sgen 0 0 2100 1380
"
}

  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################


common::send_gid_msg -ssname BD::TCL -id 2052 -severity "CRITICAL WARNING" "This Tcl script was generated from a block design that is out-of-date/locked. It is possible that design <$design_name> may result in errors during construction."

create_root_design ""


