# HP 800 G1 DM：OpenWrt 25.12.6 PVE 旁路网关编译方案

> 状态：待执行设计稿
> 目标主机：HP EliteDesk 800 G1 DM
> 硬件：Intel i7-4785T、16GB 内存、240GB 存储、单口 Intel i217
> 部署方式：Proxmox VE QEMU/KVM 虚拟机
> 目标系统：OpenWrt 25.12.6 x86/64 generic
> 本文生成方案，不执行源码修改、编译或 PVE 部署

## 1. 功能目标

在 PVE 中运行一台 x86/64 OpenWrt，作为旁路网关，同时提供：

- 与主网关和内部虚拟网络互通的 IPv4/IPv6 路由。
- ShadowsocksR Plus+ 客户端透明代理，连接原有的远程旧版 VMess 节点。
- VLESS 节点可选支持，但不得牺牲旧版 VMess 兼容性。
- ZeroTier 内网穿透。
- WireGuard 异地组网。
- DDNS IPv6，将明确选择的内部服务发布到公网。
- KMS 激活服务。
- 阿里云盘转 WebDAV。
- 局域网 WOL 唤醒。
- 中文 LuCI 管理和基础诊断工具。

OpenWrt 只作为 VMess 客户端。远程 VMess/VLESS 服务器仍由现有服务提供，
OpenWrt 不开放 VMess/VLESS 服务端。

## 2. 版本和兼容性决策

截至 2026-10-24，OpenWrt 最新稳定版是 **25.12.6**，其发布说明使用
Linux 6.12.112，并包含 uhttpd、rpcd、mbedTLS、OpenSSL 和 LuCI 的
安全修复。因此主方案使用 OpenWrt 25.12.6，而不是旧 LEDE 的
24.10.5 基线。

SSR Plus+ 不能简单采用当前最新 helloworld `dev`：

- 最新 SSR Plus+ 已移除 V2ray-core 选择，主要改为 Xray/Mihomo。
- 当前 Xray VMess 客户端只编码 VMess AEAD，不保留旧版非 AEAD 路径。
- 旧 VMess 支持是硬性条件，所以 SSR Plus+ 固定到仍带 V2Ray 选项、
  nftables 后端和 `alterId` 支持的提交。

推荐固定版本：

| 组件 | 固定版本/提交 | 原因 |
|---|---|---|
| OpenWrt | `v25.12.6` / `64900e756efa667774214f9c6b17c113222e01f7` | 当前最新稳定版 |
| packages feed | `openwrt-25.12` / `1846886aabcb0bf29ba5ed041ac16c84fb95ed5f` | 25.12 配套 feed |
| luci feed | `openwrt-25.12` / `75a306df84a020c57a631ef5b4c02ace56d93387` | 25.12 LuCI |
| routing feed | `openwrt-25.12` / `48c808034414a2112cf9d5261a20a320e8d0d170` | 路由/VPN 包 |
| telephony feed | `openwrt-25.12` / `2618106d5846a4a542fdf5809f0d3ed228ce439b` | 依赖闭包 |
| helloworld | `f619ed60cf23ed578bbf6ff0688e1f8a97bb4da8` | SSR Plus+ v190，保留 V2Ray + nftables + alterId |
| V2Ray Core | `5.47.0` | 已实测旧版 VMess；支持 VLESS；使用 Go 1.26 |

如果执行时 25.12 系列已有更新的补丁版本，可以升级到该系列的最新稳定版，
但只能在完成 SSR Plus+ 包编译和旧 VMess 回归测试后进行。

## 3. 旧版 VMess 必须满足的验收条件

已使用 V2Ray 5.47.0 客户端做过端到端互操作测试：

- 服务端：V2Ray 4.45.2，`alterId=64`，允许非 AEAD 旧版 VMess。
- 客户端：V2Ray 5.47.0，`alterId=64`。
- 通过客户端 SOCKS 代理请求本地 HTTP 服务，返回 `HTTP_CODE=200`。
- 服务端日志确认收到非 VMessAEAD 的旧版连接。

SSR Plus+ v190 已具备：

- VMess 订阅导入时保留 `aid`。
- LuCI 提供 `alter_id` 字段。
- 生成 V2Ray JSON 时写入 `alterId`。

最终必须用实际远程节点验证，至少核对：

- 地址和端口。
- UUID。
- `alterId`。
- `security`，例如 `auto`。
- TCP、WebSocket、HTTP/2、gRPC 或 QUIC 传输方式。
- TLS、SNI 和 WebSocket Host/Path。

仅运行 `v2ray test` 只能证明语法正确，不能证明旧节点握手、认证和传输
参数正确。真实节点测试是镜像验收门槛。

## 4. PVE 和网络拓扑

物理 i217 不直通给 OpenWrt。它由 PVE 主机管理，OpenWrt 使用 VirtIO 网卡。

```text
互联网
  |
主网关/主路由
  |
Intel i217
  |
PVE vmbr0（上游 LAN）
  |--- PVE 管理地址
  |--- OpenWrt WAN
          |
       OpenWrt
          |
PVE vmbr1（内部 LAN）
  |--- OpenWrt LAN
  |--- 其他 VM/CT
  |--- 内部服务
```

示例地址，执行时使用实际主网关网段替换：

```text
主网关：       192.168.1.1
OpenWrt WAN：  192.168.1.2/24
OpenWrt LAN：  10.10.0.1/24
PVE 管理地址： 192.168.1.10/24
WireGuard：    10.20.0.0/24
```

路由关系：

```text
主网关静态路由：10.10.0.0/24 via 192.168.1.2
主网关 VPN 回程：WireGuard/ZeroTier 网段 via 192.168.1.2
OpenWrt 默认路由：via 192.168.1.1
```

静态路由只负责让主 LAN 访问 OpenWrt 后面的网段，不会自动让主 LAN 所有
上网流量经过透明代理。主 LAN 需要透明代理时，必须让 DHCP 下发网关/DNS
为 OpenWrt，或由主网关执行策略路由。

每个二层广播域只运行一个 DHCP。`vmbr0` 继续由主网关提供 DHCP；
`vmbr1` 可交给 OpenWrt。主 LAN 和 OpenWrt 内部 LAN 不能同时争用 DHCP。

## 5. PVE 虚拟机参数

```text
Guest type:  QEMU/KVM
Machine:     q35
Firmware:    OVMF/UEFI
CPU:         4 vCPU，CPU type=host
Memory:      2048MB 起步；OpenList 大量索引时可提高到 4096MB
Disk:        VirtIO SCSI，16GB qcow2
Network 0:   VirtIO -> vmbr0（WAN）
Network 1:   VirtIO -> vmbr1（LAN）
Boot:        scsi0
```

建议生成 SquashFS + ext4 overlay 的 EFI qcow2。PVE 快照和备份比直接维护
raw img 更安全。

## 6. 软件包设计

基础配置以 `x86_64/configs/openwrt-25.12.6-pve-aio.fragment` 为种子。

### 6.1 SSR Plus+、VMess 和 VLESS

```text
CONFIG_PACKAGE_luci-app-ssr-plus=y
CONFIG_PACKAGE_luci-app-ssr-plus_Nftables_Transparent_Proxy=y
# CONFIG_PACKAGE_luci-app-ssr-plus_Iptables_Transparent_Proxy is not set
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_V2ray=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_NONE_V2RAY is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Xray is not set
CONFIG_PACKAGE_v2ray-core=y
# CONFIG_PACKAGE_v2ray-plugin is not set
```

客户端专用配置：

```text
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Server is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Rust_Server is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Server is not set
```

透明代理使用 firewall4/nftables：

```text
CONFIG_PACKAGE_firewall4=y
CONFIG_PACKAGE_nftables=y
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_dnsmasq_full_nftset=y
CONFIG_PACKAGE_kmod-nft-nat=y
CONFIG_PACKAGE_kmod-nft-socket=y
CONFIG_PACKAGE_kmod-nft-tproxy=y
```

不启用旧 iptables 透明代理后端，也不在同一固件里同时启用两套后端。
V2Ray 5.47 已含 VLESS 支持，节点可在同一 SSR Plus+ 页面中选择 VMess 或
VLESS，不需要额外核心。

### 6.2 WireGuard、ZeroTier 和路由

```text
CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_wireguard-tools=y
CONFIG_PACKAGE_luci-proto-wireguard=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_zerotier=y
CONFIG_PACKAGE_luci-app-zerotier=y
```

- WireGuard 使用路由模式，示例网段 `10.20.0.0/24`。
- ZeroTier 使用托管路由模式，宣告 `10.10.0.0/24`，不桥接广播域。
- 主网关保留 VPN 网段回程路由；OpenWrt 配置 `net.ipv4.ip_forward=1`
  和 `net.ipv6.conf.all.forwarding=1`。

### 6.3 DDNS IPv6

“DDNS6”不是独立软件包。使用：

```text
CONFIG_PACKAGE_ddns-scripts=y
CONFIG_PACKAGE_ddns-scripts-services=y
CONFIG_PACKAGE_luci-app-ddns=y
CONFIG_PACKAGE_<DDNS_PROVIDER_PACKAGE>=y
```

`<DDNS_PROVIDER_PACKAGE>` 根据实际 DNS 服务商选择，例如 Cloudflare、
DNSPod 或阿里云扩展。配置为 IPv6 AAAA 更新。

IPv6 发布服务必须满足以下之一：

- 主网关向 OpenWrt 委派 PD，OpenWrt 能获得可用的 IPv6 前缀。
- 主网关把具体服务端口转发到 OpenWrt 的稳定 IPv6 地址。
- 主网关作为反向代理终止 TLS，再转发至 OpenWrt 内部服务。

只有单个 `/128` 时，NAT66 MASQUERADE 不能自动允许公网主动入站。此场景
必须在主网关做端口转发或反向代理。

### 6.4 KMS 和 WOL

```text
CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_luci-app-wol=y
CONFIG_PACKAGE_etherwake=y
```

- KMS 使用 TCP 1688，只允许内网、WireGuard 和 ZeroTier 访问。
- WOL 从 OpenWrt 的 WAN/vmbr0 侧向主 LAN 发送定向广播。
- 睡眠设备若清除了 ARP，可配置静态 ARP 以稳定唤醒。
- WOL 只能唤醒目标所在的物理二层网络，不能直接唤醒公网设备。

### 6.5 阿里云盘 WebDAV

```text
CONFIG_PACKAGE_openlist=y
CONFIG_PACKAGE_luci-app-openlist=y
CONFIG_PACKAGE_luci-i18n-openlist-zh-cn=y
```

OpenList 同时提供 Web 管理和 WebDAV。阿里云盘令牌、WebDAV 密码和
OpenList 数据目录不得进入 Git。公网只开放 WebDAV 的 HTTPS 入口；
OpenList 管理页面限制在 LAN、WireGuard 或 ZeroTier。

## 7. 编译前目录和依赖

建议在 xps13 使用全新的独立目录：

```text
/home/chenmo/Software/openwrt/openwrt-25.12.6-x86-pve-aio
```

不要覆盖当前 `/home/chenmo/Software/openwrt/lede`，那里包含 WNDR3800、
Y1/Y1s 的构建状态和备份。

阶段预检：

1. 确认该目录不存在或为空；存在时停止，不做递归删除。
2. 确认至少有 50GB 空闲磁盘。
3. 确认 GCC、make、Python、rsync、unzip、git、qemu-img、file、
   sha256sum 等构建依赖可用。
4. 记录主机时区、CPU 核数、内存和可用磁盘。
5. 检查 OpenWrt 25.12.6 是否仍是当前最新稳定补丁版本。

## 8. 源码和 Feeds 锁定

克隆指定标签：

```sh
git clone --branch v25.12.6 --depth=1 \
  https://github.com/openwrt/openwrt.git \
  /home/chenmo/Software/openwrt/openwrt-25.12.6-x86-pve-aio
```

Feeds 使用本文第 2 节的固定 SHA。写入 feeds.conf.default 后执行：

```sh
./scripts/feeds update -a
./scripts/feeds install -a
```

必须校验：

```text
git -C feeds/helloworld rev-parse HEAD
  = f619ed60cf23ed578bbf6ff0688e1f8a97bb4da8

feeds/helloworld/luci-app-ssr-plus/Makefile
  = PKG_VERSION 190

feeds/helloworld/v2ray-core/Makefile
  = PKG_VERSION 5.47.0
```

如果 feed checkout 与固定 SHA 不一致，停止编译。

## 9. 生成 `.config`

1. 从干净 x86/64 generic 配置开始。
2. 合并 `x86_64/configs/openwrt-25.12.6-pve-aio.fragment`。
3. 选择实际 DDNS 服务商包。
4. 执行 `make defconfig`。
5. 再检查 Kconfig 是否覆盖了关键选项。

必须实际选中：

```text
TARGET_x86_64_DEVICE_generic
luci-app-ssr-plus
luci-app-ssr-plus_Nftables_Transparent_Proxy
luci-app-ssr-plus_INCLUDE_V2ray
v2ray-core
dnsmasq-full
dnsmasq_full_nftset
kmod-nft-tproxy
kmod-wireguard
zerotier
ddns-scripts
openlist
vlmcsd
luci-app-wol
```

必须未选中：

```text
luci-app-ssr-plus_INCLUDE_NONE_V2RAY
luci-app-ssr-plus_INCLUDE_Xray
luci-app-ssr-plus_Iptables_Transparent_Proxy
v2ray-plugin
所有 Shadowsocks/SSR 服务端组件
```

## 10. 分阶段构建

### 阶段 A：配置和依赖静态门禁

在完整构建前检查：

- OpenWrt 25.12.6、LuCI 25.12 和固定版 SSR Plus+ v190 的源码/FeeD 提交。
- V2Ray 5.47、nftables、WireGuard、ZeroTier、OpenList、KMS 和 WOL 的配置项。
- `alterId` 导入、编辑和生成代码确实存在。

不提前调用 `make package/<name>/compile`。包级目标可能绕过
`target/linux`，导致内核 `modules.builtin` 尚未生成时错误进入
`package/kernel/linux`。完整 `make` 会强制依赖图顺序：kernel、modules、
packages、images。

### 阶段 B：完整镜像

```sh
make download -j8
make -j4 TARGET_DEVICES=generic V=s
```

成功后检查：

```text
bin/targets/x86/64/
  *-generic-squashfs-combined-efi.qcow2
  *-generic-squashfs-combined-efi.img.gz
  *.manifest
```

当前 25.12 target 可能只输出 `*-combined-efi.img.gz`。缺少 qcow2 时，
使用 `gzip -dc` 恢复 raw img，再通过
`qemu-img convert -f raw -O qcow2 -c` 转换并执行
`qemu-img check`，不需要重新编译固件。

### 阶段 C：静态验收

- manifest 包含 `v2ray-core 5.47.0`。
- manifest 包含 `luci-app-ssr-plus`、`dnsmasq-full`、`kmod-nft-tproxy`。
- manifest 不包含 `v2ray-plugin`、Xray、Shadowsocks/SSR 服务端组件。
- rootfs 存在 `/usr/bin/v2ray`。
- SSR Plus+ 生成器包含 `alterId`。
- 使用 Python `json.loads` 验证实际生成的 V2Ray JSON。
- 记录 qcow2、img.gz 和 manifest 的大小与 SHA-256。

### 阶段 D：PVE 临时 VM

1. 创建临时 VM，使用 q35、OVMF、VirtIO SCSI。
2. 导入 qcow2，连接 `vmbr0` 和 `vmbr1`。
3. 先只从 PVE 控制台访问，不开放公网。
4. 设置 WAN、LAN、静态路由和 DNS。
5. 验证 OpenWrt → 主网关。
6. 验证主网关 → OpenWrt 内部 LAN。
7. 确认没有路由环路。

### 阶段 E：功能联调

- 旧 VMess：使用真实节点完成 HTTP/HTTPS 访问。
- VLESS：如果启用，单独验证，不能替代旧 VMess 测试。
- 透明代理：验证 TCP；启用 UDP/TProxy 时单独验证 UDP。
- nftables：检查 bridge/forward 和 `ss_spec` 规则实际存在。
- ZeroTier：验证托管路由和回程路由。
- WireGuard：验证握手、双向访问和 MTU。
- DDNS6：验证 AAAA 更新和公网入口。
- KMS：只从允许的网段连接 TCP 1688。
- OpenList：验证 WebDAV 登录、上传、下载和令牌保护。
- WOL：抓包确认目标 MAC 的 Magic Packet。
- 重启 PVE/OpenWrt 后验证配置和持久化。

## 11. 安全边界

- LuCI、SSH、KMS、OpenList 管理页不直接暴露公网。
- 公网只开放明确服务端口，优先使用 443 和反向代理。
- WireGuard/ZeroTier 私钥、DDNS API Token、Aliyun 令牌和 WebDAV 密码
  不进入 Git，不写入公开镜像。
- OpenList 数据目录和配置权限设为仅 root/服务用户可读。
- 防火墙默认拒绝公网入站。
- 不给 OpenWrt VM 做 i217 PCI 直通。
- 不使用与主网关冲突的默认路由或静态路由。

## 12. 待执行时确认的参数

以下参数会影响首次启动配置和网络联调，但不影响源码版本锁定：

1. 主网关 LAN 地址和实际内网网段。
2. 主网关是否支持静态路由、IPv6 PD、RA 和端口转发。
3. DDNS 服务商、域名和 AAAA 策略。
4. 要公开的具体服务和端口。
5. 旧 VMess 节点的脱敏参数及真实连通测试权限。
6. OpenList 是否只用于阿里云盘，还是还要挂载其他存储。
7. PVE 管理地址和计划使用的 VMID、存储池。

## 13. 交付物

- OpenWrt 25.12.6 x86/64 EFI qcow2。
- `*-generic-squashfs-combined-efi.img.gz` 救援镜像。
- package manifest。
- SHA-256 清单。
- PVE 导入参数和双网桥配置。
- VMess/VLESS、WireGuard、ZeroTier、DDNS6、KMS、OpenList、WOL
  验收结果。

## 14. 合并构建脚本

已生成可脱离 SSH、同时串行执行 x86_64、Y1 和 Y1s 的编排脚本：

```text
x86_64/scripts/merged-openwrt-build.sh
```

使用说明：

```text
x86_64/docs/merged-openwrt-build.md
```

脚本默认顺序为 `x86_64 -> y1 -> y1s`，使用共享全局锁；Y1/Y1s 通过各自
的 `run` 前台入口执行，不走嵌套 `start`。脚本生成后不会自动运行，
必须在用户明确批准后手动调用 `start`。
