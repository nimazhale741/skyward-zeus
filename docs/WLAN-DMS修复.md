# WLAN 那 11 秒：cnss2 等 DMS 的问题和修法

## 现象

recovery 里 `skyward` 4.8 秒就起来了，但 WLAN 要 28 秒才可用，`dmesg` 里是 201 行：

```
cnss: DMS QMI connection not established      （200 次，每 50 ms 一条）
cnss: Unable to get MAC from DMS after retries
qca6490: using MAC address from wlan_mac.bin
```

`cnss2` 的 `cnss_setup_dms_mac()` 会向 modem 的 DMS 服务要 WLAN MAC；
recovery 里没有 modem，于是死等 `200 × 50 ms ≈ 10 s` 才回退到 `persist/wlan_mac.bin`。

## 为什么配置层/ skyward 改不了

`cnss2.ko` 不是 vendor 分区的模块，而是打包在 **vendor_boot 的 vendor ramdisk**
（`lib/modules/cnss2.ko`）里，由 first-stage init 在 **1.85 秒**加载——
比 skyward（4.8 秒）和任何 recovery 进程都早。所以“在 recovery 里 bind mount 一个改过的模块”永远晚一步。

## 修法（4 个字节）

`cnss2.ko` 的 `cnss_fw_ready_hdlr` 里，DMS 重试循环是：

```asm
8674: mov w24, #0xc8      ; 200 次
8678: ldr w8, [x19, #0x1c94]
867c: cbnz w8, #0x86a0
8680: mov x0, x19
8684: bl  cnss_qmi_get_dms_mac
8688: cmn w0, #0xb         ; -EAGAIN
868c: b.ne #0x86a0
8690: mov w0, #0x32        ; 50 ms
8694: bl  msleep
8698: subs w24, w24, #1
869c: b.ne #0x8678
```

把 `0x8674` 的 `0xc8` 改成 `0x1`（机器码 `18 19 80 52` → `38 00 80 52`），
循环只跑一次（50 ms）就放弃，然后照常回退到 `wlan_mac.bin`。

## 为什么只动 4 字节、不动镜像布局

vendor_boot 的 ramdisk 是 LZ4 legacy 压缩的 cpio。改完再用 LZ4 HC（level 12，8 MiB 块）
重新压缩，正好压回和原镜像**完全相同的字节数**（23,809,795），
所以 vendor_boot 头、DTB、vendor ramdisk table、bootconfig 全部原样保留，只替换 ramdisk 数据。

## 怎么刷

优先 fastboot：

```powershell
adb reboot bootloader
fastboot flash vendor_boot_a "vendor_boot-v0.5.0-zeus-OS4.0.0.44.XPBCNXM.img"
fastboot reboot
```

也可以在 recovery 里写回（root adb）：

```bash
adb push vendor_boot-v0.5.0-zeus-OS4.0.0.44.XPBCNXM.img /sdcard/
adb shell su -c 'dd if=/sdcard/vendor_boot-v0.5.0-zeus-OS4.0.0.44.XPBCNXM.img of=/dev/block/by-name/vendor_boot_a bs=1M && sync'
adb reboot
```

## 注意

- **版本绑定**：镜像里的模块和 DTB 只匹配 `OS4.0.0.44.XPBCNXM` 的 zeus；系统版本不同不要刷。
- **先备份**：`dd if=/dev/block/by-name/vendor_boot_a of=/sdcard/vendor_boot-backup.img bs=1M`
- 写 vendor_boot 时断电会无法开机，只能靠 fastboot 刷回备份。
- 系统 OTA 会重写 `vendor_boot_a`，升级后重新刷一次即可；recovery 镜像不用重刷。
- 系统启动也用这份模块：MAC 改为从 `persist/wlan_mac.bin` 取，实测联网正常、MAC 不变。
- 只刷 recovery、不刷 vendor_boot：WLAN 仍会等 11 秒（约 28 秒联网）。

## 按自己机器的 vendor_boot 打补丁（推荐给其他版本）

`tools/patch_vendor_boot.py` 会自己解开镜像里的 ramdisk、找到这段循环、改 4 字节，
再用 LZ4 HC 压回原长度，镜像其余部分一字不动：

```bash
pip install lz4
python tools/patch_vendor_boot.py vendor_boot.img vendor_boot-dmsfix.img
```

`vendor_boot.img` 从自己手机 dump（recovery 里 root adb）：

```bash
adb shell su -c 'dd if=/dev/block/by-name/vendor_boot_a of=/sdcard/vendor_boot.img bs=1M'
adb pull /sdcard/vendor_boot.img
```

写完的镜像刷回：

```bash
adb push vendor_boot-dmsfix.img /sdcard/
adb shell su -c 'dd if=/sdcard/vendor_boot-dmsfix.img of=/dev/block/by-name/vendor_boot_a bs=1M && sync'
adb reboot
```

脚本会打印 `patched cnss2 ... movz #200 -> #1` 并自检（重新解压、确认 4 字节生效）。
换系统版本、换机型都可能让循环偏移变化，脚本是按指令特征定位的，不依赖固定偏移；
万一找不到会直接报错，不会写坏镜像。
