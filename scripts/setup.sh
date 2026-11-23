#!/usr/bin/env bash
# 拉上游 Skyward v0.5.0，应用本仓库补丁（diting 功能移植），产出可编译的工作树。
#
# 用法：./scripts/setup.sh [rev]        默认 v0.5.0
# 结果：./upstream/  已打补丁、已放 devices/zeus.toml
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

REV=${1:-v0.5.0}
UPSTREAM=https://github.com/kirklin/skyward

echo "==> fetch $UPSTREAM @ $REV"
rm -rf upstream
git init -q upstream
git -C upstream remote add origin "$UPSTREAM"
git -C upstream fetch -q --depth 1 origin "$REV"
git -C upstream checkout -q FETCH_HEAD

echo "==> 放设备配置"
cp devices/zeus.toml upstream/devices/

echo "==> 应用补丁"
cd upstream
for p in "$ROOT"/patches/*.patch; do
    echo "    $(basename "$p")"
    git apply --check "$p" || { echo "!! $(basename "$p") 不能干净应用"; exit 1; }
    git apply "$p"
done

BASE_VERSION=$(grep -m1 '^version = "' Cargo.toml | cut -d'"' -f2)
echo "==> 完成（上游版本 $BASE_VERSION）"
cat <<'EOF'
cd upstream
export PATH="$HOME/.cargo/bin:$PATH" ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-/opt/android-ndk-r28c}
cargo ndk -t arm64-v8a --platform 30 build --release -p skyward
RUSTFLAGS="-C target-feature=+crt-static" cargo ndk -t arm64-v8a --platform 30 \
    build --release -p skyward-system-init --target-dir target/system-init
cargo build --release -p skyward-pack
EOF