#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${SCRIPT_DIR}/ai-check-pkgbuild"
CONFIG_ENV="${SCRIPT_DIR}/config.env"
INSTALL_DIR="/usr/local/bin"
PARU_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/paru"
PARU_CONFIG_FILE="$PARU_CONFIG_DIR/paru.conf"
AI_CHECK_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ai-check-aur"
AI_CHECK_CONFIG_FILE="$AI_CHECK_CONFIG_DIR/config.env"
CACHE_DIR="$HOME/.cache/ai-check-aur"

if [ ! -f "$SCRIPT" ]; then
  echo "Error: $SCRIPT not found"
  exit 1
fi

echo "[install] 安装脚本到 $INSTALL_DIR/$SCRIPT"
sudo install -Dm755 "$SCRIPT" "$INSTALL_DIR/$SCRIPT"

echo "[install] 创建缓存目录 $CACHE_DIR"
mkdir -p "$CACHE_DIR"

# Install config.env
if [ -f "$CONFIG_ENV" ]; then
  mkdir -p "$AI_CHECK_CONFIG_DIR"
  if [ ! -f "$AI_CHECK_CONFIG_FILE" ]; then
    echo "[install] 安装配置文件到 $AI_CHECK_CONFIG_FILE"
    cp "$CONFIG_ENV" "$AI_CHECK_CONFIG_FILE"
  else
    echo "[install] 配置文件已存在: $AI_CHECK_CONFIG_FILE"
  fi
fi

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

if [ ! -f "$PARU_CONFIG_FILE" ]; then
  echo "[install] 创建 paru 配置文件 $PARU_CONFIG_FILE"
  mkdir -p "$PARU_CONFIG_DIR"
  cat > "$PARU_CONFIG_FILE" <<- 'EOF'
[options]
CleanAfter

[bin]
PreBuildCommand = ai-check-pkgbuild
EOF
elif ! grep -qs "PreBuildCommand" "$PARU_CONFIG_FILE"; then
  echo "[install] 添加 PreBuildCommand 到 $PARU_CONFIG_FILE"
  add_prebuild "$PARU_CONFIG_FILE"
else
  echo "[install] paru.conf 已配置 PreBuildCommand"
fi

echo ""
echo "安装完成！"
echo ""
echo "文件："
echo "  $INSTALL_DIR/ai-check-pkgbuild    主脚本"
echo "  $AI_CHECK_CONFIG_FILE              配置文件"
echo "  $PARU_CONFIG_FILE                  paru 配置"
echo ""
echo "修改配置："
echo "  vim $AI_CHECK_CONFIG_FILE"
echo ""
echo "下次执行 paru -Syu 时自动生效。"
echo "临时跳过审查: paru --skipreview -Syu"
