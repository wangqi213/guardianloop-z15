# PC LSL-to-Z15 UART bridge

This program only forwards raw OpenBCI LSL EEG samples to the Z15 serial
link.  It does not calculate fatigue, contact an ESP32, or make any control
decision.

## Install

Create a Python environment and install the packages listed in
`requirements.txt`.  `pylsl` must be able to discover the actual OpenBCI GUI
LSL stream, and the host serial port must be the Z15 board's CH340 port.

## Send live EEG

```text
python lsl_to_uart.py --port COMx --stream-name obci_eeg1
```

The sender accepts a stream with at least eight channels and maps sample
positions 0 through 7 to the transport labels `Ch1` through `Ch8`.  These are
ordinal transport labels only; no electrode placement is inferred.

## Send offline synthetic data

```text
python simulate_sender.py --port COMx --frames 80
```

The simulator uses the identical packet encoder, producing 25 samples per
packet at 250 Hz.  It is suitable for exercising the Z15 receiver when an
OpenBCI stream is unavailable.

See `../../GuardianLoop_Z15_2025_1/docs/eeg_transport_v0.md` for the exact
wire format and scaling rule.
