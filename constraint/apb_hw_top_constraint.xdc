############################################################
# PYNQ-Z2
# APB4 Master-Slave Hardware Demonstration
############################################################


############################################################
# CLOCK
# PYNQ-Z2 onboard PL clock
# Frequency = 125 MHz
# Pin = H16
############################################################

set_property PACKAGE_PIN H16 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

create_clock -period 8.000 -name sys_clk [get_ports clk]


############################################################
# BUTTONS
############################################################

# ----------------------------------------------------------
# BTN0 -> RESET
# Pin = D19
# ----------------------------------------------------------

set_property PACKAGE_PIN D19 [get_ports reset_btn]
set_property IOSTANDARD LVCMOS33 [get_ports reset_btn]


# ----------------------------------------------------------
# BTN1 -> APB TRANSFER
# Pin = D20
# ----------------------------------------------------------

set_property PACKAGE_PIN D20 [get_ports transfer_btn]
set_property IOSTANDARD LVCMOS33 [get_ports transfer_btn]


# ----------------------------------------------------------
# BTN2 -> READ / WRITE
# Pin = L20
# ----------------------------------------------------------

set_property PACKAGE_PIN L20 [get_ports write_btn]
set_property IOSTANDARD LVCMOS33 [get_ports write_btn]


############################################################
# SWITCHES
############################################################

# ----------------------------------------------------------
# SW0 -> wait_states[0]
# Pin = M20
# ----------------------------------------------------------

set_property PACKAGE_PIN M20 [get_ports {wait_states[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {wait_states[0]}]


# ----------------------------------------------------------
# SW1 -> wait_states[1]
# Pin = M19
# ----------------------------------------------------------

set_property PACKAGE_PIN M19 [get_ports {wait_states[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {wait_states[1]}]


############################################################
# LEDS
############################################################

# ----------------------------------------------------------
# LED0 -> PSEL
# Pin = R14
# ----------------------------------------------------------

set_property PACKAGE_PIN R14 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]


# ----------------------------------------------------------
# LED1 -> PENABLE
# Pin = P14
# ----------------------------------------------------------

set_property PACKAGE_PIN P14 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]


# ----------------------------------------------------------
# LED2 -> PREADY
# Pin = N16
# ----------------------------------------------------------

set_property PACKAGE_PIN N16 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]


# ----------------------------------------------------------
# LED3 -> PWRITE
# Pin = M14
# ----------------------------------------------------------

set_property PACKAGE_PIN M14 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]


############################################################
# END OF CONSTRAINT FILE
############################################################