#!/bin/bash

# ==========================================================
# 脚本名称: agent_daemon.sh (受控节点 Webhook 守护进程 V1.2)
# 核心功能: 智能防打扰注册、进程防冲突自检、后台静默监听
# ==========================================================

INSTALL_DIR="/opt/ip_sentinel"
CONFIG_FILE="${INSTALL_DIR}/config.conf"
IP_CACHE="${INSTALL_DIR}/core/.last_ip" # 【新增】本地 IP 状态缓存文件

[ ! -f "$CONFIG_FILE" ] && exit 1
source "$CONFIG_FILE"

# 如果没有配置 TG，说明未开启联控模式，直接退出
[ -z "$TG_TOKEN" ] || [ -z "$CHAT_ID" ] && exit 0

# 默认 Webhook 监听端口
AGENT_PORT=${AGENT_PORT:-9527}
NODE_NAME=$(hostname | cut -c 1-15)

# --- [重点升级 1: 守护进程防冲突自检] ---
# 检查是否已经有 webhook 进程在监听当前端口，如果有，直接安静退出 (Cron 友好)
if pgrep -f "webhook.py $AGENT_PORT" > /dev/null; then
    # 保持静默，不输出多余日志，防止打扰系统的 syslog
    exit 0
fi

# 1. 获取本机原生公网 IPv4
AGENT_IP=$(curl -4 -s -m 5 api.ip.sb/ip)

if [ -n "$AGENT_IP" ]; then
    # --- [重点升级 2: 智能防打扰注册机制] ---
    LAST_IP=""
    [ -f "$IP_CACHE" ] && LAST_IP=$(cat "$IP_CACHE")

    # 只有当这是第一次运行，或者公网 IP 发生变动时，才发送 Telegram 申请
    if [ "$AGENT_IP" != "$LAST_IP" ]; then
        REG_MSG="👋 **[边缘节点接入申请]**%0A节点: \`${NODE_NAME}\`%0A地址: \`${AGENT_IP}:${AGENT_PORT}\`%0A%0A⚠️ **安全验证**: 为防止非法节点接入，请长按复制下方代码，并**发送给我**以完成最终授权录入：%0A%0A\`#REGISTER#|${NODE_NAME}|${AGENT_IP}|${AGENT_PORT}\`"
        
        curl -s -m 5 -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" \
            -d "text=${REG_MSG}" \
            -d "parse_mode=Markdown" > /dev/null
        
        echo "✅ [Agent] 已向司令部发送接入申请，请在 Telegram 手机端完成授权！"
        # 记录当前 IP 到缓存文件
        echo "$AGENT_IP" > "$IP_CACHE"
    else
        echo "ℹ️ [Agent] IP 未变动 ($AGENT_IP)，跳过重复注册申请。"
    fi
fi

# 3. 启动轻量级 Python3 Webhook 监听服务
cat > "${INSTALL_DIR}/core/webhook.py" << 'EOF'
import http.server
import socketserver
import subprocess
import sys

PORT = int(sys.argv[1])

class AgentHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # 统一返回成功，防止 Master 请求超时阻塞
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Agent Received Action\n")
        
        # 路由分发
        if self.path == '/trigger_run':
            subprocess.Popen(['bash', '/opt/ip_sentinel/core/mod_google.sh'])
        elif self.path == '/trigger_report':
            subprocess.Popen(['bash', '/opt/ip_sentinel/core/tg_report.sh'])
        elif self.path == '/trigger_log':
            bash_cmd = """
            source /opt/ip_sentinel/config.conf
            LOG_DATA=$(tail -n 15 /opt/ip_sentinel/logs/sentinel.log)
            NODE=$(hostname | cut -c 1-15)
            curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
                -d "chat_id=${CHAT_ID}" \
                -d "text=📄 **[${NODE}] 实时运行日志:**%0A\`\`\`log%0A${LOG_DATA}%0A\`\`\`" \
                -d "parse_mode=Markdown"
            """
            subprocess.Popen(['bash', '-c', bash_cmd])

    def log_message(self, format, *args):
        # 关闭默认的控制台日志输出，保持后台清爽
        pass

try:
    with socketserver.TCPServer(("", PORT), AgentHandler) as httpd:
        httpd.serve_forever()
except Exception as e:
    sys.exit(1)
EOF

# --- [重点升级 3: 真正的静默后台启动] ---
echo "🚀 [Agent] 正在后台启动 Webhook 监听服务 (端口: $AGENT_PORT)..."
# 使用 nohup 和 & 将进程完全推入后台，不阻塞当前终端
nohup python3 "${INSTALL_DIR}/core/webhook.py" "$AGENT_PORT" > /dev/null 2>&1 &

# 尝试脱离终端会话控制 (忽略报错以兼容不同 shell 环境)
disown 2>/dev/null || true

echo "✅ [Agent] 守护进程启动完毕，可安全关闭终端。"