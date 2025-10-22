#!/bin/bash

# Nextcloud AIO 自定义 CA 证书部署脚本
# 此脚本将自动修改 OnlyOffice 镜像并部署整个 Nextcloud AIO 环境

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/nextcloud-aio.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] 信息:${NC} $1"
}

# 显示使用说明
show_usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -c, --cert-dir DIR          证书目录路径"
    echo "  -t, --target-image IMAGE    自定义镜像名称 (默认: nextcloud-aio-onlyoffice-custom:latest)"
    echo "  -f, --force                 强制重新构建镜像"
    echo "  --skip-image-build          跳过镜像构建，直接使用现有镜像"
    echo "  --only-build-image          只构建镜像，不启动服务"
    echo "  -h, --help                  显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -c /path/to/certificates"
    echo "  $0 --skip-image-build"
    echo "  $0 --only-build-image -f"
    echo ""
}

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "缺少必需的依赖: ${missing_deps[*]}"
        exit 1
    fi
    
    # 检查必需的脚本
    local required_scripts=("setup.sh" "start.sh" "modify-onlyoffice-image.sh")
    for script in "${required_scripts[@]}"; do
        if [ ! -f "${SCRIPT_DIR}/${script}" ]; then
            error "缺少必需的脚本: ${script}"
            exit 1
        fi
    done
}

# 加载配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log "加载配置文件: $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        warn "配置文件不存在，将运行初始设置"
        return 1
    fi
}

# 运行初始设置
run_setup() {
    log "运行初始设置..."
    if ! "${SCRIPT_DIR}/setup.sh"; then
        error "初始设置失败"
        exit 1
    fi
    
    # 重新加载配置
    load_config
}

# 构建自定义镜像
build_custom_image() {
    local cert_dir="$1"
    local target_image="$2"
    local force="$3"
    
    log "构建自定义 OnlyOffice 镜像..."
    
    local build_args=()
    if [ -n "$cert_dir" ]; then
        build_args+=("-c" "$cert_dir")
    fi
    
    build_args+=("-t" "$target_image")
    
    if [ "$force" = "true" ]; then
        build_args+=("-f")
    fi
    
    if ! "${SCRIPT_DIR}/modify-onlyoffice-image.sh" "${build_args[@]}"; then
        error "自定义镜像构建失败"
        exit 1
    fi
    
    log "自定义镜像构建完成: $target_image"
}

# 更新配置以使用自定义镜像
update_config_for_custom_image() {
    local target_image="$1"
    
    log "更新配置以使用自定义镜像"
    
    # 备份配置文件
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # 更新或添加自定义镜像配置
    if grep -q "^ONLYOFFICE_CUSTOM_IMAGE=" "$CONFIG_FILE"; then
        sed -i "s|^ONLYOFFICE_CUSTOM_IMAGE=.*|ONLYOFFICE_CUSTOM_IMAGE=\"$target_image\"|" "$CONFIG_FILE"
    else
        echo "" >> "$CONFIG_FILE"
        echo "# 自定义 OnlyOffice 镜像（包含 CA 证书）" >> "$CONFIG_FILE"
        echo "ONLYOFFICE_CUSTOM_IMAGE=\"$target_image\"" >> "$CONFIG_FILE"
    fi
    
    info "配置已更新，将使用自定义镜像: $target_image"
}

# 验证证书配置
validate_certificate_setup() {
    local cert_dir="$1"
    
    if [ -z "$cert_dir" ]; then
        if [ -n "$NEXTCLOUD_TRUSTED_CACERTS_DIR" ]; then
            cert_dir="$NEXTCLOUD_TRUSTED_CACERTS_DIR"
        else
            error "未指定证书目录，请使用 -c 选项或在配置文件中设置 NEXTCLOUD_TRUSTED_CACERTS_DIR"
            return 1
        fi
    fi
    
    if [ ! -d "$cert_dir" ]; then
        error "证书目录不存在: $cert_dir"
        return 1
    fi
    
    # 检查证书文件
    local cert_files=($(find "$cert_dir" -name "*.crt" -o -name "*.pem" 2>/dev/null))
    if [ ${#cert_files[@]} -eq 0 ]; then
        error "证书目录中没有找到 .crt 或 .pem 文件: $cert_dir"
        return 1
    fi
    
    log "证书验证通过，发现 ${#cert_files[@]} 个证书文件"
    return 0
}

# 启动服务
start_services() {
    log "启动 Nextcloud AIO 服务..."
    
    if ! "${SCRIPT_DIR}/start.sh"; then
        error "服务启动失败"
        exit 1
    fi
    
    log "服务启动完成"
}

# 显示部署状态
show_deployment_status() {
    echo ""
    log "部署完成！"
    echo ""
    
    if [ -f "${SCRIPT_DIR}/status.sh" ]; then
        info "当前服务状态:"
        "${SCRIPT_DIR}/status.sh"
    fi
    
    echo ""
    echo "下一步操作:"
    echo "1. 访问 Nextcloud 管理界面配置应用"
    echo "2. 检查 OnlyOffice 是否正常工作"
    echo "3. 验证自定义 CA 证书是否生效"
    echo ""
    echo "有用的命令:"
    echo "  查看服务状态: ./status.sh"
    echo "  查看容器日志: docker logs nextcloud-aio-onlyoffice"
    echo "  停止服务: ./stop.sh"
    echo ""
}

# 主函数
main() {
    local cert_dir=""
    local target_image="nextcloud-aio-onlyoffice-custom:latest"
    local force="false"
    local skip_image_build="false"
    local only_build_image="false"
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--cert-dir)
                cert_dir="$2"
                shift 2
                ;;
            -t|--target-image)
                target_image="$2"
                shift 2
                ;;
            -f|--force)
                force="true"
                shift
                ;;
            --skip-image-build)
                skip_image_build="true"
                shift
                ;;
            --only-build-image)
                only_build_image="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log "开始 Nextcloud AIO 自定义 CA 证书部署..."
    
    # 检查依赖
    check_dependencies
    
    # 加载配置，如果失败则运行设置
    if ! load_config; then
        run_setup
    fi
    
    # 如果不跳过镜像构建
    if [ "$skip_image_build" != "true" ]; then
        # 验证证书配置
        if ! validate_certificate_setup "$cert_dir"; then
            exit 1
        fi
        
        # 使用验证后的证书目录
        if [ -z "$cert_dir" ]; then
            cert_dir="$NEXTCLOUD_TRUSTED_CACERTS_DIR"
        fi
        
        # 构建自定义镜像
        build_custom_image "$cert_dir" "$target_image" "$force"
        
        # 更新配置
        update_config_for_custom_image "$target_image"
        
        # 重新加载配置
        load_config
    fi
    
    # 如果只构建镜像，则退出
    if [ "$only_build_image" = "true" ]; then
        log "镜像构建完成，退出"
        exit 0
    fi
    
    # 启动服务
    start_services
    
    # 显示部署状态
    show_deployment_status
}

# 运行主函数
main "$@"