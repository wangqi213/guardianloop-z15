# GuardianLoop AXI-Lite v0 board-validation baseline

## Scope

This record freezes the first Z15 board-level verification of the minimal PS to
PL AXI4-Lite path. It covers only the custom `guardianloop_regs_v0` IP and its
standalone ARM test. It does not validate the future EEG pipeline, external
PL I/O, interrupts, DMA, or ESP32 communication.

## Implemented hardware baseline

- Project: `GuardianLoop_Z15_2025_1`.
- Device: `xc7z015clg485-2`.
- Block-design top: `guardianloop_bd_wrapper`.
- PS to PL clock: `FCLK0 = 50 MHz`.
- PS master path: `processing_system7_0/M_AXI_GP0` to `axi_smc_0` to
  `guardianloop_regs_v0_0/S_AXI`.
- Automatically assigned AXI-Lite base address:
  `0x40000000` (4 KiB segment).
- Register map: `SCRATCH` RW at `0x00`, `BUILD_ID` RO at `0x04`
  (`0x474C0001`), and `STATUS` RO at `0x08` (bit 0 set after reset release).

## Board-level verification result

The following sequence was completed over JTAG on the Z15:

1. `guardianloop_bd_wrapper.bit` was downloaded successfully.
2. ARM Cortex-A9 core 0 started `guardianloop_regs_test.elf`.
3. The test read the expected `BUILD_ID` value.
4. The test wrote and read back `SCRATCH` successfully.
5. The test read `STATUS` with bit 0 set.
6. The debugger stopped at the final decision point with `failures = 0` and
   final `value = 0x00000001`.

Therefore the initial PS-to-PL AXI-Lite register access milestone passed on
hardware.

## Reproducibility boundaries

The bitstream, routed checkpoints, implementation runs, XSA, ELF, Vitis
workspace, logs, and debug-temporary files are generated artifacts and are not
tracked in Git. The tracked source baseline consists of the Vivado project,
Block Design, required XCI metadata, custom IP sources and packaging metadata,
configuration documentation, and the archived ARM test source.
