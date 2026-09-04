#include "eeg_transport_v0.h"

#include "xil_printf.h"
#include "xparameters.h"
#include "xstatus.h"
#include "xuartps.h"

#ifndef XPAR_XUARTPS_0_DEVICE_ID
#error "UART0 is not present in this platform. Regenerate the platform from UART0-enabled guardianloop_bd."
#endif

static int uart_open(XUartPs *uart) {
    XUartPs_Config *config = XUartPs_LookupConfig(XPAR_XUARTPS_0_DEVICE_ID);
    if (config == NULL) {
        return XST_FAILURE;
    }
    if (XUartPs_CfgInitialize(uart, config, config->BaseAddress) != XST_SUCCESS) {
        return XST_FAILURE;
    }
    if (XUartPs_SetBaudRate(uart, 115200U) != XST_SUCCESS) {
        return XST_FAILURE;
    }
    XUartPs_SetOperMode(uart, XUARTPS_OPER_MODE_NORMAL);
    return XST_SUCCESS;
}

int main(void) {
    XUartPs uart;
    gl_eeg_receiver_t receiver;
    uint8_t rx_bytes[64];
    uint32_t last_reported_frames = 0U;

    xil_printf("GuardianLoop EEG transport v0 receiver\r\n");
    if (uart_open(&uart) != XST_SUCCESS) {
        xil_printf("FAIL: UART0 initialization\r\n");
        return 1;
    }
    gl_eeg_receiver_init(&receiver);
    xil_printf("UART0 ready: 115200 8N1, waiting for GLEE frames\r\n");

    for (;;) {
        const u32 received = XUartPs_Recv(&uart, rx_bytes, sizeof(rx_bytes));
        if (received != 0U) {
            (void)gl_eeg_receiver_feed(&receiver, rx_bytes, received);
        }
        if (receiver.stats.frames_ok != last_reported_frames) {
            const unsigned long rate_millihz =
                (unsigned long)(gl_eeg_estimated_sample_rate_hz(&receiver.stats) * 1000.0);
            last_reported_frames = receiver.stats.frames_ok;
            xil_printf(
                "EEG frames=%lu crc=%lu fmt=%lu gaps=%lu ring=%lu rate_mHz=%lu\r\n",
                (unsigned long)receiver.stats.frames_ok,
                (unsigned long)receiver.stats.crc_errors,
                (unsigned long)receiver.stats.format_errors,
                (unsigned long)receiver.stats.sequence_gaps,
                (unsigned long)receiver.ring.count,
                rate_millihz
            );
        }
    }
}
