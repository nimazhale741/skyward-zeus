# Skyward for Xiaomi 12 Pro (zeus)

小米 12 Pro（`zeus` / 2201122C / SM8450 / `taro`）的 [Skyward](https://github.com/MartyrsBlog/skyward)
移植。上游是 kirklin 用 Rust 写的仿小米设置风格 Recovery；这里放这一台机器的适配文件。

基底：官方 `OS3.0.3.0.VLBCNXM` 的 recovery 分区镜像（100 MiB 整块）。
已在 `OS4.0.0.44.XPBCNXM` 的 zeus 上实测通过。

## 目录

```
devices/zeus.toml     设备配置
patches/              相对上游 v0.3.1 的改动
scripts/              构建与打包脚本
docs/                 刷入说明、运行逻辑
```

## 刷入

整块写入 `recovery_a`（A/B，无裸 `recovery` 分区）：

```bash
su -c 'dd if=/storage/emulated/0/Asia/skyward-zeus.img of=/dev/block/by-name/recovery_a bs=1M && sync'
su -c 'reboot recovery'
```

或电脑：

```powershell
adb reboot bootloader
fastboot flash recovery_a "skyward-zeus.img"
fastboot reboot        # 等约 35 秒进系统后
adb reboot recovery
```

## 已知行为

- **WLAN 页初始为“关”**：驱动后台预热约 26 s 后 `wlan0` 就绪，点亮开关 1~2 s 出列表；
- 开机 26 s 内点开关要等接口就绪，那段 20 s 是 `cnss2` 等 modem 的 DMS 应答，配置层改不掉；
- 震动固件已随镜像打包（`aw8697_haptic.bin`），日志出现 `loaded aw8697_haptic.bin - size: 3537` 即正常。

## 许可

上游为 GPL-3.0，本移植同样按 GPL-3.0 发布，见 `LICENSE`。
