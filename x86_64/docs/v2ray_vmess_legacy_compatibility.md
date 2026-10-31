# V2Ray 与旧版 VMess 兼容性结论

验证日期：2026-10-24

## 结论

`v2ray-core 5.2.0` 和 `5.47.0` 核心本身都支持 2018 年前后常见的
旧版 VMess：

- 节点使用非零 `alterId` 时，客户端走旧版 VMess MD5 头部兼容路径。
- 节点使用 `alterId=0` 时，客户端走 VMess AEAD。
- 远程 VMess 服务端必须与客户端使用相同的 UUID、`alterId`、加密方式和传输设置。

但当前仓库中的 `luci-app-ssr-plus` 配置生成器没有把 `alterId` 写进
V2Ray JSON，订阅解析器还会忽略带非零 `aid` 的 VMess 链接。因此，
**仅替换为 V2Ray 5.2.0 核心不能保证 SSR Plus+ 可连接旧节点**。

## 源码依据

V2Ray 5.2.0 的 `proxy/vmess/outbound/outbound.go` 包含：

```go
isAEAD := false
if !aeadDisabled && len(account.AlterIDs) == 0 {
    isAEAD = true
}
```

`proxy/vmess/account.go` 使用以下字段建立旧版备用 ID：

```go
AlterIDs: protocol.NewAlterIDs(protoID, uint16(a.AlterId))
```

客户端编码器在 `isAEAD == false` 时使用 MD5 时间摘要、旧版响应密钥
派生和 AES 请求头加密路径。V2Ray 5.2.0、5.47.0 和检查时的最新版
5.53.0 都保留此分支。

## SSR Plus+ 集成缺口

当前 `luci-app-ssr-plus` 存在两个需要修补的位置：

1. `root/usr/share/shadowsocksr/subscribe.lua`

   解析 VMess 链接时没有保存 `aid`，并在 `aid > 0` 时将
   `result.server` 清空，导致旧节点无法正常导入。

2. `root/usr/share/shadowsocksr/gen_config.lua`

   `vmess_vless()` 只生成 `id`、`security` 和 VLESS `encryption`，
   没有生成 VMess `alterId`。V2Ray 会因此按 `alterId=0` 使用 AEAD，
   无法连接要求非零 `alterId` 的旧服务端。

客户端 LuCI 页面也需要一个 `alter_id` 数值字段，以便手动填写旧节点
参数，而不只依赖订阅导入。

## 必须应用的兼容补丁

实现阶段应在 SSR Plus+ 包源码中加入以下逻辑，并在
`make defconfig` 和镜像打包后再次确认：

```text
订阅导入：
  result.alter_id = tonumber(info.aid) or 0
  不得因 aid > 0 清空 result.server

配置生成：
  vmess 节点写入 alterId = tonumber(server.alter_id or server.aid) or 0
  vless 节点不写入 alterId

LuCI：
  增加 alter_id 数值输入项，默认 0，仅对 VMess 显示
```

兼容补丁必须随镜像进入 `/usr/share/shadowsocksr/gen_config.lua` 和
`subscribe.lua`，不能只修改本地方案文档。

## 端到端验证

已在 xps13 的 `/tmp` 中执行本地互操作测试：

- 客户端：V2Ray 5.2.0 Linux x86_64。
- 服务端：V2Ray 4.45.2 Linux x86_64，`alterId=64`。
- 服务端设置 `v2ray.vmess.aead.forced=false`，模拟 2018 年旧服务端
  接受非 AEAD VMess。
- V2Ray 5.2.0 客户端配置 `alterId=64`。
- V2Ray 5.47.0 客户端使用相同配置再次测试。
- 通过客户端 SOCKS 入站访问本地 HTTP 服务。

结果：

```text
HTTP_CODE=200
服务端日志：
Critical Warning: a non VMessAEAD connection is received
127.0.0.1:47368 accepted tcp:127.0.0.1:18080
```

上述两组测试都证明核心能够协商并传输旧版 VMess，但不等同于已连接
用户的实际远程节点。最终验收仍必须使用脱敏后的真实节点参数进行实际
访问测试。

测试配置保存在：

```text
tools/v2ray_compat/server-v4.45.2-legacy-aid64.json
tools/v2ray_compat/client-v5.2.0-legacy-aid64.json
```

以上配置只使用回环地址和测试 UUID，不包含真实凭据。

## VLESS 评估

`v2ray-core 5.2.0` 和 `5.47.0` 都已包含 VLESS 入站、出站和配置解析
代码，固定版 SSR Plus+ v190 也能生成 VLESS 节点配置。因此增加 VLESS
支持不需要升级到更高版本的核心。

面向 OpenWrt 25.12.6 的正式方案建议固定 5.47.0，因为：

- 已实际验证旧 VMess 兼容路径。
- 官方二进制使用 Go 1.26，与 OpenWrt 25.12 的 Go 工具链匹配。
- VLESS 已在该版本中可用。
- SSR Plus+ v190 仍保留 V2Ray 核心选择。

当前最新 SSR Plus+ 已移除 V2Ray 核心选项，现代 Xray VMess 客户端只实现
AEAD 路径，因此不能直接替代固定版 v190。

检查时 V2Fly 最新版为 5.53.0，源码仍保留旧 VMess 客户端分支，并提供
VLESS。只有在 5.47.0 在实际节点验收中出现无法修复的问题时，才考虑升级，
且必须重新执行旧 VMess 互操作测试。
