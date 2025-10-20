#!/bin/bash

# Nextcloud AIO 离线部署 - 状态检查脚本
# 显示容器运行状态和健康检查

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/nextcloud-aio.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 状态图标
ICON_RUNNING="🟢"
ICON_STOPPED="🔴"
ICON_STARTING="🟡"
ICON_UNHEALTHY="🟠"
ICON_HEALTHY="✅"
ICON_WARNING="⚠️"
ICON_ERROR="❌"
ICON_INFO="ℹ️"

# 日志函数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] 警告:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] 错误:${NC} $1"
}

info() {
    echo -e "${CYAN}$1${NC}"
}

# 检查Docker是否运行
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker 未安装"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker 服务未运行"
        exit 1
    fi
}

# 加载配置文件
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    else
        warn "配置文件 $CONFIG_FILE 不存在"
        return 1
    fi
}

# 获取容器状态
get_container_status() {
    local container_name="$1"
    
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo "running"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo "stopped"
    else
        echo "missing"
    fi
}

# 获取容器健康状态
get_container_health() {
    local container_name="$1"
    
    local health_status
    health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")
    
    case "$health_status" in
        "healthy")
            echo "healthy"
            ;;
        "unhealthy")
            echo "unhealthy"
            ;;
        "starting")
            echo "starting"
            ;;
        "none"|"<no value>")
            echo "none"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 获取容器运行时间
get_container_uptime() {
    local container_name="$1"
    
    docker inspect --format='{{.State.StartedAt}}' "$container_name" 2>/dev/null | \
    xargs -I {} date -d {} +%s 2>/dev/null | \
    xargs -I {} bash -c 'echo $(($(date +%s) - {}))' 2>/dev/null || echo "0"
}

# 格式化运行时间
format_uptime() {
    local seconds="$1"
    
    if [ "$seconds" -eq 0 ]; then
        echo "未运行"
        return
    fi
    
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    if [ $days -gt 0 ]; then
        echo "${days}天 ${hours}小时 ${minutes}分钟"
    elif [ $hours -gt 0 ]; then
        echo "${hours}小时 ${minutes}分钟"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}分钟 ${secs}秒"
    else
        echo "${secs}秒"
    fi
}

# 获取容器资源使用情况
get_container_resources() {
    local container_name="$1"
    
    if [ "$(get_container_status "$container_name")" != "running" ]; then
        echo "N/A,N/A,N/A"
        return
    fi
    
    local stats
    stats=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}" "$container_name" 2>/dev/null || echo "N/A,N/A,N/A")
    echo "$stats"
}

# 显示容器详细状态
show_container_status() {
    local container_name="$1"
    local display_name="$2"
    local is_optional="${3:-false}"
    
    local status
    status=$(get_container_status "$container_name")
    
    local health
    health=$(get_container_health "$container_name")
    
    local uptime_seconds
    uptime_seconds=$(get_container_uptime "$container_name")
    
    local uptime
    uptime=$(format_uptime "$uptime_seconds")
    
    local resources
    resources=$(get_container_resources "$container_name")
    IFS=',' read -r cpu_usage mem_usage mem_percent <<< "$resources"
    
    # 状态图标和颜色
    local status_icon=""
    local status_color=""
    local health_icon=""
    
    case "$status" in
        "running")
            status_icon="$ICON_RUNNING"
            status_color="$GREEN"
            ;;
        "stopped")
            status_icon="$ICON_STOPPED"
            status_color="$RED"
            ;;
        "missing")
            status_icon="$ICON_ERROR"
            status_color="$RED"
            ;;
    esac
    
    case "$health" in
        "healthy")
            health_icon="$ICON_HEALTHY"
            ;;
        "unhealthy")
            health_icon="$ICON_UNHEALTHY"
            ;;
        "starting")
            health_icon="$ICON_STARTING"
            ;;
        "none")
            health_icon="$ICON_INFO"
            ;;
        *)
            health_icon="$ICON_WARNING"
            ;;
    esac
    
    # 可选容器标记
    local optional_mark=""
    if [ "$is_optional" = "true" ] && [ "$status" = "missing" ]; then
        optional_mark=" ${YELLOW}(可选)${NC}"
    fi
    
    printf "%-25s %s %-10s %s %-12s %-15s %-10s %-15s %-8s%s\n" \
        "$display_name" \
        "$status_icon" \
        "${status_color}${status}${NC}" \
        "$health_icon" \
        "$health" \
        "$uptime" \
        "$cpu_usage" \
        "$mem_usage" \
        "$mem_percent" \
        "$optional_mark"
}

# 显示网络状态
show_network_status() {
    echo ""
    echo -e "${BLUE}=== 网络状态 ===${NC}"
    echo ""
    
    local network_name="nextcloud-aio"
    
    if docker network inspect "$network_name" &> /dev/null; then
        echo -e "${GREEN}✓${NC} Docker网络 '$network_name' 存在"
        
        # 显示网络中的容器
        local containers_in_network
        containers_in_network=$(docker network inspect "$network_name" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "")
        
        if [ -n "$containers_in_network" ]; then
            echo "  连接的容器: $containers_in_network"
        else
            echo "  ${YELLOW}⚠${NC} 网络中没有容器"
        fi
    else
        echo -e "${RED}✗${NC} Docker网络 '$network_name' 不存在"
    fi
}

# 显示卷状态
show_volume_status() {
    echo ""
    echo -e "${BLUE}=== 存储卷状态 ===${NC}"
    echo ""
    
    local volumes=(
        "nextcloud_aio_nextcloud:Nextcloud数据"
        "nextcloud_aio_database:数据库数据"
        "nextcloud_aio_database_dump:数据库备份"
        "nextcloud_aio_redis:Redis数据"
        "nextcloud_aio_apache:Apache配置"
        "nextcloud_aio_clamav:ClamAV数据"
        "nextcloud_aio_elasticsearch:搜索索引"
    )
    
    for volume_info in "${volumes[@]}"; do
        local volume_name="${volume_info%:*}"
        local volume_desc="${volume_info#*:}"
        
        if docker volume inspect "$volume_name" &> /dev/null; then
            local size
            size=$(docker system df -v --format "table {{.VolumeName}}\t{{.Size}}" | grep "^$volume_name" | awk '{print $2}' || echo "N/A")
            echo -e "${GREEN}✓${NC} $volume_desc ($volume_name) - 大小: $size"
        else
            echo -e "${YELLOW}⚠${NC} $volume_desc ($volume_name) - 不存在"
        fi
    done
}

# 显示端口状态
show_port_status() {
    echo ""
    echo -e "${BLUE}=== 端口状态 ===${NC}"
    echo ""
    
    if load_config; then
        # 检查Apache端口
        if command -v netstat &> /dev/null; then
            if netstat -tuln | grep -q ":${APACHE_PORT:-443} "; then
                echo -e "${GREEN}✓${NC} Apache端口 ${APACHE_PORT:-443} 正在监听"
            else
                echo -e "${RED}✗${NC} Apache端口 ${APACHE_PORT:-443} 未监听"
            fi
            
            # 检查Talk端口（如果启用）
            if [ "${TALK_ENABLED:-no}" = "yes" ]; then
                if netstat -tuln | grep -q ":${TALK_PORT:-3478} "; then
                    echo -e "${GREEN}✓${NC} Talk端口 ${TALK_PORT:-3478} 正在监听"
                else
                    echo -e "${RED}✗${NC} Talk端口 ${TALK_PORT:-3478} 未监听"
                fi
            fi
        else
            echo -e "${YELLOW}⚠${NC} netstat 命令不可用，无法检查端口状态"
        fi
        
        # 显示配置的访问地址
        echo ""
        echo "配置的访问地址:"
        echo "  主站点: https://${NC_DOMAIN:-localhost}:${APACHE_PORT:-443}"
        
        if [ "${TALK_ENABLED:-no}" = "yes" ]; then
            echo "  Talk服务: ${NC_DOMAIN:-localhost}:${TALK_PORT:-3478}"
        fi
    fi
}

# 显示系统资源
show_system_resources() {
    echo ""
    echo -e "${BLUE}=== 系统资源 ===${NC}"
    echo ""
    
    # 内存使用情况
    if command -v free &> /dev/null; then
        local mem_info
        mem_info=$(free -h | grep "^Mem:")
        echo "内存使用: $mem_info"
    fi
    
    # 磁盘使用情况
    if command -v df &> /dev/null; then
        echo ""
        echo "磁盘使用情况:"
        df -h | grep -E "(Filesystem|/dev/)" | head -5
    fi
    
    # Docker系统信息
    echo ""
    echo "Docker系统信息:"
    docker system df 2>/dev/null || echo "无法获取Docker系统信息"
}

# 显示日志摘要
show_log_summary() {
    echo ""
    echo -e "${BLUE}=== 最近日志摘要 ===${NC}"
    echo ""
    
    local containers=(
        "nextcloud-aio-apache"
        "nextcloud-aio-nextcloud"
        "nextcloud-aio-database"
    )
    
    for container in "${containers[@]}"; do
        if [ "$(get_container_status "$container")" = "running" ]; then
            echo -e "${CYAN}--- $container 最近日志 ---${NC}"
            docker logs --tail 3 "$container" 2>/dev/null | sed 's/^/  /' || echo "  无法获取日志"
            echo ""
        fi
    done
}

# 显示配置摘要
show_config_summary() {
    echo ""
    echo -e "${BLUE}=== 配置摘要 ===${NC}"
    echo ""
    
    if load_config; then
        echo "域名: ${NC_DOMAIN:-未设置}"
        echo "Apache端口: ${APACHE_PORT:-443}"
        echo "数据目录: ${NEXTCLOUD_DATADIR:-未设置}"
        echo "挂载目录: ${NEXTCLOUD_MOUNT:-未设置}"
        echo "时区: ${TIMEZONE:-未设置}"
        echo ""
        echo "启用的功能:"
        echo "  ClamAV: ${CLAMAV_ENABLED:-no}"
        echo "  Collabora: ${COLLABORA_ENABLED:-no}"
        echo "  OnlyOffice: ${ONLYOFFICE_ENABLED:-no}"
        echo "  Talk: ${TALK_ENABLED:-no}"
        echo "  Imaginary: ${IMAGINARY_ENABLED:-no}"
        echo "  FullTextSearch: ${FULLTEXTSEARCH_ENABLED:-no}"
        echo "  Whiteboard: ${WHITEBOARD_ENABLED:-no}"
    else
        echo -e "${YELLOW}⚠${NC} 无法加载配置文件"
    fi
}

# 主状态显示
show_main_status() {
    echo ""
    echo -e "${PURPLE}=== Nextcloud AIO 状态总览 ===${NC}"
    echo ""
    
    printf "%-25s %-12s %-14s %-15s %-10s %-15s %-8s\n" \
        "容器名称" "状态" "健康检查" "运行时间" "CPU" "内存使用" "内存%"
    echo "$(printf '%.0s-' {1..100})"
    
    # 核心容器
    show_container_status "nextcloud-aio-apache" "Apache (前端)"
    show_container_status "nextcloud-aio-nextcloud" "Nextcloud (主应用)"
    show_container_status "nextcloud-aio-notify-push" "Notify Push"
    show_container_status "nextcloud-aio-database" "PostgreSQL (数据库)"
    show_container_status "nextcloud-aio-redis" "Redis (缓存)"
    
    echo ""
    echo "可选容器:"
    echo "$(printf '%.0s-' {1..100})"
    
    # 可选容器
    show_container_status "nextcloud-aio-clamav" "ClamAV (防病毒)" true
    show_container_status "nextcloud-aio-collabora" "Collabora (办公)" true
    show_container_status "nextcloud-aio-onlyoffice" "OnlyOffice (办公)" true
    show_container_status "nextcloud-aio-talk" "Talk (通话)" true
    show_container_status "nextcloud-aio-talk-recording" "Talk Recording" true
    show_container_status "nextcloud-aio-imaginary" "Imaginary (图像)" true
    show_container_status "nextcloud-aio-fulltextsearch" "FullTextSearch" true
    show_container_status "nextcloud-aio-whiteboard" "Whiteboard (白板)" true
}

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --simple     显示简化状态"
    echo "  --detailed   显示详细状态（默认）"
    echo "  --logs       显示最近日志"
    echo "  --resources  显示系统资源"
    echo "  --config     显示配置信息"
    echo "  --help       显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                    # 显示完整状态"
    echo "  $0 --simple           # 显示简化状态"
    echo "  $0 --logs             # 显示状态和日志"
    echo ""
}

# 主函数
main() {
    local show_simple=false
    local show_logs=false
    local show_resources=false
    local show_config=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --simple)
                show_simple=true
                shift
                ;;
            --detailed)
                show_simple=false
                shift
                ;;
            --logs)
                show_logs=true
                shift
                ;;
            --resources)
                show_resources=true
                shift
                ;;
            --config)
                show_config=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    check_docker
    
    # 显示主状态
    show_main_status
    
    # 根据参数显示额外信息
    if [ "$show_simple" = "false" ]; then
        show_network_status
        show_volume_status
        show_port_status
    fi
    
    if [ "$show_resources" = "true" ]; then
        show_system_resources
    fi
    
    if [ "$show_config" = "true" ]; then
        show_config_summary
    fi
    
    if [ "$show_logs" = "true" ]; then
        show_log_summary
    fi
    
    echo ""
    echo -e "${GREEN}状态检查完成！${NC}"
    echo ""
    echo "管理命令:"
    echo "  ./start.sh   - 启动所有容器"
    echo "  ./stop.sh    - 停止所有容器"
    echo "  ./status.sh  - 查看状态（当前命令）"
    echo ""
}

# 运行主函数
main "$@"