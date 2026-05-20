#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

FAKE_BIN="$WORK_DIR/bin"
REGISTRY_DIR="$WORK_DIR/registry"
OUT_DIR="$WORK_DIR/out"
mkdir -p "$FAKE_BIN" "$REGISTRY_DIR" "$OUT_DIR"

make_fake_package() {
  local platform="$1"
  local binary_name="$2"
  local pkg_dir="$WORK_DIR/pkg-$platform"
  local tarball="$REGISTRY_DIR/$platform.tgz"

  mkdir -p "$pkg_dir/package"
  printf '%s binary\n' "$platform" > "$pkg_dir/package/$binary_name"
  printf 'license\n' > "$pkg_dir/package/LICENSE.md"
  tar -czf "$tarball" -C "$pkg_dir" package

  local shasum
  shasum="$(sha1sum "$tarball" | awk '{print $1}')"
  cat > "$REGISTRY_DIR/$platform.json" <<EOF
{"version":"1.2.3","dist":{"tarball":"https://registry.test/@anthropic-ai/claude-code-${platform}/-/claude-code-${platform}-1.2.3.tgz","shasum":"${shasum}"}}
EOF
}

make_fake_package "linux-x64" "claude"
make_fake_package "win32-x64" "claude.exe"

cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

out_file=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      out_file="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

if [[ "$url" == *"claude-code-linux-x64"* ]]; then
  platform="linux-x64"
elif [[ "$url" == *"claude-code-win32-x64"* ]]; then
  platform="win32-x64"
else
  echo "unexpected URL: $url" >&2
  exit 1
fi

if [[ -n "$out_file" ]]; then
  cp "$REGISTRY_DIR/$platform.tgz" "$out_file"
else
  cat "$REGISTRY_DIR/$platform.json"
fi
EOF
chmod +x "$FAKE_BIN/curl"

(
  cd "$ROOT_DIR"
  PATH="$FAKE_BIN:$PATH" REGISTRY_DIR="$REGISTRY_DIR" VERSION=1.2.3 PLATFORM=linux-x64 \
    ./pack-claude-code.sh "$OUT_DIR"
  PATH="$FAKE_BIN:$PATH" REGISTRY_DIR="$REGISTRY_DIR" VERSION=1.2.3 PLATFORM=win32-x64 \
    ./pack-claude-code.sh "$OUT_DIR"
)

test -f "$OUT_DIR/claude-code-offline-1.2.3-linux-x64.tar.gz"
tar -tzf "$OUT_DIR/claude-code-offline-1.2.3-linux-x64.tar.gz" | grep -q 'claude-code-offline-1.2.3-linux-x64/claude$'
tar -tzf "$OUT_DIR/claude-code-offline-1.2.3-linux-x64.tar.gz" | grep -q 'claude-code-offline-1.2.3-linux-x64/install.sh$'

test -f "$OUT_DIR/claude-code-offline-1.2.3-win32-x64.zip"
unzip -Z1 "$OUT_DIR/claude-code-offline-1.2.3-win32-x64.zip" | grep -q 'claude-code-offline-1.2.3-win32-x64/claude.exe$'
unzip -Z1 "$OUT_DIR/claude-code-offline-1.2.3-win32-x64.zip" | grep -q 'claude-code-offline-1.2.3-win32-x64/install.ps1$'
