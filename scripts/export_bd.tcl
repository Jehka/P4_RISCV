#-----------------------------------------------------------------------
# export_bd.tcl
# Run ONCE from the live, working P4 project to capture the block design
# exactly as it was when it passed on hardware:
#
#     source C:/path/to/MINERVA-P4/scripts/export_bd.tcl
#
# Writes scripts/p4_bd.tcl, which recreates the BD including everything
# that was applied by hand and is therefore missing from build_p4_bd.tcl:
#   - explicit address segments (auto-assignment left 4 of 5 unassigned)
#   - aux_reset_in tie-off
#   - cpu_reset_gpio + cpu_rst_or
#   - ila_p4 and its probe connections
#-----------------------------------------------------------------------
set here [file dirname [file normalize [info script]]]
open_bd_design [get_files p4_bd.bd]
write_bd_tcl -force -include_layout [file join $here p4_bd.tcl]
puts "Wrote [file join $here p4_bd.tcl] -- commit it."
