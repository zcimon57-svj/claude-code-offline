# Claude Code 内网离线安装详细步骤

适用环境：Linux x86_64（Euler 2.x / CentOS 7+ / RHEL 7+ / Ubuntu 18.04+），glibc ≥ 2.17，**无需 Node.js**。

---

## 步骤 1：下载离线包

在**能访问 github.com 的机器**上：

```bash
curl -fsSLO https://github.com/zcimon57-svj/claude-code-offline/releases/download/v2.1.139/claude-code-offline-2.1.139-linux-x64.tar.gz
```

或浏览器打开 https://github.com/zcimon57-svj/claude-code-offline/releases/latest 手动下载。

校验下载完整性（可选）：

```bash
ls -lh claude-code-offline-2.1.139-linux-x64.tar.gz   # 大小约 68M
tar -tzf claude-code-offline-2.1.139-linux-x64.tar.gz | head
# 期望看到 claude-code-offline-2.1.139-linux-x64/{claude,install.sh,LICENSE.md,README.txt}
```

---

## 步骤 2：拷贝到内网机

把 `claude-code-offline-2.1.139-linux-x64.tar.gz` 这**一个文件**拷到内网机即可（scp / U盘 / 内部网盘 / 跳板机）。

到内网机后先做环境自检：

```bash
uname -m                  # 期望: x86_64
ldd --version | head -1   # 期望 glibc ≥ 2.17
```

---

## 步骤 3：在内网机安装

```bash
tar -xzf claude-code-offline-2.1.139-linux-x64.tar.gz
cd claude-code-offline-2.1.139-linux-x64
./install.sh
```

`install.sh` 行为：

| 用户身份 | 默认安装位置 |
|---|---|
| root | `/usr/local/bin/claude` |
| 普通用户 | `~/.local/bin/claude` |
| 自定义：`PREFIX=/opt/claude ./install.sh` | `/opt/claude/bin/claude` |

安装时会自动校验 OS / arch / glibc，任一不满足直接报错退出。

如果提示 `~/.local/bin` 不在 PATH：

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## 步骤 4：验证 + 首次登录

```bash
which claude              # 应显示安装路径
claude --version          # 期望: 2.1.139 (Claude Code)
claude                    # 首次启动会跳 OAuth 登录
```

⚠️ 首次启动**必须能访问 `api.anthropic.com`** 完成 OAuth 登录。如果内网严格离线连不上 anthropic 域名：

- 找网管放行 `api.anthropic.com` 与 `console.anthropic.com`
- 或走 Bedrock / Vertex AI 接入（配置 `ANTHROPIC_BEDROCK_BASE_URL` 等环境变量，不在本文档范围）

---

## 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `仅支持 x86_64` | arch 不是 x86_64 | 让外网机用 `PLATFORM=linux-arm64` 重新打包 |
| `需要 glibc >= 2.17` | 系统老于 CentOS 7 | 系统升级，claude 二进制硬性要求 |
| `Permission denied` | 二进制没执行权限 | `chmod +x ~/.local/bin/claude` |
| 启动卡在登录 / 网络错误 | 无法访问 api.anthropic.com | 放行域名或改用 Bedrock |
| `command not found: claude` | PATH 未生效 | `source ~/.bashrc` 或新开 shell |

---

## 升级到新版本

claude 离线安装后**不会**自动检测新版本。要升级：

1. 在外网机重新执行 `pack-claude-code.sh`（默认拉 latest）
2. 把新 tar.gz 拷进内网，按上面步骤 3 重新 `./install.sh` 即可
3. 个人配置在 `~/.claude/` 与 `~/.claude.json`，重装不丢
