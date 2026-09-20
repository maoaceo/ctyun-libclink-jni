#!/bin/bash

# WiFi信息获取脚本 - 增强兼容性版本
# 无需root权限，兼容中文输出

DEBUG_MODE=false

# 日志函数
log_debug() {
    if [ "$DEBUG_MODE" = true ]; then
        echo "[DEBUG] $*" >&2
    fi
}

log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

# 检查并尝试安装依赖
check_dependencies() {
    local missing_deps=()
    local packages=()
    
    # 检查基本命令
    for cmd in "ip" "grep" "awk" "sed" "head" "cut"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "基础命令 $cmd 缺失"
            return 1
        fi
    done
    
    # 检查无线相关命令
    if ! command -v "iw" >/dev/null 2>&1; then
        log_info "iw命令未找到，尝试寻找替代方案"
        
        # 检查iwconfig
        if command -v "iwconfig" >/dev/null 2>&1; then
            log_info "找到iwconfig，将使用它作为替代"
        else
            log_info "提示: 安装iw可获取更完整的信息"
            log_info "Ubuntu/Debian: sudo apt install wireless-tools iw"
            log_info "Fedora/RHEL: sudo dnf install wireless-tools iw"
            log_info "Arch: sudo pacman -S iw"
        fi
    fi
    
    return 0
}


# 获取WiFi接口（最兼容的方法）
get_wifi_interface() {
    log_debug "搜索WiFi接口..."
    
    # 方法1: 通过/sys/class/net（最可靠）
    if [ -d "/sys/class/net" ]; then
        for iface in /sys/class/net/*; do
            iface_name=$(basename "$iface")
            
            # 检查无线设备标志
            if [ -f "$iface/wireless" ] || [ -f "$iface/phy80211" ]; then
                log_debug "通过/sys发现无线接口: $iface_name"
                echo "$iface_name"
                return 0
            fi
            
            # 检查uevent中的设备类型
            if [ -f "$iface/uevent" ]; then
                if grep -q "DEVTYPE=wlan" "$iface/uevent" 2>/dev/null || \
                   grep -q "DEVTYPE=wifi" "$iface/uevent" 2>/dev/null; then
                    log_debug "通过uevent发现无线接口: $iface_name"
                    echo "$iface_name"
                    return 0
                fi
            fi
        done
    fi
    
    # 方法2: 使用ip命令
    if command -v "ip" >/dev/null 2>&1; then
        # 查找wl*接口（常见的无线接口命名）
        interface=$(ip link show 2>/dev/null | grep -E '^[0-9]+: wl' | \
                    head -1 | awk -F: '{print $2}' | sed 's/^ //')
        [ -n "$interface" ] && echo "$interface" && return 0
        
        # 查找wlan*接口
        interface=$(ip link show 2>/dev/null | grep -E '^[0-9]+: wlan' | \
                    head -1 | awk -F: '{print $2}' | sed 's/^ //')
        [ -n "$interface" ] && echo "$interface" && return 0
    fi
    
    # 方法3: 使用iw命令
    if command -v "iw" >/dev/null 2>&1; then
        interface=$(iw dev 2>/dev/null | grep "Interface" | head -1 | awk '{print $2}')
        [ -n "$interface" ] && echo "$interface" && return 0
    fi
    
    # 方法4: 使用iwconfig
    if command -v "iwconfig" >/dev/null 2>&1; then
        interface=$(iwconfig 2>/dev/null | grep -E "^[[:alnum:]]+" | \
                    grep -v "no wireless" | head -1 | awk '{print $1}')
        [ -n "$interface" ] && echo "$interface" && return 0
    fi
    
    # 方法5: 检查/proc/net/wireless
    if [ -f "/proc/net/wireless" ]; then
        interface=$(awk 'NR>2 {print $1}' /proc/net/wireless 2>/dev/null | \
                    head -1 | tr -d :)
        [ -n "$interface" ] && echo "$interface" && return 0
    fi
    
    log_error "未找到无线网络接口"
    return 1
}

# 解码字符串中的转义序列
decode_string() {
    local str="$1"
    
    # 如果没有转义序列，直接返回
    if ! echo "$str" | grep -q '\\x'; then
        echo "$str"
        return
    fi
    
    # 使用多种方法尝试解码
    local decoded=""
    
    # 方法1: 使用printf（最可靠）
    decoded=$(printf "%b" "$str" 2>/dev/null)
    
    # 方法2: 使用echo -e（备选）
    if [ -z "$decoded" ] || [ "$decoded" = "$str" ]; then
        decoded=$(echo -e "$str" 2>/dev/null)
    fi
    
    # 方法3: 手动处理常见中文转义
    if [ "$decoded" = "$str" ]; then
        # 替换常见的中文字符转义
        decoded=$(echo "$str" | sed \
            -e 's/\\xe5/å/g' \
            -e 's/\\xb1/±/g' \
            -e 's/\\x8c/Œ/g' \
            -e 's/\\x88/ˆ/g' 2>/dev/null)
    fi
    
    echo "${decoded:-$str}"
}

# 清理和格式化字符串
clean_string() {
    local str="$1"
    
    # 去除首尾空格
    str=$(echo "$str" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 解码转义序列
    str=$(decode_string "$str")
    
    # 移除可能的引号
    str=$(echo "$str" | sed "s/^['\"]//;s/['\"]$//")
    
    echo "$str"
}

# 使用iw获取信息（现代系统）
get_info_iw() {
    local interface="$1"
    log_debug "使用iw命令..."
    
    local iw_info
    if ! iw_info=$(iw dev "$interface" link 2>&1); then
        log_debug "iw命令执行失败: $iw_info"
        return 1
    fi
    
    log_debug "iw输出: $iw_info"
    
    # 提取SSID（处理可能的编码问题）
    local ssid_raw=$(echo "$iw_info" | grep -E "SSID:" | cut -d: -f2-)
    local ssid=$(clean_string "$ssid_raw")
    
    # 提取信号强度
    local signal=$(echo "$iw_info" | grep -E "signal:" | awk '{print $2}' | grep -oE '[0-9\-]+')
    
    # 提取频率
    local freq=$(echo "$iw_info" | grep -E "freq:" | awk '{print $2}')
    
    # 提取其他信息
    local tx_rate=$(echo "$iw_info" | grep -E "tx bitrate:" | awk '{for(i=3;i<=NF;i++) printf $i" "; print ""}' | sed 's/ $//')
    local rx_rate=$(echo "$iw_info" | grep -E "rx bitrate:" | awk '{for(i=3;i<=NF;i++) printf $i" "; print ""}' | sed 's/ $//')
    
    # 解析频段和信道
    local band="未知"
    local channel="未知"
    if [ -n "$freq" ] && [[ "$freq" =~ ^[0-9]+$ ]]; then
        if [ "$freq" -le 2484 ]; then
            band="2.4GHz"
            channel=$(( (freq - 2412) / 5 + 1 ))
        elif [ "$freq" -le 5935 ]; then
            band="5GHz"
            channel=$(( (freq - 5180) / 5 + 36 ))
        else
            band="6GHz/其他"
        fi
    fi
    
    # 返回结果
    echo "SSID:$ssid"
    echo "信号强度:${signal:--}"
    echo "频率:${freq:--}"
    echo "频段:$band"
    echo "信道:$channel"
    echo "发送速率:${tx_rate:--}"
    echo "接收速率:${rx_rate:--}"
    echo "接口:$interface"
    
    return 0
}

# 使用iwconfig获取信息（传统系统）
get_info_iwconfig() {
    local interface="$1"
    log_debug "使用iwconfig命令..."
    
    local iwconfig_info
    if ! iwconfig_info=$(iwconfig "$interface" 2>&1); then
        log_debug "iwconfig命令执行失败"
        return 1
    fi
    
    log_debug "iwconfig输出: $iwconfig_info"
    
    # 提取ESSID
    local essid_raw=$(echo "$iwconfig_info" | grep -o 'ESSID:"[^"]*"' | cut -d'"' -f2)
    local ssid=$(clean_string "$essid_raw")
    
    # 提取信号强度
    local signal=$(echo "$iwconfig_info" | grep -o "Signal level=[0-9\-]*" | cut -d= -f2)
    
    # 提取频率
    local freq_raw=$(echo "$iwconfig_info" | grep -o "Frequency:[0-9.]* GHz" | cut -d: -f2)
    local freq=""
    if [ -n "$freq_raw" ]; then
        freq=$(echo "$freq_raw" | awk '{printf "%.0f", $1 * 1000}')
    fi
    
    # 提取其他信息
    local bitrate=$(echo "$iwconfig_info" | grep -o "Bit Rate=[0-9.]*" | cut -d= -f2)
    
    # 返回结果
    echo "SSID:$ssid"
    echo "信号强度:${signal:--}"
    echo "频率:${freq:--}"
    echo "频段:未知"
    echo "信道:未知"
    echo "发送速率:${bitrate:--}"
    echo "接收速率:--"
    echo "接口:$interface"
    
    return 0
}

# 获取加密类型
get_encryption_type() {
    local ssid="$1"
    local interface="$2"
    
    # 方法1: 使用nmcli
    if command -v "nmcli" >/dev/null 2>&1; then
        log_debug "尝试使用nmcli获取加密类型..."
        
        # 获取WiFi列表
        local wifi_list
        if wifi_list=$(nmcli -t -f SSID,SECURITY device wifi 2>/dev/null); then
            local security=""
            
            # 逐行查找匹配的SSID
            while IFS= read -r line; do
                local list_ssid=$(echo "$line" | cut -d: -f1)
                list_ssid=$(clean_string "$list_ssid")
                
                if [ "$list_ssid" = "$ssid" ]; then
                    security=$(echo "$line" | cut -d: -f2-)
                    security=$(clean_string "$security")
                    [ "$security" = "--" ] && security="开放网络"
                    echo "$security"
                    return 0
                fi
            done <<< "$wifi_list"
        fi
    fi
    
    # 方法2: 检查已知的加密特征
    log_debug "无法确定加密类型"
    echo "未知"
    return 0
}

# 主函数
main() {
    log_info "开始WiFi信息扫描..."
    
    # 检查依赖
    if ! check_dependencies; then
        log_error "系统缺少必要组件"
        exit 1
    fi
    
    # 获取WiFi接口
    local interface
    if ! interface=$(get_wifi_interface); then
        log_error "未检测到无线网卡或未连接"
        echo "可能的原因:"
        echo "1. 无线网卡未启用"
        echo "2. 未安装无线网卡驱动"
        echo "3. 系统运行在虚拟机中"
        echo "4. 缺少无线工具包"
        exit 1
    fi
    
    log_info "发现无线接口: $interface"
    
    # 尝试获取连接信息
    local wifi_info=""
    
    # 首先尝试iw（现代方法）
    if wifi_info=$(get_info_iw "$interface"); then
        log_info "使用iw获取信息成功"
    # 然后尝试iwconfig（传统方法）
    elif wifi_info=$(get_info_iwconfig "$interface"); then
        log_info "使用iwconfig获取信息成功"
    else
        log_error "无法获取WiFi连接信息"
        echo "请检查:"
        echo "1. WiFi是否已连接"
        echo "2. 尝试命令: iw dev $interface link"
        echo "3. 尝试命令: iwconfig $interface"
        exit 1
    fi
    
    # 解析获取的信息
    local ssid=$(echo "$wifi_info" | grep "^SSID:" | cut -d: -f2-)
    local signal=$(echo "$wifi_info" | grep "^信号强度:" | cut -d: -f2)
    local freq=$(echo "$wifi_info" | grep "^频率:" | cut -d: -f2)
    local band=$(echo "$wifi_info" | grep "^频段:" | cut -d: -f2)
    local channel=$(echo "$wifi_info" | grep "^信道:" | cut -d: -f2)
    local tx_rate=$(echo "$wifi_info" | grep "^发送速率:" | cut -d: -f2)
    local rx_rate=$(echo "$wifi_info" | grep "^接收速率:" | cut -d: -f2)
    
    # 获取加密类型
    local encryption=""
    if [ -n "$ssid" ] && [ "$ssid" != "--" ] && [ "$ssid" != "未知" ]; then
        encryption=$(get_encryption_type "$ssid" "$interface")
    else
        encryption="未知"
    fi
    
    # 输出结果
    echo ""
    echo "=== WiFi连接信息 ==="
    echo "WiFi名称: $ssid"
    echo "信号强度: $signal dBm"
    echo "频率: $freq MHz"
    echo "频段: $band"
    echo "信道: $channel"
    echo "发送速率: $tx_rate"
    echo "接收速率: $rx_rate"
    echo "加密类型: $encryption"
    echo "网络接口: $interface"
    echo "==================="
}

# 设置编码环境
export LC_ALL=C.UTF-8 2>/dev/null
export LANG=C.UTF-8 2>/dev/null

# 执行主函数
main