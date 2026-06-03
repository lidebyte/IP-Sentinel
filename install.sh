#!/bin/bash
# ==========================================================
# 脚本名称: install.sh (v4.3.0 Bootstrapper)
# 核心功能: 极简引导入口。包含 Ctrl+C 优雅中断与 TTY 终端重连
# ==========================================================

# ----------------------------------------------------------
# [中断防护] 捕获 Ctrl+C 并执行优雅的战场清理
# ----------------------------------------------------------
cleanup_and_exit() {
    echo -e "\n\n\033[33m⚠️ 检测到中断信号 (Ctrl+C)，安装操作已被手动中止。\033[0m"
    echo -e "🧹 正在清理临时沙盒文件..."
    rm -rf "$SECURE_TMP" 2>/dev/null
    exit 1
}
# 绑定中断信号
trap cleanup_and_exit INT QUIT TERM
trap 'rm -rf "$SECURE_TMP" 2>/dev/null' EXIT HUP

if [ "$EUID" -ne 0 ]; then
  echo -e "\033[31m❌ 权限被拒绝: 部署 IP-Sentinel 需要最高系统权限。\033[0m"
  exit 1
fi

SECURE_TMP=$(mktemp -d /tmp/ips_install.XXXXXX)
REPO_RAW_URL="https://raw.githubusercontent.com/hotyue/IP-Sentinel/feature/v4.3.0-modular"

echo -e "\n⏳ 正在拉取 IP-Sentinel v4.3.0 安装模块引擎..."

curl -fsSL --connect-timeout 10 --retry 3 "${REPO_RAW_URL}/install/build_agent.sh" -o "${SECURE_TMP}/build_agent.sh"

if [ ! -s "${SECURE_TMP}/build_agent.sh" ]; then
    echo -e "\033[31m❌ 致命错误：核心安装引擎拉取失败！\033[0m"
    exit 1
fi

export SECURE_TMP
export REPO_RAW_URL
chmod +x "${SECURE_TMP}/build_agent.sh"

# ==========================================================
# 【核心黑科技】强制终端重连 (TTY Re-attach)
# 彻底粉碎 curl | bash 管道流劫持，将 stdin 交还给键盘！
# ==========================================================
exec < /dev/tty

source "${SECURE_TMP}/build_agent.sh"
exit 0
