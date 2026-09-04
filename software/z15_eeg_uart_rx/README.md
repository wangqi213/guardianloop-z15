# Z15 EEG UART receiver

This directory contains the Zynq bare-metal receiver for GuardianLoop EEG
transport v0.  The portable parser and circular buffer have no Vivado/Vitis
dependency and are covered by `tests/test_eeg_transport_v0.c`.

`src/main.c` is the board-facing adapter.  It receives bytes from the PS
UART0 driver (`XUartPs`), feeds them to the portable parser, and reports
complete frames, CRC failures, sequence gaps, and a source-timestamp-derived
sample-rate estimate.  It does not use PL filtering or classify fatigue.

The receiver preserves 2,000 samples × 8 channels (8 seconds at 250 Hz) in
RAM.  The current oldest/newest history can be retrieved through
`gl_eeg_ring_get()` for a later storage or analysis stage.

## Target build prerequisites

Build the source as a standalone Cortex-A9 application against a platform
generated from the UART0-enabled `guardianloop_bd` hardware definition.  The
application obtains the UART peripheral identifiers from the generated
`xparameters.h`; it does not contain a handwritten UART base address.

The default serial format is 115200 bit/s, 8 data bits, no parity, one stop
bit, matching the PC bridge defaults.  The UART is used only after the PS
UART0/MIO14–15 configuration documented in the board design note is present.
