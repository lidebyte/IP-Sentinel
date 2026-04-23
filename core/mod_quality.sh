#!/bin/bash
# ==========================================================
# IP-Sentinel: 深海声呐 (IP 质量全维异步检测模块)
# ==========================================================

source /opt/ip_sentinel/config.conf

TARGET_IP=$(echo "${BIND_IP:-$PUBLIC_IP}" | tr -d '[]')
IP_PROTO="${IP_PREF:-4}"

# 1. 静默拉取 JSON
JSON_DATA=$(timeout 180 bash <(curl -sL https://IP.Check.Place) -y -j -${IP_PROTO} -i "${TARGET_IP}" 2>/dev/null)

if [ -z "$JSON_DATA" ]; then
    curl -s -X POST "${TG_API_URL}" \
        -d "chat_id=${CHAT_ID}" \
        -d "parse_mode=Markdown" \
        -d "text=❌ *深海声呐探测失败*
📍 节点：\`${NODE_ALIAS}\`
🌐 锁定IP：\`${PUBLIC_IP}\`
⚠️ *未收到回波。检测源超时或 IP 路由受阻。*" >/dev/null
    exit 1
fi

# 2. 提取核心基础指标
IP_ADDR=$(echo "$JSON_DATA" | jq -r '.Head.IP // empty')
[ -z "$IP_ADDR" ] && IP_ADDR="$PUBLIC_IP"

SCAM_SCORE=$(echo "$JSON_DATA" | jq -r '.Score.SCAMALYTICS // "0"')
FRAUD_RISK=$(echo "$JSON_DATA" | jq -r '.Score.ipapi // "0%"')
USAGE_TYPE=$(echo "$JSON_DATA" | jq -r '.Type.Usage.IPinfo // "Unknown"')

# 3. 提取流媒体与 AI 解锁指标
NF_STAT=$(echo "$JSON_DATA" | jq -r '.Media.Netflix.Status // "Unknown"')
NF_REG=$(echo "$JSON_DATA" | jq -r '.Media.Netflix.Region // ""')
YT_STAT=$(echo "$JSON_DATA" | jq -r '.Media.Youtube.Status // "Unknown"')
YT_REG=$(echo "$JSON_DATA" | jq -r '.Media.Youtube.Region // ""')
DP_STAT=$(echo "$JSON_DATA" | jq -r '.Media.DisneyPlus.Status // "Unknown"')
DP_REG=$(echo "$JSON_DATA" | jq -r '.Media.DisneyPlus.Region // ""')
TK_STAT=$(echo "$JSON_DATA" | jq -r '.Media.TikTok.Status // "Unknown"')
TK_REG=$(echo "$JSON_DATA" | jq -r '.Media.TikTok.Region // ""')
GPT_STAT=$(echo "$JSON_DATA" | jq -r '.Media.ChatGPT.Status // "Unknown"')
GPT_REG=$(echo "$JSON_DATA" | jq -r '.Media.ChatGPT.Region // ""')

DNS_BLACK=$(echo "$JSON_DATA" | jq -r '.Mail.DNSBlacklist.Blacklisted // "0"')
DNS_MARK=$(echo "$JSON_DATA" | jq -r '.Mail.DNSBlacklist.Marked // "0"')

# 4. “送中” 逻辑判定
WARNING_MSG=""
if [[ "$YT_REG" == *"[CN]"* ]] || [[ "$YT_STAT" == *"China"* ]]; then
    WARNING_MSG="%0A🚨 **高危警告：该 IP 已被 Google / YouTube 送中！**%0A"
fi

# 5. 组装 Markdown 战报
REPORT="🎯 *深海声呐 - 深度探测报告*
📍 节点：\`${NODE_ALIAS}\`
🌐 IP：\`${IP_ADDR}\`${WARNING_MSG}

*🛡️ 信用评估*
• **Scamalytics：** \`${SCAM_SCORE}/100\`
• **IPAPI 风险：** \`${FRAUD_RISK}\`
• **属性类别：** \`${USAGE_TYPE}\`

*🎬 核心解锁状态*
• **YouTube:** \`${YT_STAT}\` ${YT_REG}
• **Netflix:** \`${NF_STAT}\` ${NF_REG}
• **Disney+:** \`${DP_STAT}\` ${DP_REG}
• **TikTok:** \`${TK_STAT}\` ${TK_REG}
• **ChatGPT:** \`${GPT_STAT}\` ${GPT_REG}

*✉️ 纯净度*
严重黑名单: \`${DNS_BLACK}\` | 轻度标记: \`${DNS_MARK}\`

_👉 [🔍 点击前往 Scamalytics 查阅详细 IP 信用](https://scamalytics.com/ip/${TARGET_IP})_

\`[SYSTEM_REPORT]|QUALITY|${NODE_NAME}|${SCAM_SCORE}|${NF_STAT}\`"

# 6. 直送指挥部
curl -s -X POST "${TG_API_URL}" \
    -d "chat_id=${CHAT_ID}" \
    -d "parse_mode=Markdown" \
    -d "disable_web_page_preview=true" \
    -d "text=${REPORT}" >/dev/null