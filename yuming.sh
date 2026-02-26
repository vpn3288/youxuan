#!/bin/bash

# 检查依赖
if ! command -v bc &> /dev/null; then
    echo "正在安装必要组件 bc..."
    if command -v apt &> /dev/null; then sudo apt update && sudo apt install -y bc
    elif command -v yum &> /dev/null; then sudo yum install -y bc
    fi
fi

# 颜色定义
RED='\033[031m'
GREEN='\033[032m'
YELLOW='\033[033m'
BLUE='\033[034m'
PURPLE='\033[035m'
BOLD='\033[1m'
NC='\033[0m'

# --- 域名库大扩容 ---
DOMAINS=(
    # --- 你提供的 Apple 系列 ---
    "gateway.icloud.com" "itunes.apple.com" "swdist.apple.com" "swcdn.apple.com" 
    "updates.cdn-apple.com" "mensura.cdn-apple.com" "osxapps.itunes.apple.com" "aod.itunes.apple.com"
    # --- 你提供的 Google/Microsoft/Mozilla ---
    "dl.google.com" "www.google-analytics.com" "download-installer.cdn.mozilla.net" "addons.mozilla.org"
    "software.download.prss.microsoft.com" "cdn-dynmedia-1.microsoft.com"
    # --- 你提供的 CDN/Amazon/Nvidia ---
    "s0.awsstatic.com" "d1.awsstatic.com" "images-na.ssl-images-amazon.com" "m.media-amazon.com"
    "player.live-video.net" "academy.nvidia.com"
    # --- 你提供的 游戏/动画/技术 ---
    "one-piece.com" "lol.secure.dyn.riotcdn.net" "www.lovelive-anime.jp" "www.python.org"
    "vuejs-jp.org" "vuejs.org" "zh-hk.vuejs.org" "react.dev" "www.java.com" 
    "www.oracle.com" "www.mysql.com" "www.mongodb.com" "redis.io"
    # --- 你提供的 教育/DNS/其他 ---
    "www.caltech.edu" "www.calstatela.edu" "www.suny.edu" "www.suffolk.edu"
    "cname.vercel-dns.com" "vercel-dns.com" "www.swift.com" "www.cisco.com" 
    "www.asus.com" "www.samsung.com" "www.amd.com" "www.umcg.nl" "github.io"
    # --- 经典的日本/新加坡本地大厂 ---
    "www.nintendo.co.jp" "www.sony.co.jp" "www.rakuten.co.jp" "www.grab.com" "www.razer.com" "www.nus.edu.sg"
)

echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "${BLUE}${BOLD}      VPS 代理优选域名筛选专业版 v3.1 (全库扩充)      ${NC}"
echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "正在扫描全网 ${#DOMAINS[@]} 个优质节点，这可能需要一两分钟...\n"

printf "${BOLD}%-35s | %-8s | %-8s | %-8s | %-10s${NC}\n" "域名 (Domain)" "TLS1.3" "X25519" "HTTP/2" "延迟(ms)"
echo "---------------------------------------------------------------------------------------"

RECOMMEND_LIST=""

for domain in "${DOMAINS[@]}"; do
    # 1. 延迟测试 (Ping 2次)
    avg_latency=$(ping -c 2 -i 0.2 -W 1 $domain 2>/dev/null | awk -F '/' 'END {print $5}')
    
    if [ -z "$avg_latency" ]; then
        continue
    fi

    # 2. TLS1.3 & HTTP/2 检测
    # 使用更加鲁棒的检测方式
    http_info=$(curl -I --tlsv1.3 --http2 --connect-timeout 2 -s "https://$domain" 2>&1)
    
    tls_pass=0; h2_pass=0
    [[ $http_info == *"HTTP/"* ]] && tls_pass=1
    [[ $http_info == *"HTTP/2"* ]] && h2_pass=1

    # 3. X25519 核心检测 (REALITY 必需)
    x25519_info=$(timeout 2s openssl s_client -connect ${domain}:443 -tls1_3 -servername ${domain} 2>/dev/null | grep "Server Temp Key")
    x_pass=0
    [[ $x25519_info == *"X25519"* ]] && x_pass=1

    # 状态格式化
    [ $tls_pass -eq 1 ] && tls_str="${GREEN}PASS${NC}" || tls_str="${RED}FAIL${NC}"
    [ $x_pass -eq 1 ] && x_str="${GREEN}YES${NC}" || x_str="${RED}NO${NC}"
    [ $h2_pass -eq 1 ] && h2_str="${GREEN}YES${NC}" || h2_str="${YELLOW}NO${NC}"
    
    # 延迟着色
    lat_val=$(printf "%.2f" $avg_latency)
    if (( $(echo "$avg_latency < 5" | bc -l) )); then
        lat_str="${GREEN}${lat_val}${NC}"
    elif (( $(echo "$avg_latency < 50" | bc -l) )); then
        lat_str="${YELLOW}${lat_val}${NC}"
    else
        lat_str="${lat_val}"
    fi

    printf "%-35s | %-17s | %-17s | %-17s | %-10s\n" "$domain" "$tls_str" "$x_str" "$h2_str" "$lat_str"

    # 记录符合条件的域名 (必须 TLS1.3 和 X25519)
    if [ $tls_pass -eq 1 ] && [ $x_pass -eq 1 ]; then
        RECOMMEND_LIST="${RECOMMEND_LIST}${avg_latency}|${domain}\n"
    fi
done

echo "---------------------------------------------------------------------------------------"
echo -e "\n${PURPLE}${BOLD}🏆 【最终筛选结果 - 最佳邻居推荐】${NC}"

if [ -n "$RECOMMEND_LIST" ]; then
    # 排序并输出前 5 名
    echo -e "$RECOMMEND_LIST" | sort -n | head -n 5 | while IFS="|" read -r lat dom; do
        ((i++))
        printf "${GREEN}${BOLD}Top %d: %-30s | 延迟: %s ms${NC}\n" "$i" "$dom" "$lat"
    done
    echo -e "\n${BLUE}💡 提示：Top 1 是你这台 VPS 物理距离最近、协议最匹配的“灵魂伴侣”。${NC}"
else
    echo -e "${RED}未能找到符合 TLS1.3 + X25519 的域名，请检查 VPS 网络或 OpenSSL 版本。${NC}"
fi
