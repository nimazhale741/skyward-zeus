#!/usr/bin/env bash
# 拉上游 Skyward 指定版本，应用本仓库的补丁，产出可直接编译的工作树。
#
# 用法：./scripts/setup.sh [tag]        默认 v0.3.1
# 结果：./upstream/  已打补丁、已放 devices/zeus.toml
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

TAG=${1:-v0.3.1}
UPSTREAM=https://github.com/MartyrsBlog/skyward

echo "==> clone $UPSTREAM @ $TAG"
rm -rf upstream
git clone --depth 1 --branch "$TAG" "$UPSTREAM" upstream

echo "==> 放设备配置"
cp devices/zeus.toml upstream/devices/

echo "==> 应用补丁"
cd upstream
for p in "$ROOT"/patches/*.patch; do
    echo "    $(basename "$p")"
    git apply --check "$p" || { echo "!! $(basename "$p") 不能干净应用（上游可能已改），需要手工 rebase"; exit 1; }
    git apply "$p"
done

echo "==> 完成。接下来编译："
cat <<'EOF'
cd upstream
export PATH="$HOME/.cargo/bin:$PATH" ANDROID_NDK_HOME=/opt/android-ndk-r28c
cargo ndk -t arm64-v8a --platform 30 build --release -p skyward
RUSTFLAGS="-C target-feature=+crt-static" cargo ndk -t arm64-v8a --platform 30 \
    build --release -p skyward-system-init --target-dir target/system-init
cargo build --release -p skyward-pack
EOF
