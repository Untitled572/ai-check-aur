#!/bin/bash
set -e

if [[ $EUID == 0 ]]; then
  echo "请以普通用户运行 ./install.sh；也可用 ./install.sh --user 完全避免 sudo。" >&2
  exit 1
fi

USER_INSTALL=false
case "${1:-}" in
  --user) USER_INSTALL=true ;;
  '') ;;
  *) echo "用法: $0 [--user]" >&2; exit 1 ;;
esac
[[ $# -le 1 ]] || { echo "用法: $0 [--user]" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${SCRIPT_DIR}/ai-check-pkgbuild"
CONFIG_ENV="${SCRIPT_DIR}/config.env"
INSTALL_DIR="/usr/local/bin"
if [[ $USER_INSTALL == true ]]; then
  INSTALL_DIR="$HOME/.local/bin"
fi
INSTALLED_SCRIPT="$INSTALL_DIR/ai-check-pkgbuild"
HOOK_COMMAND=ai-check-pkgbuild
if [[ $USER_INSTALL == true ]]; then
  printf -v HOOK_COMMAND '%q' "$INSTALLED_SCRIPT"
fi
PARU_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/paru"
PARU_CONFIG_FILE="${PARU_CONF:-$PARU_CONFIG_DIR/paru.conf}"
AI_CHECK_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ai-check-aur"
AI_CHECK_CONFIG_FILE="$AI_CHECK_CONFIG_DIR/config.env"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ai-check-aur"

if [ ! -f "$SCRIPT" ]; then
  echo "Error: $SCRIPT not found"
  exit 1
fi

echo "[install] 安装脚本到 $INSTALLED_SCRIPT"
if [[ $USER_INSTALL == true ]]; then
  install -Dm755 "$SCRIPT" "$INSTALLED_SCRIPT"
else
  sudo install -Dm755 "$SCRIPT" "$INSTALLED_SCRIPT"
fi

echo "[install] 创建缓存目录 $CACHE_DIR"
mkdir -p "$CACHE_DIR"

# Install/update config.env
if [ -f "$CONFIG_ENV" ]; then
  mkdir -p "$AI_CHECK_CONFIG_DIR"
  if [ ! -f "$AI_CHECK_CONFIG_FILE" ]; then
    echo "[install] 安装配置文件到 $AI_CHECK_CONFIG_FILE"
    cp "$CONFIG_ENV" "$AI_CHECK_CONFIG_FILE"
  else
    # Preserve the complete user file; migrate only the retired Xiaomi model.
    # A subshell prevents settings in this file from changing installer paths.
    USER_MODEL=$(source "$AI_CHECK_CONFIG_FILE" && printf '%s' "${AI_CHECK_MODEL:-}")
    if [[ $USER_MODEL == xiaomi/mimo-v2.5 ]]; then
      echo "[install] 将 MiMo 2.5 更新为 MiMo 2.6 Flash（已备份原配置）"
      cp -p "$AI_CHECK_CONFIG_FILE" "$AI_CHECK_CONFIG_FILE.bak"
      printf '\n# MiMo 2.5 已退役，迁移到官方 MiMo 2.6 Flash\nAI_CHECK_MODEL="xiaomi/mimo-v2.6-flash"\n' >> "$AI_CHECK_CONFIG_FILE"
    else
      echo "[install] 保留现有配置: $AI_CHECK_CONFIG_FILE"
    fi
  fi
fi

add_prebuild() {
  local file="$1"
  local updated
  updated=$(AI_CHECK_HOOK_COMMAND="$HOOK_COMMAND" awk '
    BEGIN { command = ENVIRON["AI_CHECK_HOOK_COMMAND"] }
    /^[[:space:]]*\[/ {
      in_bin = ($0 ~ /^[[:space:]]*\[bin\][[:space:]]*(#.*)?$/)
      if (in_bin && !added) {
        print; print "PreBuildCommand = " command; added = 1; next
      }
    }
    in_bin && /^[[:space:]]*PreBuildCommand[[:space:]]*=/ { next }
    { print }
    END { if (!added) print "\n[bin]\nPreBuildCommand = " command }
  ' "$file")
  printf '%s\n' "$updated" > "$file"
}

if [ ! -f "$PARU_CONFIG_FILE" ]; then
  echo "[install] 创建 paru 配置文件 $PARU_CONFIG_FILE"
  mkdir -p "$(dirname -- "$PARU_CONFIG_FILE")"
  # Preserve the system configuration that paru would otherwise have loaded.
  if [[ -f /etc/paru.conf ]]; then
    cp /etc/paru.conf "$PARU_CONFIG_FILE"
  else
    printf '[options]\nCleanAfter\n' > "$PARU_CONFIG_FILE"
  fi
fi

EXISTING_HOOK=$(awk '
  /^[[:space:]]*\[/ { in_bin = ($0 ~ /^[[:space:]]*\[bin\][[:space:]]*(#.*)?$/) }
  in_bin && /^[[:space:]]*PreBuildCommand[[:space:]]*=/ {
    sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*(#.*)?$/, ""); print
  }
' "$PARU_CONFIG_FILE")
if [[ -z $EXISTING_HOOK ]]; then
  echo "[install] 添加 PreBuildCommand 到 $PARU_CONFIG_FILE"
  add_prebuild "$PARU_CONFIG_FILE"
elif [[ $EXISTING_HOOK == "$HOOK_COMMAND" ]]; then
  echo "[install] paru.conf 已配置 PreBuildCommand"
elif [[ $EXISTING_HOOK == ai-check-pkgbuild ||
        $EXISTING_HOOK == /usr/local/bin/ai-check-pkgbuild ||
        $EXISTING_HOOK == "$HOME/.local/bin/ai-check-pkgbuild" ]]; then
  echo "[install] 将 paru 钩子更新为 $HOOK_COMMAND（已备份原配置）"
  cp -p "$PARU_CONFIG_FILE" "$PARU_CONFIG_FILE.bak"
  add_prebuild "$PARU_CONFIG_FILE"
else
  echo "[install] ERROR: $PARU_CONFIG_FILE 已有其他 PreBuildCommand，请手动接入 ai-check-pkgbuild: $EXISTING_HOOK" >&2
  exit 1
fi

echo ""
echo "安装完成！"
echo ""
echo "文件："
echo "  $INSTALLED_SCRIPT                   主脚本"
echo "  $AI_CHECK_CONFIG_FILE               配置文件"
echo "  $PARU_CONFIG_FILE                   paru 配置"
echo ""
echo "修改配置："
echo "  vim $AI_CHECK_CONFIG_FILE"
echo ""
echo "下次执行 paru -Syu 时自动生效。"
echo "临时跳过 AI 审查: AI_CHECK_ENABLED=false paru -Syu"
