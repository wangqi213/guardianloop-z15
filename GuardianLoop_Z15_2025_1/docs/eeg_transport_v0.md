# GuardianLoop EEG transport v0

## Purpose and scope

EEG transport v0 moves raw eight-channel samples from the PC's actual OpenBCI
LSL stream to the Z15 ARM processor.  The PC is a transport bridge only.  It
does not run fatigue classification, and this milestone adds no PL EEG
filtering, ESP32 behavior, or external PL I/O.

The Vitis-side receiver retains the newest eight seconds of samples in an ARM
RAM circular buffer.  Later stages may consume that stored raw data, but they
must not reinterpret the transport labels as electrode positions without a
separate, verified montage source.

## Board UART evidence and adopted setting

The V1.1 bottom-board schematic is the board-level source used here:

- `D:\ican\【正点原子】Z15 ZYNQ7015开发板资料盘（A盘）\3_开发板原理图和硬件相关文件\ZYNQ7015_开发板底板原理图_1V1.pdf`, sheet 02, labels `PS_MIO14 → PS_UART_RX` and `PS_MIO15 → PS_UART_TX`.
- The same schematic, sheet 07, identifies U19 as `CH340E` and connects its
  `TXD` to `PS_RXD` and `RXD` to `PS_TXD` (the normal crossed UART direction).
- AMD Vivado 2025.1 Zynq-7000 PS configuration data identifies UART0's valid
  MIO pair `MIO 14 .. 15`.  The Vivado setting used for this design is
  `PCW_EN_UART0=1`, `PCW_UART0_UART0_IO={MIO 14 .. 15}`, baud `115200`.
- The CH340 data sheet identifies TXD as its UART output and RXD as its UART
  input, and specifies operation through 2 Mbit/s.  Therefore 115200 bit/s is
  within the documented bridge capability.

This config enables PS UART0 only.  It does not add an XDC or a PL port:
MIO belongs to the Zynq PS I/O path.

## LSL input contract

The current OpenBCI GUI source creates LSL time-series streams from its data
buffer.  Its LSL metadata does not establish a reliable electrode montage for
this project, so the bridge uses only the actual sample-vector order:

| Transport label | LSL sample position | Meaning |
|---|---:|---|
| `Ch1` … `Ch8` | `0` … `7` | Ordinal first eight values of each resolved EEG sample; not an inferred electrode name. |

The bridge rejects a stream with fewer than eight values.  It defaults to the
existing project stream name `obci_eeg1`, but the operator may set the exact
current stream name with `--stream-name`.

OpenBCI GUI sources reviewed for this contract:

- https://github.com/OpenBCI/OpenBCI_GUI/blob/master/OpenBCI_GUI/NetworkStreamOut.pde
- https://github.com/OpenBCI/OpenBCI_GUI/blob/master/OpenBCI_GUI/BoardCyton.pde

## Wire format

Each frame carries exactly 25 samples × 8 channels.  At 250 Hz this is 100 ms
of source data.  Every multi-byte field is **little-endian**.  Payload samples
are sample-major: all eight channel values for sample 0, then sample 1, and so
on.

| Byte offset | Bytes | Field | Value / meaning |
|---:|---:|---|---|
| 0 | 4 | `magic` | ASCII `GLEE` (`47 4C 45 45`) |
| 4 | 1 | `version` | `1` |
| 5 | 1 | `header_bytes` | `32` |
| 6 | 2 | `flags` | `0` in v0; reserved for compatible future use |
| 8 | 4 | `sequence` | Unsigned frame sequence, wraps at 2^32 |
| 12 | 8 | `source_timestamp_ns` | LSL timestamp of sample 0, rounded to ns; LSL clock domain, not UTC |
| 20 | 2 | `sample_count` | `25` |
| 22 | 1 | `channel_count` | `8` |
| 23 | 1 | `sample_format` | `1`: signed 16-bit little-endian |
| 24 | 4 | `sample_rate_millihz` | `250000` (250 Hz) |
| 28 | 4 | `scale_nv_per_lsb` | `10` |
| 32 | 400 | `payload` | 25 × 8 signed `int16` values |
| 432 | 4 | `crc32` | IEEE CRC-32 over bytes 0–431, excluding this CRC field |

The total is **436 bytes per frame**.  The input scaling is `int16 =
round(value_µV × 100)`: one LSB is 10 nV = 0.01 µV.  Values outside
[-327.68, +327.67] µV are saturated to `int16` range and counted by the PC
sender.  This explicitly preserves the stream's numeric units assumed from
the OpenBCI GUI raw time-series source; it does not apply filtering or a
fatigue transform.

## Capacity and integrity behavior

- 10 frames/s × 436 bytes/frame × 10 UART bits/byte (8N1) = **43,600 bit/s**.
- At 115,200 bit/s, line use is about **37.85%**, and a single full frame takes
  about **37.85 ms** to transmit, leaving margin inside its 100 ms interval.
- The receiver scans for the four-byte magic, validates the fixed layout and
  CRC, and then accepts the packet.  CRC or format failures are counted.
- A nonconsecutive sequence contributes to `sequence_gaps`; a wrap from
  `0xFFFF_FFFF` to zero is valid.
- Source rate is calculated from accepted frame timestamps and sample counts.
- The RAM circular buffer stores 2,000 samples × 8 signed 16-bit channels:
  exactly eight seconds at 250 Hz (32,000 bytes for samples plus timestamps).

## Components

- `software/pc_lsl_to_z15_uart/lsl_to_uart.py`: live LSL-to-UART bridge.
- `software/pc_lsl_to_z15_uart/simulate_sender.py`: serial sender with no
  OpenBCI or LSL dependency.
- `software/pc_lsl_to_z15_uart/protocol.py`: single source of PC packet
  serialization and CRC behavior.
- `software/z15_eeg_uart_rx/src/eeg_transport_v0.c`: portable Z15-side parser,
  integrity counters, rate calculation, and circular buffer.
- `software/z15_eeg_uart_rx/src/main.c`: UART0/XUartPs adapter, to be built
  against a platform generated from the UART0-enabled hardware definition.
