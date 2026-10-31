# 新计算机迁移说明

## 1. 克隆仓库

```sh
git clone git@github.com:HatsusenoAlpha/openwrt_for_my_old_router.git
cd openwrt_for_my_old_router
```

仓库不包含固件、Flash 备份或磁盘镜像。

## 2. 基础工具

需要：

- Git 和 OpenSSH
- Codex
- Node.js 与 `@deepseek-ai/dsh`
- PowerShell 7 或 Bash
- 可选：Python 3、OpenWrt 编译依赖

Windows 安装 dsh：

```powershell
npm install -g @deepseek-ai/dsh
dsh --version
```

## 3. 本地环境变量

```powershell
Copy-Item .env.example .env.local
.\scripts\load-agent-env.ps1
```

Linux/macOS：

```sh
cp .env.example .env.local
source scripts/load-agent-env.sh
```

至少设置：

```text
DEEPSEEK_API_KEY
```

Codex 自定义 provider 还需要一个兼容 Responses API 的网关 URL 和模型 ID。

## 4. Codex + DeepSeek API

官方 Codex 配置参考：

https://developers.openai.com/codex/config-reference/

重要约束：

- 自定义 provider 使用 `model_providers.<id>`、`base_url`、`env_key`。
- Codex 当前只支持 `wire_api = "responses"`。
- provider/auth 配置必须放在用户级 Codex 配置中，项目级
  `.codex/config.toml` 会忽略这些字段。

复制模板：

```text
agents/codex/profile-deepseek.config.toml.example
```

到：

```text
$CODEX_HOME/profile-deepseek.config.toml
```

默认 `CODEX_HOME` 通常是 `~/.codex`。然后运行：

```sh
codex --profile deepseek
```

如果 DeepSeek 端点仅支持 Chat Completions，需要先通过独立兼容网关转换为
Responses API；不要假设 `api.deepseek.com` 的普通 `/v1` 接口可直接被 Codex
当作 Responses API 使用。

## 5. dsh（DeepSeek Harness）

当前验证版本：`0.2.0-rc.2`。

```powershell
$env:DEEPSEEK_API_KEY = '<set locally>'
dsh --profile headless "Read AGENTS.md and summarize the build plans"
```

dsh 默认 home 为 `~/.dsh`，也可以设置：

```text
DSH_HOME
```

API Key provider 使用：

```text
DEEPSEEK_API_KEY
```

自定义覆盖模板位于：

```text
agents/dsh/cordis.patch.yml.example
```

使用前先检查现有 `$DSH_HOME/cordis.patch.yml`，只合并必要条目，不能直接覆盖
其他 profile 或用户配置。

## 6. OpenWrt 源码

本仓库只保存方案和脚本。构建前需要在新计算机或 SSH 远端准备 OpenWrt 源码。
历史环境使用：

```text
xps13:/home/chenmo/Software/openwrt/lede
```

如果源码路径变化，请同步修改各构建脚本中的 `SOURCE_ROOT` 或远端路径。

## 7. 预检

Windows：

```powershell
.\scripts\validate-workspace.ps1
```

Linux/macOS：

```sh
./scripts/validate-workspace.sh
```

预检会确认仓库远端、关键方案文件、Agent 工具以及不应被 Git 跟踪的固件目录。
