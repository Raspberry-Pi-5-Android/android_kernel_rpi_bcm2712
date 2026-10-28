#!/bin/bash
# Copyright (C) 2026 The Raspberry-Pi-5-Android Project
# SPDX-License-Identifier: Apache-2.0
#
# Build the Raspberry Pi 5 kernel used by this tree: the Raspberry Pi kernel
# with bcm2712_defconfig, the AOSP android-base.config and the board options
# in android_rpi5.config.
#
# Usage:
#   KSRC=/path/to/raspberrypi-linux OUT=/path/to/build ./build_kernel.sh [--install]
#
# --install copies Image.gz, the board DTBs, the overlays and the modules named
# in modules.list into this directory and rewrites BUILD_INFO. The vendor
# partition ships only the listed modules and loads them with modprobe.
set -euo pipefail

KERNEL_URL=https://github.com/raspberrypi/linux.git
KERNEL_BRANCH=rpi-6.12.y
KERNEL_COMMIT=3163cc5b7c428294db03c4b19260e5c16c626d7a
# android-base.config is a verbatim copy of this file.
ANDROID_BASE_SOURCE="https://android.googlesource.com/kernel/configs f3ac1b9ecf5224b8d24371888e308fffae6207d7 v/android-6.6/android-base.config"

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
"$KSRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" \
  "$HERE/android-base.config" "$HERE/android_rpi5.config"
make -C "$KSRC" O="$OUT" olddefconfig

# Print the options of a fragment that olddefconfig did not keep.
unapplied() {
  while IFS= read -r line; do
    case "$line" in
      "# CONFIG_"*" is not set")
        sym=${line#\# }
        sym=${sym%% *}
        if grep -q "^$sym=" "$OUT/.config"; then
          echo "$line"
        fi
        ;;
      ""|"#"*) ;;
      *)
        grep -qxF "$line" "$OUT/.config" || echo "$line"
        ;;
    esac
  done < "$1"
}

# Every board option must survive olddefconfig.
missing=$(unapplied "$HERE/android_rpi5.config")
if [ -n "$missing" ]; then
  echo "error: options in android_rpi5.config not applied:" >&2
  echo "$missing" >&2
  exit 1
fi
# android-base.config is written for the Android Common Kernel and the LLVM
# toolchain; the options this kernel does not provide are listed in BUILD_INFO.
base_missing=$(unapplied "$HERE/android-base.config")

make -C "$KSRC" O="$OUT" -j"$(nproc)" Image.gz dtbs modules

if [ "${1:-}" = "--install" ]; then
  boot=$OUT/arch/arm64/boot
  cp "$boot/Image.gz" "$HERE/Image.gz"
  for dtb in "$HERE"/bcm2712*.dtb; do
    cp "$boot/dts/broadcom/$(basename "$dtb")" "$dtb"
  done
  rm -rf "$HERE/overlays"
  mkdir "$HERE/overlays"
  cp "$boot"/dts/overlays/*.dtbo "$boot/dts/overlays/overlay_map.dtb" "$HERE/overlays/"
  rm -rf "$HERE/modules"
  mkdir "$HERE/modules"
  while IFS= read -r mod; do
    case "$mod" in ""|"#"*) continue ;; esac
    found=$(find "$OUT" -name "$mod.ko")
    if [ "$(printf '%s\n' "$found" | grep -c .)" != 1 ]; then
      echo "error: expected exactly one $mod.ko, found: $found" >&2
      exit 1
    fi
    cp "$found" "$HERE/modules/"
  done < "$HERE/modules.list"
  {
    echo "source: $KERNEL_URL $KERNEL_BRANCH $KERNEL_COMMIT"
    echo "release: $(make -s -C "$KSRC" O="$OUT" kernelrelease)"
    echo "compiler: $("${CROSS_COMPILE}gcc" --version | head -1)"
    echo "config: bcm2712_defconfig + android-base.config + android_rpi5.config"
    echo "android-base.config: $ANDROID_BASE_SOURCE"
    echo "android-base.config options not provided by this kernel:"
    printf '%s\n' "$base_missing" | sed 's/^/  /'
    echo "sha256:"
    (cd "$HERE" && sha256sum Image.gz bcm2712*.dtb modules/*.ko)
  } > "$HERE/BUILD_INFO"
fi
