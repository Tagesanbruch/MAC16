# MAC16 SDC Constraints for 1GHz operation
# Target: 55nm icsprout PDK

# Clock definition - 1GHz = 1ns period
create_clock -name core_clock -period 1.0 [get_ports clk]

# Clock uncertainty (jitter + skew)
set_clock_uncertainty 0.05 [get_clocks core_clock]

# Input delay - assume 30% of clock period
set_input_delay -clock core_clock -max 0.3 [get_ports {inA inB mode}]
set_input_delay -clock core_clock -min 0.0 [get_ports {inA inB mode}]

# Output delay - assume 30% of clock period
set_output_delay -clock core_clock -max 0.3 [get_ports {sum_out carry out_ready}]
set_output_delay -clock core_clock -min 0.0 [get_ports {sum_out carry out_ready}]

# Reset is asynchronous
set_false_path -from [get_ports rst_n]

# Max transition and capacitance
set_max_transition 0.1 [current_design]
set_max_fanout 20 [current_design]
