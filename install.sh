#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${SCRIPT_DIR}/ai-check-pkgbuild"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/paru"
CONFIG_FILE="$CONFIG_DIR/paru.conf"
CACHE_DIR="$HOME/.cache/ai-check-aur"

if [ ! -f "$SCRIPT" ]; then
  echo "Error: $SCRIPT not found"
  exit 1
fi

echo "[install] 安装脚本到 $INSTALL_DIR/$SCRIPT"
sudo install -Dm755 "$SCRIPT" "$INSTALL_DIR/$SCRIPT"

echo "[install] 创建缓存目录 $CACHE_DIR"
mkdir -p "$CACHE_DIR"

add_prebuild() {
  local file="$1"
  if grep -qs "^\[bin\]" "$file" 2>/dev/null; then
    sed -i '/^\[bin\]/a PreBuildCommand = ai-check-pkgbuild' "$file"
  else
    echo "" >> "$file"
    echo "[bin]" >> "$file"
    echo "PreBuildCommand = ai-check-pkgbuild" >> "$file"
  fi
}

if [ ! -f "$CONFIG_FILE" ]; then
  echo "[install] 创建 paru 配置文件 $CONFIG_FILE"
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<- 'EOF'
[options]
CleanAfter

[bin]
PreBuildCommand = ai-check-pkgbuild
EOF
elif ! grep -qs "PreBuildCommand" "$CONFIG_FILE"; then
  echo "[install] 添加 PreBuildCommand 到 $CONFIG_FILE"
  add_prebuild "$CONFIG_FILE"
else
  echo "[install] paru.conf 已配置 PreBuildCommand"
fi

echo ""
echo "安装完成！检查项："
echo "  - $INSTALL_DIR/$SCRIPT"
echo "  - $CACHE_DIR"
echo "  - $CONFIG_FILE"
echo ""
echo "下次执行 paru -Syu 时自动生效。"
echo "如需临时跳过审查: paru --skipreview -Syu"
