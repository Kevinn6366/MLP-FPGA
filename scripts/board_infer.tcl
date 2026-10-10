if {[llength $argv] != 1} {error "Expected one packed int8 tensor argument"}
set hex [lindex $argv 0]
if {![regexp {^[0-9a-fA-F]{8}$} $hex]} {error "Invalid input tensor"}
source [file join [file dirname [info script]] board_common.tcl]
board_attach 0
lassign [board_infer $hex] y0 y1 raw
puts "BOARD_RESULT x=$hex output=\[$y0,$y1\] source=FPGA_PL clock=25MHz"
flush stdout
board_close
