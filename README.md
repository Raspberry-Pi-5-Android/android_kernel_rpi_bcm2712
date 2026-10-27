# android_kernel_rpi_bcm2712

Prebuilt Raspberry Pi kernel for AOSP Android on the Raspberry Pi 5 (BCM2712) Linux 6.12.

## Contents

| Path | Purpose |
|---|---|
| `Image.gz` | Kernel image |
| `bcm2712*.dtb`, `overlays/` | Device trees and overlays |
| `modules/`, `modules.list` | Wi-Fi and Bluetooth kernel modules |
| `android_rpi5.config` | Android options added to `bcm2712_defconfig` |
| `build_kernel.sh` | Rebuilds everything above from source |
| `BUILD_INFO` | Source commit, compiler and checksums |

## Source and license

Built from [`raspberrypi/linux`](https://github.com/raspberrypi/linux) at the commit listed in
`BUILD_INFO`. GPL-2.0.
