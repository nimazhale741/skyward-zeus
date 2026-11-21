#!/usr/bin/env bash
# 把编译产物打成 zeus（小米 12 Pro）可刷入的 recovery 镜像。
#
# 用法：STOCK=../stock-recovery.img FIRMWARE=../aw8697_haptic.bin ./scripts/pack-zeus.sh out/skyward-zeus.img
#
# 环境变量：
#   BASE      编译工作树（默认 upstream）
#   STOCK     官方 OS3.0.3.0.VLBCNXM 的 recovery 镜像（100 MiB 整块）
#   FIRMWARE  aw8697 马达固件（3537 B，md5 9c2b0ebd8f5027fb1cc841f7a3963a85）
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

BASE=${BASE:-upstream}
OUT=${1:-out/skyward-zeus.img}
STOCK=${STOCK:-../stock-recovery.img}
FIRMWARE=${FIRMWARE:-../aw8697_haptic.bin}

[ -f "$STOCK" ]    || { echo "!! 找不到 $STOCK（官方 recovery.img，100 MiB）"; exit 1; }
[ -f "$FIRMWARE" ] || { echo "!! 找不到 $FIRMWARE（aw8697_haptic.bin）"; exit 1; }
[ -x "$BASE/target/release/skyward-pack" ] || { echo "!! 先编译 skyward-pack：cargo build --release -p skyward-pack"; exit 1; }

EXTRA=""
for f in "$BASE"/companion/a31/servicemanager "$BASE"/companion/a31/hwservicemanager; do
    EXTRA="$EXTRA --extra $f:skyward/hidl/a31/$(basename "$f"):0755"
done
for f in "$BASE"/companion/a31/lib/*.so; do
    b=$(basename "$f")
    EXTRA="$EXTRA --extra $f:skyward/hidl/a31/lib/$b:0755"
done
# 震动：ramdisk 里 /etc 指向 /system/etc，ueventd 第一个搜索站是 /etc/firmware，
# 放这里才不会被 modem 分区挂载的 /vendor/firmware 遮住。
EXTRA="$EXTRA --extra $FIRMWARE:system/etc/firmware/aw8697_haptic.bin:0644"

mkdir -p "$(dirname "$OUT")"
"$BASE/target/release/skyward-pack" recovery --stock "$STOCK" \
    --binary "$BASE/target/aarch64-linux-android/release/skyward" \
    --system-init "$BASE/target/system-init/aarch64-linux-android/release/system-init" \
    --config devices/zeus.toml \
    --font "$BASE/resources/fonts/MiSansVF.ttf" \
    --mono "$BASE/resources/fonts/KirkMono-Regular.ttf" \
    --mono-license "$BASE/resources/fonts/KirkMono-OFL.txt" \
    $EXTRA --out "$OUT"

echo "--- 自检 ---"
"$BASE/target/release/skyward-pack" cat "$OUT" system/bin/recovery | sha256sum
sha256sum "$BASE/target/aarch64-linux-android/release/skyward"
"$BASE/target/release/skyward-pack" cat "$OUT" skyward/device.toml | grep -n "prewarm" || true
ls -l "$OUT"
sha256sum "$OUT"
