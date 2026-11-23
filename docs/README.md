# 文档清单（永久保留）

这些文档是发布的一部分，**任何版本都不要删除、不要替换**；README、release 说明和
`scripts/check-docs.sh` 都指向这里。

| 文件 | 内容 | 什么时候看 |
| --- | --- | --- |
| [文件说明.md](文件说明.md) | 每个 release 资产和仓库文件是干什么的、刷哪个分区、风险 | 第一次下载时 |
| [源码补丁教程.md](源码补丁教程.md) | `patches/0001-diting-0.5.0.patch` 怎么用、怎么编译、常见错误 | 想自己编译时 |
| [vendor_boot补丁教程.md](vendor_boot补丁教程.md) | 给自己机器的 vendor_boot 打 cnss2 补丁、刷回、验证、回滚 | 想修 WLAN 11 秒时 |
| [WLAN-DMS修复.md](WLAN-DMS修复.md) | 那 11 秒的原理、改了哪 4 个字节 | 想知道为什么 |
| [刷入简易说明.md](刷入简易说明.md) | 最短的刷入步骤 | 只想刷 |
| [运行逻辑.md](运行逻辑.md) | recovery 启动和页面的运行逻辑 | 想改代码时 |

## 防丢检查

```bash
./scripts/check-docs.sh
```

GitHub Actions 每次 push 也会跑 `.github/workflows/docs.yml`，少一个文件都会失败。
