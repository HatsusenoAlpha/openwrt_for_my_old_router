# Lenovo Newifi Y1 / Y1s 编译方案

更新日期：2026-10-24

## 目标

按照最新 WNDR3800 固件的功能路线，重新构建：

- `lenovo_newifi-y1`
- `lenovo_newifi-y1s`

两台设备均属于 `ramips/mt7620`，CPU 为 MIPS32 小端，不能用 WNDR3800
使用的 mips32 大端 V2Ray 文件。两个设备的 `IMAGE_SIZE` 均为
`16064 KiB`。上一版 sysupgrade 约 13.89 MB，距离镜像上限约 2.5 MB。

## 共同功能

- OpenWrt 24.10.5，16 MiB Flash，SquashFS。
- LuCI 使用英文，不安装任何 `luci-i18n-*-zh-cn`。
- `luci-light` + LuCI 软件包管理页面。
| 设备 | 默认 LAN | preinit/failsafe | DHCP 地址池 |
|---|---|---|---|
| Y1 | `192.168.6.1/24` | `192.168.6.1` | `192.168.6.100-192.168.6.249` |
| Y1s | `192.168.4.1/24` | `192.168.4.1` | `192.168.4.100-192.168.4.249` |

- Y1 广播地址：`192.168.6.255`。
- Y1s 广播地址：`192.168.4.255`。
- `dnsmasq-full`，不安装基础 `dnsmasq`。
- `procd-ujail`、`procd-seccomp`。
- IPv6、NAT6、flow offloading。
- Turbo ACC、UPnP、KMS、WOL、ZeroTier。
- p910nd、USB printer、HP 打印热插拔和 LuCI 打印页面。
- `wget-ssl`、`xz`、`xz-utils`、`jq`。
- 不安装 curl、libcurl、coremark、GNU timeout、DDNS 服务定义、
  ncurses/terminfo 和 UHTTPD 设置页。

## SSR Plus+ / VMess

旧 Y1 配置启用了 `v2ray-plugin`，但没有 V2Ray Core，因此不能连接 VMess。
本方案改为：

```text
CONFIG_PACKAGE_luci-app-ssr-plus=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_V2ray=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_NONE_V2RAY is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_V2ray_Plugin is not set
CONFIG_PACKAGE_v2ray-core=y
# CONFIG_PACKAGE_v2ray-plugin is not set
```

Y1/Y1s 使用：

```text
V2Ray 4.45.2
官方 mips32le 静态发布文件
ZIP SHA-256:
6fae6cb0293be4b64c92b738195f5af5fd2d158c63d69c170a7a6e360cca2faf
```

安装布局：

```text
/usr/bin/v2ray.real   V2Ray 4.45.2 mips32le
/usr/bin/v2ray        兼容 SSR Plus "v2ray run -config" 的脚本
```

不启用 UPX。WNDR3800 上的实测表明 UPX LZMA 虽然能减小文件，但 Go
runtime 在 QEMU 中启动失败；当前 Y1 镜像余量足够，不应引入该风险。

## 文件

- `assets/v2ray-core-mipsel.Makefile`：mips32le 的 V2Ray 包定义。
- `assets/v2ray-wrapper`：v5 命令风格兼容脚本。
- `assets/luci-app-ssr-plus.Makefile`：移除 V2Ray 对 curl 的强制依赖。
- `configs/y1.previous.config`：上一版 Y1 的完整配置基线。
- `configs/y1s.previous.config`：上一版 Y1s 的完整配置基线。
- `configs/y1.features.fragment`：Y1 功能与 `192.168.6.0/24` 网络设置。
- `configs/y1s.features.fragment`：Y1s 功能与 `192.168.4.0/24` 网络设置。

## 自动编译脚本

脚本只能通过显式 `start` 或 `run` 启动，生成脚本本身不会自动编译。

```text
y1_y1s/scripts/build-y1.sh
y1_y1s/scripts/build-y1s.sh
```

脚本行为：

1. 保存远端当前 `.config`、V2Ray Makefile 和 SSR Plus Makefile。
2. 使用共用的 `flock`，保证 Y1 和 Y1s 不会同时改写同一个构建目录。
3. 切换到对应设备的完整配置，并写入各自的 LAN、广播和 preinit 地址。
4. 替换为 mips32le V2Ray 包。
5. 应用 WNDR3800 功能、网络和中文移除配置。
6. 调用 `make defconfig` 解析依赖。
7. 再次强制写入不可由 Kconfig 默认值覆盖的最终选项。
8. 使用 `make -j4 TARGET_DEVICES=<device>` 构建。
9. 复制镜像、manifest 和 SHA256 到任务 artifact 目录。
10. 无论成功或失败，恢复原始 `.config` 和 feed Makefile。

`setsid + nohup` 使进程脱离启动它的 SSH 会话。只要 xps13 本身不关机，
本地电脑关机不会中断编译。

启动方式：

```sh
cd /home/chenmo/Software/openwrt/lede/.codex-autobuild/y1-y1s

# 可同时提交两个任务；内部锁会让它们串行执行
./scripts/build-y1.sh start
./scripts/build-y1s.sh start

# 查看状态
./scripts/build-y1.sh status
./scripts/build-y1s.sh status
```

默认并行度为 4，可以通过环境变量覆盖：

```sh
AUTOBUILD_JOBS=2 ./scripts/build-y1.sh start
```

脚本默认给下载器使用：

```text
socks5://192.168.100.1:1080
```

可通过 `AUTOBUILD_SOCKS_PROXY` 覆盖。

网络和依赖处理与 x86 合并任务保持一致：

- 同时设置 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY` 和 Git
  `http.proxy`。
- V2Ray mips32le 包使用带 SHA-256 校验的五次重试和断点续传。
- 失败的分片和旧文件移动到带时间戳的 `*.failed-*` 文件。
- 构建前运行 `make download` 预取所选软件包。
- 构建前校验五个 Feed 的固定提交，以及 SSR Plus、V2Ray、ZeroTier、
  vlmcsd 的已安装包路径。
- 启用 `set -Eeuo pipefail`，任何关键阶段失败都会停止并在状态文件记录
  非零退出码。
- 明确构建顺序为：配置校验 → `make tools/install` →
  `make toolchain/install` → `make download` →
  `make package/base-files/clean` → 完整 `make`。任何包级操作都放在
  OpenWrt 主机工具和目标交叉工具链就绪之后。

## 与 x86 编译错误的对照检查

Y1/Y1s 共用脚本已经覆盖 x86 构建中出现过的依赖顺序问题：

- 不存在提前调用 `make package/<name>/compile` 的路径。
- `make tools/install`、`make toolchain/install` 均位于
  `make download`、`make package/base-files/clean` 和完整 `make` 之前。
- Feed 提交、目标包链接和主机命令在切换 `.config` 前检查。
- 构建失败由 `set -Eeuo pipefail` 和状态文件记录，不会继续错误状态。

以下 x86 专项问题不适用于 Y1/Y1s：

- Y1/Y1s 使用 OpenWrt 24.10.5 和 `opkg`，不使用 OpenWrt 25.12 的
  `apk-tools`，因此不需要改写 `vlmcsd` 的 `svn1113` 包版本。
- Y1/Y1s 输出 raw `sysupgrade.bin`，不涉及 x86 的 qcow2 收集或转换。

本次检查不改变设备配置、软件包集合、LAN 地址、镜像尺寸限制或产物规则。

## 构建验收

每个设备的 manifest 必须满足：

```text
存在 v2ray-core
不存在 v2ray-plugin
存在 luci-app-ssr-plus
存在 shadowsocksr-libev-ssr-redir
存在 kmod-ipt-tproxy
存在 iptables-mod-tproxy
存在 dnsmasq-full
存在 p910nd/kmod-usb-printer
不存在 luci-i18n-*-zh-cn
不存在 curl/libcurl4
```

镜像必须满足：

```text
sysupgrade.bin <= 16,449,536 B
```

首次启动验收：

```text
Y1 LAN/failsafe = 192.168.6.1/24
Y1s LAN/failsafe = 192.168.4.1/24
LuCI 可打开
SSR Plus 可选择 V2Ray 节点
/usr/bin/v2ray -version 正常
```

## 尚未执行

本方案和脚本已生成，但没有启动任何 Y1 或 Y1s 编译。必须收到明确编译命令
后，才可调用脚本的 `start`。
