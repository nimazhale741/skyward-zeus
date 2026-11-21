# Skyward for Xiaomi 12 Pro (zeus)

小米 12 Pro（`zeus` / 2201122C / SM8450 / `taro`）的 [Skyward](https://github.com/MartyrsBlog/skyward)
移植。上游是 kirklin 用 Rust 写的仿小米设置风格 Recovery；本仓库只放**这一个机型**需要的
设备配置、代码补丁和构建脚本，上游发新版时按补丁 rebase 即可。

基底：官方 `OS3.0.3.0.VLBCNXM` 的 recovery 分区镜像（100 MiB 整块，末 64 B 是 AVB footer）。
已在 `OS4.0.0.44.XPBCNXM` 的 zeus 上实测通过。

## 目录

```
devices/zeus.toml     设备配置：震动、WLAN 预热、模块加载、触摸、分区
patches/              相对上游 v0.3.1 的 5 个补丁
scripts/setup.sh      clone 上游 v0.3.1 + 打补丁，产出可编译的工作树
scripts/pack-zeus.sh  把编译产物打成 100 MiB 可刷镜像
scripts/release-zeus.sh  一键：编译 → 打包 → 按更新源命名压 zip → 可选 gh 发布
docs/刷入简易说明.md   手机上照着刷的一页说明
```

## 四段补丁在改什么

| 补丁 | 内容 |
|---|---|
| `crates_skyward_src_wlan.rs.patch` | `INTERFACE_WAIT` 20 s → 45 s（cnss2 等 DMS 11 s + 首启校准 6 s）；新增 `pub fn prewarm()` |
| `crates_skyward_src_main.rs.patch` | 模块加载完成后起独立线程，按 `[wlan] prewarm` 提前把 Wi-Fi 芯片带起来 |
| `crates_skyward_src_ui.rs.patch` | WLAN 页面初始为“关”，点开关才起 supplicant（行为回到上游原样，只改注释） |
| `crates_skyward-config_src_lib.rs.patch` | `[wlan]` 增加 `#[serde(default)] pub prewarm: bool` |
| `crates_skyward-net_src_github.rs.patch` | `LATEST` 指向 `nimazhale741/skyward-zeus` 的 releases（应用内更新源） |

## 构建

依赖：`rustc 1.100+`、`cargo-ndk 4.1.2+`、NDK r28c（`ANDROID_NDK_HOME` 指向它）。

```bash
./scripts/setup.sh                 # 拉上游 v0.3.1 到 ./upstream，打 5 个补丁，拷 device.toml
cd upstream
export PATH="$HOME/.cargo/bin:$PATH" ANDROID_NDK_HOME=/opt/android-ndk-r28c

cargo ndk -t arm64-v8a --platform 30 build --release -p skyward
RUSTFLAGS="-C target-feature=+crt-static" cargo ndk -t arm64-v8a --platform 30 \
    build --release -p skyward-system-init --target-dir target/system-init
cargo build --release -p skyward-pack
```

## 打包

需要把官方 `recovery.img`（100 MiB 整块）放到仓库根目录的上层，命名为 `stock-recovery.img`
（或用 `STOCK=/path/to/recovery.img` 指定），另外需要马达固件 `aw8697_haptic.bin`
（3537 B，md5 `9c2b0ebd8f5027fb1cc841f7a3963a85`，取自本机 `/vendor/firmware/`）：

```bash
STOCK=../stock-recovery.img FIRMWARE=../aw8697_haptic.bin \
    ./scripts/pack-zeus.sh out/skyward-zeus.img
```

输出恒为 `104,857,600` 字节。打包时有 27 条 `--extra` 是必须的：`companion/a31/`
里的 `servicemanager`、`hwservicemanager` 和 24 个 `.so` 塞进 `skyward/hidl/a31/`，
再加上马达固件塞进 `system/etc/firmware/`（`/etc` 在 ramdisk 指向 `/system/etc`，而
ueventd 第一个搜索站是 `/etc/firmware`，这样不会被 modem 分区挂载的 `/vendor/firmware` 遮住）。

## 一键出包

```bash
./scripts/release-zeus.sh v0.3.1 OS3.0.3.0.VLBCNXM
# 产出 skyward-v0.3.1-zeus-OS3.0.3.0.VLBCNXM.zip 并打印 SHA-256
# 装了 gh 且已 gh auth login 时，追加：--upload <owner>/<repo>
```

## 作为应用内更新源

Skyward 的「检查更新」写死读 GitHub 最新 Release，改指向本仓库需要改一行后重新编译：

```rust
// crates/skyward-net/src/github.rs:8
pub const LATEST: &str = "https://api.github.com/repos/<owner>/<repo>/releases/latest";
```

Release 资产的硬约定（不符会被判为“没有为本机适配的包”）：

- 文件名 `skyward-<tag>-zeus-*.zip`，tag 能解析成 semver（如 `v0.3.1`）
- zip 里**只能有一个**以 `.img` 结尾的条目
- 资产要有 GitHub 计算的 SHA-256（`digest` 字段）
- 镜像内 `skyward/device.toml` 的 `codename` 必须是 `zeus`

## 已知行为

- **WLAN 页初始为“关”**：驱动后台预热约 26 s 后 `wlan0` 就绪，点亮开关 1~2 s 出列表；
- 开机 26 s 内点开关，要等接口就绪，那段 20 s 是 `cnss2` 等 modem 的 DMS 应答，配置层改不掉；
- 震动固件不加载时听感“刺啦尖锐”，本移植已通过把 `aw8697_haptic.bin` 放进
  `system/etc/firmware` 修好（日志 `loaded aw8697_haptic.bin - size: 3537`）。

## 许可

上游为 GPL-3.0，本移植同样按 GPL-3.0 发布，见 `LICENSE`。字体（MiSans、KirkMono）随上游一起分发。
