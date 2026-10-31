# PVE HP 800 G1 DM OpenWrt AIO 旁路网关编译方案

> 更新：正式编译请使用
> `PVE_HP800G1_OpenWrt_25.12.6_compile_plan.md`。本文件保留为早期
> 24.10.5/V2Ray 5.2.0 设计记录。

> 状态：设计评审稿，尚未执行
> 目标宿主机：HP EliteDesk 800 G1 DM
> CPU：Intel i7-4785T
> 内存：16GB
> 存储：240GB
> 物理网卡：单口 Intel i217，千兆
> 目标平台：Proxmox VE 虚拟机，OpenWrt x86/64

## 1. 需求拆解

需要构建一个运行在 PVE 中的 OpenWrt AIO 旁路网关：

1. 可作为旁路网关，与主网关通过静态路由互相指向。
2. ZeroTier 内网穿透。
3. WireGuard 异地组网。
4. 通过 DDNS IPv6 暴露指定的内网服务。
5. KMS 激活服务。
6. ShadowsocksR Plus+ 客户端透明代理。
7. 将本地流量转发到原有的远程 VMess 节点。
8. 将阿里云盘转换为 WebDAV 服务。
9. WOL 局域网唤醒。
10. 保留 LuCI 中文管理界面和便于维护的诊断工具。

### 1.1 代理运行边界

本项目的 OpenWrt 是 VMess 客户端，不是 VMess 服务端：

```text
内部客户端
    -> OpenWrt SSR Plus+ / V2Ray 客户端
    -> 加密的 VMess 出站连接
    -> 远程 VMess 节点
    -> 互联网
```

- 远程 VMess 节点由原有服务提供，不在 PVE 或 OpenWrt 内搭建。
- OpenWrt 只维护远程节点的出站配置，并接收来自透明代理规则的本地流量。
- 不启用 SSR Plus+ 的服务器模式，不创建公开的 VMess 入站监听端口。
- V2Ray 二进制本身同时具备入站和出站能力，但本项目生成的配置只允许本地透明代理入站和远程 VMess 出站。
- 防火墙不得向主 LAN 或公网开放 VMess 服务端口；“远程节点”的地址和端口只作为客户端目标使用。

## 2. SSR Plus+ / VMess 实现路线

本 x86 方案直接采用工作区已验证的
`x86_64/docs/shadowsocksr_plus_compile_plan.md`，不复用 WNDR3800
受体积限制的 `v2ray-plugin` 封装方案。`v2ray-plugin` 是 Shadowsocks
的 SIP003 插件，不能运行远程 VMess 节点。

远程 VMess 节点由外部服务器提供；OpenWrt 仅作为客户端，维护本地透明
代理入站和远程 VMess 出站。x86 使用源码构建的 `v2ray-core 5.2.0`，
不使用当前远端包目录中的 mips32 预编译核心，也不使用 WNDR3800 的
`.real` 包装脚本。

必须选择的配置：

```text
CONFIG_PACKAGE_luci-app-ssr-plus=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_V2ray=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_NONE_V2RAY is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Xray is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_SagerNet_Core is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Trojan is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_V2ray_Plugin is not set
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Client=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Server is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Rust_Server is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Server is not set
CONFIG_PACKAGE_v2ray-core=y
# CONFIG_PACKAGE_v2ray-plugin is not set
```

x86_64 的 SSR Plus+ 服务端选择默认是 `Shadowsocks-libev`。因此必须
显式选择 `INCLUDE_Shadowsocks_NONE_Server=y`，不能只删除某个服务端
选项；否则 `make defconfig` 可能重新选中服务端组件。

同时使用 `x86_64/assets/luci-app-ssr-plus.Makefile`，保留已经验证的
“V2Ray 客户端不依赖 curl”修改。SSR Plus 中少量网页连通性检测按钮仍会
直接调用 curl，但它们不是 VMess 运行和透明代理的必要条件。

运行配置采用客户端模式：

- 将远程 VMess 节点作为 **出站服务器（outbound）** 添加。
- 只启用客户端透明代理，不启用 SSR Plus+ 的服务器模式。
- 节点参数由远程提供商给出，包括地址、端口、UUID、`alterId`、加密方式，
  以及 TCP/WS/gRPC、TLS/SNI 等传输设置。
- 本地监听只用于 TPROXY、DNS 或回环代理，必须受防火墙和内网访问范围限制。
- 验收时检查不存在面向 WAN 或主 LAN 开放的 VMess 服务端监听端口。

### 2.1 V2Ray 源码包与工具链

执行阶段应将以下源码 Makefile 安装到独立 x86 构建树的对应包目录：

```text
x86_64/assets/v2ray-core-v5-source.Makefile
  -> package/.../v2ray-core/Makefile

x86_64/assets/luci-app-ssr-plus.Makefile
  -> package/.../luci-app-ssr-plus/Makefile
```

目标包路径以隔离构建树中的实际 Feed 路径为准，执行前先确认目标文件，
不能覆盖当前 WNDR3800 工作目录中的 mips32 Makefile。

源码版核心参数：

```text
PKG_VERSION=5.2.0
GO_PKG=github.com/v2fly/v2ray-core/v5
```

该版本的 `quic-go v0.31.1` 与仓库默认 Go 1.26 不兼容。构建
`v2ray-core` 时必须把现有 Go 1.19 的 `bin` 目录放到
`TARGET_PATH_PKG` 最前面：

```text
/home/chenmo/Software/openwrt/lede/.codex-blueprint-codex-20261023/go119/go/bin
```

并在该构建环境中设置：

```text
GOPROXY=https://goproxy.cn,direct
GOSUMDB=sum.golang.google.cn
```

以上路径来自已验证实现路线。阶段 1 必须先确认工具链仍存在且版本为
Go 1.19；如果隔离构建环境无法访问该路径，应复制或重新准备同版本工具链，
不能回退到仓库默认 Go 版本。

### 2.2 旧版 VMess 硬性兼容条件

用户要求连接 2018 年前后配置的远程 VMess 节点，因此不能只验证
“配置能够解析”。必须同时验证旧版非 AEAD VMess 数据路径。

源码和实际互操作测试已经确认：

- `v2ray-core 5.2.0` 在 `alterId > 0` 时使用旧版 VMess MD5 兼容路径。
- 在 `alterId=0` 时使用 VMess AEAD。
- 使用 5.2.0 客户端连接接受非 AEAD VMess、`alterId=64` 的
  V2Ray 4.45.2 服务端，实际 HTTP 请求返回 200。

但当前 `luci-app-ssr-plus` 版本存在两个集成缺口：

- `subscribe.lua` 没有保存 VMess `aid`，并会在 `aid > 0` 时清空
  远程服务器地址，导致旧节点不能正常导入。
- `gen_config.lua` 没有向 V2Ray JSON 写入 `alterId`，核心会按
  `alterId=0` 使用 AEAD，因而不能连接旧服务端。

因此本方案把 SSR Plus+ 兼容补丁列为必选构建步骤：

```text
订阅解析：
  result.alter_id = tonumber(info.aid) or 0
  不得因为 aid > 0 清空 result.server

VMess 配置生成：
  alterId = tonumber(server.alter_id or server.aid) or 0
  VLESS 节点不写入 alterId

LuCI：
  增加 alter_id 数值字段，默认 0，仅用于 VMess
```

详细依据和实测记录见
`x86_64/docs/v2ray_vmess_legacy_compatibility.md`。补丁必须进入最终
rootfs，而不能只修改源码树或方案文档。

最终验收必须用脱敏后的实际旧节点执行真实 SOCKS/透明代理访问。仅通过
`v2ray test` 只能说明配置语法有效，不能证明节点参数和旧协议握手正确。

### 2.3 VLESS 可选能力

V2Ray 5.2.0 已支持 VLESS，当前 SSR Plus+ LuCI 也包含 VLESS 节点类型。
因此增加 VLESS 不需要升级核心。

旧 VMess 支持优先于 VLESS。建议继续固定：

```text
v2ray-core 5.2.0
```

如果未来需要使用新版核心，必须在升级后重新执行旧版 VMess
`alterId > 0` 互操作测试。检查时 V2Fly 最新版为 5.53.0，源码仍保留
旧 VMess 客户端分支，但它不是当前已验证的构建基线。

## 3. 推荐网络拓扑

建议采用“双虚拟网桥”结构，而不是把物理 i217 直通给 OpenWrt。

```text
互联网/主路由器
        |
  Intel i217
        |
    PVE vmbr0（上游 LAN）
        |
  OpenWrt WAN vNIC
        |
  OpenWrt（路由/防火墙/代理）
        |
    PVE vmbr1（内部虚拟 LAN）
        |
  +------+------+------+
  |      |      |      |
PVE服务  其他VM  CT   OpenWrt LAN服务
```

推荐参数示例：

```text
主网关：       192.168.1.1
OpenWrt WAN：  192.168.1.2/24，默认路由指向 192.168.1.1
OpenWrt LAN：  10.10.0.1/24
PVE 管理地址： 192.168.1.10/24（vmbr0）
内部局域网：   10.10.0.0/24（vmbr1）
```

### 3.1 主网关和旁路网关“IP 互指”

主网关需要增加：

```text
10.10.0.0/24       -> 192.168.1.2
WireGuard 网段     -> 192.168.1.2
ZeroTier 管理网段  -> 192.168.1.2（仅在需要由主 LAN 主动访问时）
```

OpenWrt 需要：

```text
默认路由 -> 192.168.1.1
192.168.1.0/24 为 WAN 直连网络
```

这样：

- PVE 内部 VM/CT 可以通过 OpenWrt 访问外网和 VPN。
- 主 LAN 可以通过主网关静态路由访问 OpenWrt 后面的内部 LAN。
- 不需要在主网关和 OpenWrt 之间做相互 NAT。
- 远程 ZeroTier/WireGuard 节点可以路由到 `10.10.0.0/24` 和 `192.168.1.0/24`。

如果主网关不支持静态路由，则无法实现严格意义上的“双向互指”。备选方案只能是：

- 将需要代理的设备默认网关直接设为 `192.168.1.2`；或
- 将主 LAN 整体交给 OpenWrt 路由。

### 3.2 DHCP 和 DNS

整个二层网络只能有一个 DHCP 服务：

- 主 LAN：建议保留主网关 DHCP，只把需要透明代理的客户端的网关/DNS 改为 OpenWrt。
- PVE 内部 `vmbr1`：由 OpenWrt 提供 DHCPv4、RA/DHCPv6 和 DNS。
- 若主网关 DHCP 支持下发 option 3/6，可把主 LAN 的网关和 DNS 指向 OpenWrt。
- 不要在主 LAN 和 OpenWrt 内部 LAN 上同时启动两个 DHCP。

## 4. PVE 虚拟机设计

建议：

```text
Guest type:  QEMU/KVM
Machine:     q35
Firmware:    OVMF/UEFI
vCPU:        2–4
Memory:      2048MB（最低 1024MB）
System disk: 8–16GB
Disk bus:    VirtIO SCSI
Network 0:   VirtIO，接 vmbr0（WAN）
Network 1:   VirtIO，接 vmbr1（内部 LAN）
```

i217 由 PVE 主机通过 `vmbr0` 管理。OpenWrt VM 内看到的是 VirtIO 网卡，而不是物理 i217。
不建议把 i217 PCI Passthrough 给 OpenWrt，否则 PVE 管理、其他 VM 和容器可能失去主网络连接。

## 5. 编译目标与产物

目标：

```text
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y
```

建议生成：

```text
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_ROOTFS_PARTSIZE=4096
CONFIG_GRUB_EFI_IMAGES=y
CONFIG_QCOW2_IMAGES=y
CONFIG_TARGET_IMAGES_GZIP=y
```

首选产物：

```text
bin/targets/x86/64/openwrt-x86-64-generic-squashfs-combined-efi.qcow2
```

PVE 导入流程（执行阶段再做）：

```bash
qm importdisk <VMID> openwrt-x86-64-generic-squashfs-combined-efi.qcow2 <存储>
qm set <VMID> --scsihw virtio-scsi-pci --scsi0 <存储>:vm-<VMID>-disk-0
qm set <VMID> --efidisk0 <存储>:1,efitype=4m,pre-enrolled-keys=0
qm set <VMID> --boot order=scsi0
```

同时保留一份 `combined-efi.img.gz` 作为 PVE/救援环境备用镜像。

## 6. 软件包选择

### 6.1 基础路由与透明代理

```text
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_dnsmasq_full_dhcp=y
CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y
CONFIG_PACKAGE_dnsmasq_full_ipset=y
CONFIG_PACKAGE_firewall=y
CONFIG_PACKAGE_iptables=y
CONFIG_PACKAGE_ip6tables=y
CONFIG_PACKAGE_ipset=y
CONFIG_PACKAGE_iptables-mod-tproxy=y
CONFIG_PACKAGE_kmod-ipt-tproxy=y
CONFIG_PACKAGE_kmod-ipt-nat=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_kmod-ipt-nat6=y
CONFIG_PACKAGE_ip-full=y
# CONFIG_PACKAGE_curl is not set
```

### 6.2 SSR Plus+ / VMess

以 `x86_64/configs/ssrplus-vmess.fragment` 为唯一 SSR Plus+ 配置片段，
合并进干净 x86 `.config` 后运行 `make defconfig`。核心配置为：

```text
CONFIG_PACKAGE_luci-app-ssr-plus=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_V2ray=y
CONFIG_PACKAGE_v2ray-core=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_NONE_V2RAY is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Xray is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_SagerNet_Core is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Trojan is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_V2ray_Plugin is not set
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Client=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Server is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Rust_Server is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Server is not set
# CONFIG_PACKAGE_v2ray-plugin is not set
```

VMess 通过 `v2ray-core` 运行；SSR libev 客户端用于 SSR Plus+ 的其他
客户端能力。x86 不需要 `v2ray-plugin`，也不使用 mips32 预编译核心。
Go 1.19 和指定代理设置见第 2.1 节。

### 6.3 WireGuard

```text
CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_wireguard-tools=y
CONFIG_PACKAGE_luci-proto-wireguard=y
```

建议使用路由模式：

```text
WireGuard LAN: 10.20.0.0/24
Listen port:   UDP 51820
```

主 LAN 若需要主动访问 WireGuard 对端，在主网关添加相应静态路由，
下一跳为 `192.168.1.2`。

### 6.4 ZeroTier

```text
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_zerotier=y
CONFIG_PACKAGE_luci-app-zerotier=y
CONFIG_PACKAGE_luci-i18n-zerotier-zh-cn=y
```

建议使用 ZeroTier 托管路由，而不是二层桥接：

- 在 ZeroTier Central 宣告 `10.10.0.0/24`。
- 通过 OpenWrt 的 ZeroTier 接口路由到内部 LAN。
- 避免把 LAN 与 ZeroTier 直接桥接，减少广播和环路风险。

### 6.5 DDNS IPv6

源码中没有一个名为 `ddns6` 的包；没有发现独立包名。
应使用支持 IPv6 的 `ddns-scripts`，再选择实际 DNS 服务商扩展：

```text
CONFIG_PACKAGE_ddns-scripts=y
CONFIG_PACKAGE_ddns-scripts-services=y
CONFIG_PACKAGE_luci-app-ddns=y
CONFIG_PACKAGE_luci-i18n-ddns-zh-cn=y
CONFIG_PACKAGE_ddns-scripts-<provider>=y
```

`<provider>` 可能是 Cloudflare、DNSPod、阿里云等，需根据实际域名服务选择。

IPv6 入站是否需要 NAT66 取决于上游：

- 主网关能向下游委派 IPv6 前缀（PD）：最佳，OpenWrt 内部服务使用全局 IPv6 地址，DDNS6 更新 AAAA。
- 只有单个 /128 地址：必须由主网关做 IPv6 端口转发，或在主网关做反向代理。
- 单纯 NAT66 MASQUERADE 只能支持出口访问，不能自动让公网主动访问内部服务。

### 6.6 阿里云盘 WebDAV

源码同时提供：

- `go-aliyundrive-webdav`：直接的阿里云盘 WebDAV 服务。
- `openlist` + `luci-app-openlist`：支持阿里云盘和多种存储，也内置 WebDAV。

推荐使用 OpenList，因为源码中同时存在维护中的 LuCI 管理和中文翻译：

```text
CONFIG_PACKAGE_openlist=y
CONFIG_PACKAGE_luci-app-openlist=y
CONFIG_PACKAGE_luci-i18n-openlist-zh-cn=y
```

如果只需要最小化阿里云盘 WebDAV，可以作为替代方案：

```text
CONFIG_PACKAGE_go-aliyundrive-webdav=y
```

阿里云盘令牌和 WebDAV 密码不能写入 Git。服务目录权限应设为 `0600`，
对外只开放 HTTPS，并强制认证。

### 6.7 KMS 与 WOL

```text
CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y
CONFIG_PACKAGE_luci-app-wol=y
CONFIG_PACKAGE_luci-i18n-wol-zh-cn=y
CONFIG_PACKAGE_etherwake=y
```

KMS 默认监听 TCP 1688。应只允许内网、ZeroTier 或 WireGuard 访问，
不要直接暴露到公网。

WOL 需要知道目标设备 MAC，并在目标所在的二层网络发送广播；跨网段时应使用
Directed Broadcast 或固定 ARP 方案。

### 6.8 中文 LuCI 和诊断

建议保留：

```text
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-app-firewall=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y
CONFIG_PACKAGE_luci-proto-ipv6=y
CONFIG_PACKAGE_odhcp6c=y
CONFIG_PACKAGE_odhcpd-ipv6only=y
CONFIG_PACKAGE_tcpdump-mini=y
# CONFIG_PACKAGE_curl is not set
```

`curl` 默认不安装；如果实际 DDNS 服务商脚本或网页连通性检测按钮将其
作为硬依赖，由依赖解析或显式配置重新加入，但它不属于 VMess 运行链路。

## 7. 透明代理工作方式

OpenWrt 作为旁路网关时：

1. 客户端网关和 DNS 指向 OpenWrt。
2. SSR Plus+ 通过 dnsmasq-full/ipset 进行域名分类。
3. iptables 的 `REDIRECT` / `TPROXY` 规则将命中流量送入本地代理。
4. VMess 流量由 V2Ray 的本地 `dokodemo-door` 接收，再由 VMess
   outbound 发往远程节点；SSR 类型流量可由 `ssr-redir` 处理。
5. V2Ray 只与远程 VMess 节点建立出站连接，不开放公网 VMess 服务端。
6. 未命中规则的流量正常转发到主网关。
7. 内部 VM/CT 通过 `10.10.0.1` 使用代理。
8. 主 LAN 客户端可选择使用 OpenWrt 网关，或由主网关策略路由部分网段。

典型数据路径：

```text
LAN 客户端
  -> iptables REDIRECT / TPROXY
  -> ssr-redir 或 V2Ray dokodemo-door
  -> VMess 出站
  -> 远程 VMess 节点
  -> Internet
```

TCP 透明代理依赖 iptables 与 TPROXY/REDIRECT 规则；UDP 代理还需要
`kmod-ipt-tproxy` 和正确的 UDP 策略。V2Ray 5.x 使用原生
`v2ray run -config ...`，不需要 WNDR3800 的 `.real` 包装脚本。
运行前应使用 `v2ray test -config ...` 验证 SSR Plus+ 实际生成的配置。

必须避免的环路：

- 主网关默认路由不能指向旁路网关后又通过同一个默认路由返回。
- OpenWrt 默认路由必须是主网关 `192.168.1.1`。
- 静态路由只针对 VPN 网段或明确的内部网段，不应形成默认路由环。

## 8. 安全设计

- LuCI、SSH、KMS、WebDAV 管理端不直接暴露公网。
- DDNS6 只开放明确的服务端口。
- 对外 HTTP 服务建议经 Nginx/Caddy 反向代理，并启用 TLS。
- WireGuard/ZeroTier 隧道优先于直接公网管理。
- 禁止把 `/etc/openlist`、阿里云 token、WireGuard 私钥、DDNS API token 提交到 Git。
- 防火墙默认拒绝公网入站，只放行已确认的 IPv6 服务端口。
- 限制 OpenList WebDAV 上传大小、并发数和可访问路径。

## 9. 构建实施阶段（待批准后执行）

### 阶段 0：参数确认

执行前必须确定：

- 主网关型号和 LAN 地址。
- 主网关是否支持静态路由、IPv6 PD 和 DHCP option 3/6。
- DDNS 服务商、域名和 IPv6 模式。
- 阿里云盘 WebDAV 采用 OpenList 还是 `go-aliyundrive-webdav`。
- 对外暴露的具体服务和端口。
- 旧 VMess 订阅/节点的脱敏样例，必须包含 `alterId`、加密方式和传输协议。
- 一个可实际连通旧节点的最小测试凭据，或由用户在隔离网络完成最终节点测试。

### 阶段 1：隔离源码与配置

- 在新目录构建 x86，不覆盖现有 WNDR3800/Y1/Y1S 配置。
- 锁定 LEDE 和 Feeds 提交。
- 复用下载缓存。
- 复制 `x86_64/configs/ssrplus-vmess.fragment` 到 x86 工作目录。
- 用 `x86_64/assets/v2ray-core-v5-source.Makefile` 替换 x86 构建树中
  对应的 `v2ray-core/Makefile`，替换前确认目标路径只属于 x86 构建。
- 用 `x86_64/assets/luci-app-ssr-plus.Makefile` 同步已验证的 SSR Plus+
  依赖修改，特别是去掉 V2Ray 客户端的 curl 强制依赖。
- 应用旧版 VMess 集成补丁，修改 `subscribe.lua`、`gen_config.lua` 和
  LuCI 节点配置页面，确保 `alterId` 能从导入/界面传递到 V2Ray JSON。
- 验证 Go 1.19 工具链可执行，并将它放在 `TARGET_PATH_PKG` 最前面。
- 设置 `GOPROXY=https://goproxy.cn,direct` 和
  `GOSUMDB=sum.golang.google.cn`。

### 阶段 2：生成 x86 配置

- 生成 x86/64 干净 `.config`。
- 合并 `ssrplus-vmess.fragment` 和其余功能配置。
- 运行 `make defconfig`。
- 再次检查 VMess 核心、WireGuard、ZeroTier、DDNS6、OpenList/KMS/WOL
  均被实际选中。
- 检查 SSR Plus+ 的 V2Ray 客户端选项未被 `defconfig` 改写。
- 检查 `Shadowsocks_NONE_Server=y`，三种 Shadowsocks/SSR 服务端组件均未选中。
- 检查 `v2ray-plugin`、Xray、SagerNet、Trojan 均未选中。
- 使用旧节点参数生成配置，确认 V2Ray JSON 中 `alterId` 与节点值完全一致。
- 确认订阅导入保留非零 `aid`，不再清空远程地址。

### 阶段 3：构建与验收

- `make download -j8`
- `make -j1 V=s TARGET_DEVICES=generic`
- 检查 `combined-efi.qcow2`、rootfs、manifest。
- 检查 manifest 包含 `v2ray-core`，不包含 `v2ray-plugin`。
- 检查 rootfs 存在 `/usr/bin/v2ray` 和
  `/usr/bin/ssr-redir`（或 SSR Plus 实际使用的 redir 路径）。
- 检查 x86 镜像没有混入 mips32 V2Ray 二进制或 `.real` 包装脚本。
- 使用实际生成的 `/var/etc/v2-ssr-retcp.json` 执行
  `v2ray test -config /var/etc/v2-ssr-retcp.json`。
- 使用旧节点的真实但脱敏配置执行 SOCKS 或透明代理访问测试；只有实际
  返回预期网页内容才算满足旧 VMess 硬性条件。
- 如果同时启用 VLESS，单独验证 VLESS 节点；不得用 VLESS 测试结果替代
  旧 VMess 验收。
- 检查 DDNS IPv6 脚本、WireGuard 模块、ZeroTier、OpenList、vlmcsd、WOL。
- 在 PVE 中以 OVMF + q35 启动临时 VM，验证网卡、Web 管理和串口/控制台。

### 阶段 4：网络联调

- 配置 `vmbr0` 上游和 `vmbr1` 内网。
- 验证 OpenWrt → 主网关和主网关 → OpenWrt 的双向静态路由。
- 验证 DNS、DHCP、RA 和 IPv6 PD 是否冲突。
- 验证 WireGuard/ZeroTier 路由和回程路由。
- 模拟断电后重新启动，确认服务自恢复。

## 10. 资源估算

- OpenWrt VM：2–4 vCPU、2GB RAM、8–16GB 虚拟磁盘。
- 编译阶段需要至少 30GB 空闲磁盘和多线程下载缓存。
- x86 固件不受 WNDR3800 的 16MB 限制。
- OpenList、V2Ray、WireGuard、ZeroTier 与系统日志建议保留至少 2GB 可用空间。

## 11. 不执行的事项

本方案当前不执行：

- 不修改现有 WNDR3800/Y1/Y1S `.config`。
- 不创建或启动 PVE VM。
- 不写入 DDNS、阿里云盘或 WireGuard 密钥。
- 不开放公网端口。
- 不向设备刷写固件。
