# craft-rea-skills

给 AI coding agent 用的两套「软件取证 / 重建」技能包，一键装到 **Claude Code**、**Codex**（以及 MCP 客户端）：

| 技能 | 作用 | 上游 | 形态 |
|---|---|---|---|
| **Craft Anything** | 盯着任意网站 / 桌面应用 / 手机应用 / 游戏做真实取证式检查（Clean room 或 Deep 模式），然后让 coding agent 用你指定的技术栈重建一份，并自动比对原版直到接近 | [storytold/craft-anything](https://github.com/storytold/craft-anything) | 桌面 App + CLI + MCP server（30 个 Essentials 工具） |
| **REA**（Reverse Engineer Anything） | 二进制 / 托管代码 / Electron-JS / 打包产物 / 固件 / 浏览器目标的逆向工程，输出带证据等级的结论，可对接 Ghidra / IDA / JADX | [morluto/rea](https://github.com/morluto/rea) | npm 包 `rea-agents` + MCP server（207 个工具） |

两者都是 **MCP server + Skill 指令** 的双层结构：Skill 决定 agent 何时用、怎么用；MCP 提供真正干活的工具。

---

## 30 秒安装

### Windows

```powershell
git clone https://github.com/ljh15039080965-prog/craft-rea-skills
cd craft-rea-skills
pwsh -File scripts/install.ps1            # 默认同时配置 claude_code + codex
pwsh -File scripts/verify.ps1             # 验证注册与 MCP 握手
```

### macOS / Linux

```bash
git clone https://github.com/ljh15039080965-prog/craft-rea-skills
cd craft-rea-skills
bash scripts/install.sh
bash scripts/verify.sh
```

装完 **重启 Claude Code / Codex**，工具才会出现在会话里。

---

## 安装脚本干了什么

`scripts/install.ps1`（或 `install.sh`）按顺序执行：

1. **REA**
   - `npx -y rea-agents@6.5.0 setup --client <client> --yes`
   - 写入 MCP 注册（Claude Code 写 `~/.claude.json`，Codex 写 `~/.codex/config.toml`），并把 `reverse-engineer-anything` skill 放进客户端 skills 目录
   - 自带备份：`*.rea.backup.<hash>.recovery`
2. **Craft Anything**
   - 检测不到 `craft-anything-cli` 时，从上游 Release 拉当前平台的包（Windows 为 portable zip）解压到安装目录
   - `craft-anything-cli setup --client <client> --yes`
   - 同时安装 `craft-anything` skill（Claude Code → `~/.claude/skills/`，Codex → `~/.agents/skills/`）
3. 逐项打印 `[configured]` / `[skipped]`，任一步失败只影响该步。

可选参数：

```powershell
pwsh -File scripts/install.ps1 -Client claude_code     # 只配 Claude Code
pwsh -File scripts/install.ps1 -Client codex           # 只配 Codex
pwsh -File scripts/install.ps1 -CraftAnythingDir D:\Tools\craft-anything
pwsh -File scripts/install.ps1 -SkipCraft -SkipRea      # 分开用
```

---

## 客户端支持矩阵

| 客户端 | REA 注册命令 | Craft Anything 注册命令 | 状态 |
|---|---|---|---|
| Claude Code | `npx -y rea-agents@6.5.0 setup --client claude_code --yes` | `craft-anything-cli setup --client claude_code --yes` | ✅ 已验证 |
| Codex | `... --client codex --yes` | `... --client codex --yes` | ✅ 已验证 |
| Claude Desktop | `... --client claude_desktop --yes`（需先完全退出客户端） | `... --client claude_desktop --yes` | 可用 |
| VS Code / OpenCode / Copilot CLI / Cursor | `... --client vscode` 等 | 同名 `--client` | 可用 |
| DeepSeek Harness (DSH) | 手工写 MCP 条目 | 同名手工条目 | 见 `docs/mcp-clients.md` |

REA 支持的 client 完整列表：`npx -y rea-agents@6.5.0 doctor --json` 里的 `clientStates`。

---

## 能不能「直接调用」

- **Skill 层**：装完 skill 后，agent 在会话里看到 `craft-anything` 和 `reverse-engineer-anything` 两个 skill 目录项，可以按描述自动命中，也可以显式点名（`用 craft-anything 看看这个网站`）。
- **MCP 层**：需要 **新开会话 / 重启客户端**。MCP server 是客户端启动时握手注册的，当前已打开的会话不会凭空多出工具。
- **命令行层**：随时可直调，不需要 agent：

```bash
craft-anything-cli doctor
craft-anything-cli commands
craft-anything-cli rebuild https://example.com "Recreate this website"
npx -y rea-agents@6.5.0 doctor --client claude_code --json
```

实测握手结果（本仓库验证基线）：

```
craft-anything  name=craft-anything  version=0.6.1  protocol=2025-06-18  tools=30
rea             name=rea             version=6.5.0  protocol=2025-06-18  tools=207
```

---

## 依赖与可选引擎

| 必需 | 说明 |
|---|---|
| Node.js ≥ 22.19 | REA 运行 `npx rea-agents` 与 `mcp` |
| npm | 同上 |
| 一个已登录的 coding agent | Craft Anything 的 **Build** 阶段要用（Claude Code 一等支持；Codex 适配器存在） |

可选（缺了只是少一路「第二意见」，不影响主流程）：

`Ghidra`（`GHIDRA_INSTALL_DIR`）、`IDA`（`REA_IDA_MCP_CONFIG`）、`JADX`（`REA_JADX_MCP_JAR`）、`Hopper`、`jadx`/`apktool`（需 Java）、`frida`、`gdb`/`lldb`、`mitmdump`、`binwalk`/`unblob`、`tshark`、`objdump`、`rizin`、`ilspycmd`、`vineflower`。

---

## 常见问题

**npm 报 `ECONNREFUSED 127.0.0.1:7897`**
`~/.npmrc` 里写了已关闭的本地代理。安装脚本会自动加 `--proxy=false --https-proxy=false` 绕过；或手工改 `~/.npmrc` 去掉 `proxy` / `https-proxy`。

**Claude Desktop 注册后又消失**
Claude Desktop 运行中会用内存里的配置覆写文件。先完全退出它，再跑 setup，最后启动。

**MCP 工具没出现**
1. `pwsh -File scripts/verify.ps1` 看是 `missing` 还是 `aligned`
2. `aligned` 但仍无工具 → 是没重启客户端，或客户端 MCP 启动报错（看客户端自己的 MCP 日志），不要重复跑 setup
3. `craft-anything-cli doctor` 里 `mcp:self-test` 必须为 `ok`

**Clean room 与 Deep 的区别**
Clean room（默认）：不读目标内部代码/文件/页面源码，只看访客可见的东西（截图、可见文本、测得布局、字体、颜色、间距）。Deep：读代码、文件、JS，可用 Ghidra。Clean room 是 Craft Anything 自身的工具策略，不是操作系统沙箱。

---

## 许可

本仓库只做**分发与安装编排**，不修改上游代码。

- Craft Anything：MIT OR Apache-2.0，Copyright (c) 2026 ArtCraft Team and the Craft Anything contributors。`ArtCraft` 名称、字标、Logo 为其商标，不在代码许可内；本仓库不含任何品牌资源。
- REA（`rea-agents`）：许可见 [morluto/rea](https://github.com/morluto/rea) 仓库 LICENSE。
- 本仓库脚本与文档：MIT。
