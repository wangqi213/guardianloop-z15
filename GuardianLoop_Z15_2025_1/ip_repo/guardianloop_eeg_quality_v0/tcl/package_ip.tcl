set script_dir [file normalize [file dirname [info script]]]
set ip_root [file normalize [file join $script_dir ..]]

create_project -in_memory guardianloop_eeg_quality_v0_pack -part xc7z015clg485-2
add_files -norecurse [list [file join $ip_root hdl guardianloop_eeg_quality_v0_v1_0.sv]]
set_property top guardianloop_eeg_quality_v0_v1_0 [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir $ip_root -vendor guardianloop.org -library user -taxonomy /UserIP -set_current true
set core [ipx::current_core]
set_property name guardianloop_eeg_quality_v0 $core
set_property display_name {GuardianLoop EEG Quality v0} $core
set_property description {Fixed-point 8-channel EEG quality window statistics with AXI4-Stream input and AXI4-Lite configuration/status.} $core
set_property version 1.0 $core

set lite_if [ipx::get_bus_interfaces s_axi -of_objects $core]
set lite_protocol [ipx::get_bus_parameters PROTOCOL -of_objects $lite_if]
if {[llength $lite_protocol] == 0} { set lite_protocol [ipx::add_bus_parameter PROTOCOL $lite_if] }
set_property value AXI4LITE $lite_protocol

set stream_if [ipx::get_bus_interfaces s_axis -of_objects $core]
set stream_protocol [ipx::get_bus_parameters TDATA_NUM_BYTES -of_objects $stream_if]
if {[llength $stream_protocol] == 0} { set stream_protocol [ipx::add_bus_parameter TDATA_NUM_BYTES $stream_if] }
set_property value 16 $stream_protocol
ipx::associate_bus_interfaces -busif s_axi:s_axis -clock s_axi_aclk $core
set aclk_if [ipx::get_bus_interfaces s_axi_aclk -of_objects $core]
set associated_busif [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $aclk_if]
set_property value s_axi:s_axis $associated_busif

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core
close_project
