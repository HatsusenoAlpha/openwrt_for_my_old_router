# dsh（DeepSeek Harness）

验证版本：`0.2.0-rc.2`。

## 安装

```sh
npm install -g @deepseek-ai/dsh
dsh --version
```

## 凭据

官方 API Key 插件默认读取：

```text
DEEPSEEK_API_KEY
```

不要把 Key 写入仓库。可设置 `DSH_HOME` 隔离 profile；默认 home 是 `~/.dsh`。

## 启动

在当前工程根目录执行：

```sh
dsh --profile headless "Read AGENTS.md and summarize the active build plans"
dsh --profile web
```

dsh 将当前目录作为默认工作区。

## 自定义 Provider 覆盖

参考 `@deepseek-ai/dsh-llm-deepseek-api-key` 的配置格式并合并：

```text
agents/dsh/cordis.patch.yml.example
```

目标位置可以是：

```text
$DSH_HOME/cordis.patch.yml
```

或指定 profile 的 `cordis.patch.yml`。合并前先检查现有内容；不要覆盖其他用户
配置。

检查组合后的配置：

```sh
dsh --profile headless --dump-config
```

## 本工程任务入口

先阅读 `AGENTS.md`。Y1/Y1s 的三任务合并清单位于：

```text
y1_y1s/merge_compile_tasks.json
```
