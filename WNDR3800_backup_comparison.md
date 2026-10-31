# WNDR3800 原备份与当前重构固件对比

分析日期：2026-10-24

## 备份身份

- 文件：`backup/WNDR3800-fwbackup.bin`
- 大小：`16,777,216` 字节，即完整 16MiB Flash dump
- SHA-256：`e4d33998d459012ed1e564a6c0b09ebbfc73641fd9b73ec4268440f840311c91`
- 系统：OpenWrt SNAPSHOT `r1879-8840d7c`
- 目标：`ar71xx/generic`
- 内核：Linux `4.9.208`
- 运行时包数量：238

该备份不是 Netgear 原厂固件，而是旧版 OpenWrt 的整片 Flash 备份。

## 分区与镜像结构

| 区域 | 偏移 | 内容 |
|---|---:|---|
| U-Boot 及保留区 | `0x000000` | U-Boot |
| U-Boot 环境 | `0x050000` | 启动环境 |
| 内核起点 | `0x070000` | Netgear DNI + MIPS uImage |
| SquashFS | `0x1B7500` | 旧只读 rootfs |
| SquashFS 结束 | `0xBC97B2` | 大小 10,560,370 字节，之后补齐到 64KiB |
| JFFS2 overlay | `0xBD0000–0xE40000` | 可写配置和后来安装的软件 |
| U-Boot 固件上限 | `0xE40000` | 14.25MiB |
| 未使用间隙 | `0xE40000–0xFF0000` | 不属于 U-Boot 允许刷入的镜像 |
| ART | `0xFF0000` | 射频校准数据 |

这解释了 U-Boot 的 14.25MiB 上限。当前 WNDR3800 sysupgrade 为
15,139,630 字节，超过 14.25MiB 门限 197,422 字节。

## 旧备份具有的功能

- OpenWrt LuCI 中文界面及 Netgear 主题
- SSR Plus+，含旧版 V2Ray、Trojan、Shadowsocks libev/SSR 组件
- UPnP IGD
- DDNS
- Adbyby Plus 广告过滤
- Guest Wi-Fi
- SQM QoS 与 CAKE
- SFE FastPath
- nlbwmon 流量统计
- TTYD 网页终端
- WebAdmin
- RamFree
- KMS（vlmcsd）
- WOL
- IPv6 协议支持
- PPPoE
- USB 存储、Ext4/FAT/exFAT/NTFS、自动挂载

## 旧备份中的打印功能核验

旧备份没有以下包或文件：

- `p910nd`
- `kmod-usb-printer`
- `luci-app-p910nd`
- `luci-app-usb-printer`
- `usblp.ko`
- `sihp1020.dl`
- HP 1020 USB 上电推送脚本

因此，旧备份本身不包含 HP LaserJet 1020 网络打印链路。该功能不能在重构时从备份中“恢复”，只能继续从当前工程保留。

## 当前重构固件必须保留的打印链路

- `/usr/sbin/p910nd`
- `/etc/init.d/p910nd`
- `/etc/config/p910nd`
- `/etc/hotplug.d/usbmisc/20-p910nd`
- `/lib/modules/6.6.144/usblp.ko`
- `/usr/lib/sihp1020.dl`
- `/etc/hotplug.d/usb/10-printer`
- `luci-app-p910nd`（英文界面）
- `luci-app-usb-printer`（英文界面）
- `kmod-usb-core`、`kmod-usb2`、`kmod-usb-ohci`、`kmod-usb-ehci`

HP `sihp1020.dl` 的 SHA-256：

```text
c14fdf0af84d1df40545eef7c7d4e2e07dd58fe933e14cc7c29697209e87cd01
```

## 与当前 WNDR3800 重构固件对比

| 项目 | 旧备份 | 当前重构 |
|---|---|---|
| OpenWrt | SNAPSHOT r1879 | 24.10.5 r7863-6883e66e8 |
| 目标 | ar71xx/generic | ath79/generic |
| 内核 | 4.9.208 | 6.6.144 |
| rootfs 压缩大小 | 10,560,370 B | 11,787,076 B |
| 内核区域 | 约 1.34 MiB | 2,691,479 B |
| 包数量 | 238 | 248 |
| SSR Plus+ | 有，旧 V2Ray/Trojan/libev | 有，V2Ray 4.45.2 VMess + SSR libev |
| IPv6 | 基础协议支持 | NAT6、odhcp6c、odhcpd、tproxy 完整保留 |
| KMS / WOL | 有 | 有 |
| ZeroTier | 无 | 有 |
| Turbo ACC | 等价 SFE FastPath | flow offloading |
| SQM / DDNS / Adbyby | 有 | 当前精简版未包含 |
| Guest Wi-Fi / TTYD / WebAdmin | 有 | 当前精简版未包含 |
| nlbwmon / RamFree | 有 | 当前精简版未包含 |
| USB 存储/NTFS/exFAT | 有 | 已移除，避免占用镜像体积 |
| HP 1020 网络打印 | 无 | 有，完整保留 |

## 尺寸差异来源

当前重构 rootfs 比旧备份大约 1.75MiB，主要来自：

1. Linux 6.6 内核和现代 mac80211/crypto 模块更大。
2. OpenWrt 24.10 使用 ucode、新版 LuCI 和新版 OpenSSL 3.6。
3. ZeroTier 与完整 USB 打印栈是旧备份没有的功能。
4. 现代 musl/GCC 生成的动态库体积不同。
5. 新旧固件均使用 1MiB XZ SquashFS 块，以兼顾压缩率和 WNDR3800 的 U-Boot 限值。

## 刷机门限与下一步

最新 WNDR3800 sysupgrade 镜像为 14,811,950 字节，低于 U-Boot 的 14.25MiB
门限。最终镜像使用 1MiB XZ SquashFS 块，并保留 130,258 字节余量。

裁剪时禁止移除上面的 p910nd、usblp、HP 微码、打印热插拔和 LuCI 打印相关项。
保留 `procd-ujail`、`procd-seccomp`、`dnsmasq-full` 和透明代理相关内核模块。
最终裁剪结果以 manifest 和实际镜像大小为准。

## 2026-10-24 精简构建结果

已移除：

- `openssl-util`
- `wget-ssl`
- `jq`
- `xz`
- `xz-utils`
- 全部 LuCI 简体中文翻译
- `v2ray-plugin`
- `curl`、`libcurl4`、`libnghttp2-14`
- `coremark`
- `coreutils-timeout`
- `ddns-scripts-services`
- `luci-lib-chartjs`
- `libncurses6`、`terminfo`
- `luci-app-package-manager`
- `luci-app-uhttpd`

已确认：

- `dnsmasq-full` 开启，基础 `dnsmasq` 未安装。
- `procd-ujail`、`procd-seccomp` 保留。
- p910nd、usblp、HP 1020 微码、LuCI 打印界面和热插拔脚本全部保留。
- `v2ray-core 4.45.2` 提供真正的 VMess 出站能力；SSR Plus 的
  `dokodemo-door` 与 `ssr-redir` 继续提供透明代理。
- `v2ray-plugin` 已删除；它不是 VMess 客户端，不能替代 V2Ray 核心。
- `v2ray run -config` 由兼容包装脚本转换为 V2Ray v4 的 `-config` 调用。
- 使用 SSR Plus 生成的 VMess + WebSocket + TLS 测试配置执行
  `v2ray -test`，结果为 `Configuration OK`。
- 镜像中不存在任何 `luci-i18n-*-zh-cn` 包，LuCI 以英文界面显示。
- 默认 LAN 为 `192.168.10.1/24`，同时写入首次启动 board 配置和
  preinit/failsafe 配置。
- 恢复 `wget-ssl`、`xz`、`xz-utils`、`jq` 和 LuCI 软件包管理页面。

实际构建退出码为 0：

| 镜像 | 大小 | SHA-256 |
|---|---:|---|
| sysupgrade | 14,811,950 B / 14.126 MiB | `ee761951f5fc61f04f278aacd8db68bae6a43c93b6b0900121f2e08dacad68b4` |
| factory | 14,811,269 B / 14.125 MiB | `85a3d39c8093495d73eaeea97fb2295560767eb4f41f3c2cc42e96460635a2c6` |

相对 14.25MiB 的 `0xE40000 = 14,942,208` 字节门限，
sysupgrade 尚余 130,258 字节，factory 尚余 130,939 字节。
