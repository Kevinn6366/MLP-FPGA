# Download only. No simulation, test vectors or reference-model dependency.
source [file join [file dirname [info script]] board_common.tcl]
board_attach 1
board_write vio_reset 1
board_write vio_request 0
board_write vio_x 00000000
board_write vio_reset 0
refresh_hw_vio $board_vio
if {([board_read vio_status] & 7) != 4 || [board_read vio_count] != 0} {
    error "Programmed design is not idle or its clock is not locked"
}
puts "PROGRAM_READY: xc7z020 PL configured; MLP4 clock locked; ready for tensor input"
flush stdout
board_close
