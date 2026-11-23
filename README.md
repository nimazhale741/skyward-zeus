# Skyward for Xiaomi 12 Pro (zeus)

小米 12 Pro（`zeus` / 2201122C / SM8450 / `taro`）的 [Skyward](https://github.com/kirklin/skyward) 移植。

> **第一次来先看：[docs/文件说明.md](docs/文件说明.md)** —— 每个文件是干什么的、该刷哪个、刷错会怎样。
> 全部文档（永久保留，不要删除/替换）：[docs/README.md](docs/README.md)。
> 想修 WLAN 11 秒？看 [docs/vendor_boot补丁教程.md](docs/vendor_boot补丁教程.md)。
> 想自己编译？看 [docs/源码补丁教程.md](docs/源码补丁教程.md)。

## 现在是什么

| 项 | 值 |
| --- | --- |
| 上游 | `kirklin/skyward` **v0.5.0** |
| 叠加 | diting 分支的 WLAN 预热、已保存网络自动连接、接口等待 45 s（见 `patches/`） |
| 实测系统 | `OS4.0.0.44.XPBCNXM`（zeus，A/B，slot a） |
| WLAN | 原厂 `cnss2` 会等 modem DMS 约 11 秒；用 `tools/patch_vendor_boot.py` 给自己机器的 vendor_boot 打补丁后，开机约 15 秒可上网 |

## 我该刷哪个？

| 我想要 | 用哪个文件 | 刷到哪里 |
| --- | --- | --- |
| 用上 Skyward recovery | `skyward-v0.5.0-zeus.img`（release） | `recovery_a` |
| recovery 里“更新 Skyward” | `skyward-v0.5.0-zeus-OS4.0.0.44.XPBCNXM.zip`（release） | 不刷，放手机里给更新用 |
| 修 WiFi 那 11 秒 | **用 `tools/patch_vendor_boot.py` 打自己机器的 vendor_boot** | `vendor_boot_a`（打完后） |
| 自己编译 | `patches/0001-diting-0.5.0.patch` + `scripts/setup.sh` | 不刷 |

**release 里不再提供现成的 vendor_boot 镜像**：它和系统版本绑定，跨版本刷会出问题；请用工具按自己机器打。

## 目录

```
devices/zeus.toml            设备配置
patches/0001-diting-0.5.0.patch  相对上游 v0.5.0 的源码补丁
scripts/setup.sh             拉 v0.5.0、打补丁、放配置
scripts/pack-zeus.sh         把编译产物打成 100 MiB recovery 镜像
scripts/release-zeus.sh      编 + 打包 + 压 zip + 发布
tools/patch_vendor_boot.py   给任意 zeus 的 vendor_boot 自动打 cnss2 补丁
docs/文件说明.md              每个文件/每个 release 资产是干什么的
docs/源码补丁教程.md          补丁怎么用、怎么编
docs/vendor_boot补丁教程.md   vendor_boot 补丁怎么打、怎么刷、怎么回滚
docs/WLAN-DMS修复.md          11 秒的原理
```

## 构建（简版）

```bash
./scripts/setup.sh
cd upstream
export PATH="$HOME/.cargo/bin:$PATH" ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-/opt/android-ndk-r28c}
cargo ndk -t arm64-v8a --platform 30 build --release -p skyward
RUSTFLAGS="-C target-feature=+crt-static" cargo ndk -t arm64-v8a --platform 30 \
    build --release -p skyward-system-init --target-dir target/system-init
cargo build --release -p skyward-pack
cd ..
./scripts/release-zeus.sh v0.5.0 OS4.0.0.44.XPBCNXM
```

完整说明见 [docs/源码补丁教程.md](docs/源码补丁教程.md)。

## 刷入（recovery）

```powershell
adb reboot bootloader
fastboot flash recovery_a "skyward-v0.5.0-zeus.img"
fastboot set_active a
fastboot reboot
# 等约 35 秒系统起来后
adb reboot recovery
```

刷前先备份：`dd if=/dev/block/by-name/recovery_a of=/sdcard/recovery-backup.img bs=1M`（recovery 里 adb 直连即 root）。

## 已知行为

- 重启菜单里的 **用户空间 fastbootd**（或 `adb reboot fastboot`）可用：进入后 `fastboot devices` 能看到设备。
- **rec 内在线更新**：检查与下载默认走 `v4.gh-proxy.org`（快），失败自动换 `gh-proxy.com`，再失败直连 GitHub；下载后仍校验 SHA-256。
- WLAN 页初始为“关”；芯片后台预热，未打 vendor_boot 补丁时约 26 秒就绪，打了约 15 秒；点开开关 1~2 秒出列表。
- 界面语言跟随系统（15 种）。

## 许可

上游 GPL-3.0，本移植同样按 GPL-3.0 发布，见 `LICENSE`。
