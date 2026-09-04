"""Create and build an isolated Vitis EEG UART-to-DMA link-test app."""

import vitis

XSA = r"D:\ican\GuardianLoop_Vitis_2025_1\hardware\guardianloop_bd.xsa"
WORKSPACE = r"D:\ican\GuardianLoop_Vitis_2025_1\eeg_dma_build_workspace_v3"
SOURCE = r"D:\ican\ican_fpga_project\software\z15_eeg_uart_rx\src"

client = vitis.create_client()
client.set_workspace(WORKSPACE)
platform = client.create_platform_component(
    name="guardianloop_eeg_dma_platform",
    hw_design=XSA,
    cpu="ps7_cortexa9_0",
    os="standalone",
    domain_name="standalone_ps7_cortexa9_0",
    template="empty_application",
)
platform.build()
app = client.create_app_component(
    name="guardianloop_eeg_dma_test",
    platform=platform.project_location,
    domain="standalone_ps7_cortexa9_0",
    template="empty_application",
)
app.import_files(
    from_loc=SOURCE,
    files=["guardianloop_eeg_dma_test.c", "eeg_transport_v0.c", "eeg_transport_v0.h"],
    dest_dir_in_cmp="src",
)
app.build()
vitis.dispose()
