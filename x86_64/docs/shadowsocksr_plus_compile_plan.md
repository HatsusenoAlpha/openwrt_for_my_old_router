# x86_64 ShadowsocksR Plus+ / VMess 编译方案

> 当前正式方案：OpenWrt 25.12.6 使用 SSR Plus+ v190、
> `v2ray-core 5.47.0`、nftables 透明代理和 Go 1.26。请以项目根目录的
> `PVE_HP800G1_OpenWrt_25.12.6_compile_plan.md` 为准。本文以下
> 5.2.0/Go 1.19 内容保留为早期 24.10 路线记录。

来源基线：2026-10-24 已通过构建和配置校验的 WNDR3800 固件。

## 目标

为后续 x86/64 OpenWrt 镜像提供已验证的 SSR Plus+ 编译方案。x86_64
不受 WNDR3800 的 14.25 MiB U-Boot 限制，因此不需要使用 WNDR3800 的
mips32 预编译包或兼容包装脚本。

最终数据路径：

```text
LAN 客户端
  -> iptables REDIRECT / TPROXY
  -> ssr-redir 或 V2Ray dokodemo-door
  -> VMess 出站
  -> 远程 VMess 节点
  -> Internet
```

## 核心结论

- `v2ray-plugin` 是 Shadowsocks SIP003 插件，不是 VMess 客户端。
- 要连接 VMess 节点必须安装真正的 `v2ray-core`。
- V2Ray 5.2.0 核心支持 `alterId > 0` 的旧版 VMess，但早期
  SSR Plus+ 配置生成器必须增加 `alterId` 传递和订阅导入修复，详见
  `docs/v2ray_vmess_legacy_compatibility.md`。
- 旧版 VMess 支持是本项目的硬性条件；在真实节点验收前不得用
  `alterId=0` 或更新版核心替代。
- SSR Plus+ 的 `dokodemo-door` 接收透明代理流量，`ssr-redir` 或
  SSR Plus 的 iptables 规则负责把 LAN 流量送入本地代理。
- WNDR3800 使用 V2Ray 4.45.2，是因为 V2Ray 5.2 的完整核心无法塞入
  其 14.25 MiB 镜像限制。
- x86_64 没有该限制，后续构建应优先使用本仓库的 V2Ray 5.2.0 源码包。

## 必须选择的配置

```text
CONFIG_PACKAGE_luci-app-ssr-plus=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_V2ray=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_NONE_V2RAY is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Xray is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_SagerNet_Core is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Trojan is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_V2ray_Plugin is not set
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Client=y
# x86_64 的 Shadowsocks Server Selection 默认是 Shadowsocks-libev；
# 客户端专用固件必须显式选择 None。
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Server is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Rust_Server is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Server is not set
CONFIG_PACKAGE_v2ray-core=y
# CONFIG_PACKAGE_v2ray-plugin is not set
```

`luci-app-ssr-plus` 会继续拉入 SSR libev、ipset、iptables TPROXY、
dnsmasq-full、microsocks、dns2socks、dns2tcp、tcping 等运行组件。

## V2Ray 5.2.0 构建

当前远端 `v2ray-core/Makefile` 已被 WNDR3800 改成 mips32 预编译版本，
不能直接用于 x86_64。构建 x86_64 前必须换成：

```text
x86_64/assets/v2ray-core-v5-source.Makefile
```

该 Makefile 使用：

```text
PKG_VERSION=5.2.0
GO_PKG=github.com/v2fly/v2ray-core/v5
```

其 `quic-go v0.31.1` 不支持仓库默认的 Go 1.26，因此构建时必须把已有的
Go 1.19 工具链放在 `TARGET_PATH_PKG` 最前面：

```text
/home/chenmo/Software/openwrt/lede/.codex-blueprint-codex-20261023/go119/go/bin
```

同时设置：

```text
GOPROXY=https://goproxy.cn,direct
GOSUMDB=sum.golang.google.cn
```

在 x86_64 配置中，`Shadowsocks Server Selection` 会默认选中
`Shadowsocks-libev`。仅关闭某个服务端选项不够可靠，必须同时选择
`INCLUDE_Shadowsocks_NONE_Server=y`，否则运行 `make defconfig` 后可能
重新启用服务端组件。客户端专用固件应关闭 Shadowsocks-libev、
Shadowsocks-rust 和 ShadowsocksR-libev 三种服务端选项。

## SSR Plus 依赖补丁

当前 `luci-app-ssr-plus/Makefile` 已移除 V2Ray 选项对 curl 的强制依赖，
与 WNDR3800 保持一致：

```text
-PACKAGE_$(PKG_NAME)_INCLUDE_V2ray:curl
```

因此 VMess 启动和透明代理不依赖 curl。SSR Plus 中少数网页连接检测功能
仍直接调用 curl，若必须保留这些检测按钮，可以另行加入：

```text
CONFIG_PACKAGE_curl=y
```

这不是 VMess 运行的必要条件。

## 建议的 SSR 专用配置片段

参见 `x86_64/configs/ssrplus-vmess.fragment`。

完整 x86 网络、存储、KVM 和 PVE 部署规划继续使用项目根目录的
`PVE_HP800G1_OpenWrt_AIO_compile_plan.md`。该文件中的旧
`v2ray-plugin` 说明应以本目录的 V2Ray Core 方案为准。

## 构建前后验收

```text
/usr/bin/v2ray                        必须存在
/usr/bin/ssr-redir 或 SSR redir       必须存在
manifest 中存在 v2ray-core
manifest 中不存在 v2ray-plugin
SSR Plus 中 INCLUDE_V2ray=y
SSR Plus 中 INCLUDE_NONE_V2RAY=n
SSR Plus 中 Shadowsocks Server Selection=None
manifest 中不存在 Shadowsocks/ShadowsocksR 服务端组件
```

启动 V2Ray 前用以下命令验证配置：

```sh
v2ray test -config /var/etc/v2-ssr-retcp.json
```

如果当前 SSR Plus 调用形式是 `v2ray run -config ...`，V2Ray 5.x 原生支持
该命令，不需要 WNDR3800 使用的 `.real` 包装脚本。

实际连接 VMess 节点时，还必须满足：

- 节点 UUID、AlterId、加密方式和传输协议与服务器一致。
- SSR Plus+ 生成的 V2Ray JSON 必须实际包含旧节点的非零 `alterId`；
  仅核心支持但生成器遗漏该字段时仍无法连接。
- WebSocket/TLS 节点的 Host、路径和 SNI 正确。
- 使用 TCP 透明代理时需要 iptables TPROXY/REDIRECT 规则。
- 使用 UDP 时需要 `kmod-ipt-tproxy` 和相应 UDP 规则。
- 不得把远程 VMess 节点配置误建成面向 WAN 的 SSR Plus 服务端。

## 相关文件

- `x86_64/assets/v2ray-core-v5-source.Makefile`
- `x86_64/assets/luci-app-ssr-plus.Makefile`
- `x86_64/configs/ssrplus-vmess.fragment`
