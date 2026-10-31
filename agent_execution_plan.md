# WNDR3800 OpenWrt 固件编译：AI Agent 执行计划

> 计划版本：2026-10-24
> 目标主机：`xps13`
> 源码目录：`/home/chenmo/Software/openwrt/lede`
> 目标设备：NETGEAR WNDR3800（ath79/generic，16 MiB Flash，128 MiB RAM）

## 0. 执行契约

AI Agent 必须按阶段执行，并在每个阶段末尾检查门禁。门禁失败时先保留日志和分析原因，不得用 `git reset --hard`、无边界 `rm -rf` 或关闭安全检查来强行通过。

执行期间必须遵守以下规则：

1. 先只读预检，确认主机、源码目录、磁盘、Git 状态、已有构建和正在运行的编译进程。
2. 修改已有源码树前创建带时间戳的备份；不要向已存在的源码目录再次 `git clone` 覆盖。
3. `sudo` 需要密码时停止当前阶段，请用户在本机终端完成授权或提供已授权执行；不要把密码写入命令、日志或对话。
4. 最终固件必须同时满足：
   - 严格小于 `15,200,000` 字节（十进制 15.2MB）；
   - 严格小于 `15.2 * 1024 * 1024` 字节（15.2MiB）；
   - 小于 WNDR3800 的 `15872 KiB` 镜像分区上限。
5. 构建完成后必须从实际镜像的 manifest 和 rootfs 验证软件包，不能只看 `.config`。
6. 计划只负责编译和取回镜像，不包含自动刷机或启动真机验证。
7. 最终镜像可能因源码或工具链变化产生不同哈希；哈希只对同一次构建有效。

在后续阶段使用一致的执行变量。每次新开 shell 时重新导出：

```bash
export WNDR_SOURCE=/home/chenmo/Software/openwrt/lede
export WNDR_RUN_ID=${WNDR_RUN_ID:-20261024-wndr3800}
export WNDR_WORK="$WNDR_SOURCE/.agent-work/$WNDR_RUN_ID"
mkdir -p "$WNDR_WORK"
```

## 1. 基线与已知正确版本

已验证工作树的基线提交如下。若目录已经存在且干净，直接使用当前工作树；若必须从零重建，则检出这些提交，而不是使用移动分支。

```text
LEDE:       6883e66e8b002791cce8587ddb85b63b81b0754c
packages:   360859c8a6dcb7dc294dfc68389a8eeec8c8392a
luci:       0631d439f5d57fab7f077a70e10e3b81809ae5e3
routing:    56d7a818b71b83b0051b85d38efa3b3b558adf75
telephony:  a04b7acfd30a6f8f4d78e62955376c4febcb0976
helloworld: 9ec3e2d32753629aa9e40465611ba6e206970af5
```

注意：`helloworld` 不存在 `v1.45` 标签。原方案中的该标签是无效的，必须使用上面的 2022-12-30 最后提交。

严格复现时，在 Feeds 初始化后检出这些提交。只在对应 Feed 工作树干净时执行：

```bash
git -C feeds/packages checkout 360859c8a6dcb7dc294dfc68389a8eeec8c8392a
git -C feeds/luci checkout 0631d439f5d57fab7f077a70e10e3b81809ae5e3
git -C feeds/routing checkout 56d7a818b71b83b0051b85d38efa3b3b558adf75
git -C feeds/telephony checkout a04b7acfd30a6f8f4d78e62955376c4febcb0976
git -C feeds/helloworld checkout 9ec3e2d32753629aa9e40465611ba6e206970af5
```

如果浅克隆中没有目标提交，先通过可达的 GitHub 镜像按提交号执行 `git fetch --depth=1 <URL> <commit>`，再检出 `FETCH_HEAD`。不要在已有未知改动的工作树中强行检出。

## 2. 阶段 A：只读预检

在 `xps13` 上执行：

```bash
set +e
hostname
id
uname -a
df -h /home/chenmo
cd /home/chenmo/Software/openwrt/lede || exit 1
git status --short --branch
git rev-parse HEAD
git -C feeds/packages rev-parse HEAD
git -C feeds/luci rev-parse HEAD
git -C feeds/routing rev-parse HEAD
git -C feeds/telephony rev-parse HEAD
git -C feeds/helloworld rev-parse HEAD
pgrep -af 'make|git clone|go build' || true
```

门禁 A：

- 主机名应为 `chenmo-XPS-13-9343` 或用户确认的 xps13。
- 源码目录存在且磁盘可用空间不少于 20GB。
- 若目录有未知本地改动，保存 `git diff`，不得清理或覆盖。
- 若有编译进程，不启动第二个构建。

## 3. 阶段 B：宿主机依赖

先检查 `sudo` 是否已授权，以及现有工具是否足够：

```bash
sudo -n true
make prereq
```

若 `sudo -n true` 失败，暂停并请用户完成一次 `sudo -v` 或在 xps13 终端执行安装。不要在自动化脚本中尝试输入密码。

Ubuntu 24.04 建议安装：

```bash
sudo apt update
sudo apt install -y \
  ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
  bzip2 ccache cmake cpio curl device-tree-compiler fastjar flex gawk gettext \
  gcc-multilib g++-multilib git gperf haveged help2man intltool libc6-dev-i386 \
  libelf-dev libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev \
  libncurses-dev libreadline-dev libssl-dev libtool lrzsz msmtp nano patch pkgconf \
  python3 python3-pip python3-ply python3-docutils python3-setuptools qemu-utils \
  rsync scons squashfs-tools subversion swig texinfo u-boot-tools unzip wget \
  xmlto xz-utils zlib1g-dev nodejs
```

包名可能随 Ubuntu 版本变化。`make prereq` 返回 0 时，少量缺失的可选包不应阻止继续；把缺失项和结果记录到日志。

## 4. 阶段 C：Feeds 锁定

### 4.1 保护当前 Feeds 配置

```bash
cd "$WNDR_SOURCE"
mkdir -p "$WNDR_WORK"
cp -a feeds.conf.default "$WNDR_WORK/feeds.conf.default.before"
cp -a .config "$WNDR_WORK/.config.before"
```

### 4.2 锁定 helloworld

当前树应包含：

```text
src-git helloworld https://ghfast.top/https://github.com/fw876/helloworld.git^9ec3e2d32753629aa9e40465611ba6e206970af5
```

若仍是默认地址，可用单提交方式避免完整克隆：

```bash
feed_commit=9ec3e2d32753629aa9e40465611ba6e206970af5
git -C feeds/helloworld fetch --depth=1 \
  https://ghfast.top/https://github.com/fw876/helloworld.git "$feed_commit"
git -C feeds/helloworld checkout -B codex-2022-12-31 FETCH_HEAD
```

然后使用脚本按行替换 `feeds.conf.default` 中的 helloworld 地址，保留其他启用和注释行。替换后校验：

```bash
git -C feeds/helloworld rev-parse HEAD
./scripts/feeds update helloworld
./scripts/feeds install -a
```

门禁 C：

- `feeds/helloworld` 的 `HEAD` 必须是 `9ec3e2d...`。
- `scripts/feeds list -r helloworld` 能看到 `luci-app-ssr-plus`。
- Feeds 更新失败时，优先检查 GitHub 连通性。主域不可达但 `api.github.com`、`codeload.github.com` 或 `ghfast.top` 可用时，使用可达镜像。

## 5. 阶段 D：HP 1020 微码与启动脚本

建立目录：

```bash
mkdir -p files/usr/lib files/etc/hotplug.d/usb files/etc/hotplug.d/iface files/etc/sysctl.d
```

`sihp1020.dl` 必须放在 `files/usr/lib/sihp1020.dl`。如果旧树把它放在 `files/etc/`，移动而不是复制，避免重复占用：

```bash
if [ -f files/etc/sihp1020.dl ] && [ ! -f files/usr/lib/sihp1020.dl ]; then
    mv files/etc/sihp1020.dl files/usr/lib/sihp1020.dl
fi
test -s files/usr/lib/sihp1020.dl
```

若文件不存在，停止并获取可信的 HP LaserJet 1020 微码。只接受上面的 SHA-256，不得用任意同名文件替代。

预期 SHA-256：

```text
c14fdf0af84d1df40545eef7c7d4e2e07dd58fe933e14cc7c29697209e87cd01
```

创建 `files/etc/hotplug.d/usb/10-printer`：

```sh
#!/bin/sh
[ "$ACTION" = "add" ] || exit 0
[ "$PRODUCT" = "3f0/2b17/100" ] || exit 0

FIRMWARE=/usr/lib/sihp1020.dl
DEVICE=/dev/usb/lp0
[ -r "$FIRMWARE" ] || exit 0

for _attempt in 1 2 3 4 5; do
    if [ -c "$DEVICE" ]; then
        cat "$FIRMWARE" > "$DEVICE"
        exit $?
    fi
    sleep 1
done
```

创建 `files/etc/hotplug.d/iface/99-nat66`：

```sh
#!/bin/sh
[ "$ACTION" = "ifup" ] || exit 0
case "$INTERFACE" in
    wan6|wan) ;;
    *) exit 0 ;;
esac

DEVICE=$(uci -q get network.wan6.device)
[ -n "$DEVICE" ] || DEVICE=$(uci -q get network.wan.device)
[ -n "$DEVICE" ] || DEVICE=$(ip -6 route show default 2>/dev/null |
    awk '/ dev / { for (i=1; i<=NF; i++) if ($i == "dev") { print $(i+1); exit } }')
[ -n "$DEVICE" ] || exit 0

ip6tables -t nat -C POSTROUTING -o "$DEVICE" -j MASQUERADE 2>/dev/null ||
    ip6tables -t nat -A POSTROUTING -o "$DEVICE" -j MASQUERADE
```

创建 `files/etc/sysctl.d/99-nat66-forwarding.conf`：

```text
net.ipv6.conf.all.forwarding=1
```

设置权限并检查：

```bash
chmod 755 files/etc/hotplug.d/usb/10-printer files/etc/hotplug.d/iface/99-nat66
sh -n files/etc/hotplug.d/usb/10-printer
sh -n files/etc/hotplug.d/iface/99-nat66
sha256sum files/usr/lib/sihp1020.dl
```

## 6. 阶段 E：必需补丁

### 6.1 修复 shadowsocksr-libev 悬空指针

创建 `feeds/helloworld/shadowsocksr-libev/patches/104-fix-compatible-suffix-memory.patch`：

```diff
--- a/server/server.c
+++ b/server/server.c
@@ -1943,8 +1943,7 @@
             memcpy(text, protocol, strlen(protocol) - 11);
             int length = strlen(protocol) - 11;
             free(protocol);
-            obfs = (char*)malloc(length);
-            memset(protocol, 0x00, length);
+            protocol = (char*)calloc(length + 1, 1);
             memcpy(protocol, text, length);
             LOGI("protocol compatible enable, %s", protocol);
             free(text);
@@ -1965,8 +1964,7 @@
             memcpy(text, obfs, strlen(obfs) - 11);
             int length = strlen(obfs) - 11;
             free(obfs);
-            obfs = (char*)malloc(length);
-            memset(obfs, 0x00, length);
+            obfs = (char*)calloc(length + 1, 1);
             memcpy(obfs, text, length);
             LOGI("obfs compatible enable, %s", obfs);
             free(text);
```

该补丁同时修复 GCC 13 的 `-Werror=use-after-free` 和原代码缺少字符串结尾的问题。

### 6.2 阻止静态库进入目标镜像

修改 `package/libs/toolchain/Makefile` 中的 `Package/libc/install_lib`：

```make
define Package/libc/install_lib
    # Static archives are build-time only; do not ship them in the target image.
endef
```

这是历史构建首次超限的主要原因。rootfs 中的 `libstdc++.a`、`libc.a` 等约 42.6MB 静态库均不应进入固件。

修改前保存原 Makefile，并保留 diff：

```bash
cp -a package/libs/toolchain/Makefile "$WNDR_WORK/toolchain.Makefile.before"
git diff -- package/libs/toolchain/Makefile > "$WNDR_WORK/toolchain-static-libs.patch"
```

## 7. 阶段 F：配置切片

先备份 `.config`，再追加以下配置，最后运行 `make defconfig`：

```text
CONFIG_TARGET_ath79=y
CONFIG_TARGET_ath79_generic=y
CONFIG_TARGET_ath79_generic_DEVICE_netgear_wndr3800=y

CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_dnsmasq_full_dhcp=y
CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y
CONFIG_PACKAGE_dnsmasq_full_ipset=y
# CONFIG_PACKAGE_dnsmasq_full_dnssec is not set
# CONFIG_PACKAGE_dnsmasq_full_authdns is not set
CONFIG_PACKAGE_odhcp6c=y
CONFIG_PACKAGE_odhcpd-ipv6only=y

CONFIG_PACKAGE_kmod-ipt-nat6=y
CONFIG_PACKAGE_kmod-ipt-tproxy=y
CONFIG_PACKAGE_kmod-ipt-ipset=y
CONFIG_PACKAGE_kmod-ipt-offload=y

# CONFIG_PACKAGE_kmod-fs-ext4 is not set
# CONFIG_PACKAGE_kmod-fs-vfat is not set
# CONFIG_PACKAGE_kmod-fs-ntfs is not set
# CONFIG_PACKAGE_kmod-fs-ntfs3 is not set

CONFIG_PACKAGE_kmod-usb-core=y
CONFIG_PACKAGE_kmod-usb2=y
CONFIG_PACKAGE_kmod-usb-printer=y
CONFIG_PACKAGE_luci-app-p910nd=y
CONFIG_PACKAGE_luci-i18n-p910nd-zh-cn=y

CONFIG_PACKAGE_luci-app-ssr-plus=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_NONE_V2RAY=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_V2ray is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Xray is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_SagerNet_Core is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ChinaDNS_NG is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Hysteria is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_IPT2Socks is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Kcptun is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_NaiveProxy is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Redsocks2 is not set
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Client=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Client is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Rust_Client is not set
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Server is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Rust_Server is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Simple_Obfs is not set
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_V2ray_Plugin=y
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Client=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Server is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Trojan is not set

CONFIG_PACKAGE_luci-app-zerotier=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-wol=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_luci-i18n-ssr-plus-zh-cn=y
CONFIG_PACKAGE_luci-i18n-zerotier-zh-cn=y
CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y
CONFIG_PACKAGE_luci-i18n-wol-zh-cn=y

CONFIG_PACKAGE_luci-app-turboacc=y
CONFIG_PACKAGE_TURBOACC_INCLUDE_FLOW_OFFLOADING=y
CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn=y
# CONFIG_PACKAGE_TURBOACC_INCLUDE_BBR_CCA is not set
# CONFIG_PACKAGE_kmod-tcp-bbr is not set

CONFIG_PACKAGE_miniupnpd-iptables=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y

# CONFIG_PACKAGE_openssh-server is not set
# CONFIG_PACKAGE_openssh-keygen is not set
# CONFIG_PACKAGE_openssh-client is not set
# CONFIG_PACKAGE_openssh-sftp-server is not set
# CONFIG_PACKAGE_htop is not set
# CONFIG_PACKAGE_nping is not set
# CONFIG_PACKAGE_vsftpd is not set
# CONFIG_PACKAGE_luci-app-vsftpd is not set
# CONFIG_PACKAGE_luci-i18n-vsftpd-zh-cn is not set
# CONFIG_PACKAGE_adblock-fast is not set
# CONFIG_PACKAGE_luci-app-adblock-fast is not set
# CONFIG_PACKAGE_luci-i18n-adblock-fast-zh-cn is not set
# CONFIG_PACKAGE_nlbwmon is not set
# CONFIG_PACKAGE_luci-app-nlbwmon is not set
# CONFIG_PACKAGE_luci-i18n-nlbwmon-zh-cn is not set
# CONFIG_PACKAGE_ddns-scripts is not set
# CONFIG_PACKAGE_ddns-scripts_aliyun is not set
# CONFIG_PACKAGE_ddns-scripts_dnspod is not set
# CONFIG_PACKAGE_luci-app-ddns is not set
# CONFIG_PACKAGE_luci-i18n-ddns-zh-cn is not set
# CONFIG_PACKAGE_unzip is not set
# CONFIG_PACKAGE_ath10k-firmware is not set
```

Vi 不安装 `vim` 或 `nano`。使用 BusyBox 内置 Vi，最终通过镜像中的 `/bin/vi -> busybox` 和 BusyBox 的 `CONFIG_VI=y` 验证。

执行并验证：

```bash
make defconfig
grep -E '^CONFIG_TARGET_ath79_generic_DEVICE_netgear_wndr3800=y$' .config
grep -E '^CONFIG_PACKAGE_(luci-app-(ssr-plus|p910nd|zerotier|vlmcsd|wol|turboacc|upnp)|miniupnpd-iptables)=y$' .config
grep -E '^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_(V2ray|Xray|Shadowsocks_Rust|Trojan)=y$' .config && exit 1 || true
```

## 8. 阶段 G：旧版 Go 与 v2ray-plugin

旧 Feeds 中的 `quic-go v0.31.1` 会拒绝 Go 1.20+。当前 LEDE 的交叉 Go 可能是 1.26，因此必须先使用 Go 1.19 构建 `v2ray-plugin`。

检查：

```bash
staging_dir/hostpkg/lib/go-cross/bin/go version
```

若没有可用的 Go 1.19：

```bash
go119_root=".agent-work/go119"
mkdir -p "$go119_root"
curl -fL --retry 2 \
  https://mirrors.aliyun.com/golang/go1.19.13.src.tar.gz \
  -o "$go119_root/go1.19.13.src.tar.gz"
sha256sum "$go119_root/go1.19.13.src.tar.gz"
tar -xzf "$go119_root/go1.19.13.src.tar.gz" -C "$go119_root"
(
  cd "$go119_root/go/src"
  GOROOT_BOOTSTRAP="/home/chenmo/Software/openwrt/lede/staging_dir/hostpkg/lib/go-cross" \
    ./make.bash
)
"$go119_root/go/bin/go" version
```

已验证下载文件的 SHA-256：

```text
ccf36b53fb0024a017353c3ddb22c1f00bc7a8073c6aac79042da24ee34434d3
```

临时切换 Go 并使用 trap 保证恢复：

```bash
go119_bin="/home/chenmo/Software/openwrt/lede/.agent-work/go119/go/bin/go"
go_link=staging_dir/hostpkg/bin/go
old_go_link=$(readlink "$go_link")
restore_go_link() { ln -sfn "$old_go_link" "$go_link"; }
trap restore_go_link EXIT
ln -sfn "$go119_bin" "$go_link"

export CFLAGS="-Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types"
export CXXFLAGS="$CFLAGS"
export GOPROXY="https://goproxy.cn,direct"

make package/v2ray-plugin/clean
make package/v2ray-plugin/compile -j1 V=s
```

门禁 G：

- 插件编译返回 0。
- `bin/packages/mips_24kc/helloworld/v2ray-plugin_*.ipk` 存在。
- `readlink staging_dir/hostpkg/bin/go` 恢复为原来的 `../lib/go-cross/bin/go`。

## 9. 阶段 H：下载和主构建

```bash
export CFLAGS="-Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types"
export CXXFLAGS="$CFLAGS"

make download -j8
make prereq
```

若 `make download` 返回非 0，先检查缺失的源文件。`shadowsocksr-libev` 的官方下载镜像可能返回 404，但 GitHub API/`ghfast.top` 回退仍然可用。不要以忽略哈希的方式继续。

配置变更后，强制重建目标 rootfs 安装快照，避免旧 `.a` 文件残留：

```bash
root_dir=staging_dir/target-mips_24kc_musl/root-ath79
if [ -d "$root_dir" ]; then
  mv "$root_dir" "$WNDR_WORK/root-ath79.before-rebuild"
fi
```

启动目标设备限定构建：

```bash
make -j1 V=s TARGET_DEVICES=netgear_wndr3800
```

这里的 `TARGET_DEVICES=netgear_wndr3800` 必须作为 make 命令行变量传入。Lean 的 ath79 镜像阶段默认会生成大量无关型号；该变量只构建 WNDR3800 的目标镜像，同时保持单线程构建。

建议用 `nohup setsid` 后台执行，把 stdout/stderr 写入日志，并把退出码写入单独文件。轮询日志时报告当前软件包或镜像阶段，不要重复启动构建。

## 10. 阶段 I：处理体积超限

只有在构建成功但文件超过体积门禁时，按以下顺序处理：

1. 检查 rootfs 静态库：

```bash
find staging_dir/target-mips_24kc_musl/root-ath79 -type f -name '*.a' -printf '%s %p\n'
```

2. 检查可选包的实际压缩后体积：

```bash
find bin/packages/mips_24kc bin/targets/ath79/generic/packages \
  -type f -name '*.ipk' -printf '%s %f\n' | sort -nr | head -80
```

3. 优先移除未要求的功能，而不是笼统删除无线驱动。已知可移除项包括 OpenSSH、htop、nping、vsftpd、AdBlock、nlbwmon、DDNS、独立 unzip。
4. Turbo ACC 可以只保留 `FLOW_OFFLOADING`，关闭可选 BBR；不要删除 UPnP、vlmcsd、Vi、ZeroTier、p910nd 或 SSR Plus+。
5. 修改配置后重新执行 `make defconfig`，然后重新生成 rootfs；仅重新打包旧 rootfs 不足以清理已移除包。
6. 镜像按 64KiB 边界填充，有时内容只减少几KB仍不会改变最终文件大小；需要跨过填充边界。

禁止把 `IMAGE_SIZE` 改大，也禁止跳过 `check-size`。

## 11. 阶段 J：强制验收

最终输出：

```text
bin/targets/ath79/generic/openwrt-ath79-generic-netgear_wndr3800-squashfs-sysupgrade.bin
bin/targets/ath79/generic/openwrt-ath79-generic-netgear_wndr3800-squashfs-factory.img
bin/targets/ath79/generic/openwrt-ath79-generic-netgear_wndr3800.manifest
```

### 11.1 文件大小

```bash
python3 - <<'PY'
import os
for p in [
    "bin/targets/ath79/generic/openwrt-ath79-generic-netgear_wndr3800-squashfs-sysupgrade.bin",
    "bin/targets/ath79/generic/openwrt-ath79-generic-netgear_wndr3800-squashfs-factory.img",
]:
    size = os.path.getsize(p)
    assert size > 10_000_000
    assert size < 15_200_000
    assert size < 15.2 * 1024 * 1024
    assert size < 15872 * 1024
    print(os.path.basename(p), size, f"{size / 1024 / 1024:.3f} MiB")
PY
```

### 11.2 Manifest

必须包含：

```text
busybox
kmod-ipt-offload
luci-app-turboacc
luci-app-upnp
luci-app-vlmcsd
miniupnpd-iptables
vlmcsd
luci-app-ssr-plus
v2ray-plugin
shadowsocksr-libev-ssr-local
shadowsocksr-libev-ssr-redir
luci-app-p910nd
luci-app-zerotier
luci-app-wol
kmod-ipt-nat6
kmod-ipt-tproxy
kmod-ipt-ipset
kmod-usb-printer
odhcpd-ipv6only
odhcp6c
dnsmasq-full
```

不得包含：

```text
xray-core
v2ray-core
trojan
hysteria
naiveproxy
openssh-server
```

### 11.3 Rootfs 和脚本

```bash
rootfs=build_dir/target-mips_24kc_musl/linux-ath79_generic/root.squashfs
unsquashfs -ll "$rootfs" | grep -E 'squashfs-root/(bin/vi|usr/lib/sihp1020.dl|etc/hotplug.d/usb/10-printer|etc/hotplug.d/iface/99-nat66|usr/bin/vlmcsd|usr/sbin/miniupnpd)$'
test "$(unsquashfs -ll "$rootfs" | grep -c '\.a$')" -eq 0
```

验证 Vi 是 BusyBox 链接：

```bash
find staging_dir/target-mips_24kc_musl/root-ath79 -maxdepth 3 -type l -name vi -printf '%p -> %l\n'
```

预期：

```text
.../bin/vi -> busybox
```

### 11.4 图片元数据和签名

警告：必须先把镜像复制到临时文件，并使用正确参数顺序 `fwtool -i <输出元数据> <镜像>`。错误地调用 `fwtool -i <镜像>` 可能截断正式镜像。

```bash
tmpdir=$(mktemp -d)
cp -p bin/targets/ath79/generic/openwrt-ath79-generic-netgear_wndr3800-squashfs-sysupgrade.bin "$tmpdir/probe.bin"
staging_dir/host/bin/fwtool -i "$tmpdir/meta" "$tmpdir/probe.bin"
staging_dir/host/bin/fwtool -s "$tmpdir/sig" "$tmpdir/probe.bin"
cat "$tmpdir/meta"
test -s "$tmpdir/sig"
```

元数据应包含：

```text
"supported_devices":["netgear,wndr3800","wndr3700"]
"board": "netgear_wndr3800"
```

### 11.5 哈希与最终记录

```bash
sha256sum \
  bin/targets/ath79/generic/openwrt-ath79-generic-netgear_wndr3800-squashfs-sysupgrade.bin \
  bin/targets/ath79/generic/openwrt-ath79-generic-netgear_wndr3800-squashfs-factory.img
```

参考构建结果（同源码基线时）：

```text
sysupgrade.bin  15,139,630 bytes
SHA-256         6463d66664389438d0115eddbc37d034cc2700d056d9141a1be119e1e1b5af24

factory.img     15,138,949 bytes
SHA-256         c7165e5050a2af128342378ef98514a130a01bbccd9966cf48edef52dae4c606
```

## 12. 阶段 K：取回本地

如果 MCP 的 `download_file` 服务运行在 xps13 本身，它的 `local_path` 可能仍解析到 xps13，而不是当前 Windows 工作区。已验证可靠方式是从 Windows 本机使用 OpenSSH/SCP：

```powershell
$dest = Join-Path (Get-Location) 'artifacts\wndr3800-openwrt-24.10.5'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

& 'C:\Windows\System32\OpenSSH\scp.exe' -p `
  'xps13:/home/chenmo/Software/openwrt/lede/bin/targets/ath79/generic/openwrt-ath79-generic-netgear_wndr3800-squashfs-sysupgrade.bin' `
  'xps13:/home/chenmo/Software/openwrt/lede/bin/targets/ath79/generic/openwrt-ath79-generic-netgear_wndr3800-squashfs-factory.img' `
  $dest

Get-FileHash -Algorithm SHA256 -LiteralPath `
  "$dest\openwrt-ath79-generic-netgear_wndr3800-squashfs-sysupgrade.bin", `
  "$dest\openwrt-ath79-generic-netgear_wndr3800-squashfs-factory.img"
```

必须再次与 xps13 上的 `sha256sum` 结果逐一比对。

## 13. 回滚

所有备份存放在：

```text
/home/chenmo/Software/openwrt/lede/.agent-work/<stamp>/
```

至少保留：

```text
feeds.conf.default.before
.config.before
toolchain.Makefile.before
root-ath79.before-rebuild
build.log
download.log
```

恢复配置时使用明确目标，不执行全目录删除。独立 Feed 的补丁可在 `feeds/helloworld` 中通过 Git diff 查看和撤销。

## 14. 完成条件

只有以下条件全部成立才算完成：

- [ ] 构建退出码为 `0`。
- [ ] `sysupgrade.bin` 和 `factory.img` 均存在且非空。
- [ ] 两个文件都小于 15,200,000 字节，并低于 15,872 KiB 分区上限。
- [ ] manifest 包含全部必需包，且不存在 Xray/V2Ray/Trojan 等重核心。
- [ ] rootfs 中存在 BusyBox Vi 链接、HP 微码、NAT66 脚本、UPnP、Turbo ACC 和 vlmcsd。
- [ ] rootfs 中静态 `.a` 文件数量为 0。
- [ ] `fwtool` 可在副本上读取设备元数据和签名。
- [ ] 本地副本哈希与 xps13 源文件一致。
- [ ] 明确告知用户：未自动刷机，也未完成真机启动测试。

刷机选择：

- 原厂 Netgear 固件首次刷入：使用 `factory.img`。
- 已运行 OpenWrt 的升级：使用 `sysupgrade.bin`。
- 通过 Breed Web 控制台刷写：通常使用 `factory.img`，并确认目标为固件分区。
