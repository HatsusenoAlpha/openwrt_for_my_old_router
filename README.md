# OpenWrt for Old Routers

可迁移的 OpenWrt 构建方案、设备配置、验证记录和无人值守编译脚本。

## 当前目标

- NETGEAR WNDR3800（ath79 / MIPS32 big-endian）
- Lenovo Newifi Y1 / Y1s（ramips / MIPS32 little-endian）
- x86/64 OpenWrt / PVE 构建方案

## 重要约束

- 本仓库不保存固件、完整 Flash 备份或磁盘镜像。
- `artifacts/`、`backup/`、`r66s/` 以及常见固件扩展名均被 `.gitignore` 排除。
- API Key、SSH 密码和本机凭据不得提交。
- 正式编译必须有用户明确授权。

## 新计算机快速开始

```powershell
git clone git@github.com:HatsusenoAlpha/openwrt_for_my_old_router.git
cd openwrt_for_my_old_router
Copy-Item .env.example .env.local
.\scripts\validate-workspace.ps1
```

详细步骤见 [新计算机迁移说明](docs/new_computer_setup.md)。

## Agent 入口

Codex 和 DeepSeek Harness（`dsh`）都应先阅读根目录 [AGENTS.md](AGENTS.md)。

- Codex + DeepSeek 配置模板：`agents/codex/`
- dsh profile 覆盖模板：`agents/dsh/`
- 远端编译任务清单：`y1_y1s/merge_compile_tasks.json`
- x86_64 构建说明：`x86_64/docs/merged-openwrt-build.md`
- Y1/Y1s 编译方案：`y1_y1s/compile_plan.md`
- WNDR3800 主方案：`compile_plan.md`、`agent_execution_plan.md`

## 远端构建环境

历史构建使用 SSH 主机别名 `xps13`，OpenWrt 源码位于：

```text
/home/chenmo/Software/openwrt/lede
```

源码树本身不在本仓库中。新计算机必须自行准备 OpenWrt 源码、工具链和 feed，
然后按照各设备方案执行。

## 固件产物

固件只保存在本地或远端工作目录，不通过 GitHub 同步。需要转移固件时使用
SCP、U 盘或其他文件传输方式。
