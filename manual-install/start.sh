#!/bin/bash

# Nextcloud AIO 离线部署 - 容器启动脚本
# 使用 docker run 命令启动各个容器

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

# 加载配置文件
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        error "配置文件 $CONFIG_FILE 不存在"
        echo "请先运行 ./setup.sh 进行初始设置"
        exit 1
    fi
    
    log "加载配置文件: $CONFIG_FILE"
    source "$CONFIG_FILE"
    
    # 验证必需的配置
    if [ -z "$NC_DOMAIN" ] || [ -z "$NEXTCLOUD_PASSWORD" ] || [ -z "$DATABASE_PASSWORD" ]; then
        error "配置文件中缺少必需的参数"
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

# 创建Docker网络
create_network() {
    local network_name="nextcloud-aio"
    
    if ! docker network inspect "$network_name" &> /dev/null; then
        log "创建Docker网络: $network_name"
        docker network create "$network_name"
    else
        log "Docker网络已存在: $network_name"
    fi
}

# 创建Docker卷
create_volumes() {
    log "创建Docker卷..."
    
    local volumes=(
        "nextcloud_aio_nextcloud"
        "nextcloud_aio_database"
        "nextcloud_aio_database_dump"
        "nextcloud_aio_redis"
        "nextcloud_aio_apache"
    )
    
    # 根据启用的功能添加额外的卷
    [ "$CLAMAV_ENABLED" = "yes" ] && volumes+=("nextcloud_aio_clamav")
    [ "$ONLYOFFICE_ENABLED" = "yes" ] && volumes+=("nextcloud_aio_onlyoffice")
    [ "$FULLTEXTSEARCH_ENABLED" = "yes" ] && volumes+=("nextcloud_aio_elasticsearch")
    [ "$TALK_RECORDING_ENABLED" = "yes" ] && volumes+=("nextcloud_aio_talk_recording")
    
    for volume in "${volumes[@]}"; do
        if ! docker volume inspect "$volume" &> /dev/null; then
            docker volume create "$volume"
            log "创建卷: $volume"
        fi
    done
}

# 停止并删除现有容器
cleanup_containers() {
    log "清理现有容器..."
    
    local containers=(
        "nextcloud-aio-apache"
        "nextcloud-aio-nextcloud"
        "nextcloud-aio-notify-push"
        "nextcloud-aio-database"
        "nextcloud-aio-redis"
        "nextcloud-aio-clamav"
        "nextcloud-aio-collabora"
        "nextcloud-aio-onlyoffice"
        "nextcloud-aio-talk"
        "nextcloud-aio-talk-recording"
        "nextcloud-aio-imaginary"
        "nextcloud-aio-fulltextsearch"
        "nextcloud-aio-whiteboard"
    )
    
    for container in "${containers[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            log "停止并删除容器: $container"
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        fi
    done
}

# 启动数据库容器
start_database() {
    log "启动PostgreSQL数据库容器..."
    
    docker run -d \
        --name nextcloud-aio-database \
        --network nextcloud-aio \
        --user 999 \
        --init \
        --restart unless-stopped \
        --read-only \
        --tmpfs /var/run/postgresql \
        --cap-drop NET_RAW \
        --shm-size 268435456 \
        --stop-timeout 1800 \
        -v nextcloud_aio_database:/var/lib/postgresql/data:rw \
        -v nextcloud_aio_database_dump:/mnt/data:rw \
        -e POSTGRES_PASSWORD="$DATABASE_PASSWORD" \
        -e POSTGRES_DB=nextcloud_database \
        -e POSTGRES_USER=nextcloud \
        -e TZ="$TIMEZONE" \
        -e PGTZ="$TIMEZONE" \
        ghcr.io/nextcloud-releases/aio-postgresql:latest
    
    # 等待数据库启动
    log "等待数据库启动..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if docker exec nextcloud-aio-database pg_isready -U nextcloud &> /dev/null; then
            log "数据库已就绪"
            break
        fi
        sleep 2
        ((retries--))
    done
    
    if [ $retries -eq 0 ]; then
        error "数据库启动超时"
        exit 1
    fi
}

# 启动Redis容器
start_redis() {
    log "启动Redis容器..."
    
    docker run -d \
        --name nextcloud-aio-redis \
        --network nextcloud-aio \
        --user 999 \
        --init \
        --restart unless-stopped \
        --read-only \
        --tmpfs /var/run/redis \
        --tmpfs /tmp \
        --cap-drop NET_RAW \
        -v nextcloud_aio_redis:/data:rw \
        -e REDIS_HOST_PASSWORD="$REDIS_PASSWORD" \
        -e TZ="$TIMEZONE" \
        ghcr.io/nextcloud-releases/aio-redis:latest
    
    # 等待Redis启动
    log "等待Redis启动..."
    sleep 5
}

# 启动可选容器
start_optional_containers() {
    # ClamAV
    if [ "$CLAMAV_ENABLED" = "yes" ]; then
        log "启动ClamAV容器..."
        docker run -d \
            --name nextcloud-aio-clamav \
            --network nextcloud-aio \
            --user 100 \
            --init \
            --restart unless-stopped \
            --read-only \
            --tmpfs /var/log/clamav \
            --tmpfs /var/lib/clamav \
            --tmpfs /tmp \
            --cap-drop NET_RAW \
            -v nextcloud_aio_clamav:/var/lib/clamav:rw \
            -e TZ="$TIMEZONE" \
            ghcr.io/nextcloud-releases/aio-clamav:latest
    fi
    
    # Collabora
    if [ "$COLLABORA_ENABLED" = "yes" ]; then
        log "启动Collabora容器..."
        docker run -d \
            --name nextcloud-aio-collabora \
            --network nextcloud-aio \
            --init \
            --restart unless-stopped \
            --cap-add MKNOD \
            --cap-drop NET_RAW \
            -e aliasgroup1="https://$NC_DOMAIN:$APACHE_PORT" \
            -e extra_params="--o:ssl.enable=false --o:ssl.termination=true --o:welcome.enable=false --o:net.frame_ancestors=$NC_DOMAIN:$APACHE_PORT" \
            -e dictionaries="$COLLABORA_DICTIONARIES" \
            -e TZ="$TIMEZONE" \
            ghcr.io/nextcloud-releases/aio-collabora:latest
    fi
    
    # OnlyOffice
    if [ "$ONLYOFFICE_ENABLED" = "yes" ]; then
        log "启动OnlyOffice容器..."
        
        # 确定使用的镜像
        local onlyoffice_image="ghcr.io/nextcloud-releases/aio-onlyoffice:latest"
        if [ -n "$ONLYOFFICE_CUSTOM_IMAGE" ]; then
            onlyoffice_image="$ONLYOFFICE_CUSTOM_IMAGE"
            log "使用自定义OnlyOffice镜像: $onlyoffice_image"
        fi
        
        # 检查镜像是否存在
        if ! docker image inspect "$onlyoffice_image" &> /dev/null; then
            warn "OnlyOffice镜像不存在: $onlyoffice_image"
            if [ -n "$ONLYOFFICE_CUSTOM_IMAGE" ]; then
                error "自定义镜像不存在，请先运行 ./modify-onlyoffice-image.sh 创建自定义镜像"
                exit 1
            fi
        fi
        
        # 检查CA证书目录是否存在
        local ca_mount_options=""
        if [ -n "$NEXTCLOUD_TRUSTED_CACERTS_DIR" ] && [ -d "$NEXTCLOUD_TRUSTED_CACERTS_DIR" ]; then
            log "检测到CA证书目录: $NEXTCLOUD_TRUSTED_CACERTS_DIR"
            log "将CA证书挂载到OnlyOffice容器的 /var/www/onlyoffice/Data/certs 目录"
            ca_mount_options="-v $NEXTCLOUD_TRUSTED_CACERTS_DIR:/var/www/onlyoffice/Data/certs:ro"
        elif [ -n "$NEXTCLOUD_TRUSTED_CACERTS_DIR" ]; then
            warn "配置的CA证书目录不存在: $NEXTCLOUD_TRUSTED_CACERTS_DIR"
            warn "OnlyOffice将不会加载自定义CA证书"
        fi
        
        docker run -d \
            --name nextcloud-aio-onlyoffice \
            --network nextcloud-aio \
            --init \
            --restart unless-stopped \
            --cap-drop NET_RAW \
            -v nextcloud_aio_onlyoffice:/var/lib/onlyoffice:rw \
            $ca_mount_options \
            -e JWT_ENABLED=true \
            -e JWT_HEADER=AuthorizationJwt \
            -e JWT_SECRET="$ONLYOFFICE_SECRET" \
            -e TZ="$TIMEZONE" \
            "$onlyoffice_image"
    fi
    
    # Talk
    if [ "$TALK_ENABLED" = "yes" ]; then
        log "启动Talk容器..."
        docker run -d \
            --name nextcloud-aio-talk \
            --network nextcloud-aio \
            --init \
            --restart unless-stopped \
            --read-only \
            --tmpfs /var/log/supervisord \
            --tmpfs /var/run/supervisord \
            --tmpfs /opt/eturnal/run \
            --tmpfs /tmp \
            --cap-drop NET_RAW \
            -p "$APACHE_IP_BINDING:$TALK_PORT:$TALK_PORT/tcp" \
            -p "$APACHE_IP_BINDING:$TALK_PORT:$TALK_PORT/udp" \
            -e NC_DOMAIN="$NC_DOMAIN" \
            -e TURN_SECRET="$TURN_SECRET" \
            -e SIGNALING_SECRET="$SIGNALING_SECRET" \
            -e INTERNAL_SECRET="$TALK_INTERNAL_SECRET" \
            -e TZ="$TIMEZONE" \
            ghcr.io/nextcloud-releases/aio-talk:latest
    fi
    
    # Talk Recording
    if [ "$TALK_RECORDING_ENABLED" = "yes" ]; then
        log "启动Talk Recording容器..."
        docker run -d \
            --name nextcloud-aio-talk-recording \
            --network nextcloud-aio \
            --init \
            --restart unless-stopped \
            --read-only \
            --tmpfs /tmp \
            --cap-drop NET_RAW \
            -e RECORDING_SECRET="$RECORDING_SECRET" \
            -e TZ="$TIMEZONE" \
            ghcr.io/nextcloud-releases/aio-talk-recording:latest
    fi
    
    # Imaginary
    if [ "$IMAGINARY_ENABLED" = "yes" ]; then
        log "启动Imaginary容器..."
        docker run -d \
            --name nextcloud-aio-imaginary \
            --network nextcloud-aio \
            --user 33 \
            --init \
            --restart unless-stopped \
            --read-only \
            --tmpfs /tmp \
            --cap-drop NET_RAW \
            -e IMAGINARY_SECRET="$IMAGINARY_SECRET" \
            -e TZ="$TIMEZONE" \
            ghcr.io/nextcloud-releases/aio-imaginary:latest
    fi
    
    # FullTextSearch
    if [ "$FULLTEXTSEARCH_ENABLED" = "yes" ]; then
        log "启动FullTextSearch容器..."
        docker run -d \
            --name nextcloud-aio-fulltextsearch \
            --network nextcloud-aio \
            --user 1000 \
            --init \
            --restart unless-stopped \
            --cap-drop NET_RAW \
            -v nextcloud_aio_elasticsearch:/usr/share/elasticsearch/data:rw \
            -e FULLTEXTSEARCH_PASSWORD="$FULLTEXTSEARCH_PASSWORD" \
            -e ES_JAVA_OPTS="$FULLTEXTSEARCH_JAVA_OPTIONS" \
            -e TZ="$TIMEZONE" \
            ghcr.io/nextcloud-releases/aio-fulltextsearch:latest
    fi
    
    # Whiteboard
    if [ "$WHITEBOARD_ENABLED" = "yes" ]; then
        log "启动Whiteboard容器..."
        docker run -d \
            --name nextcloud-aio-whiteboard \
            --network nextcloud-aio \
            --user 33 \
            --init \
            --restart unless-stopped \
            --read-only \
            --tmpfs /tmp \
            --cap-drop NET_RAW \
            -e WHITEBOARD_SECRET="$WHITEBOARD_SECRET" \
            -e TZ="$TIMEZONE" \
            ghcr.io/nextcloud-releases/aio-whiteboard:latest
    fi
}

# 启动Nextcloud容器
start_nextcloud() {
    log "启动Nextcloud容器..."
    
    # 构建环境变量
    local env_vars=(
        -e NEXTCLOUD_HOST=nextcloud-aio-nextcloud
        -e POSTGRES_HOST=nextcloud-aio-database
        -e POSTGRES_PORT=5432
        -e POSTGRES_PASSWORD="$DATABASE_PASSWORD"
        -e POSTGRES_DB=nextcloud_database
        -e POSTGRES_USER=nextcloud
        -e REDIS_HOST=nextcloud-aio-redis
        -e REDIS_HOST_PASSWORD="$REDIS_PASSWORD"
        -e APACHE_HOST=nextcloud-aio-apache
        -e APACHE_PORT="$APACHE_PORT"
        -e NC_DOMAIN="$NC_DOMAIN"
        -e ADMIN_USER=admin
        -e ADMIN_PASSWORD="$NEXTCLOUD_PASSWORD"
        -e NEXTCLOUD_DATA_DIR=/mnt/ncdata
        -e OVERWRITEHOST="$NC_DOMAIN"
        -e OVERWRITEPROTOCOL=https
        -e TURN_SECRET="$TURN_SECRET"
        -e SIGNALING_SECRET="$SIGNALING_SECRET"
        -e NEXTCLOUD_MOUNT="$NEXTCLOUD_MOUNT"
        -e CLAMAV_ENABLED="$CLAMAV_ENABLED"
        -e ONLYOFFICE_ENABLED="$ONLYOFFICE_ENABLED"
        -e COLLABORA_ENABLED="$COLLABORA_ENABLED"
        -e TALK_ENABLED="$TALK_ENABLED"
        -e UPDATE_NEXTCLOUD_APPS="$UPDATE_NEXTCLOUD_APPS"
        -e TZ="$TIMEZONE"
        -e TALK_PORT="$TALK_PORT"
        -e IMAGINARY_ENABLED="$IMAGINARY_ENABLED"
        -e PHP_UPLOAD_LIMIT="$NEXTCLOUD_UPLOAD_LIMIT"
        -e PHP_MEMORY_LIMIT="$NEXTCLOUD_MEMORY_LIMIT"
        -e FULLTEXTSEARCH_ENABLED="$FULLTEXTSEARCH_ENABLED"
        -e PHP_MAX_TIME="$NEXTCLOUD_MAX_TIME"
        -e TRUSTED_CACERTS_DIR="$NEXTCLOUD_TRUSTED_CACERTS_DIR"
        -e STARTUP_APPS="$NEXTCLOUD_STARTUP_APPS"
        -e ADDITIONAL_APKS="$NEXTCLOUD_ADDITIONAL_APKS"
        -e ADDITIONAL_PHP_EXTENSIONS="$NEXTCLOUD_ADDITIONAL_PHP_EXTENSIONS"
        -e INSTALL_LATEST_MAJOR="$INSTALL_LATEST_MAJOR"
        -e TALK_RECORDING_ENABLED="$TALK_RECORDING_ENABLED"
        -e REMOVE_DISABLED_APPS="$REMOVE_DISABLED_APPS"
        -e IMAGINARY_SECRET="$IMAGINARY_SECRET"
        -e WHITEBOARD_SECRET="$WHITEBOARD_SECRET"
        -e WHITEBOARD_ENABLED="$WHITEBOARD_ENABLED"
    )
    
    # 添加可选的主机名
    [ "$CLAMAV_ENABLED" = "yes" ] && env_vars+=(-e CLAMAV_HOST=nextcloud-aio-clamav)
    [ "$COLLABORA_ENABLED" = "yes" ] && env_vars+=(-e COLLABORA_HOST=nextcloud-aio-collabora)
    [ "$ONLYOFFICE_ENABLED" = "yes" ] && env_vars+=(-e ONLYOFFICE_HOST=nextcloud-aio-onlyoffice -e ONLYOFFICE_SECRET="$ONLYOFFICE_SECRET")
    [ "$TALK_ENABLED" = "yes" ] && env_vars+=(-e TALK_HOST=nextcloud-aio-talk)
    [ "$IMAGINARY_ENABLED" = "yes" ] && env_vars+=(-e IMAGINARY_HOST=nextcloud-aio-imaginary)
    [ "$FULLTEXTSEARCH_ENABLED" = "yes" ] && env_vars+=(-e FULLTEXTSEARCH_HOST=nextcloud-aio-fulltextsearch -e FULLTEXTSEARCH_PORT=9200 -e FULLTEXTSEARCH_USER=elastic -e FULLTEXTSEARCH_INDEX=nextcloud-aio -e FULLTEXTSEARCH_PASSWORD="$FULLTEXTSEARCH_PASSWORD")
    [ "$TALK_RECORDING_ENABLED" = "yes" ] && env_vars+=(-e RECORDING_SECRET="$RECORDING_SECRET" -e TALK_RECORDING_HOST=nextcloud-aio-talk-recording)
    
    docker run -d \
        --name nextcloud-aio-nextcloud \
        --network nextcloud-aio \
        --init \
        --restart unless-stopped \
        --cap-drop NET_RAW \
        --stop-timeout 600 \
        -v nextcloud_aio_nextcloud:/var/www/html:rw \
        -v "$NEXTCLOUD_DATADIR":/mnt/ncdata:rw \
        -v "$NEXTCLOUD_MOUNT":"$NEXTCLOUD_MOUNT":rw \
        -v "$NEXTCLOUD_TRUSTED_CACERTS_DIR":/usr/local/share/ca-certificates:ro \
        "${env_vars[@]}" \
        ghcr.io/nextcloud-releases/aio-nextcloud:latest
    
    # 等待Nextcloud启动
    log "等待Nextcloud启动..."
    local retries=60
    while [ $retries -gt 0 ]; do
        if docker exec nextcloud-aio-nextcloud php -f /var/www/html/occ status --no-warnings 2>/dev/null | grep -q "installed: true"; then
            log "Nextcloud已就绪"
            break
        fi
        sleep 5
        ((retries--))
    done
    
    if [ $retries -eq 0 ]; then
        warn "Nextcloud启动检查超时，但容器可能仍在初始化中"
    fi
}

# 启动Notify Push容器
start_notify_push() {
    log "启动Notify Push容器..."
    
    docker run -d \
        --name nextcloud-aio-notify-push \
        --network nextcloud-aio \
        --user 33 \
        --init \
        --restart unless-stopped \
        --read-only \
        --tmpfs /tmp \
        --cap-drop NET_RAW \
        -v nextcloud_aio_nextcloud:/var/www/html:ro \
        -e NC_DOMAIN="$NC_DOMAIN" \
        -e NEXTCLOUD_HOST=nextcloud-aio-nextcloud \
        -e POSTGRES_HOST=nextcloud-aio-database \
        -e POSTGRES_PASSWORD="$DATABASE_PASSWORD" \
        -e POSTGRES_DB=nextcloud_database \
        -e POSTGRES_USER=nextcloud \
        -e REDIS_HOST=nextcloud-aio-redis \
        -e REDIS_HOST_PASSWORD="$REDIS_PASSWORD" \
        -e TZ="$TIMEZONE" \
        ghcr.io/nextcloud-releases/aio-notify-push:latest
}

# 启动Apache容器
start_apache() {
    log "启动Apache容器..."
    
    # 构建环境变量
    local env_vars=(
        -e NC_DOMAIN="$NC_DOMAIN"
        -e NEXTCLOUD_HOST=nextcloud-aio-nextcloud
        -e APACHE_HOST=nextcloud-aio-apache
        -e APACHE_PORT="$APACHE_PORT"
        -e TZ="$TIMEZONE"
        -e APACHE_MAX_SIZE="$APACHE_MAX_SIZE"
        -e APACHE_MAX_TIME="$NEXTCLOUD_MAX_TIME"
        -e NOTIFY_PUSH_HOST=nextcloud-aio-notify-push
    )
    
    # 添加可选的主机名
    [ "$COLLABORA_ENABLED" = "yes" ] && env_vars+=(-e COLLABORA_HOST=nextcloud-aio-collabora)
    [ "$ONLYOFFICE_ENABLED" = "yes" ] && env_vars+=(-e ONLYOFFICE_HOST=nextcloud-aio-onlyoffice)
    [ "$TALK_ENABLED" = "yes" ] && env_vars+=(-e TALK_HOST=nextcloud-aio-talk)
    [ "$WHITEBOARD_ENABLED" = "yes" ] && env_vars+=(-e WHITEBOARD_HOST=nextcloud-aio-whiteboard)
    
    docker run -d \
        --name nextcloud-aio-apache \
        --network nextcloud-aio \
        --user 33 \
        --init \
        --restart unless-stopped \
        --read-only \
        --tmpfs /var/log/supervisord \
        --tmpfs /var/run/supervisord \
        --tmpfs /usr/local/apache2/logs \
        --tmpfs /tmp \
        --tmpfs /home/www-data \
        --cap-drop NET_RAW \
        -p "$APACHE_IP_BINDING:$APACHE_PORT:$APACHE_PORT/tcp" \
        -p "$APACHE_IP_BINDING:$APACHE_PORT:$APACHE_PORT/udp" \
        -v nextcloud_aio_nextcloud:/var/www/html:ro \
        -v nextcloud_aio_apache:/mnt/data:rw \
        "${env_vars[@]}" \
        ghcr.io/nextcloud-releases/aio-apache:latest
}

# 等待所有容器健康
wait_for_health() {
    log "等待所有容器健康检查通过..."
    
    local containers=(
        "nextcloud-aio-database"
        "nextcloud-aio-redis"
        "nextcloud-aio-nextcloud"
        "nextcloud-aio-notify-push"
        "nextcloud-aio-apache"
    )
    
    # 添加可选容器
    [ "$CLAMAV_ENABLED" = "yes" ] && containers+=("nextcloud-aio-clamav")
    [ "$COLLABORA_ENABLED" = "yes" ] && containers+=("nextcloud-aio-collabora")
    [ "$ONLYOFFICE_ENABLED" = "yes" ] && containers+=("nextcloud-aio-onlyoffice")
    [ "$TALK_ENABLED" = "yes" ] && containers+=("nextcloud-aio-talk")
    [ "$TALK_RECORDING_ENABLED" = "yes" ] && containers+=("nextcloud-aio-talk-recording")
    [ "$IMAGINARY_ENABLED" = "yes" ] && containers+=("nextcloud-aio-imaginary")
    [ "$FULLTEXTSEARCH_ENABLED" = "yes" ] && containers+=("nextcloud-aio-fulltextsearch")
    [ "$WHITEBOARD_ENABLED" = "yes" ] && containers+=("nextcloud-aio-whiteboard")
    
    local max_wait=300  # 5分钟
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        local all_healthy=true
        
        for container in "${containers[@]}"; do
            if ! docker ps --filter "name=$container" --filter "status=running" --format '{{.Names}}' | grep -q "^${container}$"; then
                all_healthy=false
                break
            fi
        done
        
        if $all_healthy; then
            log "所有容器都在运行"
            return 0
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
        echo -n "."
    done
    
    echo ""
    warn "等待容器健康检查超时，请检查容器状态"
    return 1
}

# 显示启动结果
show_result() {
    echo ""
    echo -e "${BLUE}=== Nextcloud AIO 启动完成 ===${NC}"
    echo ""
    echo "访问地址: https://$NC_DOMAIN:$APACHE_PORT"
    echo "管理员用户: admin"
    echo "管理员密码: (已在配置文件中设置)"
    echo ""
    echo "容器状态:"
    docker ps --filter "name=nextcloud-aio-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    echo "管理命令:"
    echo "  ./stop.sh    - 停止所有容器"
    echo "  ./status.sh  - 查看详细状态"
    echo ""
}

# 主函数
main() {
    check_root
    load_config
    check_docker
    
    log "开始启动 Nextcloud AIO..."
    
    create_network
    create_volumes
    cleanup_containers
    
    # 按依赖顺序启动容器
    start_database
    start_redis
    start_optional_containers
    start_nextcloud
    start_notify_push
    start_apache
    
    wait_for_health
    show_result
    
    log "Nextcloud AIO 启动完成！"
}

# 运行主函数
main "$@"