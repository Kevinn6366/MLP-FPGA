# Vivado 2019.1 hardware interface. No simulation or Python is used here.
set board_root [file normalize [file join [file dirname [info script]] ..]]
proc board_log {event {details ""}} {
    puts "BOARD_LOG: $event $details"
    flush stdout
}
proc board_attach {{program 0}} {
    global board_root board_device board_vio board_probes
    set ltx [file join $board_root build board mlp_board.ltx]
    set bit [file join $board_root build board mlp_board.bit]
    if {![file exists $ltx]} {error "Missing LTX; build the board design first"}
    if {$program && ![file exists $bit]} {error "Missing bitstream"}
    board_log CONNECT "server=127.0.0.1:3121"
    open_hw
    connect_hw_server -url 127.0.0.1:3121
    set targets [get_hw_targets -quiet *210351B10585A]
    if {[llength $targets] != 1} {error "Expected Zybo JTAG serial 210351B10585A; check USB and board power"}
    current_hw_target [lindex $targets 0]
    set_property PARAM.FREQUENCY 5000000 [current_hw_target]
    board_log TARGET "serial=210351B10585A JTAG=5MHz"
    open_hw_target
    set devices [get_hw_devices -quiet xc7z020*]
    if {[llength $devices] != 1} {error "Expected one xc7z020 on this board"}
    set board_device [lindex $devices 0]
    current_hw_device $board_device
    set_property PROBES.FILE $ltx $board_device
    set_property FULL_PROBES.FILE $ltx $board_device
    if {$program} {
        board_log PROGRAM "device=xc7z020"
        set_property PROGRAM.FILE $bit $board_device
        program_hw_devices $board_device
        puts "PROGRAMMED_PL: $board_device $bit"
    }
    board_log PROBES "device=xc7z020"
    refresh_hw_device $board_device
    set vios [get_hw_vios -quiet -of_objects $board_device]
    if {[llength $vios] != 1} {error "Expected MLP VIO core; program this project's bitstream first"}
    set board_vio [lindex $vios 0]
    foreach signal {vio_x vio_request vio_reset vio_y vio_status vio_count vio_id} {
        set matches [get_hw_probes -quiet -of_objects $board_vio -filter "NAME =~ *${signal}*"]
        if {[llength $matches] != 1} {error "Missing or ambiguous VIO probe $signal"}
        set board_probes($signal) [lindex $matches 0]
    }
    refresh_hw_vio $board_vio
    if {[board_read vio_id] != 0x4d4c5034} {error "Unexpected hardware design identifier"}
    board_log READY "design=MLP4 core_clock=25MHz"
}
proc board_read {name} {
    global board_probes
    set raw [get_property INPUT_VALUE $board_probes($name)]
    set raw [string map {_ "" " " ""} $raw]
    regsub -nocase {^0x} $raw {} raw
    if {![regexp {^[0-9a-fA-F]+$} $raw]} {error "Unknown hardware value for $name: $raw"}
    return [expr "0x$raw"]
}
proc board_write {name value} {
    global board_probes
    set_property OUTPUT_VALUE $value $board_probes($name)
    commit_hw_vio $board_probes($name)
}
proc board_infer {hex} {
    global board_vio
    if {![regexp {^[0-9a-fA-F]{8}$} $hex]} {error "Input must be exactly eight hex digits"}
    # Each request has a clean reset and fresh completion count: no stale result.
    board_log RESET
    board_write vio_reset 1
    board_write vio_request 0
    board_write vio_x $hex
    board_log INPUT "packed=$hex shape=1x4"
    board_write vio_reset 0
    refresh_hw_vio $board_vio
    if {([board_read vio_status] & 7) != 4 || [board_read vio_count] != 0} {
        error "Board not idle after reset, or 25 MHz clock not locked"
    }
    board_log IDLE "locked=1 busy=0 completed_count=0"
    board_log REQUEST "layers=4"
    board_write vio_request 1
    set complete 0
    for {set tries 0} {$tries < 50} {incr tries} {
        after 20
        refresh_hw_vio $board_vio
        if {([board_read vio_status] & 7) == 6 && [board_read vio_count] == 1} {
            set complete 1
            break
        }
    }
    if {!$complete} {error "Hardware inference timed out"}
    board_log DONE "busy=0 done=1 completed_count=1"
    set raw [board_read vio_y]
    set y0 [expr {$raw & 0xffffffff}]
    set y1 [expr {($raw >> 32) & 0xffffffff}]
    if {$y0 >= 0x80000000} {set y0 [expr {$y0 - 0x100000000}]}
    if {$y1 >= 0x80000000} {set y1 [expr {$y1 - 0x100000000}]}
    board_log READ "output=\[$y0,$y1\] shape=1x2"
    return [list $y0 $y1 $raw]
}
proc board_close {} {
    board_log CLOSE "releasing_JTAG"
    close_hw_target
    disconnect_hw_server
    close_hw
    board_log CLOSED
}
