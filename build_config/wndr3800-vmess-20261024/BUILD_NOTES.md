# WNDR3800 VMess 精简构建

构建日期：2026-10-24

## 最终镜像

| 镜像 | 大小 | SHA-256 |
|---|---:|---|
| sysupgrade | 14,811,950 B | `ee761951f5fc61f04f278aacd8db68bae6a43c93b6b0900121f2e08dacad68b4` |
| factory | 14,811,269 B | `85a3d39c8093495d73eaeea97fb2295560767eb4f41f3c2cc42e96460635a2c6` |

U-Boot 上限为 `0xE40000 = 14,942,208` 字节。sysupgrade 剩余
130,258 字节，约 127.2 KiB。

## 关键配置

- OpenWrt 24.10.5，ath79/generic，Netgear WNDR3800。
- SquashFS 块大小 1 MiB，XZ 压缩。
- 使用 `luci-light`，不使用包含软件包管理页的 `luci` 元包。
- LuCI 仅保留英文，删除全部简体中文翻译。
- 默认 LAN 为 `192.168.10.1/24`，DHCP 地址池为
  `192.168.10.100-192.168.10.249`。
- `dnsmasq-full`、`procd-ujail`、`procd-seccomp` 保留。
- p910nd、usblp、HP 1020 微码、USB 打印热插拔及英文 LuCI 打印页面保留。
- 恢复 `wget-ssl`、`xz`、`xz-utils`、`jq` 和 LuCI 软件包管理页面。
- V2Ray 保持未使用 UPX 的 4.45.2 官方 mips32 二进制。
- WNDR3800 的 Realtek RTL8366S 交换机提供 WAN PHY4 和 MDIO 总线。
- 已加入 `kmod-switch-rtl8366s`，并自动包含
  `kmod-switch-rtl8366-smi`、`kmod-swconfig` 和 `kmod-libphy`。

## VMess 与透明代理

SSR Plus 使用两个不同组件：

- `shadowsocksr-libev-ssr-redir`：透明代理的 TCP 重定向入口。
- `v2ray-core`：实际的 VMess 协议客户端。

`v2ray-plugin` 是 Shadowsocks SIP003 插件，不是 VMess 客户端，因此已移除。

由于 V2Ray v5 全协议二进制无法容纳在 WNDR3800 的 U-Boot 限制内，本次使用
V2Fly 官方 v4.45.2 的 mips32 大端静态发布文件。`/usr/bin/v2ray` 是兼容
SSR Plus 调用的薄包装脚本，会把：

```text
v2ray run -config ...
```

转换为 v4 支持的：

```text
v2ray.real -config ...
```

已使用 SSR Plus 风格的 VMess + WebSocket + TLS + dokodemo-door + SOCKS
配置执行 `v2ray -test`，结果为 `Configuration OK`。

## 复现文件

- `dotconfig`：最终 `.config`。
- `luci-app-ssr-plus.Makefile`：移除了 V2Ray 选项对 curl 的强制依赖。
- `v2ray-core.Makefile`：固定 V2Ray 4.45.2 mips32 发布包及 SHA-256。
- `v2ray-wrapper`：SSR Plus v5 命令风格兼容脚本。

远端源码目录：`/home/chenmo/Software/openwrt/lede`

远端构建备份目录：`.codex-backups/20261024-vmess-trim`
