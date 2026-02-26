#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║      REALITY 优选伪装域名筛选器 v6.0                             ║
# ║      筛选标准: TLS1.3 + X25519 + Akamai/Fastly/Google CDN       ║
# ║      剔除: Cloudflare托管 / 自建源站 / IP地址 / 政府域名          ║
# ╚══════════════════════════════════════════════════════════════════╝

# ── 版本号 ────────────────────────────────────────────────────────────────────
SCRIPT_VERSION="6.0"
SCRIPT_URL="https://raw.githubusercontent.com/vpn3288/youxuan/refs/heads/main/yuming.sh"

# ── 清除上次残留临时文件 ──────────────────────────────────────────────────────
rm -rf /tmp/yuming_* /tmp/tmp.* 2>/dev/null

# ── 自我更新（非管道模式才执行，防止 curl|bash 死循环）──────────────────────
if [[ ! -p /dev/stdin ]]; then
    REMOTE_VER=$(curl -sSfL --max-time 5 \
        "${SCRIPT_URL}?$(date +%s)" 2>/dev/null \
        | grep -m1 'SCRIPT_VERSION=' | cut -d'"' -f2)
    if [[ -n "$REMOTE_VER" && "$REMOTE_VER" != "$SCRIPT_VERSION" ]]; then
        echo -e "\e[33m[UPDATE] 发现新版本 v${REMOTE_VER}，正在更新...\e[0m"
        TMPFILE=$(mktemp /tmp/yuming_XXXXXX.sh)
        if curl -sSfL --max-time 15 "${SCRIPT_URL}?$(date +%s)" -o "$TMPFILE" 2>/dev/null; then
            chmod +x "$TMPFILE" && bash "$TMPFILE" && rm -f "$TMPFILE" && exit 0
        fi
        rm -f "$TMPFILE"
        echo -e "\e[31m[UPDATE] 更新失败，继续使用当前版本 v${SCRIPT_VERSION}\e[0m"
    fi
fi

# ── 环境依赖检查 ──────────────────────────────────────────────────────────────
for cmd in bc openssl curl ping; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "正在安装依赖: $cmd ..."
        apt-get update -qq && apt-get install -y -qq "$cmd" 2>/dev/null \
            || yum install -y "$cmd" 2>/dev/null \
            || { echo "无法安装 $cmd，请手动安装后重试"; exit 1; }
    fi
done

# ── 颜色定义 ──────────────────────────────────────────────────────────────────
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
PURPLE='\e[35m'
CYAN='\e[36m'
BOLD='\e[1m'
DIM='\e[2m'
NC='\e[0m'

# ── 并行数 ────────────────────────────────────────────────────────────────────
PARALLEL=5

# ══════════════════════════════════════════════════════════════════════════════
# 域名库 — 按 REALITY 伪装适用性精选
#
# 收录原则：
#   ✅ Akamai / Fastly / Google / AWS CloudFront 托管的纯 CDN 分发节点
#   ✅ 对"只握手不发HTTP请求"宽容，不触发 WAF / bot 检测
#   ✅ 证书长期稳定，全球节点响应一致
#   ✅ 社区长期实测验证可用
#   ❌ 剔除 Cloudflare 托管（bot检测会重置握手）
#   ❌ 剔除自建源站（会拒绝异常握手）
#   ❌ 剔除政府/金融域名（安全策略严格）
#   ❌ 剔除纯 IP（无SNI，REALITY无意义）
#   ❌ 剔除社交媒体主站（频繁bot检测 + 证书轮换）
# ══════════════════════════════════════════════════════════════════════════════
DOMAINS=(
    # ── Apple CDN（Akamai托管 · 社区验证最稳定 · 首选）──────────────────────
    "gateway.icloud.com"
    "itunes.apple.com"
    "swdist.apple.com"
    "swcdn.apple.com"
    "updates.cdn-apple.com"
    "mensura.cdn-apple.com"
    "osxapps.itunes.apple.com"
    "aod.itunes.apple.com"
    "xp.apple.com"
    "cvws.icloud-content.com"

    # ── Google CDN（自建CDN · 纯下载节点 · 无WAF）───────────────────────────
    "dl.google.com"
    "www.google-analytics.com"
    "storage.googleapis.com"
    "fonts.googleapis.com"
    "ajax.googleapis.com"
    "redirector.gvt1.com"

    # ── Microsoft CDN（Akamai/Edgecast托管 · 下载节点宽容度高）─────────────
    "software.download.prss.microsoft.com"
    "cdn-dynmedia-1.microsoft.com"
    "download.microsoft.com"
    "officecdn.microsoft.com"
    "officecdn-microsoft-com.akamaized.net"
    "go.microsoft.com"

    # ── Amazon / AWS CloudFront（纯资源分发节点）────────────────────────────
    "s0.awsstatic.com"
    "d1.awsstatic.com"
    "m.media-amazon.com"
    "player.live-video.net"
    "images-na.ssl-images-amazon.com"

    # ── Mozilla（Fastly托管 · 社区长期验证）─────────────────────────────────
    "download-installer.cdn.mozilla.net"
    "addons.mozilla.org"
    "www.mozilla.org"

    # ── 游戏公司 CDN（自建CDN / Akamai · 纯资源分发 · 无bot检测）───────────
    "lol.secure.dyn.riotcdn.net"
    "one-piece.com"
    "www.lovelive-anime.jp"
    "academy.nvidia.com"
    "cdn.akamai.steamstatic.com"
    "steamcdn-a.akamaihd.net"
    "www.nintendo.co.jp"
    "www.ea.com"

    # ── 硬件 / 科技厂商官网（Akamai托管 · 企业CDN节点）─────────────────────
    "www.razer.com"
    "www.samsung.com"
    "www.asus.com"
    "www.amd.com"
    "www.cisco.com"
    "www.oracle.com"
    "www.java.com"
    "www.mysql.com"
    "www.swift.com"

    # ── 开发者 / 技术文档（Fastly / Akamai托管 · 纯静态内容）───────────────
    "www.python.org"
    "vuejs.org"
    "vuejs-jp.org"
    "zh-hk.vuejs.org"
    "react.dev"
    "redis.io"
    "www.mongodb.com"

    # ── Vercel CDN 节点（非 Cloudflare · 社区验证）──────────────────────────
    "cname.vercel-dns.com"
    "vercel-dns.com"

    # ── GitHub CDN（Fastly托管 · 纯资源节点）────────────────────────────────
    "github.io"
    "objects.githubusercontent.com"

    # ── 教育网（Akamai托管高校CDN · 非自建服务器 · 社区验证）───────────────
    "www.caltech.edu"
    "www.calstatela.edu"
    "www.suny.edu"
    "www.suffolk.edu"

    # ── 其他社区长期验证可用 ─────────────────────────────────────────────────
    "www.fom-international.com"
    "www.umcg.nl"
    "www.u-can.co.jp"
)

# ── 临时目录 ──────────────────────────────────────────────────────────────────
RESULT_DIR=$(mktemp -d /tmp/yuming_XXXXXX)
trap 'rm -rf "$RESULT_DIR"' EXIT

# ── CDN 托管商识别函数 ────────────────────────────────────────────────────────
detect_cdn() {
    local ssl_info=$1
    if   echo "$ssl_info" | grep -qi "akamai\|akamaized\|akamaihd"; then echo "Akamai"
    elif echo "$ssl_info" | grep -qi "fastly";                        then echo "Fastly"
    elif echo "$ssl_info" | grep -qi "cloudfront\|amazonaws";         then echo "AWS CF"
    elif echo "$ssl_info" | grep -qi "google\|gvt1\|gvt2";            then echo "Google"
    elif echo "$ssl_info" | grep -qi "microsoft\|msecnd\|edgecast";   then echo "MS CDN"
    elif echo "$ssl_info" | grep -qi "cloudflare";                     then echo "CF_WARN"
    else                                                                     echo "Other"
    fi
}
export -f detect_cdn

# ── 单域名完整测试函数 ────────────────────────────────────────────────────────
test_domain() {
    local domain=$1

    # ① Ping（2包·1秒超时·取平均RTT）
    local lat
    lat=$(ping -c 2 -W 1 "$domain" 2>/dev/null | awk -F '/' 'END {print $5}')
    [[ -z "$lat" ]] && return

    # ② TLS 1.3 + X25519 握手（REALITY核心·4秒超时）
    local ssl_info
    ssl_info=$(timeout 3s openssl s_client \
        -connect "${domain}:443" \
        -tls1_3 \
        -servername "${domain}" \
        </dev/null 2>/dev/null)

    echo "$ssl_info" | grep -q "X25519" || return

    # ③ 握手宽容度检测
    #    向服务器发空包后观察是否立即断开
    #    宽容的CDN节点会保持等待；严格的服务器立刻RST
    local tolerant="YES"
    local rtt_check
    rtt_check=$(timeout 1s bash -c \
        "echo '' | openssl s_client -connect '${domain}:443' \
         -tls1_3 -servername '${domain}' -quiet 2>&1 | head -1" 2>/dev/null)
    echo "$rtt_check" | grep -qi "errno\|refused\|reset\|error" && tolerant="WARN"

    # ④ HTTP/2 检测
    local h2="NO"
    curl -sI --http2 --connect-timeout 2 --max-time 3 \
        "https://$domain" 2>/dev/null | grep -qi "HTTP/2" && h2="YES"

    # ⑤ CDN 托管商识别
    local cdn
    cdn=$(detect_cdn "$ssl_info")

    # ⑥ 综合评分（排序权重）
    #    基础 = 延迟(ms)；H2加分；CF扣分；宽容度WARN扣分
    local score
    score=$(printf "%.3f" "$lat")
    [[ "$h2"       == "YES"  ]] && score=$(echo "$score - 0.5" | bc -l 2>/dev/null || echo "$score")
    [[ "$cdn"      == "CF_WARN" ]] && score=$(echo "$score + 5.0" | bc -l 2>/dev/null || echo "$score")
    [[ "$tolerant" == "WARN" ]] && score=$(echo "$score + 2.0" | bc -l 2>/dev/null || echo "$score")

    # ⑦ 写结果（score|延迟|域名|H2|CDN|宽容度）
    printf "%.3f|%s|%s|%s|%s|%s\n" \
        "$score" "$lat" "$domain" "$h2" "$cdn" "$tolerant" \
        > "${RESULT_DIR}/${domain//[\/.]/_}"
}

export -f test_domain
export RESULT_DIR

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${BLUE}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════════╗"
echo "  ║       REALITY 优选伪装域名筛选器  v${SCRIPT_VERSION}                         ║"
echo "  ║       TLS 1.3  ·  X25519  ·  CDN识别  ·  握手宽容度检测         ║"
echo "  ╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  域名库 : ${CYAN}${BOLD}${#DOMAINS[@]} 个${NC}  （已剔除CF托管/自建源站/IP/政府域名）"
echo -e "  并行数 : ${CYAN}${BOLD}${PARALLEL}${NC}  ·  筛选协议: ${CYAN}${BOLD}TLS 1.3 + X25519${NC}"
echo ""
echo -e "  ${YELLOW}▶ 正在扫描，请稍候...${NC}"
echo ""

# ── 并行执行 ──────────────────────────────────────────────────────────────────
total=${#DOMAINS[@]}
for (( i=0; i<total; i+=PARALLEL )); do
    batch=( "${DOMAINS[@]:i:PARALLEL}" )
    for domain in "${batch[@]}"; do
        test_domain "$domain" &
    done
    wait
done

# ── 汇总排序 ──────────────────────────────────────────────────────────────────
results=$(cat "${RESULT_DIR}"/* 2>/dev/null | sort -t'|' -k1 -n)

# ── 结果表格 ──────────────────────────────────────────────────────────────────
echo -e "${BOLD}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "  ${BOLD}%-38s | %-7s | %-6s | %-6s | %s${NC}\n" \
    "域名" "CDN托管" "HTTP/2" "宽容度" "延迟(ms)"
echo -e "${BOLD}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [[ -z "$results" ]]; then
    echo ""
    echo -e "  ${RED}⚠️  未发现任何符合条件的域名。${NC}"
    echo -e "  ${YELLOW}可能原因：VPS 出口屏蔽了 TLS 1.3 / X25519，或网络不通。${NC}"
    echo ""
    echo -e "  ${YELLOW}手动验证命令：${NC}"
    echo -e "  ${CYAN}openssl s_client -connect swcdn.apple.com:443 -tls1_3 -servername swcdn.apple.com${NC}"
    exit 1
fi

count=0
while IFS='|' read -r score lat dom h2 cdn tolerant; do
    [[ -z "$lat" || -z "$dom" ]] && continue
    (( count++ ))

    # 延迟着色
    if   (( $(echo "$lat < 10"  | bc -l 2>/dev/null || echo 0) )); then latcolor=$GREEN
    elif (( $(echo "$lat < 50"  | bc -l 2>/dev/null || echo 0) )); then latcolor=$CYAN
    elif (( $(echo "$lat < 150" | bc -l 2>/dev/null || echo 0) )); then latcolor=$YELLOW
    else latcolor=$RED
    fi

    # CDN 着色
    case "$cdn" in
        Akamai|Fastly|Google|"AWS CF"|"MS CDN") cdncolor=$GREEN  ;;
        "CF_WARN")                                 cdncolor=$YELLOW ;;
        *)                                       cdncolor=$NC     ;;
    esac

    # 宽容度 / H2 着色
    [[ "$tolerant" == "YES" ]] && tolcolor=$GREEN || tolcolor=$YELLOW
    [[ "$h2"       == "YES" ]] && h2color=$GREEN  || h2color=$NC

    printf "  %-38s | ${cdncolor}%-7s${NC} | ${h2color}%-6s${NC} | ${tolcolor}%-6s${NC} | ${latcolor}%s ms${NC}\n" \
        "$dom" "$cdn" "$h2" "$tolerant" "$lat"

done <<< "$results"

echo -e "${BOLD}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  共找到 ${CYAN}${BOLD}${count}${NC} 个通过 TLS 1.3 + X25519 验证的域名"
echo ""

# ── TOP 3 推荐 ────────────────────────────────────────────────────────────────
echo -e "${PURPLE}${BOLD}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}${BOLD}  ║              🏆  REALITY 最佳伪装域名  TOP 3                   ║${NC}"
echo -e "${PURPLE}${BOLD}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

rank=1
while IFS='|' read -r score lat dom h2 cdn tolerant; do
    [[ -z "$lat" || -z "$dom" ]] && continue
    [[ $rank -gt 3 ]] && break

    case $rank in
        1) medal="🥇"; rankcolor=$GREEN  ;;
        2) medal="🥈"; rankcolor=$CYAN   ;;
        3) medal="🥉"; rankcolor=$YELLOW ;;
    esac

    echo -e "  ${medal}  ${rankcolor}${BOLD}${dom}${NC}"
    printf "      延迟: ${CYAN}%-10s${NC} CDN: ${GREEN}%-8s${NC} HTTP/2: ${h2}  宽容度: ${tolerant}\n" \
        "${lat} ms" "$cdn"
    echo -e "      ${DIM}配置参考 →  dest: \"${dom}:443\"   serverName: \"${dom}\"${NC}"
    echo ""

    (( rank++ ))
done <<< "$results"

# ── 使用说明 ──────────────────────────────────────────────────────────────────
echo -e "${BOLD}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${YELLOW}${BOLD}💡 选域名指南${NC}"
echo -e "  ${GREEN}  · CDN = Akamai / Fastly / Google / AWS CF / MS CDN  →  优先选${NC}"
echo -e "  ${YELLOW}  · CDN = CF_WARN (Cloudflare托管)→ 有bot检测风险，稳定性差，慎用${NC}"
echo -e "  ${YELLOW}  · 宽容度 = WARN  →  服务器可能主动断开空握手，稳定性较差${NC}"
echo -e "  ${GREEN}  · HTTP/2 = YES   →  与真实用户流量特征更吻合，优先选${NC}"
echo -e "  ${NC}  · dest 与 serverName 填同一个域名，端口固定 443${NC}"
echo -e "${BOLD}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
