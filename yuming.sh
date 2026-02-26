#!/bin/bash

# 检查并安装必要组件
for cmd in bc openssl curl ping; do
    if ! command -v $cmd &> /dev/null; then
        if command -v apt &> /dev/null; then sudo apt update && sudo apt install -y $cmd
        elif command -v yum &> /dev/null; then sudo yum install -y $cmd
        fi
    fi
done

# 颜色定义
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
PURPLE='\e[35m'
BOLD='\e[1m'
NC='\e[0m'

# --- 域名库 (整合你提供的所有域名) ---
DOMAINS=(
    "gateway.icloud.com" "itunes.apple.com" "swdist.apple.com" "swcdn.apple.com" 
    "updates.cdn-apple.com" "mensura.cdn-apple.com" "osxapps.itunes.apple.com" 
    "aod.itunes.apple.com" "dl.google.com" "www.google-analytics.com" 
    "download-installer.cdn.mozilla.net" "addons.mozilla.org"
    "software.download.prss.microsoft.com" "cdn-dynmedia-1.microsoft.com"
    "s0.awsstatic.com" "d1.awsstatic.com" "images-na.ssl-images-amazon.com" 
    "m.media-amazon.com" "player.live-video.net" "academy.nvidia.com"
    "one-piece.com" "lol.secure.dyn.riotcdn.net" "www.lovelive-anime.jp" 
    "www.python.org" "vuejs.org" "react.dev" "www.java.com" "www.oracle.com" 
    "www.mysql.com" "www.mongodb.com" "redis.io" "www.caltech.edu" 
    "www.calstatela.edu" "www.suny.edu" "www.suffolk.edu" "cname.vercel-dns.com" 
    "www.cisco.com" "www.asus.com" "www.samsung.com" "www.amd.com" "github.io"
    "www.nintendo.co.jp" "www.sony.co.jp" "www.rakuten.co.jp" "www.grab.com" 
    "www.razer.com" "www.nus.edu.sg" "www.gov.sg" "www.singpost.com"
)

# 临时目录用于存放结果
RESULT_DIR=$(mktemp -d)

# --- 单个域名检测函数 ---
test_domain() {
    local domain=$1
    # 1. 延迟测试 (Ping 1次, 超时1s)
    local avg_latency=$(ping -c 1 -W 1 "$domain" 2>/dev/null | awk -F '/' 'END {print $5}')
    [[ -z "$avg_latency" ]] && return

    # 2. TLS1.3 & HTTP/2 (超时2s)
    local http_info=$(curl -I --tlsv1.3 --http2 --connect-timeout 2 -s "https://$domain" 2>&1)
    local tls_pass=0; local h2_pass=0
    [[ $http_info == *"HTTP/"* ]] && tls_pass=1
    [[ $http_info == *"HTTP/2"* ]] && h2_pass=1

    # 3. X25519 检测 (超时2s)
    local x_pass=0
    if timeout 2s openssl s_client -connect "${domain}:443" -tls1_3 -servername "${domain}" </dev/null 2>/dev/null | grep -q "X25519"; then
        x_pass=1
    fi

    # 只有通过 TLS1.3 和 X25519 的才记录
    if [[ $tls_pass -eq 1 && $x_pass -eq 1 ]]; then
        local h2_str="NO "
        [[ $h2_pass -eq 1 ]] && h2_str="YES"
        # 格式：延迟|域名|H2支持
        echo "$avg_latency|$domain|$h2_str" > "$RESULT_DIR/$domain"
    fi
}

echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "${BLUE}${BOLD}      VPS 优选域名并行筛选器 v4.0 (Parallel Turbo)      ${NC}"
echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "正在并行检测 ${#DOMAINS[@]} 个域名，请稍候 (约 5-10 秒)...\n"

# --- 并行执行任务 ---
for domain in "${DOMAINS[@]}"; do
    test_domain "$domain" & 
done
wait # 等待所有后台任务完成

echo -e "${BOLD}%-35s | %-10s | %-8s | %-10s${NC}" "域名 (Domain)" "支持H2" "支持X255" "延迟(ms)"
echo "---------------------------------------------------------------------------------------"

# 读取结果并排序显示
# 按延迟数字大小排序
results=$(cat "$RESULT_DIR"/* 2>/dev/null | sort -n)

if [[ -z "$results" ]]; then
    echo -e "${RED}未发现符合条件的域名。${NC}"
else
    while IFS='|' read -r lat dom h2; do
        # 颜色控制
        lat_color=$NC
        (( $(echo "$lat < 5" | bc -l) )) && lat_color=$GREEN
        (( $(echo "$lat >= 5 && $lat < 50" | bc -l) )) && lat_color=$YELLOW
        
        printf "%-35s | %-10s | %-8s | ${lat_color}%-10s${NC}\n" "$dom" "$h2" "YES" "$lat"
    done <<< "$results"
fi

# 最终推荐
echo "---------------------------------------------------------------------------------------"
best=$(echo "$results" | head -n 1)
if [[ -n "$best" ]]; then
    best_dom=$(echo "$best" | cut -d'|' -f2)
    best_lat=$(echo "$best" | cut -d'|' -f1)
    echo -e "\n${PURPLE}${BOLD}🏆 最终推荐 (Best Neighbor):${NC}"
    echo -e "   域名: ${GREEN}${BOLD}$best_dom${NC}"
    echo -e "   延迟: ${GREEN}${BOLD}$best_lat ms${NC}"
    echo -e "\n${BLUE}💡 建议：将此域名填入 REALITY 的 SNI/Dest 位置，伪装效果最佳。${NC}"
fi

# 清理临时文件
rm -rf "$RESULT_DIR"
