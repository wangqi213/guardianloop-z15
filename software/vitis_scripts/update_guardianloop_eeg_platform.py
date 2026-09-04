"""Update the existing Vitis standalone platform from the current no-bit XSA."""

import vitis

WORKSPACE = r"D:\ican\GuardianLoop_Vitis_2025_1\workspace"
XSA = r"D:\ican\GuardianLoop_Vitis_2025_1\hardware\guardianloop_bd.xsa"

client = vitis.create_client()
client.set_workspace(WORKSPACE)
platform = client.get_component("guardianloop_standalone_platform")
platform.update_hw(XSA)
platform.build()
vitis.dispose()
