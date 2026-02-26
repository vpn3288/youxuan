#!/bin/bash

# 颜色定义
RED='\033[031m'
GREEN='\033[032m'
YELLOW='\033[033m'
BLUE='\033[034m'
PURPLE='\033[035m'
BOLD='\033[1m'
NC='\033[0m'

# --- 扩展域名库 (分类存放) ---
# 日本
JP_DOMAINS=("www.nintendo.co.jp" "www.sony.co.jp" "www.rakuten.co.jp" "www.capcom.co.jp" "www.line.me" "www.fujitsu.com" "global.toyota")
# 美国
US_DOMAINS=("www.microsoft.com" "www.apple.com" "aws.amazon.com" "hub.docker.com" "www.nvidia.com" "download.windowsupdate.com" "www.intel.com" "www.amd.com")
# 新加坡
SG_DOMAINS=("www.shopee.sg" "www.grab.com" "www.razer.com" "www.lazada.sg" "www.dbs.com.sg" "www.straitstimes.com" "www.nus.edu.sg")
# 全球/CDN
GLOBAL_DOMAINS=("cdn.jsdelivr.net" "cdnjs.cloudflare.com" "static.doubleclick.net" "www.cloudflare.com" "www.disneyplus.com")

ALL_DOMAINS=("${JP_DOMAINS[@]}" "${US_DOMAINS[@]}" "${SG_DOMAINS[@]}" "${GLOBAL_DOMAINS[@]}")

echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "${BLUE}${BOLD}        VPS 代理节点优选域名专业筛选工具 (Enhanced v2.0)        ${NC}"
echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "正在检测当前 VPS 网络环境并筛选最佳邻居域名...\n"

printf "${BOLD}%-28s | %-8s | %-8s | %-8s | %-10s${NC}\n" "域名 (Domain)" "TLS1.3" "X25519" "HTTP/2" "延迟(ms)"
echo "--------------------------------------------------------------------------------"

BEST_DOMAIN=""
MIN_LATENCY=9999

for domain in "${ALL_DOMAINS[@]}"; do
    # 1. 延迟测试
    avg_latency=$(ping -c 3 -i 0.2 -W 1 $domain 2>/dev/null | awk -F '/' 'END {print $5}')
    
    if [ -z "$avg_latency" ]; then
        echo -e "%-28s | ${RED}Timeout${NC}" "$domain"
        continue
    fi

    # 2. TLS1.3 & HTTP/2 检测
    http_check=$(curl -I --tlsv1.3 --http2 --connect-timeout 2 -s "https://$domain" 2>&1)
    
    tls_pass=0
    h2_pass=0
    [[ $http_check == *"HTTP/"* ]] && tls_pass=1
    [[ $http_check == *"HTTP/2"* ]] && h2_pass=1

    # 3. X25519 核心检测 (REALITY 必需)
    x25519_check=$(timeout 2s openssl s_client -connect ${domain}:443 -tls1_3 -servername ${domain} 2>/dev/null | grep "Server Temp Key")
    
    x_pass=0
    [[ $x25519_check == *"X25519"* ]] && x_pass=1

    # --- 格式化显示 ---
    # TLS 1.3
    [ $tls_pass -eq 1 ] && tls_str="${GREEN}PASS${NC}" || tls_str="${RED}FAIL${NC}"
    # X25519
    [ $x_pass -eq 1 ] && x_str="${GREEN}YES${NC}" || x_str="${RED}NO${NC}"
    # HTTP2
    [ $h2_pass -eq 1 ] && h2_str="${GREEN}YES${NC}" || h2_str="${YELLOW}NO${NC}"
    
    # 延迟着色
    latency_int=${avg_latency%.*}
    if [ $latency_int -lt 10 ]; then
        lat_str="${GREEN}${avg_latency}${NC}"
    elif [ $latency_int -lt 50 ]; then
        lat_str="${YELLOW}${avg_latency}${NC}"
    else
        lat_str="${avg_latency}"
    fi

    printf "%-28s | %-17s | %-17s | %-17s | %-10s\n" "$domain" "$tls_str" "$x_str" "$h2_str" "$lat_str"

    # --- 推荐逻辑 ---
    # 必须满足 TLS1.3 和 X25519，然后在其中找延迟最低的
    if [ $tls_pass -eq 1 ] && [ $x_pass -eq 1 ]; then
        if (( $(echo "$avg_latency < $MIN_LATENCY" | bc -l) )); then
            MIN_LATENCY=$avg_latency
            BEST_DOMAIN=$domain
        fi
    fi
done

echo "--------------------------------------------------------------------------------"
if [ -n "$BEST_DOMAIN" ]; then
    echo -e "${PURPLE}${BOLD}🏆 自动化推荐 (Best Pick for this VPS):${NC}"
    echo -e "   ${GREEN}${BOLD}推荐域名: $BEST_DOMAIN${NC}"
    echo -e "   ${GREEN}${BOLD}当前延迟: $MIN_LATENCY ms${NC}"
    echo -e "\n${BLUE}💡 提示：该域名在 TLS 协议上与你的 VPS 响应最契合，建议设为 REALITY 目标域名。${NC}"
else
    echo -e "${RED}未发现完美支持 X25519 的域名，请检查 VPS 的 OpenSSL 版本。${NC}"
fi
