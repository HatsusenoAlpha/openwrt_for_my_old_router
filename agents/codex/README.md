# Codex + DeepSeek API

1. 设置 `DEEPSEEK_API_KEY`。
2. 将 `profile-deepseek.config.toml.example` 复制到用户级 Codex 配置目录：

   ```text
   $CODEX_HOME/profile-deepseek.config.toml
   ```

3. 把模板中的模型 ID 和 Responses 兼容网关 URL 替换为真实值。
4. 启动：

   ```sh
   codex --profile deepseek
   ```

Windows 可使用 `install-profile.ps1`，Linux/macOS 可使用
`install-profile.sh`。安装脚本只复制无凭据模板，不会写入 API Key。

官方参考：

- https://developers.openai.com/codex/config-reference/
