#!/bin/bash

# Nextcloud AIO 离线部署 - 容器停止脚本
# 优雅地停止所有容器

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/nextcloud-aio.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "此脚本需要以root用户身份运行"
        exit 1
    fi
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

# 获取运行中的Nextcloud AIO容器
get_running_containers() {
    docker ps --filter "name=nextcloud-aio-" --format '{{.Names}}' | sort
}

# 优雅停止容器
graceful_stop_container() {
    local container_name="$1"
    local timeout="${2:-30}"
    
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        log "停止容器: $container_name (超时: ${timeout}秒)"
        
        # 发送SIGTERM信号
        docker stop --time="$timeout" "$container_name" 2>/dev/null || {
            warn "容器 $container_name 停止超时，强制终止"
            docker kill "$container_name" 2>/dev/null || true
        }
        
        # 验证容器是否已停止
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            error "容器 $container_name 仍在运行"
            return 1
        else
            log "容器 $container_name 已停止"
        fi
    else
        log "容器 $container_name 未运行"
    fi
}

# 按依赖顺序停止容器
stop_containers_ordered() {
    log "开始停止 Nextcloud AIO 容器..."
    
    # 定义停止顺序（与启动顺序相反）
    local containers_order=(
        "nextcloud-aio-apache:10"           # 首先停止前端
        "nextcloud-aio-notify-push:10"      # 停止推送服务
        "nextcloud-aio-nextcloud:60"        # 停止主应用（给更多时间）
        "nextcloud-aio-whiteboard:10"       # 停止可选服务
        "nextcloud-aio-fulltextsearch:30"   # 停止搜索服务
        "nextcloud-aio-imaginary:10"        # 停止图像处理
        "nextcloud-aio-talk-recording:10"   # 停止录制服务
        "nextcloud-aio-talk:10"             # 停止通话服务
        "nextcloud-aio-onlyoffice:10"       # 停止办公套件
        "nextcloud-aio-collabora:10"        # 停止协作服务
        "nextcloud-aio-clamav:10"           # 停止防病毒
        "nextcloud-aio-redis:10"            # 停止缓存
        "nextcloud-aio-database:60"         # 最后停止数据库（给更多时间）
    )
    
    for container_info in "${containers_order[@]}"; do
        local container_name="${container_info%:*}"
        local timeout="${container_info#*:}"
        graceful_stop_container "$container_name" "$timeout"
    done
}

# 停止所有容器（备用方法）
stop_all_containers() {
    log "停止所有 Nextcloud AIO 容器..."
    
    local running_containers
    running_containers=$(get_running_containers)
    
    if [ -z "$running_containers" ]; then
        log "没有运行中的 Nextcloud AIO 容器"
        return 0
    fi
    
    echo "发现运行中的容器:"
    echo "$running_containers"
    echo ""
    
    # 并行停止所有容器
    echo "$running_containers" | while read -r container; do
        [ -n "$container" ] && graceful_stop_container "$container" 30 &
    done
    
    # 等待所有停止操作完成
    wait
}

# 删除容器（可选）
remove_containers() {
    local remove_flag="$1"
    
    if [ "$remove_flag" != "--remove" ]; then
        return 0
    fi
    
    log "删除已停止的容器..."
    
    local containers=(
        "nextcloud-aio-apache"
        "nextcloud-aio-notify-push"
        "nextcloud-aio-nextcloud"
        "nextcloud-aio-whiteboard"
        "nextcloud-aio-fulltextsearch"
        "nextcloud-aio-imaginary"
        "nextcloud-aio-talk-recording"
        "nextcloud-aio-talk"
        "nextcloud-aio-onlyoffice"
        "nextcloud-aio-collabora"
        "nextcloud-aio-clamav"
        "nextcloud-aio-redis"
        "nextcloud-aio-database"
    )
    
    for container in "${containers[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            log "删除容器: $container"
            docker rm "$container" 2>/dev/null || warn "删除容器 $container 失败"
        fi
    done
}

# 清理网络（可选）
cleanup_network() {
    local cleanup_flag="$1"
    
    if [ "$cleanup_flag" != "--cleanup" ]; then
        return 0
    fi
    
    local network_name="nextcloud-aio"
    
    if docker network inspect "$network_name" &> /dev/null; then
        log "删除Docker网络: $network_name"
        docker network rm "$network_name" 2>/dev/null || warn "删除网络 $network_name 失败"
    fi
}

# 显示停止结果
show_result() {
    echo ""
    echo -e "${BLUE}=== 容器停止状态 ===${NC}"
    echo ""
    
    local running_containers
    running_containers=$(get_running_containers)
    
    if [ -z "$running_containers" ]; then
        echo -e "${GREEN}✓ 所有 Nextcloud AIO 容器已停止${NC}"
    else
        echo -e "${YELLOW}⚠ 以下容器仍在运行:${NC}"
        echo "$running_containers"
    fi
    
    echo ""
    echo "所有容器状态:"
    docker ps -a --filter "name=nextcloud-aio-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true
    echo ""
}

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --remove     停止后删除容器"
    echo "  --cleanup    删除容器和网络"
    echo "  --force      强制停止所有容器（不按顺序）"
    echo "  --help       显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                    # 仅停止容器"
    echo "  $0 --remove           # 停止并删除容器"
    echo "  $0 --cleanup          # 停止容器，删除容器和网络"
    echo "  $0 --force            # 强制并行停止所有容器"
    echo ""
}

# 主函数
main() {
    local remove_flag=""
    local cleanup_flag=""
    local force_flag=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --remove)
                remove_flag="--remove"
                shift
                ;;
            --cleanup)
                cleanup_flag="--cleanup"
                remove_flag="--remove"  # cleanup 包含 remove
                shift
                ;;
            --force)
                force_flag="--force"
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
    
    check_root
    check_docker
    
    # 检查是否有运行中的容器
    local running_containers
    running_containers=$(get_running_containers)
    
    if [ -z "$running_containers" ]; then
        log "没有运行中的 Nextcloud AIO 容器"
        show_result
        exit 0
    fi
    
    # 根据参数选择停止方式
    if [ "$force_flag" = "--force" ]; then
        stop_all_containers
    else
        stop_containers_ordered
    fi
    
    # 可选操作
    remove_containers "$remove_flag"
    cleanup_network "$cleanup_flag"
    
    show_result
    
    log "Nextcloud AIO 停止完成！"
}

# 运行主函数
main "$@"