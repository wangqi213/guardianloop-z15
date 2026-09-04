# GuardianLoop EEG Quality v0

Handwritten SystemVerilog IP for fixed-point quality checks on windows of
eight-channel EEG time points.  It has no PL external pins and is not yet in a
Block Design.

The input `s_axis_tdata[127:0]` contains one time point:

```text
[15:0] Ch1, [31:16] Ch2, ... [127:112] Ch8
```

Each field is a two's-complement signed 16-bit quantity in the EEG transport
unit of 0.01 uV/LSB. `TLAST` can close a short packet/window; otherwise the
configured window count closes the window. v0 defaults to 250 samples.

Configuration is AXI4-Lite and shares `s_axi_aclk` with the stream. Threshold
limit enables reset to disabled so that reset does not assert an invented EEG
quality criterion. Software must write values and set the corresponding
enable bits before capture.

Run the independent simulation with Vivado 2025.1 from this directory's
parent project context, for example by compiling the source and
`sim/guardianloop_eeg_quality_v0_tb.sv` into a simulation-only fileset. The
repository packaging script is `tcl/package_ip.tcl`.
