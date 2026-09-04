# GuardianLoop EEG Quality v0 design

## Scope

`guardianloop_eeg_quality_v0` is a handwritten SystemVerilog IP that evaluates
per-channel acquisition quality over a fixed-point EEG time window. It does
not filter EEG, classify fatigue, infer electrode names, or connect to a Block
Design in this revision.

It uses a single shared clock/reset (`s_axi_aclk`, `s_axi_aresetn`) for its
AXI4-Lite and AXI4-Stream interfaces. The existing GuardianLoop PS design
provides FCLK0 at 50 MHz, but this IP has not yet been instantiated there.

## AXI4-Stream input

One accepted transfer is one time point across eight transport-order channels.
`TVALID` and `TREADY` form the transfer handshake. `TREADY` is asserted only
when capture is explicitly enabled through AXI-Lite.

| `TDATA` bits | Field | Format |
|---|---|---|
| 15:0 | Ch1 | signed two's-complement `int16` |
| 31:16 | Ch2 | signed two's-complement `int16` |
| … | … | … |
| 127:112 | Ch8 | signed two's-complement `int16` |

The numeric unit is the existing EEG transport unit: 0.01 µV per LSB. The
labels Ch1–Ch8 mean ordinal transport positions only. `TLAST` optionally
closes a window early; otherwise the configured window count closes it.

The default window configuration is 250 accepted time points. At the current
250 Hz transport rate this is one second. No rate clock is assumed inside PL;
the window follows valid AXI-Stream transfers.

## AXI4-Lite register map

All addresses are offsets within this IP's future AXI address segment. No
system AXI base address is chosen or recorded here.

| Offset | Register | Access | Reset | Description |
|---:|---|---|---:|---|
| 0x00 | CONTROL | RW | 0 | bit0 capture enable; bit1 max-abs enable; bit2 saturation-count enable; bit3 mean-abs enable; bit4 write-one clear result/working state. |
| 0x04 | WINDOW_SAMPLES | RW | 250 | Sample count that closes a window when `TLAST` has not closed it first. |
| 0x08 | MIN_SAMPLES | RW | 250 | Minimum count required for each channel to be valid. |
| 0x0C | MAX_ABS | RW | 0 | Maximum permitted absolute sample value; used only when CONTROL.bit1 is set. |
| 0x10 | MAX_SAT_COUNT | RW | 0 | Maximum permitted count of `0x7FFF` or `0x8000`; used only when CONTROL.bit2 is set. |
| 0x14 | MAX_MEAN_ABS | RW | 0 | Maximum permitted integer mean of absolute samples; used only when CONTROL.bit3 is set. |
| 0x18 | REQUIRED_VALID_MASK | RW | 0xFF | Channel-valid bits required for overall valid. |
| 0x20 | RESULT_STATUS | RO | 0 | bit0 capture enabled; bit1 overall valid; bit2 result ready. |
| 0x24 | VALID_CHANNEL_MASK | RO | 0 | bit *n* represents Ch*n+1* validity. |
| 0x28 | REASON_CODE | RO | 0 | Global reason bit mask below. |
| 0x2C | COMPLETED_SAMPLES | RO | 0 | Count in the last closed window. |
| 0x30 | WINDOW_SEQUENCE | RO | 0 | Incremented for every closed window. |

Per-channel result blocks begin at `0x40 + channel_index × 0x20`, where
channel index zero is Ch1. All are read-only:

| Relative offset | Field |
|---:|---|
| 0x00 | received sample count |
| 0x04 | maximum absolute amplitude |
| 0x08 | saturation count |
| 0x0C | integer mean absolute value |
| 0x10 | flags: bit0 valid, bit1 max-abs fail, bit2 saturation fail, bit3 mean-abs fail, bit4 insufficient samples |

`REASON_CODE` is bitwise: bit0 insufficient samples, bit1 max-abs failure,
bit2 saturation failure, bit3 mean-absolute failure, and bit4 one or more
required channels invalid.

All EEG-specific thresholds are software-provided AXI-Lite configuration. The
IP reset keeps every threshold check disabled to avoid assuming a clinical or
electrode-specific limit.

## Fixed-point calculation

For every accepted sample, each channel records its count, maximum absolute
value, rail-value count, and sum of absolute values. At close, mean absolute
value is the integer quotient `sum_abs / count`. Threshold comparison for the
mean uses `sum_abs > MAX_MEAN_ABS × count`, retaining integer arithmetic.

## Verification

`sim/guardianloop_eeg_quality_v0_tb.sv` independently verified:

1. normal 250-sample eight-channel window;
2. one clipped channel;
3. one excessive mean-absolute/DC-offset channel;
4. early `TLAST` with 20 samples against a configured 250-sample minimum;
5. two invalid channels causing overall valid to be zero under required mask
   `0xFF`.

Vivado Simulator 2025.1 compiled, elaborated, and passed all assertions on
2026-09-04. This is RTL simulation evidence only; no synthesis, timing, or
hardware claim is made.

## Future AXI DMA connection

An AXI DMA MM2S channel must be configured to emit an AXI4-Stream that follows
the 128-bit `TDATA` packing above, asserts `TVALID` for each time point, obeys
this IP's `TREADY`, and asserts `TLAST` on the final time point of each DMA
descriptor packet. The stream and quality IP must share FCLK0 or use a
separately designed and verified AXI-Stream clock converter. A future AXI
interconnect/SmartConnect connection must provide the IP's AXI4-Lite control
segment; its base address must be assigned by that future Block Design's
Address Editor rather than copied from any current IP.
