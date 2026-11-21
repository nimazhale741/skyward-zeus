#!/usr/bin/env bash
# 一键出包：编译 → 打包 100 MiB 镜像 → 按更新源约定命名压 zip → 打印 SHA-256（可选 gh 发布）
#
# 用法：
#   ./scripts/release-zeus.sh <tag> <系统版本串> [--upload <owner>/<repo>]
# 例：
#   ./scripts/release-zeus.sh v0.3.1 OS3.0.3.0.VLBCNXM
#   ./scripts/release-zeus.sh v0.3.1 OS3.0.3.0.VLBCNXM --upload yourname/skyward-zeus
#
# 前置：./scripts/setup.sh 已跑过（有 upstream/），且系统里有 cargo-ndk、NDK r28c、
#       ../stock-recovery.img、../aw8697_haptic.bin
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

TAG=${1:?用法: release-zeus.sh <tag> <系统版本串> [--upload owner/repo]}
OSVER=${2:?用法: release-zeus.sh <tag> <系统版本串> [--upload owner/repo]}
UPLOAD=""
if [ "${3:-}" = "--upload" ]; then UPLOAD=${4:?--upload 需要 owner/repo}; fi

export PATH="$HOME/.cargo/bin:$PATH"
export ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-/opt/android-ndk-r28c}

cd upstream
echo "==> 编译主二进制"
cargo ndk -t arm64-v8a --platform 30 build --release -p skyward
echo "==> 编译 system-init"
RUSTFLAGS="-C target-feature=+crt-static" cargo ndk -t arm64-v8a --platform 30 \
    build --release -p skyward-system-init --target-dir target/system-init
echo "==> 编译打包器"
cargo build --release -p skyward-pack
cd "$ROOT"

echo "==> 打包镜像"
IMG=out/skyward-zeus-${TAG}.img
./scripts/pack-zeus.sh "$IMG"

SIZE=$(stat -c %s "$IMG" 2>/dev/null || stat -f %z "$IMG")
[ "$SIZE" = "104857600" ] || { echo "!! 镜像不是 104857600 字节（实际 $SIZE），停止"; exit 1; }

echo "==> 按更新源约定压 zip"
ZIP="out/skyward-${TAG}-zeus-${OSVER}.zip"
rm -f "$ZIP"
( cd "$(dirname "$IMG")" && zip -j "$ROOT/$ZIP" "$(basename "$IMG")" )
ls -l "$ZIP"

echo "==> SHA-256（上传后要与 GitHub 的 digest 对得上）"
sha256sum "$IMG"
sha256sum "$ZIP"

if [ -n "$UPLOAD" ]; then
    echo "==> 发布到 $UPLOAD"
    gh release view "$TAG" -R "$UPLOAD" >/dev/null 2>&1 \
        && gh release upload "$TAG" "$ZIP" -R "$UPLOAD" --clobber \
        || gh release create "$TAG" "$ZIP" -R "$UPLOAD" --title "$TAG" --notes "zeus ($OSVER)"
fi

echo "==> 完成：$ZIP"
