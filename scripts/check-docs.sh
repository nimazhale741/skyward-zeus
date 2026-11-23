#!/usr/bin/env bash
# 这些文件是发布的一部分：少一个、README 丢了链接，就让检查失败。
set -euo pipefail
cd "$(dirname "$0")/.."

required=(
    README.md
    docs/README.md
    docs/文件说明.md
    docs/源码补丁教程.md
    docs/vendor_boot补丁教程.md
    docs/WLAN-DMS修复.md
    docs/刷入简易说明.md
    docs/运行逻辑.md
    tools/patch_vendor_boot.py
    patches/0001-diting-0.5.0.patch
    scripts/setup.sh
    scripts/pack-zeus.sh
    scripts/release-zeus.sh
    devices/zeus.toml
)

fail=0
for f in "${required[@]}"; do
    if [ ! -f "$f" ]; then
        echo "!! 缺少 $f"
        fail=1
    fi
done

# README 必须一直留着这些入口
for link in "docs/文件说明.md" "docs/源码补丁教程.md" "docs/vendor_boot补丁教程.md"; do
    if ! grep -q "$link" README.md; then
        echo "!! README.md 里少了 $link 的链接"
        fail=1
    fi
done

if [ "$fail" -ne 0 ]; then
    echo "文档不完整，先补回来再提交。"
    exit 1
fi
echo "文档齐全。"
