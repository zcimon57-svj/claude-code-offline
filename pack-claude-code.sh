#!/usr/bin/env bash
# 在【外网机器】运行：下载 Claude Code 平台二进制 + 安装脚本，打包成单个 tar.gz
# 用法:
#   ./pack-claude-code.sh [输出目录] [--push]
# 环境变量:
#   PLATFORM      目标平台（默认 linux-x64）。其它取值: linux-arm64, darwin-x64, darwin-arm64
#   NPM_REGISTRY  registry 地址（默认 https://registry.npmjs.org）
#   VERSION       指定版本号（默认 latest）
#   GH_REPO       --push 时使用的 GitHub 仓库（如 user/claude-code-offline）
#   GH_TOKEN      --push 时使用的 GitHub PAT（需 repo scope）
set -euo pipefail

REGISTRY="${NPM_REGISTRY:-https://registry.npmjs.org}"
PLATFORM="${PLATFORM:-linux-x64}"
PKG="@anthropic-ai/claude-code-${PLATFORM}"

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
curl -fSL --progress-bar -o "$WORK/pkg.tgz" "$TARBALL_URL"

if [[ -n "${SHASUM:-}" ]] && command -v sha1sum >/dev/null; then
  ACTUAL=$(sha1sum "$WORK/pkg.tgz" | awk '{print $1}')
  if [[ "$ACTUAL" != "$SHASUM" ]]; then
    echo "ERROR: SHA1 校验失败 (expected $SHASUM, got $ACTUAL)" >&2
    exit 1
  fi
  echo "       SHA1 ✓ $ACTUAL"
fi

# ---- 4. 提取 claude 二进制 + LICENSE ----
echo "[2/3] 提取二进制"
tar -xzf "$WORK/pkg.tgz" -C "$WORK" package/claude package/LICENSE.md 2>/dev/null \
  || tar -xzf "$WORK/pkg.tgz" -C "$WORK" package/claude
cp "$WORK/package/claude" "$BUNDLE_DIR/claude"
[[ -f "$WORK/package/LICENSE.md" ]] && cp "$WORK/package/LICENSE.md" "$BUNDLE_DIR/LICENSE.md"
chmod +x "$BUNDLE_DIR/claude"

# ---- 5. 写入安装脚本 ----
cat > "$BUNDLE_DIR/install.sh" <<'INSTALL_EOF'
#!/usr/bin/env bash
# Claude Code 离线安装脚本（在【内网机器】运行）
# 用法:
#   ./install.sh                # root 装到 /usr/local/bin，普通用户装到 ~/.local/bin
#   PREFIX=/opt/claude ./install.sh    # 自定义安装前缀（最终装到 $PREFIX/bin/claude）
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BIN_SRC="$SCRIPT_DIR/claude"

[[ -f "$BIN_SRC" ]] || { echo "ERROR: 找不到 $BIN_SRC（应与 install.sh 同目录）" >&2; exit 1; }

# ---- 平台校验 ----
[[ "$(uname -s)" == "Linux"  ]] || { echo "ERROR: 仅支持 Linux" >&2; exit 1; }
[[ "$(uname -m)" == "x86_64" ]] || { echo "ERROR: 仅支持 x86_64（当前 $(uname -m)）" >&2; exit 1; }

# ---- glibc 校验（需要 >= 2.17）----
if command -v ldd >/dev/null; then
  GLIBC_VER=$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "")
  if [[ -n "$GLIBC_VER" ]]; then
    GMAJ=${GLIBC_VER%.*}
    GMIN=${GLIBC_VER#*.}
    if (( GMAJ < 2 || (GMAJ == 2 && GMIN < 17) )); then
      echo "ERROR: 需要 glibc >= 2.17，当前 $GLIBC_VER" >&2
      exit 1
    fi
    echo "glibc: $GLIBC_VER ✓"
  fi
fi

# ---- 选择安装目录 ----
if [[ -n "${PREFIX:-}" ]]; then
  :
elif [[ $EUID -eq 0 ]]; then
  PREFIX="/usr/local"
else
  PREFIX="$HOME/.local"
fi
DEST_DIR="$PREFIX/bin"
DEST="$DEST_DIR/claude"

mkdir -p "$DEST_DIR"
echo "安装到: $DEST"
install -m 0755 "$BIN_SRC" "$DEST"

# ---- PATH 提示 ----
case ":$PATH:" in
  *":$DEST_DIR:"*) ;;
  *)
    echo ""
    echo "⚠️  $DEST_DIR 不在 PATH 中。请把下面这行加到 ~/.bashrc 或 ~/.profile："
    echo "    export PATH=\"$DEST_DIR:\$PATH\""
    ;;
esac

echo ""
echo "✓ 安装完成: $DEST"
"$DEST" --version 2>/dev/null || echo "(首次启动可能需要执行 'claude' 完成认证)"
INSTALL_EOF
chmod +x "$BUNDLE_DIR/install.sh"

# ---- 6. 写入 README ----
cat > "$BUNDLE_DIR/README.txt" <<EOF
Claude Code 离线安装包
======================
版本:   ${VERSION}
平台:   ${PLATFORM}
打包于: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

安装步骤（在内网机器执行）:
  tar -xzf ${BUNDLE_NAME}.tar.gz
  cd ${BUNDLE_NAME}
  ./install.sh

文件:
  claude        - Claude Code 主二进制（无 Node.js 依赖）
  install.sh    - 离线安装脚本
  LICENSE.md    - 许可证

首次运行 'claude' 时需要登录认证（需联通 Anthropic API），
若内网受限请联系管理员开通 api.anthropic.com / console.anthropic.com 白名单，
或参考企业版 Bedrock / Vertex AI 接入方案。
EOF

# ---- 7. 打包 ----
echo "[3/3] 打包"
mkdir -p "$OUT_DIR"
OUT_DIR_ABS=$(cd "$OUT_DIR" && pwd)
OUT_FILE="$OUT_DIR_ABS/${BUNDLE_NAME}.tar.gz"
tar -czf "$OUT_FILE" -C "$WORK" "$BUNDLE_NAME"

SIZE=$(stat -c%s "$OUT_FILE" 2>/dev/null || stat -f%z "$OUT_FILE")
HUMAN=$(numfmt --to=iec "$SIZE" 2>/dev/null || echo "$SIZE bytes")

cat <<EOF

✓ 打包完成
   $OUT_FILE  ($HUMAN)

把这一个文件拷到内网，然后:
   tar -xzf ${BUNDLE_NAME}.tar.gz
   cd ${BUNDLE_NAME}
   ./install.sh
EOF

# ---- 8. 推送到 GitHub（可选）----
if [[ "$PUSH" -eq 1 ]]; then
  : "${GH_REPO:?--push 需要 GH_REPO 环境变量（如 user/claude-code-offline）}"
  : "${GH_TOKEN:?--push 需要 GH_TOKEN 环境变量}"
  command -v git >/dev/null || { echo "缺少 git" >&2; exit 1; }

  echo ""
  echo "[push 1/3] 同步 docs 到 GitHub: $GH_REPO"
  REPO_WORK=$(mktemp -d)
  trap 'rm -rf "$WORK" "$REPO_WORK"' EXIT
  AUTH_URL="https://x-access-token:${GH_TOKEN}@github.com/${GH_REPO}.git"

  # clone（空仓库会失败，那就 init）
  if git clone --quiet "$AUTH_URL" "$REPO_WORK" 2>/dev/null; then
    :
  else
    git -c init.defaultBranch=main init -q "$REPO_WORK"
    git -C "$REPO_WORK" remote add origin "$AUTH_URL"
  fi

  # 复制 install.sh + pack-claude-code.sh + 当前打的 tar.gz 不进 git（走 release）
  cp "$BUNDLE_DIR/install.sh"        "$REPO_WORK/install.sh"
  cp "$BUNDLE_DIR/LICENSE.md"        "$REPO_WORK/LICENSE.md" 2>/dev/null || true
  cp "$0"                            "$REPO_WORK/pack-claude-code.sh" 2>/dev/null || true

  # README.md
  cat > "$REPO_WORK/README.md" <<README_EOF
# claude-code-offline

为内网/离线 Linux x86_64 环境（Euler / CentOS 7+ / RHEL 7+）准备的 [Claude Code](https://docs.claude.com/en/docs/claude-code) 离线安装包。

**最新版本**: \`v${VERSION}\` · [下载](https://github.com/${GH_REPO}/releases/latest) · [详细安装步骤](INSTALL.md)

直接使用 bun 静态编译的独立二进制，**无需 Node.js / npm**，仅依赖 glibc ≥ 2.17。

## 快速开始

\`\`\`bash
# 1. 在能访问 github 的机器下载离线包
curl -fsSLO https://github.com/${GH_REPO}/releases/download/v${VERSION}/${BUNDLE_NAME}.tar.gz

# 2. 拷到内网机后
tar -xzf ${BUNDLE_NAME}.tar.gz
cd ${BUNDLE_NAME}
./install.sh
claude --version
\`\`\`

## 系统要求

| 项目 | 要求 |
|---|---|
| OS | Linux |
| 架构 | x86_64（如需 arm64 见下方"重新打包"） |
| glibc | ≥ 2.17（CentOS 7 / Euler 2.x / 较新发行版均满足） |
| 网络 | 首次启动需访问 \`api.anthropic.com\` 完成 OAuth 登录 |

## 仓库内容

- [\`INSTALL.md\`](INSTALL.md) — 详细安装与排错文档
- [\`install.sh\`](install.sh) — 离线安装脚本（与 release tar.gz 内同一份，方便单独查看）
- [\`pack-claude-code.sh\`](pack-claude-code.sh) — 重新打包脚本（在外网机用）
- Releases — 每个版本一个 \`tag = v<version>\`，asset 是 \`${BUNDLE_NAME%-${VERSION}-${PLATFORM}}-<version>-${PLATFORM}.tar.gz\`

## 重新打包新版本

需要在能访问 \`registry.npmjs.org\` 的机器上：

\`\`\`bash
# 默认拉 latest
GH_REPO=${GH_REPO} GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push

# 或锁定版本
VERSION=2.1.119 GH_REPO=${GH_REPO} GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push

# 或换平台
PLATFORM=linux-arm64 GH_REPO=${GH_REPO} GH_TOKEN=ghp_xxx ./pack-claude-code.sh ./out --push
\`\`\`
README_EOF

  # INSTALL.md（操作文档）
  cat > "$REPO_WORK/INSTALL.md" <<INSTALL_DOC_EOF
# Claude Code 内网离线安装详细步骤

适用环境：Linux x86_64（Euler 2.x / CentOS 7+ / RHEL 7+ / Ubuntu 18.04+），glibc ≥ 2.17，**无需 Node.js**。

---

## 步骤 1：下载离线包

在**能访问 github.com 的机器**上：

\`\`\`bash
curl -fsSLO https://github.com/${GH_REPO}/releases/download/v${VERSION}/${BUNDLE_NAME}.tar.gz
\`\`\`

或浏览器打开 https://github.com/${GH_REPO}/releases/latest 手动下载。

校验下载完整性（可选）：

\`\`\`bash
ls -lh ${BUNDLE_NAME}.tar.gz   # 大小约 ${HUMAN}
tar -tzf ${BUNDLE_NAME}.tar.gz | head
# 期望看到 ${BUNDLE_NAME}/{claude,install.sh,LICENSE.md,README.txt}
\`\`\`

---

## 步骤 2：拷贝到内网机

把 \`${BUNDLE_NAME}.tar.gz\` 这**一个文件**拷到内网机即可（scp / U盘 / 内部网盘 / 跳板机）。

到内网机后先做环境自检：

\`\`\`bash
uname -m                  # 期望: x86_64
ldd --version | head -1   # 期望 glibc ≥ 2.17
\`\`\`

---

## 步骤 3：在内网机安装

\`\`\`bash
tar -xzf ${BUNDLE_NAME}.tar.gz
cd ${BUNDLE_NAME}
./install.sh
\`\`\`

\`install.sh\` 行为：

| 用户身份 | 默认安装位置 |
|---|---|
| root | \`/usr/local/bin/claude\` |
| 普通用户 | \`~/.local/bin/claude\` |
| 自定义：\`PREFIX=/opt/claude ./install.sh\` | \`/opt/claude/bin/claude\` |

安装时会自动校验 OS / arch / glibc，任一不满足直接报错退出。

如果提示 \`~/.local/bin\` 不在 PATH：

\`\`\`bash
echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> ~/.bashrc
source ~/.bashrc
\`\`\`

---

## 步骤 4：验证 + 首次登录

\`\`\`bash
which claude              # 应显示安装路径
claude --version          # 期望: ${VERSION} (Claude Code)
claude                    # 首次启动会跳 OAuth 登录
\`\`\`

⚠️ 首次启动**必须能访问 \`api.anthropic.com\`** 完成 OAuth 登录。如果内网严格离线连不上 anthropic 域名：

- 找网管放行 \`api.anthropic.com\` 与 \`console.anthropic.com\`
- 或走 Bedrock / Vertex AI 接入（配置 \`ANTHROPIC_BEDROCK_BASE_URL\` 等环境变量，不在本文档范围）

---

## 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| \`仅支持 x86_64\` | arch 不是 x86_64 | 让外网机用 \`PLATFORM=linux-arm64\` 重新打包 |
| \`需要 glibc >= 2.17\` | 系统老于 CentOS 7 | 系统升级，claude 二进制硬性要求 |
| \`Permission denied\` | 二进制没执行权限 | \`chmod +x ~/.local/bin/claude\` |
| 启动卡在登录 / 网络错误 | 无法访问 api.anthropic.com | 放行域名或改用 Bedrock |
| \`command not found: claude\` | PATH 未生效 | \`source ~/.bashrc\` 或新开 shell |

---

## 升级到新版本

claude 离线安装后**不会**自动检测新版本。要升级：

1. 在外网机重新执行 \`pack-claude-code.sh\`（默认拉 latest）
2. 把新 tar.gz 拷进内网，按上面步骤 3 重新 \`./install.sh\` 即可
3. 个人配置在 \`~/.claude/\` 与 \`~/.claude.json\`，重装不丢
INSTALL_DOC_EOF

  # commit & push
  cd "$REPO_WORK"
  git -c user.name="claude-code-offline-bot" -c user.email="bot@users.noreply.github.com" add -A >/dev/null
  if git -c user.name="claude-code-offline-bot" -c user.email="bot@users.noreply.github.com" diff --cached --quiet; then
    echo "  docs 无变化，跳过 commit"
  else
    git -c user.name="claude-code-offline-bot" -c user.email="bot@users.noreply.github.com" \
        commit -q -m "Release v${VERSION}: docs + install.sh"
    git push -q origin HEAD:main 2>&1 | sed "s/${GH_TOKEN}/***/g"
    echo "  ✓ docs 已推送到 main"
  fi
  cd - >/dev/null
  rm -rf "$REPO_WORK"

  # ---- Release + 上传 asset ----
  echo "[push 2/3] 创建/更新 Release v${VERSION}"
  REL_API="https://api.github.com/repos/${GH_REPO}/releases"
  REL_ID=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "$REL_API/tags/v${VERSION}" | jq -r '.id // empty')
  if [[ -n "$REL_ID" ]]; then
    echo "  Release v${VERSION} 已存在 (id=$REL_ID)，删除同名旧 asset"
    curl -s -H "Authorization: Bearer $GH_TOKEN" "$REL_API/${REL_ID}/assets" \
      | jq -r ".[] | select(.name==\"${BUNDLE_NAME}.tar.gz\") | .id" \
      | while read -r AID; do
          [[ -n "$AID" ]] && curl -sf -X DELETE -H "Authorization: Bearer $GH_TOKEN" \
            "https://api.github.com/repos/${GH_REPO}/releases/assets/$AID"
        done
  else
    REL_ID=$(curl -sf -X POST -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" "$REL_API" \
      -d "{\"tag_name\":\"v${VERSION}\",\"name\":\"v${VERSION}\",\"body\":\"Claude Code ${VERSION} offline package for Linux ${PLATFORM#linux-}.\\nSee README.md / INSTALL.md.\"}" \
      | jq -r '.id')
    echo "  ✓ Release v${VERSION} 已创建 (id=$REL_ID)"
  fi

  echo "[push 3/3] 上传 asset ${BUNDLE_NAME}.tar.gz ($HUMAN)"
  curl -sf -X POST -H "Authorization: Bearer $GH_TOKEN" \
    -H "Content-Type: application/gzip" \
    --data-binary "@$OUT_FILE" \
    "https://uploads.github.com/repos/${GH_REPO}/releases/${REL_ID}/assets?name=${BUNDLE_NAME}.tar.gz" \
    >/dev/null
  echo "  ✓ asset 上传完成"

  echo ""
  echo "====================================================="
  echo "✓ GitHub 发布完成"
  echo "  仓库:   https://github.com/${GH_REPO}"
  echo "  Release: https://github.com/${GH_REPO}/releases/tag/v${VERSION}"
  echo "  下载:   https://github.com/${GH_REPO}/releases/download/v${VERSION}/${BUNDLE_NAME}.tar.gz"
  echo "====================================================="
fi
