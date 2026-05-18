# claude-code-offline

为内网/离线 Linux x86_64 环境（Euler / CentOS 7+ / RHEL 7+）准备的 [Claude Code](https://docs.claude.com/en/docs/claude-code) 离线安装包。

**最新版本**: `v2.1.143` · [下载](https://github.com/zcimon57-svj/claude-code-offline/releases/latest) · [详细安装步骤](INSTALL.md)

直接使用 bun 静态编译的独立二进制，**无需 Node.js / npm**，仅依赖 glibc ≥ 2.17。

## 快速开始

```bash
# 1. 在能访问 github 的机器下载离线包
curl -fsSLO https://github.com/zcimon57-svj/claude-code-offline/releases/download/v2.1.143/claude-code-offline-2.1.143-linux-x64.tar.gz

# 2. 拷到内网机后
tar -xzf claude-code-offline-2.1.143-linux-x64.tar.gz
cd claude-code-offline-2.1.143-linux-x64
./install.sh
claude --version
```

## 系统要求

| 项目 | 要求 |
|---|---|
| OS | Linux |
| 架构 | x86_64（如需 arm64 见下方"重新打包"） |
| glibc | ≥ 2.17（CentOS 7 / Euler 2.x / 较新发行版均满足） |
| 网络 | 首次启动需访问 `api.anthropic.com` 完成 OAuth 登录 |

## 仓库内容

- [`INSTALL.md`](INSTALL.md) — 详细安装与排错文档
- [`install.sh`](install.sh) — 离线安装脚本（与 release tar.gz 内同一份，方便单独查看）
- [`pack-claude-code.sh`](pack-claude-code.sh) — 重新打包脚本（在外网机用）
- Releases — 每个版本一个 `tag = v<version>`，asset 是 `claude-code-offline-<version>-linux-x64.tar.gz`

## 重新打包新版本

需要在能访问 `registry.npmjs.org` 的机器上：

```bash
# 默认拉 latest
GH_REPO=zcimon57-svj/claude-code-offline GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push

# 或锁定版本
VERSION=2.1.119 GH_REPO=zcimon57-svj/claude-code-offline GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push

# 或换平台
PLATFORM=linux-arm64 GH_REPO=zcimon57-svj/claude-code-offline GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push
```
