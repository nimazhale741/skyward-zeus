#!/usr/bin/env bash
# 拉上游 Skyward 指定版本（tag 或 commit），应用本仓库的补丁，产出可编译的工作树。
#
# 用法：./scripts/setup.sh [rev]        默认 a27b022（v0.3.1 之后的 wlan 重构）
# 结果：./upstream/  已打补丁、已放 devices/zeus.toml
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

REV=${1:-a27b022}
UPSTREAM=https://github.com/MartyrsBlog/skyward

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
    git apply --check "$p" || { echo "!! $(basename "$p") 不能干净应用（上游可能已改），需要手工 rebase"; exit 1; }
    git apply "$p"
done

BASE_VERSION=$(grep -m1 '^version = "' Cargo.toml | cut -d'"' -f2)
echo "==> 完成（上游版本 $BASE_VERSION）。发布前把 Cargo.toml 的 version 改成你的 tag 数字。"
cat <<'EOF'
cd upstream
export PATH="$HOME/.cargo/bin:$PATH" ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-/opt/android-ndk-r28c}
cargo ndk -t arm64-v8a --platform 30 build --release -p skyward
RUSTFLAGS="-C target-feature=+crt-static" cargo ndk -t arm64-v8a --platform 30 \
    build --release -p skyward-system-init --target-dir target/system-init
cargo build --release -p skyward-pack
EOF
