# vendor_boot 补丁使用教程（修 WLAN 11 秒）

## 它解决什么

原厂 `cnss2.ko` 会向 modem 的 DMS 服务要 WLAN MAC，recovery 里没有 modem，
于是等 200×50 ms ≈ 10 秒才回退到 `persist/wlan_mac.bin`。
把重试次数改成 1 次，WiFi 从约 28 秒可用变成约 15 秒。

原理和那 4 个字节见 `WLAN-DMS修复.md`。

## 需要什么

- 一台 zeus（小米 12 Pro），已解锁 BL；
- 电脑装 Python 3 和 `lz4`：`pip install lz4`；
- recovery 里 adb 能拿到 root（本项目的 recovery 直连就是 root）。

## 第 1 步：备份（强烈建议）

recovery 里：

```bash
adb shell su -c 'dd if=/dev/block/by-name/vendor_boot_a of=/sdcard/vendor_boot-backup.img bs=1M'
adb pull /sdcard/vendor_boot-backup.img
```

## 第 2 步：dump 自己的 vendor_boot

```bash
adb shell su -c 'dd if=/dev/block/by-name/vendor_boot_a of=/sdcard/vendor_boot.img bs=1M'
adb pull /sdcard/vendor_boot.img
```

（slot b 就把 `vendor_boot_a` 换成 `vendor_boot_b`。）

## 第 3 步：打补丁

```bash
python tools/patch_vendor_boot.py vendor_boot.img vendor_boot-dmsfix.img
```

成功会打印：

```
patched cnss2 at module offset 0x1e674: movz #200 -> #1 (loop at 0x1e688)
lz4 block 8 MiB, level 12: 23809772 of 23809795 bytes
wrote vendor_boot-dmsfix.img: ramdisk 23809795 bytes, cnss2 patched at 0x1e674, 373 entries
```

脚本会自检：重新解压、比对整个 cpio、确认 4 字节生效；找不到循环会直接报错，不会写坏镜像。

## 第 4 步：刷回

fastboot：

```powershell
adb reboot bootloader
fastboot flash vendor_boot_a "vendor_boot-dmsfix.img"
fastboot reboot
```

或 recovery 里 dd：

```bash
adb push vendor_boot-dmsfix.img /sdcard/
adb shell su -c 'dd if=/sdcard/vendor_boot-dmsfix.img of=/dev/block/by-name/vendor_boot_a bs=1M && sync'
adb reboot
```

## 第 5 步：验证

重新进 recovery：

```bash
adb reboot recovery
adb shell 'dmesg | grep -E "DMS QMI|wlan_mac.bin|ahead of its switch"'
```

正常：

- `DMS QMI connection not established` 只有 2 行（原来 201 行）
- `t≈14.2s`：`Unable to get MAC from DMS after retries`，紧接着 `using MAC address from wlan_mac.bin`
- `t≈14.8s`：`skyward: the WLAN's chip is up ahead of its switch`

## 回滚

```powershell
fastboot flash vendor_boot_a "vendor_boot-backup.img"
```

## 常见问题

| 现象 | 原因/处理 |
| --- | --- |
| `not a vendor_boot image` | dump 错了分区（不是 vendor_boot） |
| `the ramdisk carries no lib/modules/cnss2.ko` | 版本不对/不是 zeus |
| `could not find the DMS retry loop` | 编译优化变了；把镜像和 `dmesg` 发 issue，不要硬刷 |
| `could not compress ... into N bytes` | 换个 LZ4 版本或提 issue；说明压缩没压回原大小，脚本不会写坏 |
| `needs the lz4 package` | `pip install lz4` |
| 刷完 WiFi 起不来 | 先刷回备份；确认不是跨版本镜像 |

## 注意

- **只刷 `vendor_boot_a`/`vendor_boot_b`**，不要刷 boot、不要刷 recovery；
- 镜像里的模块和 DTB 跟系统版本绑定，**不要拿别人的 vendor_boot 直接刷**；
- 系统 OTA 会重写 vendor_boot，升级后重新打一次即可；recovery 镜像不用重刷；
- 系统侧也会用这份模块：MAC 改为从 `persist/wlan_mac.bin` 取，实测联网正常、MAC 不变。
