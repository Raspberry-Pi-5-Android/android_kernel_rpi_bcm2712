#!/bin/bash
# Copyright (C) 2026 The Raspberry-Pi-5-Android Project
# SPDX-License-Identifier: Apache-2.0
#
# Build the Raspberry Pi 5 kernel used by this tree: the Raspberry Pi kernel
# with bcm2712_defconfig plus the Android options in android_rpi5.config.
#
# Usage:
#   KSRC=/path/to/raspberrypi-linux OUT=/path/to/build ./build_kernel.sh [--install]
#
# --install copies Image.gz, the board DTBs and the overlays into this directory
# and rewrites BUILD_INFO. Modules are not built because Android on this device
# loads none.
set -euo pipefail

KERNEL_URL=https://github.com/raspberrypi/linux.git
KERNEL_BRANCH=rpi-6.12.y
KERNEL_COMMIT=3163cc5b7c428294db03c4b19260e5c16c626d7a

HERE=$(cd "$(dirname "$0")" && pwd)
: "${KSRC:?set KSRC to a raspberrypi/linux checkout}"
: "${OUT:?set OUT to a build directory}"

head=$(git -C "$KSRC" rev-parse HEAD)
if [ "$head" != "$KERNEL_COMMIT" ]; then
  echo "error: $KSRC is at $head, expected $KERNEL_COMMIT" >&2
  exit 1
fi
if [ -n "$(git -C "$KSRC" status --porcelain)" ]; then
  echo "error: $KSRC has local changes" >&2
  exit 1
fi

export ARCH=arm64
export CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
# Fixed build identity so the version string does not depend on the build host.
export KBUILD_BUILD_USER=build
export KBUILD_BUILD_HOST=rpi5-android
KBUILD_BUILD_TIMESTAMP=$(git -C "$KSRC" log -1 --format=%cd --date=rfc2822)
export KBUILD_BUILD_TIMESTAMP

mkdir -p "$OUT"
make -C "$KSRC" O="$OUT" bcm2712_defconfig
"$KSRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" "$HERE/android_rpi5.config"
make -C "$KSRC" O="$OUT" olddefconfig

# Every option in the fragment must survive olddefconfig.
failed=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    "# CONFIG_"*" is not set")
      sym=${line#\# }
      sym=${sym%% *}
      if grep -q "^$sym=" "$OUT/.config"; then
        echo "error: $sym should not be set" >&2
        failed=1
      fi
      ;;
    "#"*) ;;
    *)
      if ! grep -qxF "$line" "$OUT/.config"; then
        echo "error: not applied: $line" >&2
        failed=1
      fi
      ;;
  esac
done < "$HERE/android_rpi5.config"
[ "$failed" = 0 ]

make -C "$KSRC" O="$OUT" -j"$(nproc)" Image.gz dtbs

if [ "${1:-}" = "--install" ]; then
  boot=$OUT/arch/arm64/boot
  cp "$boot/Image.gz" "$HERE/Image.gz"
  for dtb in "$HERE"/bcm2712*.dtb; do
    cp "$boot/dts/broadcom/$(basename "$dtb")" "$dtb"
  done
  rm -rf "$HERE/overlays"
  mkdir "$HERE/overlays"
  cp "$boot"/dts/overlays/*.dtbo "$boot/dts/overlays/overlay_map.dtb" "$HERE/overlays/"
  {
    echo "source: $KERNEL_URL $KERNEL_BRANCH $KERNEL_COMMIT"
    echo "release: $(make -s -C "$KSRC" O="$OUT" kernelrelease)"
    echo "compiler: $("${CROSS_COMPILE}gcc" --version | head -1)"
    echo "config: bcm2712_defconfig + android_rpi5.config"
    echo "sha256:"
    (cd "$HERE" && sha256sum Image.gz bcm2712*.dtb)
  } > "$HERE/BUILD_INFO"
fi
