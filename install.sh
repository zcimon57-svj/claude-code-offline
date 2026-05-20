#!/usr/bin/env bash
# Claude Code 离线安装脚本（在内网 Linux 机器运行）
# 用法:
#   ./install.sh
#   PREFIX=/opt/claude ./install.sh
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BIN_SRC="$SCRIPT_DIR/claude"

[[ -f "$BIN_SRC" ]] || { echo "ERROR: 找不到 $BIN_SRC（应与 install.sh 同目录）" >&2; exit 1; }

[[ "$(uname -s)" == "Linux" ]] || { echo "ERROR: 仅支持 Linux" >&2; exit 1; }
[[ "$(uname -m)" == "x86_64" ]] || { echo "ERROR: 仅支持 x86_64（当前 $(uname -m)）" >&2; exit 1; }

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

case ":$PATH:" in
  *":$DEST_DIR:"*) ;;
  *)
    echo ""
    echo "提示: $DEST_DIR 不在 PATH 中。请把下面这行加到 ~/.bashrc 或 ~/.profile："
    echo "    export PATH=\"$DEST_DIR:$PATH\""
    ;;
esac

echo ""
echo "安装完成: $DEST"
"$DEST" --version 2>/dev/null || echo "(首次启动可能需要执行 'claude' 完成认证)"
