# 手工注册 MCP（脚本之外的方式）

自动脚本覆盖不到时（例如 DeepSeek Harness、远程容器、自定义客户端），按下面的片段自己写配置。

两个 server 的关键参数：

| server 名 | 启动命令 | 说明 |
|---|---|---|
| `rea` | `cmd.exe /d /c npx -y rea-agents@6.5.0 mcp`（Windows）<br>`npx -y rea-agents@6.5.0 mcp`（macOS/Linux） | 207 个工具。首次运行会下载 npm 包 |
| `craft-anything` | `<craft-anything-cli 绝对路径> mcp` | 30 个 Essentials 工具。不需要 npx |

> 若 `~/.npmrc` 里有失效代理，把 `npx` 换成 `npx --proxy=false --https-proxy=false`。

---

## Claude Code / Claude Desktop（JSON）

`~/.claude.json`（Claude Code）或 `~/Library/Application Support/Claude/claude_desktop_config.json`（macOS 桌面版）、`%APPDATA%\Claude\claude_desktop_config.json`（Windows 桌面版）：

```json
{
  "mcpServers": {
    "rea": {
      "command": "cmd.exe",
      "args": ["/d", "/c", "npx", "-y", "rea-agents@6.5.0", "mcp"]
    },
    "craft-anything": {
      "command": "C:\\Users\\<you>\\Tools\\craft-anything\\craft-anything-0.6.1-windows-x64-portable\\craft-anything-cli.exe",
      "args": ["mcp"]
    }
  }
}
```

macOS / Linux 下 `rea` 直接写：

```json
{ "mcpServers": { "rea": { "command": "npx", "args": ["-y", "rea-agents@6.5.0", "mcp"] } } }
```

## Codex（TOML）

`~/.codex/config.toml`：

```toml
[mcp_servers.rea]
command = "cmd.exe"
args = ["/d", "/c", "npx", "-y", "rea-agents@6.5.0", "mcp"]

[mcp_servers.craft-anything]
command = 'C:\Users\<you>\Tools\craft-anything\craft-anything-0.6.1-windows-x64-portable\craft-anything-cli.exe'
args = ["mcp"]
```

## VS Code / Cursor / OpenCode / Copilot CLI

`mcp.json` 系（VS Code：`%APPDATA%\Code\User\mcp.json`；Cursor：`~/.cursor/mcp.json`）：

```json
{
  "servers": {
    "rea": { "type": "stdio", "command": "npx", "args": ["-y", "rea-agents@6.5.0", "mcp"] },
    "craft-anything": { "type": "stdio", "command": "<craft-anything-cli 绝对路径>", "args": ["mcp"] }
  }
}
```

也可以让工具自己写：`npx -y rea-agents@6.5.0 setup --client vscode --yes`、`craft-anything-cli setup --client vscode --yes`。

## DeepSeek Harness (DSH)

REA 的 doctor 会把 DSH 列为「手工配置」：在 DSH 自己的 MCP 配置里加一个 stdio server，命令同上（`rea` / `craft-anything`），`args: ["mcp"]`，然后重启 harness 会话。

## Grok Bot（托管端）

Grok Bot 的连接器存在账号里，不读本地 `mcp.json`。在 Grok Bot 对话里新增自定义 MCP server，名字 `rea`，运行在 Bot 的机器上，命令 `npx -y rea-agents@<ver> mcp`。不要把凭据写进命令或参数。

## 参数说明（craft-anything-cli mcp）

```
--all-tools       列出全部工具而非 Essentials + 已启用 toolset
--restricted      共享主机模式：关闭操作机器的工具，默认关闭 web/capture
--allow-web       配合 --restricted 打开 web_site_open
--allow-capture   配合 --restricted 打开抓取类工具
--allow-run       允许不需要询问就执行代码 / 改设备
--deep            本次运行开启 Deep 模式（可读目标代码、文件、页面源码）
--clean-room      本次运行强制 Clean room（不读目标内部）
--inbox <dir>     把人要回答的问题 / 待批操作写到目录里，由 Craft Anything App 应答
```

## 排查顺序

1. `npx -y rea-agents@6.5.0 doctor --client <client> --json` → 看 `registrations[].state`
2. `craft-anything-cli doctor` → `mcp:self-test` 必须是 `ok`
3. `node scripts/probe-mcp.mjs <cli 路径>` → 真实握手 + 工具数
4. 都 ok 但客户端里没工具 → 客户端没重启，或客户端自己的 MCP 启动日志报错（不要重复跑 setup）
