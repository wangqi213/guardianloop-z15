# EEG UART-to-DMA board validation (Vivado/Vitis 2025.1)

## Result

The GuardianLoop EEG simulation path was verified on the Z15 board with the
2025.1 hardware design and `guardianloop_eeg_dma_test` application:

```text
PC serial simulator
  -> Z15 UART0 (CH340 / PS_UART)
  -> ARM DDR receive ring and 250-sample source buffer
  -> AXI DMA MM2S
  -> guardianloop_eeg_quality_v0
  -> ARM reads status, valid mask, and reason code
```

The passing board output was:

```text
Switching to direct PL peripheral access...
MMU and data cache disabled for PL test.
GuardianLoop EEG UART->DDR->DMA quality link test
Waiting for 250 EEG time points over UART0...
UART rx=00000200 frames=00000001 crc=00000000 format=00000000 discarded=00000000 samples=00000019
UART rx=00000400 frames=00000002 crc=00000000 format=00000000 discarded=00000000 samples=00000032
UART rx=00000600 frames=00000003 crc=00000000 format=00000000 discarded=00000000 samples=0000004B
UART rx=00000800 frames=00000004 crc=00000000 format=00000000 discarded=00000000 samples=00000064
UART rx=00000A00 frames=00000005 crc=00000000 format=00000000 discarded=00000000 samples=0000007D
UART rx=00000C00 frames=00000007 crc=00000000 format=00000000 discarded=00000000 samples=000000AF
UART rx=00000E00 frames=00000008 crc=00000000 format=00000000 discarded=00000000 samples=000000C8
UART rx=00001000 frames=00000009 crc=00000000 format=00000000 discarded=00000000 samples=000000E1
UART window complete: frames=0000000A samples=000000FA
Reading GuardianLoop register IP...
GuardianLoop register BUILD_ID=474C0001
Flushing DDR cache...
Configuring Quality AXI-Lite...
Quality AXI-Lite configured.
Starting AXI DMA MM2S...
DMA complete; waiting for Quality result...
PASS: DMA complete, quality_status=0x00000007 valid_mask=0xFF reason=0x00000000
```

`quality_status=0x00000007` means capture enabled, quality-valid, and
result-ready. `valid_mask=0xFF` means all eight transport channels were valid
for this test. `reason=0x00000000` means no enabled quality rule failed.

## Board and serial conditions

- Board: Z15 (`xc7z015clg485-2`), PS UART0 connected through the board
  `PS_UART` USB-C/CH340 interface.
- PC port: `COM9` during this validation.
- UART: 115200 bit/s, 8 data bits, no parity, 1 stop bit, no flow control.
- FPGA image: the generated `guardianloop_bd_wrapper.bit` from this 2025.1
  project; it is not committed to Git.
- Debug launch: local bare-metal debug, program device enabled, PS7 init and
  PS7 post-init enabled, `ps7_cortexa9_0` selected.

The test application disables the MMU and data cache before touching the PL
AXI window. This is deliberate for the board test because the standalone BSP
MMU table did not map the user PL address range `0x4000_0000` through
`0x404F_FFFF`.

## Reproduction command

After building and starting `guardianloop_eeg_dma_test` in Vitis, resume it
from `main`, then run the PC sender from
`software/pc_lsl_to_z15_uart`:

```powershell
& "D:\Users\lenovo\anaconda3\python.exe" simulate_sender.py --port COM9 --frames 10 --chunk-bytes 1 --chunk-gap-ms 5
```

The command sends ten EEG transport frames of 25 time points each, producing
the required 250 samples. `--chunk-bytes 1 --chunk-gap-ms 5` is an intentionally
slow diagnostic mode used to avoid UART receiver overrun during this proof.

## Verified scope

- PC synthetic packet encoder and Z15 UART0 receive path.
- Transport framing, CRC validation, and 250-sample extraction with zero
  reported CRC, format, or discarded-byte errors.
- ARM access to the GuardianLoop register IP (`BUILD_ID=0x474C0001`).
- DDR source buffer to AXI DMA MM2S transfer.
- AXI4-Stream delivery into `guardianloop_eeg_quality_v0`.
- Quality IP result/status, valid-mask, and reason-code register readback.
- Implemented timing closed for the updated Quality IP: WNS `+9.572 ns`, TNS
  `0`, and zero failing endpoints at the 50 MHz FCLK0 clock.

## Limits and non-claims

- Quality thresholds were disabled for this run. This is a data-path and
  register-result verification only; it does **not** establish that real EEG
  quality assessment, clinical interpretation, or fatigue detection is
  complete.
- The serial sender was deliberately slower than the intended 250 Hz live
  transport. Continuous full-frame sending previously exposed UART overrun / CRC
  loss, so realtime UART buffering and flow-control behavior remain to be
  engineered and revalidated.
- OpenBCI/LSL live forwarding, actual electrode data, threshold selection, and
  downstream decision/control behavior are outside this board-test result.
