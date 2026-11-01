# FastRhino R66S（RK3568）独立编译规格

> 交付对象：负责编译的 agent
> 目的：从源码独立编译一个**能在本机 R66S 上启动并正常工作**的 OpenWrt/ImmortalWrt 25.12.x 镜像，
> 保留现有拨号、ZeroTier 身份、SSH 密钥、ssr-plus 节点（含 `alter_id=100`）与 Web 管理。
> 本目录 `build-spec/` 里的所有文件都是**从真实设备两个固件镜像中导出的事实数据**，可直接使用。

---

## 0. 现状与结论（先读）

| 镜像 | 栈 | 结果 |
|---|---|---|
| 本项目修复的旧镜像 | OpenWrt SNAPSHOT r5066（内核 **4.19.245-android**） | ✅ 正常启动、Web/拨号/ZeroTier 均正常（目前在用） |
| 厂商最新镜像 QWRT-R26.09.30 | OpenWrt **25.12.3** r7675（内核 **6.18.18**） | ❌ 无法启动（见 6.1 的 dtb 符号链接 bug） |
| 我们对官方新镜像的两版离线修正 | 同 25.12.3 | ❌ 仍未进入可用用户态（灯灭/无网络） |

**由此得出的编译策略**：

1. 优先编译**上游 ImmortalWrt/OpenWrt 25.12.x** 的 `rockchip/armv8` → `fastrhino_r66s` 设备（不沿用厂商的装配脚本），
   让构建系统自己生成 u-boot/ATF/dtb/boot.scr，避免厂商镜像里的符号链接与 bootflow 问题。
2. 用本目录的**旧可用内核 config** 与**包清单**校正配置，补齐厂商特有的驱动/软件。
3. 先编"**干净最小镜像**"验证能开机（只要网口、LuCI），再逐批加插件；每批都做真机验收。
4. 若干净镜像也起不来，说明 6.18 内核与本机不兼容，退回到"保留旧 4.19 系统 + 只移植 ssr-plus 196-r10"的方案（见 14）。

---

## 1. 硬件事实

| 项目 | 值 |
|---|---|
| SoC | Rockchip **RK3568**（4×Cortex-A55，最高 1.6 GHz） |
| 内存 | 2 GB（无 swap，可在系统里另建） |
| 存储 | **TF 卡启动**（`mmcblk1`），**无 eMMC**（`mmcblk0` 不存在） |
| 网口 | 2× RJ45，**PCIe RTL8125**（驱动 `r8125`，旧内核实测 `r8125: eth0 link up`） |
| 串口 | `ttyS2`，**1500000 baud**（`earlycon=uart8250,mmio32,0xfe660000`） |
| 板级标识 | `compatible = "fastrhino,r66s", "rockchip,rk3568"`（dtb 内 "FastRhino R66S"） |
| 同镜像兼容板 | R68S（`rockchip1.dtb`，`fastrhino,r68s`） |
| LED 现象参考 | 旧系统：网口橙灯常亮；官方新 u-boot（未起内核）：绿灯（u-boot 的 DHCP/pxe 扫描点亮 PHY）；两者混合：灯灭 |

---

## 2. 两个基线（事实数据）

### 2.1 旧可用系统（编译参照，已验证可启动）

| 项目 | 值 |
|---|---|
| 发行版 | OpenWrt **SNAPSHOT** `r5066-b294b1ac9` |
| 内核 | **4.19.245-android**（GCC 8.4.0，OpenWrt r5044） |
| 内核配置 | **`kernel-old.config`**（5,645 行完整配置，从 kernel.img 的 IKCONFIG 导出）✅ |
| 内核模块 | `modules-old.txt`（228 个 .ko） |
| 包 | `packages-old.txt`（**462 个**，含版本） |
| 关键版本 | `luci-base git-23.141.16773-28dd4b3-1`、`luci-app-ssr-plus **186-8**`、`luci-app-openclash 0.45.103-beta`、`luci-theme-design 5.7.6`、`zerotier 1.10.6`、`uhttpd 2022-02-07` |
| 核心 | `/usr/bin/xray`（**Xray 1.8.0**），`/var/etc/ssrplus/bin/v2ray -> xray` |

### 2.2 厂商最新镜像（编译参照，装配有 bug）

| 项目 | 值 |
|---|---|
| 发行版 | OpenWrt **25.12.3** `r7675-942a9f2c91` |
| 内核 | **6.18.18**（未内嵌 IKCONFIG，无法导出 config） |
| 内核模块 | `modules-new.txt`（335 个 .ko，**含 `r8125.ko`**） |
| 包 | `packages-new.txt`（**586 个**） |
| 关键版本 | `luci-app-ssr-plus **196-r10**`、`luci-app-openclash 0.47.133`、`luci-theme-design 7.1-r20260927`、`zerotier 1.16.0`、`uhttpd 2025-10-03` |
| 组件机制 | 不内置 xray/mihomo，`/usr/share/shadowsocksr/update_components.sh` 按需下载（`/usr/bin/xray`、`/usr/bin/mihomo`） |
| feed | 见 `feeds-new.conf`（`openwrt_core/base/luci/packages/routing/telephony` + **`ssr`、`istore`、`nas`、`nas_luci`、`qmodem`**，全部指向 `downloads.openwrt.org/releases/25.12.3/...`） |

> 说明：`ssr` / `istore` / `nas` 这些 feed 名是 **ImmortalWrt** 体系特征，因此优先以 **ImmortalWrt 25.12.3** 作为 base（若官方源无对应 feed 再回退 OpenWrt + 追加 feed）。

---

## 3. 源码与 feed

```sh
git clone https://github.com/immortalwrt/immortalwrt.git
cd immortalwrt
git checkout v25.12.3        # 与镜像 DISTRIB_RELEASE 对齐
./scripts/feeds update -a && ./scripts/feeds install -a
```

若使用 OpenWrt 官方：

```sh
git clone https://git.openwrt.org/openwrt/openwrt.git
git checkout v25.12.3
```

额外 feed（用于 `ssr` / `istore` / `nas` / `qmodem`，具体地址以 `feeds-new.conf` 为准）：

```sh
cat feeds-new.conf >> feeds.conf.default     # 或手工挑选需要的 feed
./scripts/feeds update -a && ./scripts/feeds install -a
```

---

## 4. 目标与镜像参数

```sh
make menuconfig
```

选择：

- Target System: **Rockchip**
- Subtarget: **ARMv8**
- Target Profile: **FastRhino R66S**（符号一般形如 `DEVICE_fastrhino_r66s`，请以 menuconfig 实际显示为准）
- Target Images:
  - `ext4`（p1，**64 MiB**，放 kernel + dtb + boot.scr）
  - `squashfs`（p2，**896 MiB**）
  - SquashFS block size: **1024 KiB**
  - SquashFS compression: **xz**
  - 输出 `.img.gz`（combined image）

`config.seed` 已给出上述目标/镜像参数与基础/插件包，**符号名请在 menuconfig 里核对一次**后合并进 `.config`。

---

## 5. 内核

### 5.1 用旧可用配置做基线（强烈建议）

- 文件：**`kernel-old.config`**（4.19.245 完整配置，5,645 行）
- 用途：
  1. 与上游 `target/linux/rockchip/config-6.x` 做 **diff**，找出厂商特有选项；
  2. 作为"必须存在的功能"清单（见 5.3）。

### 5.2 新内核（6.18.18）需要的模块（来自 `modules-new.txt`）

重点确认存在：

- 网络：`r8125.ko`（**RTL8125 2.5G**）、`stmmac`/`dwmac*`、`veth.ko`、`br_netfilter.ko`
- 存储：`squashfs`（xz）、`f2fs`、`ext4`、`loop`、`sdhci*`/`dw_mmc*`
- 文件系统/容器：`overlay`、`nf_conntrack*`、`nf_nat*`、`xt_*`
- 其它：`usb-storage`、`usbhid`、`rtc-*`、`gpio-*`

### 5.3 必须打开的选项（旧配置里均存在）

```text
CONFIG_SQUASHFS=y, CONFIG_SQUASHFS_XZ=y, CONFIG_SQUASHFS_LZ4=y（可选）
CONFIG_F2FS_FS=y, CONFIG_EXT4_FS=y, CONFIG_OVERLAY_FS=y
CONFIG_BLK_DEV_LOOP=y
CONFIG_CGROUPS=y, CONFIG_CGROUP_*（cpu/cpuset/memory/devices/pids/...）
CONFIG_NAMESPACES=y, CONFIG_NET_NS=y, CONFIG_PID_NS=y, CONFIG_UTS_NS=y, CONFIG_IPC_NS=y, CONFIG_USER_NS=y
CONFIG_VETH=y/m, CONFIG_BRIDGE=y, CONFIG_BRIDGE_NETFILTER=y/m
CONFIG_NF_NAT=y/m, CONFIG_IP_NF_TARGET_MASQUERADE=y/m, CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y/m
CONFIG_SECCOMP=y, CONFIG_SECCOMP_FILTER=y
CONFIG_IKCONFIG=y, CONFIG_IKCONFIG_PROC=y   ← 便于以后导出 kernel config
```

**串口**：`console=ttyS2,1500000` + `earlycon=uart8250,mmio32,0xfe660000`（boot.scr 里写死，见 6）。

---

## 6. 设备树与引导链（本次失败的核心）

### 6.1 厂商新镜像的 bug（已实测确认）

新镜像 p1（ext4）里：

```text
rockchip0.dtb   100391 B   ← R66S（fastrhino,r66s）
rockchip1.dtb   102209 B   ← R68S
rockchip.dtb    lrwxrwxrwx 13 → rockchip0.dtb     ← 符号链接
```

而 `boot.scr`（555 B）逻辑：

```text
if gpio input 55; then echo noemmc        # R66S：无 eMMC → hwflag 为空
else echo hasemmc; setenv hwflag 1 fi     # R68S
load mmc ${devnum}:1 ${fdt_addr_r} rockchip${hwflag}.dtb
```

⇒ R66S 加载的是 **`rockchip.dtb`（符号链接）**。实测：u-boot 不能把它当有效 DTB 使用，
`booti` 失败 → 内核不启动 → 卡不被写入、网口只有 u-boot 的 DHCP 扫描灯（绿），无网络。

### 6.2 编译时必须保证

1. `rockchip0.dtb` / `rockchip.dtb` 都是**真实文件**（不是符号链接），内容为 R66S dtb（参考 `boot/r66s-rockchip0.dtb`，sha256 `22cd3f09…`）；
2. 安装脚本（`/lib/upgrade/platform.sh` 或 image Makefile 的 `IMAGE/...` / `post-image` 钩子）里不要用 `ln -sf` 生成 dtb 链接；
3. `boot.scr` 引用 `rockchip.dtb` 时文件必须存在且可读；
4. 若沿用厂商 555 B 的 boot.scr，请把 `rockchip1.dtb` 也替换为 R66S dtb（本机是 R66S），或干脆改 boot.scr 固定加载 `rockchip0.dtb`；
5. bootargs 必须包含 `root=PARTUUID=<p2 uuid> rw rootwait`（由 `part uuid mmc ${devnum}:2 uuid` 得到）。

### 6.3 引导链参考

- `boot/vendor-bootchain-512-to-32MiB.bin`：旧镜像（**已验证可启动**）的 idbloader/ATF/u-boot/env 原始区域（字节 512–32 MiB）。
- `boot/old-boot.scr`（619 B，旧系统使用，固定加载 `rockchip.dtb`）
- `boot/new-boot.scr`（555 B，厂商新版，GPIO 选择 dtb）
- 上游构建会自动生成自己的 u-boot/ATF；**优先用上游生成的**（避免厂商 bootflow 问题）。

---

## 7. 分区与可写层布局

| 分区 | 偏移 | 大小 | 内容 |
|---|---|---|---|
| MBR | LBA0 | 512 B | 磁盘 ID **`0x5452574f`**；p1 状态 **0x80（bootable）**；两个分区 type 0x83 |
| p1 | 65536 扇区（32 MiB） | 131072 扇区（64 MiB） | ext4：`kernel.img` + `rockchip*.dtb` + `boot.scr` |
| p2 | 262144 扇区（128 MiB） | 1835008 扇区（896 MiB） | squashfs（`bytes_used` ≈ 88.98 MB）+ f2fs 可写层 |

**可写层规则（实测）**：首次启动时，f2fs 建立在
`align256KiB(squashfs 末尾)` 处。

- 旧镜像：squashfs 68,934,258 → 0x41C0000（68,943,872）✅
- 新镜像：squashfs 88,984,046 → **89,128,960**（分区内偏移）

构建系统（fstools）会自动完成，但若做后处理，请按同一规则。

---

## 8. 软件清单与版本

- 完整清单：`packages-old.txt`（旧，462 个，含版本）与 `packages-new.txt`（新，586 个）。
- **代理插件（alterId 关键）**：

| 包 | 旧版本 | 新版本 | 说明 |
|---|---|---|---|
| `luci-app-ssr-plus` | 186-8 | **196-r10** | 新版脚本已完整支持 `alterId`（UI/订阅/Xray JSON/Mihomo YAML）；建议用 196-r10 |
| 核心 | Xray 1.8.0 | 按需下载最新 Xray / Mihomo | 实测 **Xray 26.10.29 仍支持 alterId>0 的 legacy VMess**；Mihomo 同样支持 |
| `luci-app-openclash` | 0.45.103-beta | 0.47.133 | 可选 |

> alterId 结论详见 `docs/alterId支持分析-最新固件对比与可移植性.md`：
> 客户端 alterId>0 → 走 legacy；若服务端是 Xray 且未放开 `xray.vmess.aead.forced=false`，会被拒绝。

---

## 9. 用户配置注入（`files/` 目录）

`files/` 已包含从在用系统导出的配置（overlay 内容），构建时：

```sh
cp -a ../build-spec/files ./files     # 在 openwrt 源码树根目录
```

包含：

- `etc/config/*`（network=PPPoE、dhcp、firewall（含 shadowsocksr/openclash/zerotier/adbyby 等 include）、shadowsocksr（3 个节点，`alter_id=100`）、zero（ZeroTier 身份）、system、luci（主题/语言）、openclash、samba…）
- `etc/dropbear/authorized_keys`（SSH 公钥）与 host keys
- `etc/ssrplus/*`（gfw 列表等）
- `etc/crontabs/root`
- `etc/passwd|shadow|group`、`root/.ssh/known_hosts`

**注意**：

1. 已刻意**不包含** `etc/config/fstab`（旧卡 p3/p4 引用），分区建好后另行生成；
2. 不含 `etc/config/ucitrack`、`rpcd`（版本相关，用新固件默认）；
3. `etc/config/luci` 指定了 `luci-theme-design`，必须在构建里包含该主题，否则 LuCI 会回退到默认主题；
4. 若目标固件缺少某些旧插件（如 uuplugin、xunlei、aliyundrive），对应 config 文件无副作用，但建议人工裁剪。

---

## 10. 建议构建步骤

```sh
# 1) 源码与 feeds
git clone https://github.com/immortalwrt/immortalwrt.git && cd immortalwrt
git checkout v25.12.3
cat ../build-spec/feeds-new.conf >> feeds.conf.default
./scripts/feeds update -a && ./scripts/feeds install -a

# 2) 配置
make menuconfig                 # 按第 4 节选择 target/profile/image
cp ../build-spec/config.seed .config.seed
cat .config.seed >> .config     # 或 scripts/diffconfig
make defconfig
make download -j8

# 3) 编译（首次建议 -j4，避免内存不足）
make -j$(nproc) V=s

# 4) 产物
ls -la bin/targets/rockchip/armv8/*fastrhino*r66s*
```

---

## 11. 校验清单

### 11.1 镜像级（不刷机即可验证）

- [ ] 镜像为 combined：MBR 磁盘 ID `0x5452574f`，p1=65536/131072，p2=262144/1835008，p1 状态 0x80
- [ ] p1 里 `rockchip.dtb` 与 `rockchip0.dtb` 都是**普通文件**（`test -L` 应为假），sha256 一致
- [ ] p1 有 `kernel.img`（ARM64 Image，偏移 56 处 magic `ARMd`）与 `boot.scr`
- [ ] boot.scr 里 bootargs 含 `console=ttyS2,1500000`、`earlycon`、`root=PARTUUID=`
- [ ] squashfs 可被 `unsquashfs -ll` 完整列出（无 error）
- [ ] rootfs 含 `kmod-r8125`（`/lib/modules/<ver>/r8125.ko`）
- [ ] rootfs 含 `luci-app-ssr-plus`（196-r10 或 186-8）与 `alter_id` 字段

### 11.2 真机级（换卡开机）

- [ ] 网口灯亮（绿或橙均可，表示 PHY 已初始化），`192.168.100.1` 可达
- [ ] SSH 可用现有密钥直接登录（`authorized_keys` 已注入）
- [ ] LuCI 打开正常
- [ ] `dmesg | grep -c "SQUASHFS error"` = 0
- [ ] `ip link` 有 `eth0/eth1`，`r8125` 已加载
- [ ] PPPoE 拨号成功（`ifstatus wan`）
- [ ] `zerotier-cli info` ONLINE，节点 ID 与旧系统一致（`identity.secret` 来自 files/）
- [ ] ssr-plus 3 个节点、`alter_id=100` 保留；代理可用

---

## 12. 已知坑（务必规避）

1. **dtb 符号链接**（本次根因）：u-boot 无法当有效 DTB 加载 → 内核不启动、无网络、卡不被写。
2. **厂商新 u-boot 的 bootflow**：`bootcmd=bootflow scan -bl`，与旧 `distro_bootcmd` 行为不同；**不要混用新内核+旧 u-boot**（我们试过：灯灭）。
3. **RTL8125 驱动**：必须带 `kmod-r8125`（或内核内建），否则网口全灭。
4. **串口波特率 1500000**（不是常见的 115200）。
5. **本机无 eMMC**：任何"检测 eMMC 选择 dtb/分区"的逻辑都要以 R66S 为准。
6. **可写层对齐**：`align256KiB(squashfs_end)`，不要随意改，否则 fstools 找不到已存在的 overlay。
7. **SquashFS 必须 xz**：旧/新都用 xz；改用其他压缩方式会改变 `bytes_used` 与可写层位置（fstools 会自适应，但与原厂布局不一致，验证成本上升）。
8. **ssr-plus alterId**：客户端 alterId>0 即 legacy；Xray 服务端默认强制 AEAD，需要 `env xray.vmess.aead.forced=false`。
9. **不要照搬厂商 196-r10 的装配脚本**（其 dtb 链接 bug 就在装配层）。
10. **LuCI 主题**：`files/etc/config/luci` 指定 design 主题，构建需包含 `luci-theme-design`。

---

## 13. 交付物清单（本目录）

| 文件 | 内容 |
|---|---|
| `README.md` | 本规格 |
| `config.seed` | OpenWrt 目标/镜像/关键包配置骨架 |
| `kernel-old.config` | **旧可用内核完整配置**（4.19.245，5,645 行） |
| `modules-old.txt` / `modules-new.txt` | 两个内核的模块清单（228 / 335） |
| `packages-old.txt` / `packages-new.txt` | 两个系统的完整包+版本（462 / 586） |
| `feeds-old.conf` / `feeds-new.conf` | 两个系统的 opkg feed |
| `boot/vendor-bootchain-512-to-32MiB.bin` | 旧（可用）idbloader/ATF/u-boot/env |
| `boot/old-boot.scr` / `boot/new-boot.scr` | 两版 boot.scr（619 / 555 B） |
| `boot/r66s-rockchip0.dtb` | **R66S 设备树（真实文件，fastrhino,r66s）** |
| `boot/r68s-rockchip1.dtb` | R68S 设备树（仅供参考） |
| `files/` | 用户配置与密钥（构建时复制为 `files/`） |

---

## 14. 决策树（编译结果不理想时）

```text
干净 25.12.x 构建能开机？
├─ 能 → 逐批加插件（ssr-plus → openclash → samba/zerotier…），每批真机验收
└─ 不能（仍然灯灭/无网络）
   ├─ 检查 dtb 是否真实文件、boot.scr 加载路径、r8125 驱动、串口日志
   ├─ 尝试：厂商新 u-boot + 上游 kernel/rootfs（保持同一代）
   └─ 仍不行 → 放弃 6.18 重构，改为：
        保留当前可用的 4.19 系统（已修复的镜像），
        只把 ssr-plus 196-r10（及其 mihomo/xray 组件）作为用户态软件移植过去
        —— 这样能获得 alterId 支持，风险最小
```
