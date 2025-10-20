#!/bin/bash

# Nextcloud AIO 离线部署 - 交互式初始设置脚本
# 此脚本用于首次部署时设置环境变量

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

# 生成随机密码
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# 验证域名格式
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

# 验证端口号
validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# 验证IP地址
validate_ip() {
    local ip="$1"
    if [[ "$ip" == "0.0.0.0" ]] || [[ "$ip" == "127.0.0.1" ]]; then
        return 0
    fi
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a ip_parts=($ip)
        for part in "${ip_parts[@]}"; do
            if [ "$part" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "此脚本需要以root用户身份运行"
        exit 1
    fi
}

# 检查Docker是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker 未安装，请先安装Docker"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker 服务未运行，请启动Docker服务"
        exit 1
    fi
}

# 检查镜像是否存在
check_images() {
    log "检查Docker镜像..."
    local missing_images=()
    
    local core_images=(
        "ghcr.io/nextcloud-releases/aio-apache:latest"
        "ghcr.io/nextcloud-releases/aio-postgresql:latest"
        "ghcr.io/nextcloud-releases/aio-nextcloud:latest"
        "ghcr.io/nextcloud-releases/aio-redis:latest"
        "ghcr.io/nextcloud-releases/aio-notify-push:latest"
    )
    
    for image in "${core_images[@]}"; do
        if ! docker image inspect "$image" &> /dev/null; then
            missing_images+=("$image")
        fi
    done
    
    if [ ${#missing_images[@]} -gt 0 ]; then
        error "以下Docker镜像缺失:"
        for image in "${missing_images[@]}"; do
            echo "  - $image"
        done
        echo ""
        echo "请先运行 ./load-images.sh 加载镜像，或使用 ./download-images.sh 下载镜像"
        exit 1
    fi
    
    log "所有必需的Docker镜像已就绪"
}

# 显示欢迎信息
show_welcome() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "    Nextcloud AIO 离线部署 - 初始设置向导"
    echo "=================================================="
    echo -e "${NC}"
    echo ""
    echo "此向导将帮助您配置 Nextcloud AIO 的部署参数。"
    echo "所有配置将保存到 nextcloud-aio.conf 文件中。"
    echo ""
}

# 输入必需的配置
input_required_config() {
    echo -e "${BLUE}=== 必需配置 ===${NC}"
    echo ""
    
    # 域名配置
    while true; do
        read -p "请输入您的域名 (例如: nextcloud.example.com): " NC_DOMAIN
        if validate_domain "$NC_DOMAIN"; then
            break
        else
            error "无效的域名格式，请重新输入"
        fi
    done
    
    # Nextcloud管理员密码
    while true; do
        read -s -p "请输入Nextcloud管理员密码 (用户名为admin): " NEXTCLOUD_PASSWORD
        echo ""
        if [ ${#NEXTCLOUD_PASSWORD} -ge 8 ]; then
            read -s -p "请再次输入密码确认: " NEXTCLOUD_PASSWORD_CONFIRM
            echo ""
            if [ "$NEXTCLOUD_PASSWORD" = "$NEXTCLOUD_PASSWORD_CONFIRM" ]; then
                break
            else
                error "两次输入的密码不一致，请重新输入"
            fi
        else
            error "密码长度至少为8位，请重新输入"
        fi
    done
    
    # 时区配置
    echo ""
    echo "当前系统时区: $(timedatectl show --property=Timezone --value 2>/dev/null || echo "未知")"
    read -p "请输入时区 [默认: Asia/Shanghai]: " TIMEZONE
    TIMEZONE=${TIMEZONE:-"Asia/Shanghai"}
    
    # 数据目录
    echo ""
    read -p "请输入Nextcloud数据目录 [默认: /var/lib/nextcloud-aio/data]: " NEXTCLOUD_DATADIR
    NEXTCLOUD_DATADIR=${NEXTCLOUD_DATADIR:-"/var/lib/nextcloud-aio/data"}
    
    # 挂载目录
    echo ""
    read -p "请输入主机挂载目录 [默认: /mnt]: " NEXTCLOUD_MOUNT
    NEXTCLOUD_MOUNT=${NEXTCLOUD_MOUNT:-"/mnt"}
    
    # 验证数据目录和挂载目录不能相同
    if [ "$NEXTCLOUD_DATADIR" = "$NEXTCLOUD_MOUNT" ]; then
        error "数据目录和挂载目录不能相同"
        exit 1
    fi
}

# 输入网络配置
input_network_config() {
    echo ""
    echo -e "${BLUE}=== 网络配置 ===${NC}"
    echo ""
    
    # Apache端口
    while true; do
        read -p "请输入Apache端口 [默认: 443]: " APACHE_PORT
        APACHE_PORT=${APACHE_PORT:-443}
        if validate_port "$APACHE_PORT"; then
            break
        else
            error "无效的端口号，请输入1-65535之间的数字"
        fi
    done
    
    # Apache IP绑定
    while true; do
        read -p "请输入Apache IP绑定地址 [默认: 0.0.0.0]: " APACHE_IP_BINDING
        APACHE_IP_BINDING=${APACHE_IP_BINDING:-"0.0.0.0"}
        if validate_ip "$APACHE_IP_BINDING"; then
            break
        else
            error "无效的IP地址"
        fi
    done
    
    # Talk端口
    while true; do
        read -p "请输入Talk端口 [默认: 3478]: " TALK_PORT
        TALK_PORT=${TALK_PORT:-3478}
        if validate_port "$TALK_PORT" && [ "$TALK_PORT" -gt 1024 ]; then
            break
        else
            error "Talk端口必须大于1024"
        fi
    done
}

# 输入可选功能配置
input_optional_features() {
    echo ""
    echo -e "${BLUE}=== 可选功能配置 ===${NC}"
    echo ""
    
    # ClamAV
    read -p "是否启用ClamAV病毒扫描? [y/N]: " enable_clamav
    if [[ "$enable_clamav" =~ ^[Yy]$ ]]; then
        CLAMAV_ENABLED="yes"
    else
        CLAMAV_ENABLED="no"
    fi
    
    # Collabora
    read -p "是否启用Collabora在线办公? [y/N]: " enable_collabora
    if [[ "$enable_collabora" =~ ^[Yy]$ ]]; then
        COLLABORA_ENABLED="yes"
    else
        COLLABORA_ENABLED="no"
    fi
    
    # OnlyOffice
    read -p "是否启用OnlyOffice在线办公? [y/N]: " enable_onlyoffice
    if [[ "$enable_onlyoffice" =~ ^[Yy]$ ]]; then
        ONLYOFFICE_ENABLED="yes"
    else
        ONLYOFFICE_ENABLED="no"
    fi
    
    # Talk
    read -p "是否启用Talk聊天功能? [y/N]: " enable_talk
    if [[ "$enable_talk" =~ ^[Yy]$ ]]; then
        TALK_ENABLED="yes"
        read -p "是否启用Talk录制功能? [y/N]: " enable_talk_recording
        if [[ "$enable_talk_recording" =~ ^[Yy]$ ]]; then
            TALK_RECORDING_ENABLED="yes"
        else
            TALK_RECORDING_ENABLED="no"
        fi
    else
        TALK_ENABLED="no"
        TALK_RECORDING_ENABLED="no"
    fi
    
    # Imaginary
    read -p "是否启用Imaginary图像处理? [y/N]: " enable_imaginary
    if [[ "$enable_imaginary" =~ ^[Yy]$ ]]; then
        IMAGINARY_ENABLED="yes"
    else
        IMAGINARY_ENABLED="no"
    fi
    
    # FullTextSearch
    read -p "是否启用全文搜索? [y/N]: " enable_fulltextsearch
    if [[ "$enable_fulltextsearch" =~ ^[Yy]$ ]]; then
        FULLTEXTSEARCH_ENABLED="yes"
    else
        FULLTEXTSEARCH_ENABLED="no"
    fi
    
    # Whiteboard
    read -p "是否启用白板功能? [y/N]: " enable_whiteboard
    if [[ "$enable_whiteboard" =~ ^[Yy]$ ]]; then
        WHITEBOARD_ENABLED="yes"
    else
        WHITEBOARD_ENABLED="no"
    fi
}

# 生成密码
generate_passwords() {
    log "生成安全密码..."
    
    DATABASE_PASSWORD=$(generate_password)
    REDIS_PASSWORD=$(generate_password)
    TURN_SECRET=$(generate_password)
    SIGNALING_SECRET=$(generate_password)
    
    if [ "$ONLYOFFICE_ENABLED" = "yes" ]; then
        ONLYOFFICE_SECRET=$(generate_password)
    else
        ONLYOFFICE_SECRET=""
    fi
    
    if [ "$FULLTEXTSEARCH_ENABLED" = "yes" ]; then
        FULLTEXTSEARCH_PASSWORD=$(generate_password)
    else
        FULLTEXTSEARCH_PASSWORD=""
    fi
    
    if [ "$IMAGINARY_ENABLED" = "yes" ]; then
        IMAGINARY_SECRET=$(generate_password)
    else
        IMAGINARY_SECRET=""
    fi
    
    if [ "$TALK_RECORDING_ENABLED" = "yes" ]; then
        RECORDING_SECRET=$(generate_password)
    else
        RECORDING_SECRET=""
    fi
    
    if [ "$TALK_ENABLED" = "yes" ]; then
        TALK_INTERNAL_SECRET=$(generate_password)
    else
        TALK_INTERNAL_SECRET=""
    fi
    
    if [ "$WHITEBOARD_ENABLED" = "yes" ]; then
        WHITEBOARD_SECRET=$(generate_password)
    else
        WHITEBOARD_SECRET=""
    fi
}

# 保存配置
save_config() {
    log "保存配置到 $CONFIG_FILE ..."
    
    cat > "$CONFIG_FILE" << EOF
# Nextcloud AIO 配置文件
# 由 setup.sh 自动生成于 $(date)

# === 必需配置 ===
NC_DOMAIN=$NC_DOMAIN
NEXTCLOUD_PASSWORD=$NEXTCLOUD_PASSWORD
TIMEZONE=$TIMEZONE
NEXTCLOUD_DATADIR=$NEXTCLOUD_DATADIR
NEXTCLOUD_MOUNT=$NEXTCLOUD_MOUNT

# === 网络配置 ===
APACHE_PORT=$APACHE_PORT
APACHE_IP_BINDING=$APACHE_IP_BINDING
TALK_PORT=$TALK_PORT

# === 自动生成的密码 ===
DATABASE_PASSWORD=$DATABASE_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD
TURN_SECRET=$TURN_SECRET
SIGNALING_SECRET=$SIGNALING_SECRET
ONLYOFFICE_SECRET=$ONLYOFFICE_SECRET
FULLTEXTSEARCH_PASSWORD=$FULLTEXTSEARCH_PASSWORD
IMAGINARY_SECRET=$IMAGINARY_SECRET
RECORDING_SECRET=$RECORDING_SECRET
TALK_INTERNAL_SECRET=$TALK_INTERNAL_SECRET
WHITEBOARD_SECRET=$WHITEBOARD_SECRET

# === 功能开关 ===
CLAMAV_ENABLED="$CLAMAV_ENABLED"
COLLABORA_ENABLED="$COLLABORA_ENABLED"
ONLYOFFICE_ENABLED="$ONLYOFFICE_ENABLED"
TALK_ENABLED="$TALK_ENABLED"
TALK_RECORDING_ENABLED="$TALK_RECORDING_ENABLED"
IMAGINARY_ENABLED="$IMAGINARY_ENABLED"
FULLTEXTSEARCH_ENABLED="$FULLTEXTSEARCH_ENABLED"
WHITEBOARD_ENABLED="$WHITEBOARD_ENABLED"

# === 高级配置 ===
APACHE_MAX_SIZE=17179869184
NEXTCLOUD_UPLOAD_LIMIT=16G
NEXTCLOUD_MEMORY_LIMIT=512M
NEXTCLOUD_MAX_TIME=3600
NEXTCLOUD_TRUSTED_CACERTS_DIR=/usr/local/share/ca-certificates/my-custom-ca
NEXTCLOUD_STARTUP_APPS="deck twofactor_totp tasks calendar contacts notes"
NEXTCLOUD_ADDITIONAL_APKS=imagemagick
NEXTCLOUD_ADDITIONAL_PHP_EXTENSIONS=imagick
INSTALL_LATEST_MAJOR=no
UPDATE_NEXTCLOUD_APPS="no"
REMOVE_DISABLED_APPS=yes
COLLABORA_DICTIONARIES="de_DE en_GB en_US es_ES fr_FR it nl pt_BR pt_PT ru"
FULLTEXTSEARCH_JAVA_OPTIONS="-Xms512M -Xmx512M"
ADDITIONAL_COLLABORA_OPTIONS=['--o:security.seccomp=true']
EOF

    chmod 600 "$CONFIG_FILE"
    log "配置已保存到 $CONFIG_FILE"
}

# 创建必要的目录
create_directories() {
    log "创建必要的目录..."
    
    mkdir -p "$NEXTCLOUD_DATADIR"
    mkdir -p "$(dirname "$NEXTCLOUD_TRUSTED_CACERTS_DIR")"
    
    # 设置正确的权限
    chown -R 33:33 "$NEXTCLOUD_DATADIR" 2>/dev/null || true
    
    log "目录创建完成"
}

# 显示配置摘要
show_summary() {
    echo ""
    echo -e "${BLUE}=== 配置摘要 ===${NC}"
    echo ""
    echo "域名: $NC_DOMAIN"
    echo "Apache端口: $APACHE_PORT"
    echo "数据目录: $NEXTCLOUD_DATADIR"
    echo "挂载目录: $NEXTCLOUD_MOUNT"
    echo "时区: $TIMEZONE"
    echo ""
    echo "启用的功能:"
    [ "$CLAMAV_ENABLED" = "yes" ] && echo "  ✓ ClamAV 病毒扫描"
    [ "$COLLABORA_ENABLED" = "yes" ] && echo "  ✓ Collabora 在线办公"
    [ "$ONLYOFFICE_ENABLED" = "yes" ] && echo "  ✓ OnlyOffice 在线办公"
    [ "$TALK_ENABLED" = "yes" ] && echo "  ✓ Talk 聊天功能"
    [ "$TALK_RECORDING_ENABLED" = "yes" ] && echo "  ✓ Talk 录制功能"
    [ "$IMAGINARY_ENABLED" = "yes" ] && echo "  ✓ Imaginary 图像处理"
    [ "$FULLTEXTSEARCH_ENABLED" = "yes" ] && echo "  ✓ 全文搜索"
    [ "$WHITEBOARD_ENABLED" = "yes" ] && echo "  ✓ 白板功能"
    echo ""
}

# 主函数
main() {
    check_root
    check_docker
    check_images
    
    show_welcome
    
    if [ -f "$CONFIG_FILE" ]; then
        warn "配置文件 $CONFIG_FILE 已存在"
        read -p "是否要重新配置? [y/N]: " reconfigure
        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            log "使用现有配置文件"
            exit 0
        fi
    fi
    
    input_required_config
    input_network_config
    input_optional_features
    generate_passwords
    create_directories
    save_config
    show_summary
    
    echo -e "${GREEN}✓ 初始设置完成！${NC}"
    echo ""
    echo "下一步:"
    echo "1. 运行 ./start.sh 启动 Nextcloud AIO"
    echo "2. 访问 https://$NC_DOMAIN:$APACHE_PORT 开始使用"
    echo ""
    echo "管理命令:"
    echo "  ./start.sh   - 启动服务"
    echo "  ./stop.sh    - 停止服务"
    echo "  ./status.sh  - 查看状态"
}

# 运行主函数
main "$@"