# 合并构建脚本

脚本：

```text
x86_64/scripts/merged-openwrt-build.sh
```

它把一个 x86/64 PVE 镜像任务和 `y1_y1s/merge_compile_tasks.json` 中的
Y1、Y1s 任务合并为一个远端串行构建：

```text
x86_64 -> y1 -> y1s
```

脚本不会在生成时或上传后自动编译。只有显式执行 `preflight`、`run` 或
`start` 才会进入相应流程。

x86 配置校验后会先执行 `make tools/install` 构建主机工具，避免后续
解包和构建过程缺少 `libdeflate-gzip` 等 OpenWrt 主机工具。
随后执行 `make toolchain/install` 构建目标交叉工具链，确保
`libgcc_s.so`、目标 libc 和编译器在包级门禁之前已经安装。

不要提前调用 `make package/<name>/compile`。这种包级入口可能绕过
`target/linux`，在 `modules.builtin` 尚未生成时错误构建 kernel 包。
正式流程在工具链和下载完成后直接运行完整 `make`，由 OpenWrt 依赖图
保证 kernel、modules、packages 和 images 的顺序；目标软件包由最终
manifest 和 rootfs 验证。

OpenWrt 25.12 的 x86 target 可能只生成
`*-squashfs-combined-efi.img.gz`，而不生成 qcow2。脚本在缺少 qcow2 时
会用 `gzip -dc` 恢复 raw 镜像，再通过 `qemu-img convert -O qcow2 -c`
生成并校验 PVE 可导入的压缩 qcow2；不重新编译固件。

## 推荐远端位置

```text
/home/chenmo/Software/openwrt/lede/.codex-autobuild/x86-pve-aio/
  scripts/merged-openwrt-build.sh
  build.env
```

Y1/Y1s 入口仍使用 JSON 中约定的远端路径：

```text
/home/chenmo/Software/openwrt/lede/.codex-autobuild/y1-y1s/scripts/build-y1.sh
/home/chenmo/Software/openwrt/lede/.codex-autobuild/y1-y1s/scripts/build-y1s.sh
```

## 行为

- 使用
  `/home/chenmo/Software/openwrt/lede/.codex-autobuild/openwrt-build.lock`
  作为全局构建锁。
- x86 使用独立的 OpenWrt 25.12.6 源码树，不覆盖 LEDE 主树配置。
- Y1/Y1s 通过各自的 `run` 前台命令执行，父编排器能准确判断退出码。
- 默认任一任务失败后停止后续任务。
- Y1/Y1s 复用现有内部锁、备份和源码恢复逻辑。
- 编排器另外快照 WNDR3800 的 `.config` 和两个 feed Makefile，并在结束时恢复。
- 日志、状态、PID、任务退出码和制品路径写入脚本上级目录的
  `state/`、`artifacts/`。

## 安装后检查

```sh
bash merged-openwrt-build.sh preflight
```

`preflight` 只检查命令、路径、50 GiB 空间和源码状态，不执行
`make`、下载源码、安装 Feed 或启动构建。

## 批准后的启动方式

```sh
bash merged-openwrt-build.sh start
```

`start` 通过 `setsid nohup` 脱离当前 SSH 会话。SSH 断开后，只要 xps13
没有关机或重启，进程会继续执行。

查看状态：

```sh
bash merged-openwrt-build.sh status
```

## 可选环境文件

将 `x86_64/configs/merged-build.env.example` 复制为远端任务目录下的
`build.env`，设置并行数、DDNS 服务商扩展包或代理。

默认网络代理为：

```text
socks5://192.168.100.1:1080
```

脚本把该地址同时设置到 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY` 和
Git 的 `http.proxy`，用于源码克隆、Feeds、Make 下载器和 Go 模块访问。
可在 `build.env` 中通过 `AUTOBUILD_SOCKS_PROXY` 覆盖。

OpenWrt 的 packages、LuCI、routing 和 telephony Feed 使用相同固定提交的
GitHub 镜像。Feed 更新最多重试四次；失败时未完成的 `.tmp` Feed 会移动
到带时间戳的失败目录，便于恢复和排查。

官方 OpenWrt 25.12 Feed 不提供 `vlmcsd` 和 ZeroTier 的 LuCI 管理页面。
脚本从现有 xps13 Lean Feed 的固定提交中复制以下三个源码包到 x86 Feed：

```text
packages/net/vlmcsd
luci/applications/luci-app-vlmcsd
luci/applications/luci-app-zerotier
```

复制前校验 Lean packages 和 LuCI Feed 的提交，避免使用漂移源码。
复制后执行 `./scripts/feeds update -i`，仅重建本地索引，确保这三个包
能被后续 `feeds install` 和 Kconfig 识别。

OpenWrt 25.12 的 APK 打包器不接受 `svn1113` 这类包版本。脚本保留
上游源码标签 `PKG_SOURCE_VERSION:=svn1113`，同时把公开包版本规范化为
`PKG_VERSION:=1113`，生成 APK 版本 `1113-r5`。

DDNS 服务商尚未确定时，可以仅构建通用 `ddns-scripts` 和
`ddns-scripts-services`。确定服务商后，在 `DDNS_PROVIDER_PACKAGES`
中填写实际的 `ddns-scripts-*` 包名。
