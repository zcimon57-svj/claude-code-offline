# Claude Code 内网离线安装详细步骤

适用环境：

| 平台 | 包名 | 安装脚本 |
|---|---|---|
| Linux x64 | `claude-code-offline-2.1.221-linux-x64.tar.gz` | `install.sh` |
| Linux arm64 | `claude-code-offline-2.1.221-linux-arm64.tar.gz` | `install.sh` |
| Windows x64 | `claude-code-offline-2.1.221-win32-x64.zip` | `install.ps1` |

Linux 需要 glibc ≥ 2.17。所有平台首次运行都需要能访问 Anthropic 服务完成认证。

## 下载

在能访问 github.com 的机器上打开 https://github.com/zcimon57-svj/claude-code-offline/releases/latest ，下载对应平台 asset。

Linux x64:

```bash
curl -fsSLO https://github.com/zcimon57-svj/claude-code-offline/releases/download/v2.1.221/claude-code-offline-2.1.221-linux-x64.tar.gz
```

Linux arm64:

```bash
curl -fsSLO https://github.com/zcimon57-svj/claude-code-offline/releases/download/v2.1.221/claude-code-offline-2.1.221-linux-arm64.tar.gz
```

Windows x64:

```powershell
Invoke-WebRequest -Uri https://github.com/zcimon57-svj/claude-code-offline/releases/download/v2.1.221/claude-code-offline-2.1.221-win32-x64.zip -OutFile claude-code-offline-2.1.221-win32-x64.zip
```

## Linux 安装

```bash
tar -xzf claude-code-offline-2.1.221-linux-x64.tar.gz
cd claude-code-offline-2.1.221-linux-x64
./install.sh
claude --version
```

`install.sh` 行为：

| 用户身份 | 默认安装位置 |
|---|---|
| root | `/usr/local/bin/claude` |
| 普通用户 | `~/.local/bin/claude` |
| 自定义：`PREFIX=/opt/claude ./install.sh` | `/opt/claude/bin/claude` |

如果提示安装目录不在 PATH，把脚本输出的 `export PATH=...` 加到 shell 配置中。

## Windows 安装

```powershell
Expand-Archive claude-code-offline-2.1.221-win32-x64.zip
cd claude-code-offline-2.1.221-win32-x64
powershell -ExecutionPolicy Bypass -File .\install.ps1
claude --version
```

`install.ps1` 默认安装到 `%LOCALAPPDATA%\Programs\ClaudeCode\claude.exe`，并写入当前用户 PATH。安装后请打开新的 PowerShell 窗口再运行 `claude`。

自定义安装位置：

```powershell
$env:PREFIX = "C:\Tools\ClaudeCode"
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

## 重新打包新版本

```bash
# Linux x64
GH_REPO=zcimon57-svj/claude-code-offline GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push

# Windows x64
PLATFORM=win32-x64 GH_REPO=zcimon57-svj/claude-code-offline GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push

# Linux arm64
PLATFORM=linux-arm64 GH_REPO=zcimon57-svj/claude-code-offline GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push
```

## 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `仅支持 x86_64` / `仅支持 arm64/aarch64` | 下载的平台包与机器架构不一致 | 下载匹配平台的 release asset |
| `需要 glibc >= 2.17` | Linux 系统过老 | 升级系统或换较新发行版 |
| Windows 安装后 `claude` 不可用 | 当前 PowerShell 还没刷新 PATH | 重新打开 PowerShell |
| 启动卡在登录 / 网络错误 | 无法访问 Anthropic 服务 | 放行 `api.anthropic.com` 与 `console.anthropic.com`，或改用企业接入 |
