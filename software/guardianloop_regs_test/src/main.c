#include "xil_io.h"
#include "xil_printf.h"
#include "xil_types.h"
#include "xparameters.h"

#ifndef XPAR_GUARDIANLOOP_REGS_V0_0_BASEADDR
#error "Generated xparameters.h does not define GuardianLoop register IP base address"
#endif

#define GUARDIANLOOP_REG_BASE       XPAR_GUARDIANLOOP_REGS_V0_0_BASEADDR
#define GUARDIANLOOP_SCRATCH_OFFSET 0x00U
#define GUARDIANLOOP_BUILD_ID_OFFSET 0x04U
#define GUARDIANLOOP_STATUS_OFFSET  0x08U

#define GUARDIANLOOP_BUILD_ID_EXPECTED 0x474C0001U
#define GUARDIANLOOP_SCRATCH_TEST_VALUE 0xA5C31F72U

int main(void)
{
    int failures = 0;
    u32 value;

    xil_printf("GuardianLoop AXI-Lite register test\r\n");
    xil_printf("Base address: 0x%08lx\r\n", (unsigned long)GUARDIANLOOP_REG_BASE);

    value = Xil_In32(GUARDIANLOOP_REG_BASE + GUARDIANLOOP_BUILD_ID_OFFSET);
    if (value != GUARDIANLOOP_BUILD_ID_EXPECTED) {
        xil_printf("FAIL: BUILD_ID expected 0x%08lx, got 0x%08lx\r\n",
                   (unsigned long)GUARDIANLOOP_BUILD_ID_EXPECTED,
                   (unsigned long)value);
        failures++;
    } else {
        xil_printf("PASS: BUILD_ID = 0x%08lx\r\n", (unsigned long)value);
    }

    Xil_Out32(GUARDIANLOOP_REG_BASE + GUARDIANLOOP_SCRATCH_OFFSET,
              GUARDIANLOOP_SCRATCH_TEST_VALUE);
    value = Xil_In32(GUARDIANLOOP_REG_BASE + GUARDIANLOOP_SCRATCH_OFFSET);
    if (value != GUARDIANLOOP_SCRATCH_TEST_VALUE) {
        xil_printf("FAIL: SCRATCH expected 0x%08lx, got 0x%08lx\r\n",
                   (unsigned long)GUARDIANLOOP_SCRATCH_TEST_VALUE,
                   (unsigned long)value);
        failures++;
    } else {
        xil_printf("PASS: SCRATCH readback = 0x%08lx\r\n", (unsigned long)value);
    }

    value = Xil_In32(GUARDIANLOOP_REG_BASE + GUARDIANLOOP_STATUS_OFFSET);
    if ((value & 0x1U) == 0U) {
        xil_printf("FAIL: STATUS bit0 is not set (STATUS = 0x%08lx)\r\n",
                   (unsigned long)value);
        failures++;
    } else {
        xil_printf("PASS: STATUS bit0 is set (STATUS = 0x%08lx)\r\n",
                   (unsigned long)value);
    }

    if (failures == 0) {
        xil_printf("GuardianLoop AXI-Lite register test: PASS\r\n");
        return 0;
    }

    xil_printf("GuardianLoop AXI-Lite register test: FAIL (%d check(s))\r\n", failures);
    return 1;
}
