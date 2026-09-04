# GuardianLoop EEG DMA v0 integration

## Data path

The Block Design path is PS DDR to AXI DMA MM2S to
`guardianloop_eeg_quality_v0/s_axis`. The DMA reads DDR through PS
`S_AXI_HP0`. Its control interface and the Quality AXI4-Lite interface are
reached from PS `M_AXI_GP0` through the existing `axi_smc_0`.

`axi_smc_mem_0` connects DMA's memory-read master to HP0. All listed IP clock
interfaces use FCLK0 at 50 MHz and reset uses
`rst_ps7_0_50M/peripheral_aresetn`. UART0/MIO14–15 and
`guardianloop_regs_v0` remain present.

## Automatically assigned AXI-Lite addresses

The Vivado Address Editor assigned these segments for this design revision:

- `axi_dma_0/S_AXI_LITE`: `0x4040_0000` through `0x4040_FFFF`
- `guardianloop_eeg_quality_v0_0/s_axi`: `0x4000_1000` through
  `0x4000_1FFF`

The existing `guardianloop_regs_v0` segment remains at `0x4000_0000`.
Software obtains the first two addresses only through generated
`xparameters.h` macros, not these literals.

## Stream contract

AXI DMA uses MM2S only, simple mode (scatter-gather disabled), and a 128-bit
output stream. No stream-width converter is instantiated.

One DDR record is 16 contiguous bytes:

```text
int16 Ch1, int16 Ch2, int16 Ch3, int16 Ch4,
int16 Ch5, int16 Ch6, int16 Ch7, int16 Ch8
```

On the little-endian Cortex-A9, this maps directly to Quality `TDATA[15:0]`
through `TDATA[127:112]` without changing channel order. A simple DMA
transfer of 250 records is 4,000 bytes; its final stream beat asserts TLAST.

## ARM pure-link test

`software/z15_eeg_uart_rx/src/guardianloop_eeg_dma_test.c` receives 250 time
points, copies the latest 250×8 values to an aligned DDR buffer, flushes the
cache, enables Quality capture with all threshold checks disabled, starts
MM2S, waits for completion, then reads Quality status/mask/reason. It uses
only generated `xparameters.h` identifiers for UART, DMA, and Quality IP.

No validity threshold is invented for this link test. With threshold enables
clear, it verifies transport and register visibility only.
