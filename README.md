# claude-code-offline

为内网/离线 Linux x86_64/aarch64 与 Windows x64 环境准备的 [Claude Code](https://docs.claude.com/en/docs/claude-code) 离线安装包。

**最新版本**: `v2.1.221` · [下载](https://github.com/zcimon57-svj/claude-code-offline/releases/latest) · [详细安装步骤](INSTALL.md)

直接使用平台二进制，**无需 Node.js / npm**。Linux 依赖 glibc ≥ 2.17；Windows 使用 `claude.exe`。

## 快速开始

### Linux x64

```bash
curl -fsSLO https://github.com/zcimon57-svj/claude-code-offline/releases/download/v2.1.221/claude-code-offline-2.1.221-linux-x64.tar.gz
tar -xzf claude-code-offline-2.1.221-linux-x64.tar.gz
cd claude-code-offline-2.1.221-linux-x64
./install.sh
claude --version
```

### Linux arm64

```bash
curl -fsSLO https://github.com/zcimon57-svj/claude-code-offline/releases/download/v2.1.221/claude-code-offline-2.1.221-linux-arm64.tar.gz
tar -xzf claude-code-offline-2.1.221-linux-arm64.tar.gz
cd claude-code-offline-2.1.221-linux-arm64
./install.sh
claude --version
```

### Windows x64

```powershell
Invoke-WebRequest -Uri https://github.com/zcimon57-svj/claude-code-offline/releases/download/v2.1.221/claude-code-offline-2.1.221-win32-x64.zip -OutFile claude-code-offline-2.1.221-win32-x64.zip
Expand-Archive claude-code-offline-2.1.221-win32-x64.zip
cd claude-code-offline-2.1.221-win32-x64
powershell -ExecutionPolicy Bypass -File .\install.ps1
claude --version
```

## 仓库内容

- [`INSTALL.md`](INSTALL.md) — 详细安装与排错文档
- [`install.sh`](install.sh) — Linux 离线安装脚本
- [`install.ps1`](install.ps1) — Windows 离线安装脚本
- [`pack-claude-code.sh`](pack-claude-code.sh) — 重新打包脚本（在外网机用）
- Releases — 每个版本一个 `tag = v<version>`，asset 按平台命名

## 重新打包新版本

需要在能访问 `registry.npmjs.org` 的机器上：

```bash
# Linux x64，默认拉 latest
GH_REPO=zcimon57-svj/claude-code-offline GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push

# Windows x64，默认拉 latest
PLATFORM=win32-x64 GH_REPO=zcimon57-svj/claude-code-offline GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push

# 锁定版本
VERSION=2.1.221 PLATFORM=win32-x64 GH_REPO=zcimon57-svj/claude-code-offline GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push

# Linux arm64
PLATFORM=linux-arm64 GH_REPO=zcimon57-svj/claude-code-offline GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push
```
