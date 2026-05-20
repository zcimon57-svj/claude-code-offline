#!/usr/bin/env bash
# 在【外网机器】运行：下载 Claude Code 平台二进制 + 安装脚本，打包成离线安装包
# 用法:
#   ./pack-claude-code.sh [输出目录] [--push]
# 环境变量:
#   PLATFORM      目标平台（默认 linux-x64）。常用取值: linux-x64, linux-arm64, win32-x64
#   NPM_REGISTRY  registry 地址（默认 https://registry.npmjs.org）
#   VERSION       指定版本号（默认 latest）
#   GH_REPO       --push 时使用的 GitHub 仓库（如 user/claude-code-offline）
#   GH_TOKEN      --push 时使用的 GitHub PAT（需 repo scope）
set -euo pipefail

REGISTRY="${NPM_REGISTRY:-https://registry.npmjs.org}"
PLATFORM="${PLATFORM:-linux-x64}"
PKG="@anthropic-ai/claude-code-${PLATFORM}"

case "$PLATFORM" in
  linux-x64)
    OS_NAME="Linux"
    ARCH_NAME="x86_64"
    ARCHIVE_EXT="tar.gz"
    CONTENT_TYPE="application/gzip"
    BINARY_NAME="claude"
    INSTALLER_NAME="install.sh"
    ;;
  linux-arm64)
    OS_NAME="Linux"
    ARCH_NAME="aarch64"
    ARCHIVE_EXT="tar.gz"
    CONTENT_TYPE="application/gzip"
    BINARY_NAME="claude"
    INSTALLER_NAME="install.sh"
    ;;
  win32-x64)
    OS_NAME="Windows"
    ARCH_NAME="x64"
    ARCHIVE_EXT="zip"
    CONTENT_TYPE="application/zip"
    BINARY_NAME="claude.exe"
    INSTALLER_NAME="install.ps1"
    ;;
  *)
    echo "不支持的平台: $PLATFORM" >&2
    echo "当前脚本支持: linux-x64, linux-arm64, win32-x64" >&2
    exit 1
    ;;
esac

# 解析参数：第一个非 --push 的位置参数当作 OUT_DIR
PUSH=0
OUT_DIR="."
for arg in "$@"; do
  case "$arg" in
    --push) PUSH=1 ;;
    -*)     echo "未知选项: $arg" >&2; exit 1 ;;
    *)      OUT_DIR="$arg" ;;
  esac
done

for cmd in curl tar; do
  command -v "$cmd" >/dev/null || { echo "缺少依赖: $cmd" >&2; exit 1; }
done
if [[ "$ARCHIVE_EXT" == "zip" ]]; then
  command -v zip >/dev/null || { echo "缺少依赖: zip" >&2; exit 1; }
fi

# ---- 1. 查询版本与 tarball URL ----
if [[ -n "${VERSION:-}" ]]; then
  META_URL="$REGISTRY/$PKG/$VERSION"
else
  META_URL="$REGISTRY/$PKG/latest"
fi
echo "查询: $META_URL"
META=$(curl -fsSL "$META_URL")

if command -v jq >/dev/null; then
  VERSION=$(echo "$META" | jq -r '.version')
  TARBALL_URL=$(echo "$META" | jq -r '.dist.tarball')
  SHASUM=$(echo "$META" | jq -r '.dist.shasum // empty')
else
  VERSION=$(echo "$META" | grep -oE '"version":"[^"]+"' | head -1 | cut -d'"' -f4)
  TARBALL_URL=$(echo "$META" | grep -oE '"tarball":"[^"]+"' | head -1 | cut -d'"' -f4)
  SHASUM=$(echo "$META" | grep -oE '"shasum":"[^"]+"' | head -1 | cut -d'"' -f4 || true)
fi
[[ -n "$VERSION" && -n "$TARBALL_URL" ]] || { echo "解析 registry 失败" >&2; exit 1; }

# ---- 2. 临时工作区 ----
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

BUNDLE_NAME="claude-code-offline-${VERSION}-${PLATFORM}"
BUNDLE_DIR="$WORK/$BUNDLE_NAME"
mkdir -p "$BUNDLE_DIR"

# ---- 3. 下载并校验 ----
echo "[1/3] 下载 ${PKG}@${VERSION}"
curl -fSL --retry 5 --retry-delay 2 --retry-all-errors --progress-bar -o "$WORK/pkg.tgz" "$TARBALL_URL"

if [[ -n "${SHASUM:-}" ]] && command -v sha1sum >/dev/null; then
  ACTUAL=$(sha1sum "$WORK/pkg.tgz" | awk '{print $1}')
  if [[ "$ACTUAL" != "$SHASUM" ]]; then
    echo "ERROR: SHA1 校验失败 (expected $SHASUM, got $ACTUAL)" >&2
    exit 1
  fi
  echo "       SHA1 ✓ $ACTUAL"
fi

# ---- 4. 提取平台二进制 + LICENSE ----
echo "[2/3] 提取二进制"
tar -xzf "$WORK/pkg.tgz" -C "$WORK" "package/$BINARY_NAME" package/LICENSE.md 2>/dev/null \
  || tar -xzf "$WORK/pkg.tgz" -C "$WORK" "package/$BINARY_NAME"
cp "$WORK/package/$BINARY_NAME" "$BUNDLE_DIR/$BINARY_NAME"
[[ -f "$WORK/package/LICENSE.md" ]] && cp "$WORK/package/LICENSE.md" "$BUNDLE_DIR/LICENSE.md"
[[ "$BINARY_NAME" == "claude" ]] && chmod +x "$BUNDLE_DIR/$BINARY_NAME"

# ---- 5. 写入安装脚本 ----
if [[ "$PLATFORM" == linux-* ]]; then
  cat > "$BUNDLE_DIR/install.sh" <<INSTALL_EOF
#!/usr/bin/env bash
# Claude Code 离线安装脚本（在内网 ${OS_NAME} 机器运行）
# 用法:
#   ./install.sh
#   PREFIX=/opt/claude ./install.sh
set -euo pipefail

SCRIPT_DIR="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" && pwd )"
BIN_SRC="\$SCRIPT_DIR/claude"

[[ -f "\$BIN_SRC" ]] || { echo "ERROR: 找不到 \$BIN_SRC（应与 install.sh 同目录）" >&2; exit 1; }

[[ "\$(uname -s)" == "Linux" ]] || { echo "ERROR: 仅支持 Linux" >&2; exit 1; }
if [[ "${PLATFORM}" == "linux-x64" ]]; then
  [[ "\$(uname -m)" == "x86_64" ]] || { echo "ERROR: 仅支持 x86_64（当前 \$(uname -m)）" >&2; exit 1; }
else
  [[ "\$(uname -m)" == "aarch64" || "\$(uname -m)" == "arm64" ]] || { echo "ERROR: 仅支持 arm64/aarch64（当前 \$(uname -m)）" >&2; exit 1; }
fi

if command -v ldd >/dev/null; then
  GLIBC_VER=\$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "")
  if [[ -n "\$GLIBC_VER" ]]; then
    GMAJ=\${GLIBC_VER%.*}
    GMIN=\${GLIBC_VER#*.}
    if (( GMAJ < 2 || (GMAJ == 2 && GMIN < 17) )); then
      echo "ERROR: 需要 glibc >= 2.17，当前 \$GLIBC_VER" >&2
      exit 1
    fi
    echo "glibc: \$GLIBC_VER ✓"
  fi
fi

if [[ -n "\${PREFIX:-}" ]]; then
  :
elif [[ \$EUID -eq 0 ]]; then
  PREFIX="/usr/local"
else
  PREFIX="\$HOME/.local"
fi
DEST_DIR="\$PREFIX/bin"
DEST="\$DEST_DIR/claude"

mkdir -p "\$DEST_DIR"
echo "安装到: \$DEST"
install -m 0755 "\$BIN_SRC" "\$DEST"

case ":\$PATH:" in
  *":\$DEST_DIR:"*) ;;
  *)
    echo ""
    echo "提示: \$DEST_DIR 不在 PATH 中。请把下面这行加到 ~/.bashrc 或 ~/.profile："
    echo "    export PATH=\"\$DEST_DIR:\$PATH\""
    ;;
esac

echo ""
echo "安装完成: \$DEST"
"\$DEST" --version 2>/dev/null || echo "(首次启动可能需要执行 'claude' 完成认证)"
INSTALL_EOF
  chmod +x "$BUNDLE_DIR/install.sh"
else
  cat > "$BUNDLE_DIR/install.ps1" <<'INSTALL_EOF'
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinSrc = Join-Path $ScriptDir "claude.exe"
if (-not (Test-Path $BinSrc)) {
  throw "Cannot find claude.exe next to install.ps1"
}

$InstallDir = if ($env:PREFIX) { Join-Path $env:PREFIX "bin" } else { Join-Path $env:LOCALAPPDATA "Programs\ClaudeCode" }
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$Dest = Join-Path $InstallDir "claude.exe"
Copy-Item -Force $BinSrc $Dest

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathParts = @()
if ($userPath) { $pathParts = $userPath -split ";" | Where-Object { $_ } }
if ($pathParts -notcontains $InstallDir) {
  $newPath = if ($userPath) { "$userPath;$InstallDir" } else { $InstallDir }
  [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
  Write-Host "Added to user PATH: $InstallDir"
  Write-Host "Open a new PowerShell window before running claude from PATH."
}

Write-Host "Installed: $Dest"
& $Dest --version
INSTALL_EOF
fi

# ---- 6. 写入 README ----
if [[ "$PLATFORM" == win32-* ]]; then
  INSTALL_STEPS="  Expand-Archive ${BUNDLE_NAME}.zip
  cd ${BUNDLE_NAME}
  powershell -ExecutionPolicy Bypass -File .\\install.ps1"
else
  INSTALL_STEPS="  tar -xzf ${BUNDLE_NAME}.tar.gz
  cd ${BUNDLE_NAME}
  ./install.sh"
fi

cat > "$BUNDLE_DIR/README.txt" <<EOF
Claude Code 离线安装包
======================
版本:   ${VERSION}
平台:   ${PLATFORM}
打包于: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

安装步骤:
${INSTALL_STEPS}

文件:
  ${BINARY_NAME}        - Claude Code 主二进制（无 Node.js 依赖）
  ${INSTALLER_NAME}    - 离线安装脚本
  LICENSE.md    - 许可证

首次运行 'claude' 时需要登录认证（需联通 Anthropic API），
若内网受限请联系管理员开通 api.anthropic.com / console.anthropic.com 白名单，
或参考企业版 Bedrock / Vertex AI 接入方案。
EOF

# ---- 7. 打包 ----
echo "[3/3] 打包"
mkdir -p "$OUT_DIR"
OUT_DIR_ABS=$(cd "$OUT_DIR" && pwd)
OUT_FILE="$OUT_DIR_ABS/${BUNDLE_NAME}.${ARCHIVE_EXT}"
if [[ "$ARCHIVE_EXT" == "zip" ]]; then
  (cd "$WORK" && zip -qr "$OUT_FILE" "$BUNDLE_NAME")
else
  tar -czf "$OUT_FILE" -C "$WORK" "$BUNDLE_NAME"
fi

SIZE=$(stat -c%s "$OUT_FILE" 2>/dev/null || stat -f%z "$OUT_FILE")
HUMAN=$(numfmt --to=iec "$SIZE" 2>/dev/null || echo "$SIZE bytes")

cat <<EOF

✓ 打包完成
   $OUT_FILE  ($HUMAN)

把这一个文件拷到内网，然后:
${INSTALL_STEPS}
EOF

# ---- 8. 推送到 GitHub（可选）----
if [[ "$PUSH" -eq 1 ]]; then
  : "${GH_REPO:?--push 需要 GH_REPO 环境变量（如 user/claude-code-offline）}"
  : "${GH_TOKEN:?--push 需要 GH_TOKEN 环境变量}"
  command -v git >/dev/null || { echo "缺少 git" >&2; exit 1; }
  command -v jq >/dev/null || { echo "缺少 jq" >&2; exit 1; }

  echo ""
  echo "[push 1/3] 同步 docs 到 GitHub: $GH_REPO"
  REPO_WORK=$(mktemp -d)
  trap 'rm -rf "$WORK" "$REPO_WORK"' EXIT
  AUTH_URL="https://x-access-token:${GH_TOKEN}@github.com/${GH_REPO}.git"

  if git clone --quiet "$AUTH_URL" "$REPO_WORK" 2>/dev/null; then
    :
  else
    git -c init.defaultBranch=main init -q "$REPO_WORK"
    git -C "$REPO_WORK" remote add origin "$AUTH_URL"
  fi

  cp "$0" "$REPO_WORK/pack-claude-code.sh" 2>/dev/null || true
  cp "$BUNDLE_DIR/LICENSE.md" "$REPO_WORK/LICENSE.md" 2>/dev/null || true
  if [[ "$PLATFORM" == linux-* ]]; then
    cp "$BUNDLE_DIR/install.sh" "$REPO_WORK/install.sh"
  else
    cp "$BUNDLE_DIR/install.ps1" "$REPO_WORK/install.ps1"
  fi

  cat > "$REPO_WORK/README.md" <<README_EOF
# claude-code-offline

为内网/离线 Linux x86_64/aarch64 与 Windows x64 环境准备的 [Claude Code](https://docs.claude.com/en/docs/claude-code) 离线安装包。

**最新版本**: \`v${VERSION}\` · [下载](https://github.com/${GH_REPO}/releases/latest) · [详细安装步骤](INSTALL.md)

直接使用平台二进制，**无需 Node.js / npm**。Linux 依赖 glibc ≥ 2.17；Windows 使用 \`claude.exe\`。

## 快速开始

### Linux x64

\`\`\`bash
curl -fsSLO https://github.com/${GH_REPO}/releases/download/v${VERSION}/claude-code-offline-${VERSION}-linux-x64.tar.gz
tar -xzf claude-code-offline-${VERSION}-linux-x64.tar.gz
cd claude-code-offline-${VERSION}-linux-x64
./install.sh
claude --version
\`\`\`

### Windows x64

\`\`\`powershell
Invoke-WebRequest -Uri https://github.com/${GH_REPO}/releases/download/v${VERSION}/claude-code-offline-${VERSION}-win32-x64.zip -OutFile claude-code-offline-${VERSION}-win32-x64.zip
Expand-Archive claude-code-offline-${VERSION}-win32-x64.zip
cd claude-code-offline-${VERSION}-win32-x64
powershell -ExecutionPolicy Bypass -File .\\install.ps1
claude --version
\`\`\`

## 仓库内容

- [\`INSTALL.md\`](INSTALL.md) — 详细安装与排错文档
- [\`install.sh\`](install.sh) — Linux 离线安装脚本
- [\`install.ps1\`](install.ps1) — Windows 离线安装脚本
- [\`pack-claude-code.sh\`](pack-claude-code.sh) — 重新打包脚本（在外网机用）
- Releases — 每个版本一个 \`tag = v<version>\`，asset 按平台命名

## 重新打包新版本

需要在能访问 \`registry.npmjs.org\` 的机器上：

\`\`\`bash
# Linux x64，默认拉 latest
GH_REPO=${GH_REPO} GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push

# Windows x64，默认拉 latest
PLATFORM=win32-x64 GH_REPO=${GH_REPO} GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push

# 锁定版本
VERSION=${VERSION} PLATFORM=win32-x64 GH_REPO=${GH_REPO} GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push

# Linux arm64
PLATFORM=linux-arm64 GH_REPO=${GH_REPO} GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push
\`\`\`
README_EOF

  cat > "$REPO_WORK/INSTALL.md" <<INSTALL_DOC_EOF
# Claude Code 内网离线安装详细步骤

适用环境：

| 平台 | 包名 | 安装脚本 |
|---|---|---|
| Linux x64 | \`claude-code-offline-${VERSION}-linux-x64.tar.gz\` | \`install.sh\` |
| Linux arm64 | \`claude-code-offline-${VERSION}-linux-arm64.tar.gz\` | \`install.sh\` |
| Windows x64 | \`claude-code-offline-${VERSION}-win32-x64.zip\` | \`install.ps1\` |

Linux 需要 glibc ≥ 2.17。所有平台首次运行都需要能访问 Anthropic 服务完成认证。

## 下载

在能访问 github.com 的机器上打开 https://github.com/${GH_REPO}/releases/latest ，下载对应平台 asset。

Linux x64:

\`\`\`bash
curl -fsSLO https://github.com/${GH_REPO}/releases/download/v${VERSION}/claude-code-offline-${VERSION}-linux-x64.tar.gz
\`\`\`

Windows x64:

\`\`\`powershell
Invoke-WebRequest -Uri https://github.com/${GH_REPO}/releases/download/v${VERSION}/claude-code-offline-${VERSION}-win32-x64.zip -OutFile claude-code-offline-${VERSION}-win32-x64.zip
\`\`\`

## Linux 安装

\`\`\`bash
tar -xzf claude-code-offline-${VERSION}-linux-x64.tar.gz
cd claude-code-offline-${VERSION}-linux-x64
./install.sh
claude --version
\`\`\`

\`install.sh\` 行为：

| 用户身份 | 默认安装位置 |
|---|---|
| root | \`/usr/local/bin/claude\` |
| 普通用户 | \`~/.local/bin/claude\` |
| 自定义：\`PREFIX=/opt/claude ./install.sh\` | \`/opt/claude/bin/claude\` |

如果提示安装目录不在 PATH，把脚本输出的 \`export PATH=...\` 加到 shell 配置中。

## Windows 安装

\`\`\`powershell
Expand-Archive claude-code-offline-${VERSION}-win32-x64.zip
cd claude-code-offline-${VERSION}-win32-x64
powershell -ExecutionPolicy Bypass -File .\\install.ps1
claude --version
\`\`\`

\`install.ps1\` 默认安装到 \`%LOCALAPPDATA%\\Programs\\ClaudeCode\\claude.exe\`，并写入当前用户 PATH。安装后请打开新的 PowerShell 窗口再运行 \`claude\`。

自定义安装位置：

\`\`\`powershell
\$env:PREFIX = "C:\\Tools\\ClaudeCode"
powershell -ExecutionPolicy Bypass -File .\\install.ps1
\`\`\`

## 重新打包新版本

\`\`\`bash
# Linux x64
GH_REPO=${GH_REPO} GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push

# Windows x64
PLATFORM=win32-x64 GH_REPO=${GH_REPO} GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push

# Linux arm64
PLATFORM=linux-arm64 GH_REPO=${GH_REPO} GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push
\`\`\`

## 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| \`仅支持 x86_64\` / \`仅支持 arm64/aarch64\` | 下载的平台包与机器架构不一致 | 下载匹配平台的 release asset |
| \`需要 glibc >= 2.17\` | Linux 系统过老 | 升级系统或换较新发行版 |
| Windows 安装后 \`claude\` 不可用 | 当前 PowerShell 还没刷新 PATH | 重新打开 PowerShell |
| 启动卡在登录 / 网络错误 | 无法访问 Anthropic 服务 | 放行 \`api.anthropic.com\` 与 \`console.anthropic.com\`，或改用企业接入 |
INSTALL_DOC_EOF

  cd "$REPO_WORK"
  git -c user.name="claude-code-offline-bot" -c user.email="bot@users.noreply.github.com" add -A >/dev/null
  if git -c user.name="claude-code-offline-bot" -c user.email="bot@users.noreply.github.com" diff --cached --quiet; then
    echo "  docs 无变化，跳过 commit"
  else
    git -c user.name="claude-code-offline-bot" -c user.email="bot@users.noreply.github.com" \
        commit -q -m "Release v${VERSION}: docs + installers"
    git push -q origin HEAD:main 2>&1 | sed "s/${GH_TOKEN}/***/g"
    echo "  ✓ docs 已推送到 main"
  fi
  cd - >/dev/null
  rm -rf "$REPO_WORK"

  echo "[push 2/3] 创建/更新 Release v${VERSION}"
  REL_API="https://api.github.com/repos/${GH_REPO}/releases"
  REL_ID=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "$REL_API/tags/v${VERSION}" | jq -r '.id // empty')
  if [[ -n "$REL_ID" ]]; then
    echo "  Release v${VERSION} 已存在 (id=$REL_ID)，删除同名旧 asset"
    curl -s -H "Authorization: Bearer $GH_TOKEN" "$REL_API/${REL_ID}/assets" \
      | jq -r ".[] | select(.name==\"${BUNDLE_NAME}.${ARCHIVE_EXT}\") | .id" \
      | while read -r AID; do
          [[ -n "$AID" ]] && curl -sf -X DELETE -H "Authorization: Bearer $GH_TOKEN" \
            "https://api.github.com/repos/${GH_REPO}/releases/assets/$AID"
        done
  else
    REL_ID=$(curl -sf -X POST -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" "$REL_API" \
      -d "{\"tag_name\":\"v${VERSION}\",\"name\":\"v${VERSION}\",\"body\":\"Claude Code ${VERSION} offline packages.\\nSee README.md / INSTALL.md.\"}" \
      | jq -r '.id')
    echo "  ✓ Release v${VERSION} 已创建 (id=$REL_ID)"
  fi

  echo "[push 3/3] 上传 asset ${BUNDLE_NAME}.${ARCHIVE_EXT} ($HUMAN)"
  curl -sf -X POST -H "Authorization: Bearer $GH_TOKEN" \
    -H "Content-Type: ${CONTENT_TYPE}" \
    --data-binary "@$OUT_FILE" \
    "https://uploads.github.com/repos/${GH_REPO}/releases/${REL_ID}/assets?name=${BUNDLE_NAME}.${ARCHIVE_EXT}" \
    >/dev/null
  echo "  ✓ asset 上传完成"

  echo ""
  echo "====================================================="
  echo "✓ GitHub 发布完成"
  echo "  仓库:   https://github.com/${GH_REPO}"
  echo "  Release: https://github.com/${GH_REPO}/releases/tag/v${VERSION}"
  echo "  下载:   https://github.com/${GH_REPO}/releases/download/v${VERSION}/${BUNDLE_NAME}.${ARCHIVE_EXT}"
  echo "====================================================="
fi
