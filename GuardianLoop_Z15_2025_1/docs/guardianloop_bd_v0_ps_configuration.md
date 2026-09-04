# GuardianLoop BD v0 PS configuration basis

## Scope

This note records the first `guardianloop_bd` PS-only configuration. It contains
the Zynq PS, PS DDR interfaces, FCLK0, FCLK_RESET0_N, M_AXI_GP0, and
`proc_sys_reset`. It does not add PL user I/O, XDC, AXI interconnect, or the
GuardianLoop register IP.

## Sources

- Hardware structure and PS input clock: `D:\ican\【正点原子】Z15 ZYNQ7015开发板资料盘（A盘）\3_开发板原理图和硬件相关文件\ZYNQ7015_开发板核心板原理图_1V1.pdf`, sheets 00, 03, and 08. The V1.1 schematic identifies PS_CLK as 33.3333 MHz and shows U3/U4 as NT5CC256M16 on the 32-bit PS DDR interface.
- Board-specific, factory-validated PS settings: `D:\ican\【正点原子】Z15 ZYNQ7015开发板资料盘（A盘）\4_Source_Code\2_Embedded_Vitis\XC7Z015.rar`, member `XC7Z015/5_axi_gpio/axi_gpio.srcs/sources_1/bd/system/ip/system_processing_system7_0_0/system_processing_system7_0_0.xci`. This is the current source-code archive outside `9_Z15 ZYNQ底板V1.0版本`.
- DRAM device capability: actual core-board marking `NANYA NT5CC256M16CP-DI`, and the Nanya C-die data sheet: https://datasheet.octopart.com/NT5CC256M16CP-DI-Nanya-datasheet-26587255.pdf.

## Adopted configuration

### Nanya device values

- Memory type: DDR3L (Vivado: `DDR 3 (Low Voltage)`), 1.35 V.
- Physical organization: two 4096-Mbit x16 devices, 32-bit data bus, 1 GB total.
- Per-device addressing: 3 bank bits, 15 row bits, and 10 column bits.
- Controller frequency: 533.333333 MHz (1066.666666 MT/s data rate), within the NT5CC256M16CP-DI DDR3L-1600 capability.
- Custom timing values for the Nanya device at that controller rate: CL=8, CWL=6, tRCD=13.75 ns, tRP=13.75 ns, tRC=48.75 ns, tRAS(min)=35.0 ns, and tFAW=50.0 ns. `PCW_UIPARAM_DDR_PARTNO` is `Custom` because Vivado 2025.1 does not provide an Nanya preset; the values above identify the actual fitted part.

### Factory Z15 board values retained

- DDR frequency: `PCW_UIPARAM_DDR_FREQ_MHZ=533.333333`.
- Temperature policy: `Normal (0-85)`.
- DQS-to-CLK delay, byte lanes 0-3: `0.0, 0.0, 0.0, 0.0`.
- Board delay, byte lanes 0-3: `0.25, 0.25, 0.25, 0.25`.
- User-entered DQS/DQ/clock route lengths, lanes 0-3: all `0` mm.
- DQS package lengths, lanes 0-3: `133.8645, 119.997, 121.146, 90.125`.
- DQ package lengths, lanes 0-3: `111.7605, 123.5525, 120.714, 100.836`.
- Clock package lengths, lanes 0-3: `80.0515, 80.0515, 80.0515, 80.0515`.
- DQS/DQ/clock propagation-delay fields, lanes 0-3: all `160`.
- DDR training retained from the factory configuration: write leveling, read gate, and data-eye training enabled; clock stop and internal VREF disabled.
- FCLK0: 50 MHz (`PCW_FPGA0_PERIPHERAL_FREQMHZ=50`, `PCW_EN_CLK0_PORT=1`).
- FCLK_RESET0_N is enabled and used as the active-low external reset source of `proc_sys_reset`.

## PS UART0 transport enablement

EEG transport v0 enables the Zynq PS UART0 only, using the V1.1 bottom-board
CH340E path.  This is PS MIO rather than a PL port and does not require an
XDC:

- `PCW_EN_UART0=1`
- `PCW_UART0_UART0_IO={MIO 14 .. 15}`
- `PCW_UART0_BAUD_RATE=115200`

Board evidence is `ZYNQ7015_开发板底板原理图_1V1.pdf`, sheet 02
(`PS_MIO14 → PS_UART_RX`, `PS_MIO15 → PS_UART_TX`) and sheet 07 (U19
`CH340E`: `TXD → PS_RXD`, `RXD ← PS_TXD`).  The MIO14–15 selection is also a
valid UART0 pair in the Vivado 2025.1 Zynq-7000 PS configuration data.

## Deliberately excluded

Ethernet, SD, QSPI, USB, XDC, and PL user ports remain disabled in this
milestone.  UART0 is enabled only for the PS↔CH340 EEG transport.  M_AXI_GP0
is enabled and clocked from FCLK0, with the AXI-Lite register attachment
described below.

## AXI-Lite register attachment

The next milestone connects `processing_system7_0/M_AXI_GP0` through the
single-master/single-slave `axi_smc_0` SmartConnect to
`guardianloop_regs_v0_0/s_axi` (`guardianloop.org:user:guardianloop_regs_v0:1.0`).
The SmartConnect and register IP use `FCLK_CLK0` (50 MHz) and
`rst_ps7_0_50M/peripheral_aresetn`.

Vivado Address Editor automatic assignment placed the IP segment
`guardianloop_regs_v0_0/s_axi/reg0` at `0x4000_0000`, range `0x0000_1000`
(4 KiB). This is a new automatic assignment, not an address copied from the
vendor example.
