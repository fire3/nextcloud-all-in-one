#!/bin/bash

# Nextcloud AIO 离线部署脚本
# 此脚本用于在离线环境中部署 Nextcloud AIO

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/nextcloud-aio-images"
LOG_FILE="${SCRIPT_DIR}/deploy.log"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# 显示使用说明
show_usage() {
    echo "Nextcloud AIO 离线部署脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --load-images    只加载Docker镜像"
    echo "  --setup-config   只设置配置文件"
    echo "  --deploy         只部署服务（需要先加载镜像和配置）"
    echo "  --full           执行完整部署流程（默认）"
    echo "  --stop           停止所有服务"
    echo "  --status         查看服务状态"
    echo "  --help           显示此帮助信息"
    echo ""
    echo "部署模式:"
    echo "  --core-only      只部署核心服务"
    echo "  --with-collabora 部署核心服务 + Collabora"
    echo "  --with-talk      部署核心服务 + Talk"
    echo "  --all-features   部署所有功能"
    echo ""
}

# 检查依赖
check_dependencies() {
    log "检查系统依赖..."
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        log "错误: Docker 未安装"
        log "请先安装 Docker: https://docs.docker.com/engine/install/"
        exit 1
    fi
    
    # 检查Docker Compose
    if ! docker compose version &> /dev/null; then
        log "错误: Docker Compose 未安装或版本过低"
        log "请安装 Docker Compose v2: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    # 检查Docker服务
    if ! docker info &> /dev/null; then
        log "错误: Docker 服务未运行"
        log "请启动 Docker 服务: sudo systemctl start docker"
        exit 1
    fi
    
    log "依赖检查通过"
}

# 加载Docker镜像
load_images() {
    log "开始加载 Docker 镜像..."
    
    if [[ ! -d "$IMAGES_DIR" ]]; then
        log "错误: 镜像目录不存在: $IMAGES_DIR"
        log "请确保已正确复制镜像文件"
        exit 1
    fi
    
    # 检查是否有镜像文件
    if ! ls "${IMAGES_DIR}"/*.tar.gz &> /dev/null && ! ls "${IMAGES_DIR}"/*.tar &> /dev/null; then
        log "错误: 在 $IMAGES_DIR 中未找到镜像文件"
        exit 1
    fi
    
    # 加载压缩的镜像文件
    for file in "${IMAGES_DIR}"/*.tar.gz; do
        if [[ -f "$file" ]]; then
            log "正在加载镜像: $(basename "$file")"
            if gunzip -c "$file" | docker load; then
                log "成功加载: $(basename "$file")"
            else
                log "警告: 加载失败: $(basename "$file")"
            fi
        fi
    done
    
    # 加载未压缩的镜像文件
    for file in "${IMAGES_DIR}"/*.tar; do
        if [[ -f "$file" ]]; then
            log "正在加载镜像: $(basename "$file")"
            if docker load -i "$file"; then
                log "成功加载: $(basename "$file")"
            else
                log "警告: 加载失败: $(basename "$file")"
            fi
        fi
    done
    
    log "镜像加载完成"
    
    # 显示已加载的镜像
    log "已加载的 Nextcloud AIO 镜像:"
    docker images | grep -E "(nextcloud-releases|all-in-one)" || log "未找到相关镜像"
}

# 设置配置文件
setup_config() {
    log "设置配置文件..."
    
    # 检查是否存在配置文件
    if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
        if [[ -f "${SCRIPT_DIR}/sample.conf" ]]; then
            log "复制配置模板..."
            cp "${SCRIPT_DIR}/sample.conf" "${SCRIPT_DIR}/.env"
        elif [[ -f "${IMAGES_DIR}/sample.conf" ]]; then
            log "从镜像目录复制配置模板..."
            cp "${IMAGES_DIR}/sample.conf" "${SCRIPT_DIR}/.env"
        else
            log "错误: 未找到配置模板文件"
            exit 1
        fi
    fi
    
    # 检查compose文件
    if [[ ! -f "${SCRIPT_DIR}/compose.yaml" ]]; then
        if [[ -f "${SCRIPT_DIR}/latest.yml" ]]; then
            log "复制 compose 配置..."
            cp "${SCRIPT_DIR}/latest.yml" "${SCRIPT_DIR}/compose.yaml"
        elif [[ -f "${IMAGES_DIR}/latest.yml" ]]; then
            log "从镜像目录复制 compose 配置..."
            cp "${IMAGES_DIR}/latest.yml" "${SCRIPT_DIR}/compose.yaml"
        else
            log "错误: 未找到 compose 配置文件"
            exit 1
        fi
    fi
    
    # 检查配置是否完整
    if grep -q "TODO!" "${SCRIPT_DIR}/.env"; then
        log "警告: 配置文件中仍有未设置的参数（标记为 TODO!）"
        log "请编辑 ${SCRIPT_DIR}/.env 文件，设置所有必需的参数"
        log ""
        log "必需设置的参数包括:"
        grep "TODO!" "${SCRIPT_DIR}/.env" | head -10
        log ""
        read -p "是否继续部署？(y/N): " continue_deploy
        if [[ ! "$continue_deploy" =~ ^[Yy]$ ]]; then
            log "部署已取消，请完成配置后重新运行"
            exit 1
        fi
    fi
    
    log "配置文件设置完成"
}

# 生成密码
generate_passwords() {
    log "生成随机密码..."
    
    # 生成随机密码的函数
    generate_password() {
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
    }
    
    # 如果openssl不可用，使用备用方法
    if ! command -v openssl &> /dev/null; then
        generate_password() {
            cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 25 | head -n 1
        }
    fi
    
    # 替换配置文件中的空密码
    sed -i "s/^DATABASE_PASSWORD=$/DATABASE_PASSWORD=$(generate_password)/" "${SCRIPT_DIR}/.env"
    sed -i "s/^REDIS_PASSWORD=$/REDIS_PASSWORD=$(generate_password)/" "${SCRIPT_DIR}/.env"
    sed -i "s/^NEXTCLOUD_PASSWORD=$/NEXTCLOUD_PASSWORD=$(generate_password)/" "${SCRIPT_DIR}/.env"
    sed -i "s/^TURN_SECRET=$/TURN_SECRET=$(generate_password)/" "${SCRIPT_DIR}/.env"
    sed -i "s/^SIGNALING_SECRET=$/SIGNALING_SECRET=$(generate_password)/" "${SCRIPT_DIR}/.env"
    sed -i "s/^ONLYOFFICE_SECRET=$/ONLYOFFICE_SECRET=$(generate_password)/" "${SCRIPT_DIR}/.env"
    sed -i "s/^RECORDING_SECRET=$/RECORDING_SECRET=$(generate_password)/" "${SCRIPT_DIR}/.env"
    sed -i "s/^TALK_INTERNAL_SECRET=$/TALK_INTERNAL_SECRET=$(generate_password)/" "${SCRIPT_DIR}/.env"
    sed -i "s/^FULLTEXTSEARCH_PASSWORD=$/FULLTEXTSEARCH_PASSWORD=$(generate_password)/" "${SCRIPT_DIR}/.env"
    sed -i "s/^IMAGINARY_SECRET=$/IMAGINARY_SECRET=$(generate_password)/" "${SCRIPT_DIR}/.env"
    sed -i "s/^WHITEBOARD_SECRET=$/WHITEBOARD_SECRET=$(generate_password)/" "${SCRIPT_DIR}/.env"
    
    log "密码生成完成"
}

# 部署服务
deploy_services() {
    local deploy_mode="$1"
    
    log "开始部署 Nextcloud AIO 服务..."
    log "部署模式: $deploy_mode"
    
    cd "$SCRIPT_DIR"
    
    # 根据部署模式设置profiles
    local profiles=""
    case "$deploy_mode" in
        "core")
            profiles=""
            log "部署核心服务: Apache, Database, Nextcloud, Redis, Notify-Push"
            ;;
        "collabora")
            profiles="--profile collabora"
            log "部署核心服务 + Collabora"
            ;;
        "talk")
            profiles="--profile talk"
            log "部署核心服务 + Talk"
            ;;
        "all")
            profiles="--profile collabora --profile talk --profile talk-recording --profile clamav --profile imaginary --profile fulltextsearch --profile whiteboard"
            log "部署所有功能"
            ;;
        *)
            log "使用默认部署模式（核心服务）"
            ;;
    esac
    
    # 启动服务
    log "启动 Docker Compose 服务..."
    if docker compose $profiles up -d; then
        log "服务启动成功"
    else
        log "错误: 服务启动失败"
        exit 1
    fi
    
    # 等待服务启动
    log "等待服务启动..."
    sleep 10
    
    # 检查服务状态
    show_status
}

# 显示服务状态
show_status() {
    log "检查服务状态..."
    
    cd "$SCRIPT_DIR"
    
    echo ""
    echo "=== Docker Compose 服务状态 ==="
    docker compose ps
    
    echo ""
    echo "=== 服务健康检查 ==="
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    
    # 检查Nextcloud是否可访问
    if docker compose ps | grep -q "nextcloud-aio-apache.*Up"; then
        echo ""
        echo "=== 访问信息 ==="
        
        # 从配置文件读取域名和端口
        if [[ -f ".env" ]]; then
            source .env
            echo "Nextcloud 访问地址: https://${NC_DOMAIN:-localhost}:${APACHE_PORT:-443}"
            echo "管理员用户名: admin"
            echo "管理员密码: ${NEXTCLOUD_PASSWORD:-请检查.env文件}"
        fi
    fi
}

# 停止服务
stop_services() {
    log "停止 Nextcloud AIO 服务..."
    
    cd "$SCRIPT_DIR"
    
    if docker compose down; then
        log "服务已停止"
    else
        log "警告: 停止服务时出现错误"
    fi
}

# 主函数
main() {
    local action="full"
    local deploy_mode="core"
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --load-images)
                action="load"
                shift
                ;;
            --setup-config)
                action="config"
                shift
                ;;
            --deploy)
                action="deploy"
                shift
                ;;
            --full)
                action="full"
                shift
                ;;
            --stop)
                action="stop"
                shift
                ;;
            --status)
                action="status"
                shift
                ;;
            --core-only)
                deploy_mode="core"
                shift
                ;;
            --with-collabora)
                deploy_mode="collabora"
                shift
                ;;
            --with-talk)
                deploy_mode="talk"
                shift
                ;;
            --all-features)
                deploy_mode="all"
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log "开始执行 Nextcloud AIO 离线部署"
    log "操作: $action"
    
    # 执行相应操作
    case "$action" in
        "load")
            check_dependencies
            load_images
            ;;
        "config")
            setup_config
            generate_passwords
            ;;
        "deploy")
            check_dependencies
            deploy_services "$deploy_mode"
            ;;
        "full")
            check_dependencies
            load_images
            setup_config
            generate_passwords
            deploy_services "$deploy_mode"
            ;;
        "stop")
            stop_services
            ;;
        "status")
            show_status
            ;;
    esac
    
    log "操作完成"
}

# 运行主函数
main "$@"