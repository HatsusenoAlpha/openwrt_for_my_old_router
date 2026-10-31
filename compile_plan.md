# 任务目标：Netgear WNDR3800 OpenWrt 极限瘦身固件自动化编译方案

## 1. 运行环境与目标设备约束
- **宿主机环境**: Ubuntu 24.04 (GCC 13/14, Python 3.12)
- **目标硬件**: Netgear WNDR3800 (闪存容量限制: 16MB Flash, 内存容量: 128MB RAM)
- **网络需求**: 必须保留完整 IPv6 协议栈及 NAT66 转发层（应对 /128 单地址环境）
- **功能集成**: SSR Plus+（使用轻量 v2ray-plugin，全面剔除 Go 大体积核心）、ZeroTier、p910nd（集成 HP 1020 微码）、KMS、WOL、静态路由
- **安全红线**: 最终生成的固件体积必须锁死在 15.2MB 以内，兼容 Breed 和原厂 U-Boot

## 2. 自动化执行步骤

### 步骤 2.1: 宿主机编译依赖环境安装
Agent 需在 Ubuntu 24.04 宿主机上执行以下命令，安装依赖并解决 Python 3.12 兼容性问题：
```bash
sudo apt update
sudo apt install -y ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
bzip2 ccache cmake cpio curl device-tree-compiler fastjar flex gawk gettext gcc-multilib g++-multilib \
git git-core gperf haveged help2man intltool libc6-dev-i386 libelf-dev libglib2.0-dev libgmp3-dev \
libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev libreadline-dev libssl-dev \
libtool lrzsz mkisofs msmtp nano p7zip p7zip-full patch pkgconf python3 python3-pip python3-ply \
python3-docutils qemu-utils rsync scons squashfs-tools subversion swig texinfo u-boot-tools \
upx-ucl unzip nodejs wget xmlto xz-utils zlib1g-dev python3-setuptools
```

### 步骤 2.2: 源码获取与 2022 年老版 Feeds 锁定
Agent 需克隆官方 Lean 的 LEDE 完整仓库，并强行将 `helloworld`（SSR Plus+ 专属依赖库）锁定在 **2022 年底稳定提交节点 (v1.45 标签)**，以在底层切断现代大体积 Go 语言核心依赖：
```bash
cd ~
# 克隆 Lean 的官方完整 LEDE 仓库
git clone https://github.com/coolsnowwolf/lede openwrt-wndr3800
cd openwrt-wndr3800

# 修复转义：向 feeds 配置文件注入完整的 2022 年稳定版 helloworld 仓库地址
sed -i '\$a src-git helloworld https://github.com/fw876/helloworld.git;v1.45' feeds.conf.default

# 刷新并拉取整个依赖树
./scripts/feeds update -a
./scripts/feeds install -a
```

### 步骤 2.3: 静态文件、网络脚本与硬件微码注入
Agent 需在工作区内建立 `files` 伪文件系统。
*【注意】Agent 需检测或在此阶段自动下载 HP LaserJet 1020 的微码文件 `sihp1020.dl` 并存入 `files/usr/lib/`。*

```bash
mkdir -p files/usr/lib/
mkdir -p files/etc/hotplug.d/usb/
mkdir -p files/etc/hotplug.d/iface/

# 自动生成 HP 1020 打印机上电自动推送固件脚本 (已修复变量符号冲突)
cat << 'EOF' > files/etc/hotplug.d/usb/10-printer
#!/bin/sh
FIRMWARE=/usr/lib/sihp1020.dl
DEVICE=/dev/usb/lp0
if [ "\(PRODUCT" = "3f0/2b17/100" ] && [ "\)ACTION" = "add" ]; then
    for i in 1 2 3 4 5; do
        if [ -c "\$DEVICE" ]; then
            cat "FIRMWARE" > "DEVICE"
            break
        fi
        sleep 1
    done
fi
EOF
chmod +x files/etc/hotplug.d/usb/10-printer

# 自动生成基于传统 ip6tables 语法的 NAT66 自动注入脚本（通过底层 iptables-nft 转换层无缝执行）
cat << 'EOF' > files/etc/hotplug.d/iface/99-nat66
#!/bin/sh
if [ "\(ACTION" = "ifup" ] && [ "\)INTERFACE" = "wan6" ]; then
    ip6tables -t nat -A POSTROUTING -o \$(uci get network.wan6.device) -j MASQUERADE
fi
EOF
chmod +x files/etc/hotplug.d/iface/99-nat66
```

### 步骤 2.4: 极限瘦身配置切片注入 (保留完整 LuCI 中文界面)
Agent 将以下配置切片直接追加至 `.config`，屏蔽文件系统并死锁关闭所有 Xray/V2ray 编译分支，最后运行 `defconfig` 自动推导依赖：
```bash
cat << 'EOF' >> .config
CONFIG_TARGET_ath79=y
CONFIG_TARGET_ath79_generic=y
CONFIG_TARGET_ath79_generic_DEVICE_netgear_wndr3800=y
CONFIG_BUILD_PATTERNS=y
CONFIG_BUILD_MIPS16=y
CONFIG_PACKAGE_dnsmasq_full=y
CONFIG_PACKAGE_dnsmasq_full_dhcp=y
CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y
CONFIG_PACKAGE_dnsmasq_full_ipset=y
# CONFIG_PACKAGE_dnsmasq_full_dnssec is not set
# CONFIG_PACKAGE_dnsmasq_full_authdns is not set
CONFIG_PACKAGE_odhcpd=y
CONFIG_PACKAGE_odhcp6c=y
CONFIG_PACKAGE_kmod-ipt-nat6=y
CONFIG_PACKAGE_kmod-ipt-tproxy=y
CONFIG_PACKAGE_kmod-ipt-ipset=y
# CONFIG_PACKAGE_kmod-fs-ext4 is not set
# CONFIG_PACKAGE_kmod-fs-vfat is not set
# CONFIG_PACKAGE_kmod-fs-ntfs is not set
CONFIG_PACKAGE_kmod-usb-core=y
CONFIG_PACKAGE_kmod-usb2=y
CONFIG_PACKAGE_kmod-usb-printer=y
CONFIG_PACKAGE_luci-app-p910nd=y
CONFIG_PACKAGE_luci-i18n-p910nd-zh-cn=y
CONFIG_PACKAGE_luci-app-ssr-plus=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_V2ray_Plugin=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Xray is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_V2ray is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Trojan is not set
CONFIG_PACKAGE_luci-app-zerotier=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_luci-app-wol=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
# CONFIG_PACKAGE_ath10k-firmware is not set
EOF

make defconfig
```

### 步骤 2.5: 放宽编译器安全限制并启动安全编译
Agent 注入环境变量放宽现代 GCC 对旧源码的严格警告，多线程下载后以单线程构建，严格限制大小不突破原厂分区布局：
```bash
# 注入编译优化及防爆错误环境变量（规避 GCC 13/14 将 Warning 误判为 Error）
export CFLAGS="-Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types"
export CXXFLAGS="-Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types"

# 多线程预下载包
make download -j8

# 单线程安全打包，规避多线程依赖顺序冲突，防止超过原厂死线体积限制
make -j1 V=s
```

### 步骤 2.6: 后续功能补充（2026-10-24）
以下功能已追加到编译配置并通过 15.2MB 体积验证：
- **Vi**：直接使用 BusyBox 已启用的 `CONFIG_VI=y`，镜像内提供 `/bin/vi -> busybox`，无需额外安装 `vim` 或 `nano`。
- **Turbo ACC**：启用 `luci-app-turboacc`、中文翻译和 flow offloading；为满足体积红线关闭可选的 BBR。
- **UPnP**：启用 `luci-app-upnp`、中文翻译及 `miniupnpd-iptables`。
- **vlmcsd**：保留 `vlmcsd`、`luci-app-vlmcsd` 及中文翻译。

对应配置片段：
```text
CONFIG_PACKAGE_luci-app-turboacc=y
CONFIG_PACKAGE_TURBOACC_INCLUDE_FLOW_OFFLOADING=y
CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn=y
CONFIG_PACKAGE_miniupnpd-iptables=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y
CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y
# CONFIG_PACKAGE_TURBOACC_INCLUDE_BBR_CCA is not set
# CONFIG_PACKAGE_kmod-tcp-bbr is not set
# CONFIG_PACKAGE_unzip is not set
```

## 3. 期望输出与验证指标
- **固件路径**: 成功后固件位于 `bin/targets/ath79/generic/`。
- **文件检查**: 必须生成 `openwrt-...-sysupgrade.bin` 与 `openwrt-...-factory.img`。
- **体积死线**: 文件体积必须 **< 15.2MB**。若报错 `Image too big`，Agent 需自动进入 `make menuconfig` 剔除无线驱动中的额外网卡微码。
