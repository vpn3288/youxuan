#!/bin/bash

# 环境检查与安装
for cmd in bc openssl curl ping; do
    if ! command -v $cmd &> /dev/null; then
        apt update && apt install -y $cmd || yum install -y $cmd
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

DOMAINS=(
    "gateway.icloud.com" "itunes.apple.com" "swdist.apple.com" "swcdn.apple.com" 
    "updates.cdn-apple.com" "mensura.cdn-apple.com" "dl.google.com" "www.google-analytics.com" 
    "download-installer.cdn.mozilla.net" "addons.mozilla.org" "s0.awsstatic.com" 
    "d1.awsstatic.com" "m.media-amazon.com" "player.live-video.net" "academy.nvidia.com"
    "one-piece.com" "lol.secure.dyn.riotcdn.net" "www.python.org" "vuejs.org" 
    "react.dev" "www.java.com" "www.oracle.com" "redis.io" "www.caltech.edu" 
    "www.calstatela.edu" "www.suny.edu" "cname.vercel-dns.com" "www.samsung.com" 
    "github.io" "www.nintendo.co.jp" "www.sony.co.jp" "www.grab.com" 
    "www.razer.com" "www.nus.edu.sg" "www.gov.sg" "www.singpost.com"
)

RESULT_DIR=$(mktemp -d)

test_domain() {
    local domain=$1
    # Ping 测试 (1s 超时)
    local lat=$(ping -c 1 -W 1 "$domain" 2>/dev/null | awk -F '/' 'END {print $5}')
    [[ -z "$lat" ]] && return

    # TLS 1.3 + X25519 组合测试 (REALITY 核心)
    # 使用 openssl 直接获取结果，增加 3 秒宽限
    local ssl_info=$(timeout 3s openssl s_client -connect "${domain}:443" -tls1_3 -servername "${domain}" </dev/null 2>/dev/null)
    
    if echo "$ssl_info" | grep -q "X25519"; then
        local h2="NO "
        # 顺便检查 H2
        [[ $(curl -I --http2 --connect-timeout 2 -s "https://$domain" 2>&1) == *"HTTP/2"* ]] && h2="YES"
        echo "$lat|$domain|$h2" > "$RESULT_DIR/$domain"
    fi
}

echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "${BLUE}${BOLD}      VPS 优选域名稳定筛选器 v4.1 (Stable & Fast)      ${NC}"
echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "正在扫描域名库，请稍候...\n"

# 分批次执行，每组 10 个，防止被封 IP
BATCH_SIZE=10
for ((i=0; i<${#DOMAINS[@]}; i+=BATCH_SIZE)); do
    for ((j=i; j<i+BATCH_SIZE && j<${#DOMAINS[@]}; j++)); do
        test_domain "${DOMAINS[$j]}" &
    done
    wait
done

# 表头
printf "${BOLD}%-35s | %-8s | %-8s | %-10s${NC}\n" "域名 (Domain)" "HTTP/2" "X25519" "延迟(ms)"
echo "---------------------------------------------------------------------------------------"

results=$(cat "$RESULT_DIR"/* 2>/dev/null | sort -n)

if [[ -z "$results" ]]; then
    echo -e "${RED}⚠️ 仍未发现结果。可能原因：你的 VPS 屏蔽了 OpenSSL 外部请求，请手动尝试：${NC}"
    echo -e "${YELLOW}openssl s_client -connect www.razer.com:443 -tls1_3 -servername www.razer.com${NC}"
else
    while IFS='|' read -r lat dom h2; do
        color=$NC
        (( $(echo "$lat < 10" | bc -l) )) && color=$GREEN
        printf "%-35s | %-8s | %-8s | ${color}%-10s${NC}\n" "$dom" "$h2" "YES" "$lat"
    done <<< "$results"

    echo "---------------------------------------------------------------------------------------"
    best_dom=$(echo "$results" | head -n 1 | cut -d'|' -f2)
    best_lat=$(echo "$results" | head -n 1 | cut -d'|' -f1)
    echo -e "\n${PURPLE}${BOLD}🏆 最佳推荐: ${GREEN}$best_dom${NC} (延迟: $best_lat ms)"
fi

rm -rf "$RESULT_DIR"
