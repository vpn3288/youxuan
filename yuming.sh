#!/bin/bash
# VPS 优选域名稳定筛选器 v5.0
# 支持并行测试、扩充域名库、推荐最优3个域名

# ── 版本号（每次更新脚本时修改此处）─────────────────────────────────────────
SCRIPT_VERSION="5.0"
SCRIPT_URL="https://raw.githubusercontent.com/vpn3288/youxuan/refs/heads/main/yuming.sh"

# ── 清除本地缓存残留（防止旧版临时文件干扰）──────────────────────────────────
# 清理上次运行可能残留的临时目录（匹配 mktemp 默认命名规则）
rm -rf /tmp/tmp.* 2>/dev/null

# ── 自我更新检查（联网时自动拉最新版并重新执行）──────────────────────────────
# 仅在非管道模式下执行自更新（避免 curl|bash 时死循环）
if [[ ! -p /dev/stdin ]]; then
    REMOTE_VER=$(curl -sSfL --max-time 5 \
        "${SCRIPT_URL}?$(date +%s)" 2>/dev/null \
        | grep -m1 'SCRIPT_VERSION=' \
        | cut -d'"' -f2)

    if [[ -n "$REMOTE_VER" && "$REMOTE_VER" != "$SCRIPT_VERSION" ]]; then
        echo -e "\e[33m[UPDATE] 发现新版本 v${REMOTE_VER}，正在自动更新并重新运行...\e[0m"
        TMPFILE=$(mktemp /tmp/yuming_XXXXXX.sh)
        curl -sSfL --max-time 15 \
            "${SCRIPT_URL}?$(date +%s)" -o "$TMPFILE" 2>/dev/null \
            && chmod +x "$TMPFILE" \
            && bash "$TMPFILE" \
            && rm -f "$TMPFILE" \
            && exit 0
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
NC='\e[0m'

# ── 并行数量 ──────────────────────────────────────────────────────────────────
PARALLEL=5

# ── 域名库（扩充至 80+ 个）────────────────────────────────────────────────────
DOMAINS=(
    # Apple
    "gateway.icloud.com"
    "itunes.apple.com"
    "swdist.apple.com"
    "swcdn.apple.com"
    "updates.cdn-apple.com"
    "mensura.cdn-apple.com"
    "apple.com"
    "www.apple.com"
    # Google
    "dl.google.com"
    "www.google-analytics.com"
    "storage.googleapis.com"
    "www.google.com"
    "fonts.googleapis.com"
    "ajax.googleapis.com"
    # Mozilla
    "download-installer.cdn.mozilla.net"
    "addons.mozilla.org"
    "www.mozilla.org"
    # Amazon/AWS
    "s0.awsstatic.com"
    "d1.awsstatic.com"
    "m.media-amazon.com"
    "player.live-video.net"
    "d2lrzjdc1gd2wr.cloudfront.net"
    "aws.amazon.com"
    # Microsoft
    "download.microsoft.com"
    "aka.ms"
    "azureedge.net"
    "www.microsoft.com"
    # Gaming
    "academy.nvidia.com"
    "one-piece.com"
    "lol.secure.dyn.riotcdn.net"
    "www.nintendo.co.jp"
    "www.sony.co.jp"
    "www.razer.com"
    "store.steampowered.com"
    "cdn.akamai.steamstatic.com"
    "www.ea.com"
    "www.epicgames.com"
    "www.ubisoft.com"
    "www.twitch.tv"
    # Dev / Tech
    "www.python.org"
    "vuejs.org"
    "react.dev"
    "www.java.com"
    "www.oracle.com"
    "redis.io"
    "github.io"
    "raw.githubusercontent.com"
    "objects.githubusercontent.com"
    "www.npmjs.com"
    "registry.npmjs.org"
    "pypi.org"
    "hub.docker.com"
    "www.cloudflare.com"
    "www.digitalocean.com"
    "www.linode.com"
    # CDN
    "cname.vercel-dns.com"
    "cdn.jsdelivr.net"
    "cdnjs.cloudflare.com"
    "unpkg.com"
    "fastly.com"
    # Education
    "www.caltech.edu"
    "www.calstatela.edu"
    "www.suny.edu"
    "www.nus.edu.sg"
    "www.mit.edu"
    "www.stanford.edu"
    "www.harvard.edu"
    # Singapore / SEA
    "www.gov.sg"
    "www.singpost.com"
    "www.grab.com"
    # Consumer Electronics
    "www.samsung.com"
    "www.sony.com"
    "www.lg.com"
    "www.asus.com"
    # Social / Media
    "www.spotify.com"
    "cdn.discordapp.com"
    "discord.com"
    "www.reddit.com"
    "www.medium.com"
    # Other popular
    "www.wikipedia.org"
    "www.wikimedia.org"
    "www.cloudflare.com"
    "1.1.1.1"
)

# ── 临时目录 ──────────────────────────────────────────────────────────────────
RESULT_DIR=$(mktemp -d)
trap 'rm -rf "$RESULT_DIR"' EXIT

# ── 单域名测试函数 ─────────────────────────────────────────────────────────────
test_domain() {
    local domain=$1

    # 1. Ping 测试（1 秒超时，取平均 RTT）
    local lat
    lat=$(ping -c 2 -W 1 "$domain" 2>/dev/null | awk -F '/' 'END {print $5}')
    [[ -z "$lat" ]] && return

    # 2. TLS 1.3 + X25519 测试（REALITY 核心指标，3 秒超时）
    local ssl_info
    ssl_info=$(timeout 3s openssl s_client \
        -connect "${domain}:443" \
        -tls1_3 \
        -servername "${domain}" \
        </dev/null 2>/dev/null)

    echo "$ssl_info" | grep -q "X25519" || return

    # 3. HTTP/2 检测
    local h2="NO"
    local curl_out
    curl_out=$(curl -sI --http2 \
        --connect-timeout 2 \
        --max-time 4 \
        "https://$domain" 2>/dev/null)
    echo "$curl_out" | grep -qi "HTTP/2" && h2="YES"

    # 4. 写结果（格式：延迟|域名|H2支持）
    echo "${lat}|${domain}|${h2}" > "${RESULT_DIR}/${domain//\//_}"
}

export -f test_domain
export RESULT_DIR

# ── 主界面 ────────────────────────────────────────────────────────────────────
echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║        VPS 优选域名稳定筛选器 v5.0  (Parallel & Extended)        ║${NC}"
echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo -e "  域名库: ${CYAN}${#DOMAINS[@]}${NC} 个  |  并行数: ${CYAN}${PARALLEL}${NC}  |  检测协议: ${CYAN}TLS 1.3 + X25519${NC}\n"
echo -e "正在扫描，请稍候...\n"

# ── 并行执行（每次最多 PARALLEL 个并发）─────────────────────────────────────
active=0
for domain in "${DOMAINS[@]}"; do
    test_domain "$domain" &
    (( active++ ))
    if (( active >= PARALLEL )); then
        wait -n 2>/dev/null || wait   # bash 4.3+ 支持 wait -n；否则等全部
        active=0
    fi
done
wait  # 等待最后一批

# ── 汇总结果 ──────────────────────────────────────────────────────────────────
results=$(cat "${RESULT_DIR}"/* 2>/dev/null | sort -t'|' -k1 -n)

echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "${BOLD}%-38s | %-6s | %-6s | %s${NC}\n" "域名" "HTTP/2" "X25519" "延迟(ms)"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [[ -z "$results" ]]; then
    echo -e "\n${RED}⚠️  未发现任何符合条件的域名。${NC}"
    echo -e "${YELLOW}可能原因：VPS 出口屏蔽了 TLS 1.3 / X25519，或网络不通。${NC}"
    echo -e "${YELLOW}手动测试命令：${NC}"
    echo -e "  openssl s_client -connect www.razer.com:443 -tls1_3 -servername www.razer.com"
    exit 1
fi

count=0
while IFS='|' read -r lat dom h2; do
    [[ -z "$lat" || -z "$dom" ]] && continue
    (( count++ ))

    # 延迟着色
    if (( $(echo "$lat < 10" | bc -l 2>/dev/null || echo 0) )); then
        latcolor=$GREEN
    elif (( $(echo "$lat < 50" | bc -l 2>/dev/null || echo 0) )); then
        latcolor=$CYAN
    elif (( $(echo "$lat < 150" | bc -l 2>/dev/null || echo 0) )); then
        latcolor=$YELLOW
    else
        latcolor=$RED
    fi

    h2color=$NC
    [[ "$h2" == "YES" ]] && h2color=$GREEN

    printf "%-38s | ${h2color}%-6s${NC} | ${GREEN}%-6s${NC} | ${latcolor}%s ms${NC}\n" \
        "$dom" "$h2" "YES" "$lat"
done <<< "$results"

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "共找到 ${CYAN}${count}${NC} 个通过 TLS 1.3 + X25519 验证的域名\n"

# ── TOP 3 推荐 ────────────────────────────────────────────────────────────────
echo -e "${PURPLE}${BOLD}┌─────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${PURPLE}${BOLD}│                     🏆  TOP 3 最佳推荐                          │${NC}"
echo -e "${PURPLE}${BOLD}└─────────────────────────────────────────────────────────────────┘${NC}"

rank=1
while IFS='|' read -r lat dom h2; do
    [[ -z "$lat" || -z "$dom" ]] && continue
    [[ $rank -gt 3 ]] && break

    case $rank in
        1) medal="🥇" ;;
        2) medal="🥈" ;;
        3) medal="🥉" ;;
    esac

    echo -e "  ${medal}  ${GREEN}${BOLD}${dom}${NC}"
    echo -e "      延迟: ${CYAN}${lat} ms${NC}  |  HTTP/2: ${h2}  |  TLS 1.3 + X25519: ${GREEN}✓${NC}"
    (( rank++ ))
done <<< "$results"

echo ""
echo -e "${YELLOW}💡 使用建议：以上域名可直接用作 REALITY 配置的 dest/serverName 字段。${NC}"
echo -e "${YELLOW}   优先选择延迟低、HTTP/2 为 YES 的域名以获得最佳效果。${NC}"
