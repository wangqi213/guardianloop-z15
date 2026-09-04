# GuardianLoop AXI-Lite register test

This is the source snapshot of the first standalone ARM test for
`guardianloop_regs_v0`. It is kept in the main Git repository; the Vitis
workspace and its build products are intentionally not tracked.

## Platform dependency

The Vitis standalone platform was created from `guardianloop_bd.xsa` for the
`ps7_cortexa9_0` standalone domain. The program obtains the AXI-Lite base
address from the generated `xparameters.h` macro
`XPAR_GUARDIANLOOP_REGS_V0_0_BASEADDR`; it does not hard-code the address.

## Test coverage

- reads `BUILD_ID` at offset `0x04` and compares it with `0x474C0001`;
- writes and reads back `SCRATCH` at offset `0x00` using `0xA5C31F72`;
- reads `STATUS` at offset `0x08` and checks bit 0;
- returns zero only when all checks pass.

The verified address assignment for this baseline is `0x40000000`. That value
is evidence from the generated platform, not an address literal in the source.
