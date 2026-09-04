#include "eeg_transport_v0.h"

#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xstatus.h"
#include "xuartps.h"

#ifndef SDT
#error "This Vitis 2025.1 application requires the generated SDT standalone BSP."
#endif

#ifndef XPAR_XAXIDMA_0_BASEADDR
#error "AXI DMA is absent: build against the EEG-DMA guardianloop_bd XSA."
#endif
#ifndef XPAR_GUARDIANLOOP_EEG_QUALITY_V0_0_BASEADDR
#error "EEG Quality IP is absent: build against the EEG-DMA guardianloop_bd XSA."
#endif
#ifndef XPAR_XUARTPS_0_BASEADDR
#error "UART0 is absent: build against the UART0-enabled guardianloop_bd XSA."
#endif

#define EEG_WINDOW_SAMPLES 250U
#define EEG_WINDOW_BYTES (EEG_WINDOW_SAMPLES * GL_EEG_V0_CHANNELS * sizeof(int16_t))

#define QUALITY_CONTROL_OFFSET       0x00U
#define QUALITY_WINDOW_SAMPLES       0x04U
#define QUALITY_MIN_SAMPLES          0x08U
#define QUALITY_REQUIRED_MASK        0x18U
#define QUALITY_RESULT_STATUS        0x20U
#define QUALITY_VALID_MASK           0x24U
#define QUALITY_REASON_CODE          0x28U
#define QUALITY_RESULT_READY_MASK    0x00000004U
#define QUALITY_BASE XPAR_GUARDIANLOOP_EEG_QUALITY_V0_0_BASEADDR

/* DDR source buffer: [time point][Ch1..Ch8], little-endian signed int16. */
static int16_t dma_window[EEG_WINDOW_SAMPLES][GL_EEG_V0_CHANNELS] __attribute__((aligned(64)));

static int uart_open(XUartPs *uart) {
    XUartPs_Config *config = XUartPs_LookupConfig(XPAR_XUARTPS_0_BASEADDR);
    if (config == NULL) return XST_FAILURE;
    if (XUartPs_CfgInitialize(uart, config, config->BaseAddress) != XST_SUCCESS) return XST_FAILURE;
    if (XUartPs_SetBaudRate(uart, 115200U) != XST_SUCCESS) return XST_FAILURE;
    XUartPs_SetOperMode(uart, XUARTPS_OPER_MODE_NORMAL);
    return XST_SUCCESS;
}

static int dma_open(XAxiDma *dma) {
    XAxiDma_Config *config = XAxiDma_LookupConfig(XPAR_XAXIDMA_0_BASEADDR);
    if (config == NULL) return XST_FAILURE;
    if (XAxiDma_CfgInitialize(dma, config) != XST_SUCCESS) return XST_FAILURE;
    if (XAxiDma_HasSg(dma)) return XST_FAILURE;
    XAxiDma_IntrDisable(dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    return XST_SUCCESS;
}

static void quality_configure_thresholds_disabled(void) {
    Xil_Out32(QUALITY_BASE + QUALITY_CONTROL_OFFSET, 0x00000011U);
    Xil_Out32(QUALITY_BASE + QUALITY_WINDOW_SAMPLES, EEG_WINDOW_SAMPLES);
    Xil_Out32(QUALITY_BASE + QUALITY_MIN_SAMPLES, EEG_WINDOW_SAMPLES);
    Xil_Out32(QUALITY_BASE + QUALITY_REQUIRED_MASK, 0x000000FFU);
}

static int receive_window(XUartPs *uart, gl_eeg_receiver_t *receiver) {
    uint8_t rx[64];
    int16_t channels[GL_EEG_V0_CHANNELS];
    uint32_t sample_index;

    while (receiver->ring.count < EEG_WINDOW_SAMPLES) {
        const u32 received = XUartPs_Recv(uart, rx, sizeof(rx));
        if (received != 0U) (void)gl_eeg_receiver_feed(receiver, rx, received);
    }
    for (sample_index = 0U; sample_index < EEG_WINDOW_SAMPLES; ++sample_index) {
        if (!gl_eeg_ring_get(&receiver->ring, receiver->ring.count - EEG_WINDOW_SAMPLES + sample_index,
                             channels, NULL)) return XST_FAILURE;
        for (uint32_t channel = 0U; channel < GL_EEG_V0_CHANNELS; ++channel)
            dma_window[sample_index][channel] = channels[channel];
    }
    return XST_SUCCESS;
}

int main(void) {
    XUartPs uart;
    XAxiDma dma;
    gl_eeg_receiver_t receiver;
    u32 status;

    xil_printf("GuardianLoop EEG UART->DDR->DMA quality link test\r\n");
    if (uart_open(&uart) != XST_SUCCESS || dma_open(&dma) != XST_SUCCESS) {
        xil_printf("FAIL: UART0 or AXI DMA initialization\r\n");
        return XST_FAILURE;
    }
    gl_eeg_receiver_init(&receiver);
    xil_printf("Waiting for 250 EEG time points over UART0...\r\n");
    if (receive_window(&uart, &receiver) != XST_SUCCESS) {
        xil_printf("FAIL: UART frame buffer extraction\r\n");
        return XST_FAILURE;
    }
    Xil_DCacheFlushRange((UINTPTR)dma_window, EEG_WINDOW_BYTES);
    quality_configure_thresholds_disabled();
    if (XAxiDma_SimpleTransfer(&dma, (UINTPTR)dma_window, EEG_WINDOW_BYTES,
                               XAXIDMA_DMA_TO_DEVICE) != XST_SUCCESS) {
        xil_printf("FAIL: AXI DMA MM2S start\r\n");
        return XST_FAILURE;
    }
    while (XAxiDma_Busy(&dma, XAXIDMA_DMA_TO_DEVICE)) { }
    do { status = Xil_In32(QUALITY_BASE + QUALITY_RESULT_STATUS); }
    while ((status & QUALITY_RESULT_READY_MASK) == 0U);

    xil_printf("PASS: DMA complete, quality_status=0x%08lx valid_mask=0x%02lx reason=0x%08lx\r\n",
               (unsigned long)status,
               (unsigned long)Xil_In32(QUALITY_BASE + QUALITY_VALID_MASK),
               (unsigned long)Xil_In32(QUALITY_BASE + QUALITY_REASON_CODE));
    return XST_SUCCESS;
}
