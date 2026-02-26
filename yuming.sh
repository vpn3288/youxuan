#!/bin/bash

# 颜色定义
RED='\033[031m'
GREEN='\033[032m'
YELLOW='\033[033m'
BLUE='\033[034m'
PURPLE='\033[035m'
BOLD='\033[1m'
NC='\033[0m'

# --- 海量域名库扩容 ---
# 日本 JP (增加教育、通信、政府)
JP_DOMAINS=("www.nintendo.co.jp" "www.sony.co.jp" "www.rakuten.co.jp" "www.capcom.co.jp" "www.line.me" "www.fujitsu.com" "global.toyota" "www.u-tokyo.ac.jp" "www.mext.go.jp" "www.softbank.jp" "www.docomo.ne.jp")

# 美国 US (增加教育、媒体、政府更新)
US_DOMAINS=("www.microsoft.com" "www.apple.com" "aws.amazon.com" "hub.docker.com" "www.nvidia.com" "download.windowsupdate.com" "www.intel.com" "www.amd.com" "www.berkeley.edu" "www.stanford.edu" "www.nytimes.com" "www.cnn.com" "www.github.com" "www.zoom.us")

# 新加坡 SG (增加政府、银行、教育)
SG_DOMAINS=("www.shopee.sg" "www.grab.com" "www.razer.com" "www.lazada.sg" "www.dbs.com.sg" "www.straitstimes.com" "www.nus.edu.sg" "www.gov.sg" "www.singpost.com" "www.uobgroup.com")

# 全球/CDN/办公 (增加常用办公软件)
GLOBAL_DOMAINS=("cdn.jsdelivr.net" "cdnjs.cloudflare.com" "static.doubleclick.net" "www.cloudflare.com" "www.disneyplus.com" "www.webex.com" "www.dropbox.com" "www.visa.com")

ALL_DOMAINS=("${JP_DOMAINS[@]}" "${US_DOMAINS[@]}" "${SG_DOMAINS[@]}" "${GLOBAL_DOMAINS[@]}")

echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "${BLUE}${BOLD}      VPS 代理优选域名筛选专业版 v3.0 (海量扩容)      ${NC}"
echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "正在扫描全网优质节点，请稍候...\n"

printf "${BOLD}%-30s | %-8s | %-8s | %-8s | %-10s${NC}\n" "域名 (Domain)" "TLS1.3" "X25519" "HTTP/2" "延迟(ms)"
echo "--------------------------------------------------------------------------------"

BEST_DOMAIN=""
MIN_LATENCY=9999
RECOMMEND_LIST=()

for domain in "${ALL_DOMAINS[@]}"; do
    # 1. 延迟测试
    avg_latency=$(ping -c 2 -i 0.2 -W 1 $domain 2>/dev/null | awk -F '/' 'END {print $5}')
    
    if [ -z "$avg_latency" ]; then
        continue
    fi

    # 2. TLS1.3 & HTTP/2 检测
    http_check=$(curl -I --tlsv1.3 --http2 --connect-timeout 2 -s "https://$domain" 2>&1)
    
    tls_pass=0
    h2_pass=0
    [[ $http_check == *"HTTP/"* ]] && tls_pass=1
    [[ $http_check == *"HTTP/2"* ]] && h2_pass=1

    # 3. X25519 核心检测
    x25519_check=$(timeout 2s openssl s_client -connect ${domain}:443 -tls1_3 -servername ${domain} 2>/dev/null | grep "Server Temp Key")
    
    x_pass=0
    [[ $x25519_check == *"X25519"* ]] && x_pass=1

    # 显示逻辑
    [ $tls_pass -eq 1 ] && tls_str="${GREEN}PASS${NC}" || tls_str="${RED}FAIL${NC}"
    [ $x_pass -eq 1 ] && x_str="${GREEN}YES${NC}" || x_str="${RED}NO${NC}"
    [ $h2_pass -eq 1 ] && h2_str="${GREEN}YES${NC}" || h2_str="${YELLOW}NO${NC}"
    
    latency_int=${avg_latency%.*}
    if [ $latency_int -lt 5 ]; then
        lat_str="${GREEN}${avg_latency}${NC}"
    else
        lat_str="${avg_latency}"
    fi

    printf "%-30s | %-17s | %-17s | %-17s | %-10s\n" "$domain" "$tls_str" "$x_str" "$h2_str" "$lat_str"

    # 推荐逻辑：必须支持 TLS1.3 和 X25519
    if [ $tls_pass -eq 1 ] && [ $x_pass -eq 1 ]; then
        RECOMMEND_LIST+=("$avg_latency|$domain")
        if (( $(echo "$avg_latency < $MIN_LATENCY" | bc -l) )); then
            MIN_LATENCY=$avg_latency
            BEST_DOMAIN=$domain
        fi
    fi
done

echo "--------------------------------------------------------------------------------"
echo -e "\n${PURPLE}${BOLD}🏆 【最终筛选结果 - 推荐榜单】${NC}"

# 按延迟排序显示前 3 名
IFS=$'\n' sorted_list=($(sort -n <<<"${RECOMMEND_LIST[*]}"))
unset IFS

for i in "${!sorted_list[@]}"; do
    if [ $i -lt 3 ]; then
        val=${sorted_list[$i]%%|*}
        dom=${sorted_list[$i]##*|}
        echo -e "${GREEN}${BOLD}第 $((i+1)) 名: $dom (延迟: $val ms)${NC}"
    fi
done

echo -e "\n${BLUE}💡 选型建议：${NC}"
echo -e "1. 优先使用第 1 名作为 REALITY 的 ${YELLOW}dest${NC} 和 ${YELLOW}serverNames${NC}。"
echo -e "2. 如果你是日本 VPS，且榜单里有 .jp 域名，优先选 .jp 域名以实现本地化伪装。"
