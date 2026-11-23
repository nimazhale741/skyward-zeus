# Skyward for Xiaomi 12 Pro (zeus)

小米 12 Pro（`zeus` / 2201122C / SM8450 / `taro`）的 [Skyward](https://github.com/kirklin/skyward) 移植。

上游是 kirklin 用 Rust 写的仿小米设置风格 Recovery；这里放这台机器的适配、构建脚本和发布产物。

## 现在是什么

| 项 | 值 |
| --- | --- |
| 上游 | `kirklin/skyward` **v0.5.0** |
| 叠加 | diting 分支的 WLAN 预热、已保存网络自动连接、接口等待 45 s（见 `patches/`） |
| 实测系统 | `OS4.0.0.44.XPBCNXM`（zeus，A/B，slot a） |
| WLAN | 已修掉 `cnss2` 等 modem DMS 应答的 11 秒，开机约 15 秒可上网（见 `docs/WLAN-DMS修复.md`） |

## 目录

```
devices/zeus.toml     设备配置
patches/              相对上游 v0.5.0 的补丁（只有一个文件）
scripts/setup.sh      拉 v0.5.0、打补丁、放配置
scripts/pack-zeus.sh  把编译产物打成 100 MiB recovery 镜像
scripts/release-zeus.sh 编 + 打包 + 压 zip + 发布
docs/                 刷入说明、运行逻辑、WLAN DMS 修复
```

## 构建

```bash
./scripts/setup.sh                 # 默认 kirklin v0.5.0
cd upstream
export PATH="$HOME/.cargo/bin:$PATH" ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-/opt/android-ndk-r28c}
cargo ndk -t arm64-v8a --platform 30 build --release -p skyward
RUSTFLAGS="-C target-feature=+crt-static" cargo ndk -t arm64-v8a --platform 30 \
    build --release -p skyward-system-init --target-dir target/system-init
cargo build --release -p skyward-pack
cd ..
./scripts/release-zeus.sh v0.5.0 OS4.0.0.44.XPBCNXM
```

## 刷入

release 里有两个镜像，**先备份再刷**：

| 文件 | 刷到 | 说明 |
| --- | --- | --- |
| `skyward-v0.5.0-zeus.img` | `recovery_a` | 100 MiB 整块，不碰系统/数据 |
| `vendor_boot-v0.5.0-zeus-OS4.0.0.44.XPBCNXM.img` | `vendor_boot_a` | 修 WLAN 11 秒等待；**只有同系统版本才能用** |

```powershell
adb reboot bootloader
fastboot flash recovery_a "skyward-v0.5.0-zeus.img"
fastboot flash vendor_boot_a "vendor_boot-v0.5.0-zeus-OS4.0.0.44.XPBCNXM.img"
fastboot set_active a
fastboot reboot
# 等约 35 秒系统起来后：
adb reboot recovery
```

也可以全程在 recovery 里用 `dd` 写回（root 直连），见 `docs/WLAN-DMS修复.md`。

### 只想要 recovery（不刷 vendor_boot）

WiFi 能用，但仍是原厂 `cnss2`：开机约 28 秒才联网，比刷了 vendor_boot 慢 11 秒。

## 已知行为

- WLAN 页初始为“关”：芯片后台预热，约 15 秒完成；点开开关 1~2 秒出列表。
- 触摸固件 `st_fts_l2.ftb` 未打包：驱动自动更新会失败两次，触摸本身正常。
- `aw8697_rtp_1.bin` 未打包：只影响 RTP 音效，点击震动正常。
- 界面语言跟随系统（15 种）。

## 回滚

```powershell
fastboot flash recovery_a "官方recovery.img"
fastboot flash vendor_boot_a "原厂vendor_boot.img"
```

升级系统（OTA）会重写 `vendor_boot_a`，届时重刷一次 vendor_boot 补丁即可。

## 许可

上游 GPL-3.0，本移植同样按 GPL-3.0 发布，见 `LICENSE`。
