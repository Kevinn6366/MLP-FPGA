# Source: Digilent Zybo-Z7-Master.xdc (Rev B, Z7-10 and Z7-20).
# https://github.com/Digilent/digilent-xdc/blob/master/Zybo-Z7-Master.xdc
# Only the onboard 125 MHz PL oscillator is connected to a package pin.
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports sysclk]
# Clocking Wizard's generated XDC defines sysclk at 8.000 ns (125 MHz).
# Do not redefine that clock here: its generated-clock constraints reference it.
