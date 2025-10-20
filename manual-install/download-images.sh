#!/bin/bash

# Nextcloud AIO 离线部署镜像下载脚本
# 此脚本将下载所有必需的Docker镜像并保存为tar文件，用于离线环境部署

set -e

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/nextcloud-aio-images"
LOG_FILE="${OUTPUT_DIR}/download.log"

# 创建输出目录
mkdir -p "${OUTPUT_DIR}"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log "开始下载 Nextcloud AIO Docker 镜像..."

# 定义所有需要的镜像
declare -A IMAGES=(
    # 核心镜像（必需）
    ["aio-apache"]="ghcr.io/nextcloud-releases/aio-apache:latest"
    ["aio-postgresql"]="ghcr.io/nextcloud-releases/aio-postgresql:latest"
    ["aio-nextcloud"]="ghcr.io/nextcloud-releases/aio-nextcloud:latest"
    ["aio-redis"]="ghcr.io/nextcloud-releases/aio-redis:latest"
    ["aio-notify-push"]="ghcr.io/nextcloud-releases/aio-notify-push:latest"
    
    # 可选镜像
    ["aio-collabora"]="ghcr.io/nextcloud-releases/aio-collabora:latest"
    ["aio-talk"]="ghcr.io/nextcloud-releases/aio-talk:latest"
    ["aio-talk-recording"]="ghcr.io/nextcloud-releases/aio-talk-recording:latest"
    ["aio-clamav"]="ghcr.io/nextcloud-releases/aio-clamav:latest"
    ["aio-onlyoffice"]="ghcr.io/nextcloud-releases/aio-onlyoffice:latest"
    ["aio-imaginary"]="ghcr.io/nextcloud-releases/aio-imaginary:latest"
    ["aio-fulltextsearch"]="ghcr.io/nextcloud-releases/aio-fulltextsearch:latest"
    ["aio-whiteboard"]="ghcr.io/nextcloud-releases/aio-whiteboard:latest"
    
    # 主控制器镜像（如果需要使用AIO界面）
    ["all-in-one"]="ghcr.io/nextcloud-releases/all-in-one:latest"
)

# 核心镜像列表（必需下载）
CORE_IMAGES=(
    "aio-apache"
    "aio-postgresql" 
    "aio-nextcloud"
    "aio-redis"
    "aio-notify-push"
)

# 可选镜像列表
OPTIONAL_IMAGES=(
    "aio-collabora"
    "aio-talk"
    "aio-talk-recording"
    "aio-clamav"
    "aio-onlyoffice"
    "aio-imaginary"
    "aio-fulltextsearch"
    "aio-whiteboard"
)

# 检查Docker是否安装
if ! command -v docker &> /dev/null; then
    log "错误: Docker 未安装或不在 PATH 中"
    exit 1
fi

# 检查Docker是否运行
if ! docker info &> /dev/null; then
    log "错误: Docker 服务未运行"
    exit 1
fi

# 下载镜像函数
download_image() {
    local image_name="$1"
    local image_url="$2"
    local tar_file="${OUTPUT_DIR}/${image_name}.tar"
    
    log "正在下载镜像: ${image_url}"
    
    # 拉取镜像
    if docker pull "${image_url}"; then
        log "成功拉取镜像: ${image_url}"
        
        # 保存镜像为tar文件
        log "正在保存镜像到: ${tar_file}"
        if docker save "${image_url}" -o "${tar_file}"; then
            log "成功保存镜像: ${tar_file}"
            
            # 压缩tar文件以节省空间
            log "正在压缩镜像文件..."
            # 如果压缩文件已存在，先删除
            if [[ -f "${tar_file}.gz" ]]; then
                rm -f "${tar_file}.gz"
            fi
            
            if gzip "${tar_file}"; then
                log "成功压缩镜像文件: ${tar_file}.gz"
            else
                log "警告: 压缩失败，保留原始tar文件"
            fi
        else
            log "错误: 保存镜像失败: ${image_url}"
            return 1
        fi
    else
        log "错误: 拉取镜像失败: ${image_url}"
        return 1
    fi
}

# 显示使用说明
show_usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --core-only     只下载核心镜像（最小安装）"
    echo "  --all          下载所有镜像（包括可选组件）"
    echo "  --help         显示此帮助信息"
    echo ""
    echo "核心镜像包括: Apache, PostgreSQL, Nextcloud, Redis, Notify-Push"
    echo "可选镜像包括: Collabora, Talk, ClamAV, OnlyOffice, Imaginary, FullTextSearch, Whiteboard"
}

# 解析命令行参数
DOWNLOAD_MODE="ask"

while [[ $# -gt 0 ]]; do
    case $1 in
        --core-only)
            DOWNLOAD_MODE="core"
            shift
            ;;
        --all)
            DOWNLOAD_MODE="all"
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

# 如果没有指定模式，询问用户
if [[ "$DOWNLOAD_MODE" == "ask" ]]; then
    echo ""
    echo "请选择下载模式:"
    echo "1) 只下载核心镜像 (约 2-3GB，包含基本功能)"
    echo "2) 下载所有镜像 (约 8-10GB，包含所有可选功能)"
    echo ""
    read -p "请输入选择 (1 或 2): " choice
    
    case $choice in
        1)
            DOWNLOAD_MODE="core"
            ;;
        2)
            DOWNLOAD_MODE="all"
            ;;
        *)
            log "无效选择，退出"
            exit 1
            ;;
    esac
fi

# 根据模式确定要下载的镜像
IMAGES_TO_DOWNLOAD=()

if [[ "$DOWNLOAD_MODE" == "core" ]]; then
    log "下载模式: 仅核心镜像"
    IMAGES_TO_DOWNLOAD=("${CORE_IMAGES[@]}")
elif [[ "$DOWNLOAD_MODE" == "all" ]]; then
    log "下载模式: 所有镜像"
    IMAGES_TO_DOWNLOAD=("${CORE_IMAGES[@]}" "${OPTIONAL_IMAGES[@]}" "all-in-one")
fi

# 显示将要下载的镜像
log "将要下载的镜像:"
for image_name in "${IMAGES_TO_DOWNLOAD[@]}"; do
    log "  - ${image_name}: ${IMAGES[$image_name]}"
done

# 开始下载
log "开始下载镜像..."
FAILED_IMAGES=()
SUCCESSFUL_DOWNLOADS=0

for image_name in "${IMAGES_TO_DOWNLOAD[@]}"; do
    image_url="${IMAGES[$image_name]}"
    
    # 临时禁用 set -e 以防止单个镜像失败导致脚本退出
    set +e
    download_image "$image_name" "$image_url"
    download_result=$?
    set -e
    
    if [[ $download_result -eq 0 ]]; then
        SUCCESSFUL_DOWNLOADS=$((SUCCESSFUL_DOWNLOADS + 1))
    else
        FAILED_IMAGES+=("$image_name")
        log "镜像 ${image_name} 下载失败，继续下载其他镜像..."
    fi
    
    echo "" # 添加空行分隔
done

# 生成镜像清单文件
MANIFEST_FILE="${OUTPUT_DIR}/images-manifest.txt"
log "生成镜像清单文件: ${MANIFEST_FILE}"

cat > "${MANIFEST_FILE}" << EOF
# Nextcloud AIO 镜像清单
# 生成时间: $(date)
# 下载模式: ${DOWNLOAD_MODE}

EOF

for image_name in "${IMAGES_TO_DOWNLOAD[@]}"; do
    if [[ ! " ${FAILED_IMAGES[@]} " =~ " ${image_name} " ]]; then
        echo "${image_name}:${IMAGES[$image_name]}" >> "${MANIFEST_FILE}"
    fi
done

# 生成加载脚本
LOAD_SCRIPT="${OUTPUT_DIR}/load-images.sh"
log "生成镜像加载脚本: ${LOAD_SCRIPT}"

cat > "${LOAD_SCRIPT}" << 'EOF'
#!/bin/bash

# Nextcloud AIO 镜像加载脚本
# 在离线环境中运行此脚本来加载Docker镜像

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "开始加载 Nextcloud AIO Docker 镜像..."

# 检查Docker是否可用
if ! command -v docker &> /dev/null; then
    echo "错误: Docker 未安装或不在 PATH 中"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "错误: Docker 服务未运行"
    exit 1
fi

# 加载所有镜像文件
for file in "${SCRIPT_DIR}"/*.tar.gz; do
    if [[ -f "$file" ]]; then
        echo "正在加载镜像: $(basename "$file")"
        
        # 解压并加载
        if gunzip -c "$file" | docker load; then
            echo "成功加载: $(basename "$file")"
        else
            echo "错误: 加载失败: $(basename "$file")"
        fi
    fi
done

# 检查未压缩的tar文件
for file in "${SCRIPT_DIR}"/*.tar; do
    if [[ -f "$file" ]]; then
        echo "正在加载镜像: $(basename "$file")"
        
        if docker load -i "$file"; then
            echo "成功加载: $(basename "$file")"
        else
            echo "错误: 加载失败: $(basename "$file")"
        fi
    fi
done

echo "镜像加载完成！"
echo "您现在可以使用 docker images 查看已加载的镜像"
EOF

chmod +x "${LOAD_SCRIPT}"

# 复制配置文件到输出目录
log "复制配置文件到输出目录..."
cp "${SCRIPT_DIR}/latest.yml" "${OUTPUT_DIR}/" 2>/dev/null || true
cp "${SCRIPT_DIR}/sample.conf" "${OUTPUT_DIR}/" 2>/dev/null || true

# 生成部署说明
README_FILE="${OUTPUT_DIR}/README.md"
cat > "${README_FILE}" << EOF
# Nextcloud AIO 离线部署包

此目录包含了 Nextcloud AIO 离线部署所需的所有文件。

## 文件说明

- \`*.tar.gz\` - 压缩的Docker镜像文件
- \`load-images.sh\` - 镜像加载脚本
- \`images-manifest.txt\` - 镜像清单文件
- \`latest.yml\` - Docker Compose 配置文件
- \`sample.conf\` - 环境变量配置模板
- \`download.log\` - 下载日志

## 离线部署步骤

1. 将整个目录复制到离线环境
2. 在离线环境中运行: \`./load-images.sh\`
3. 复制配置文件: \`cp sample.conf .env\`
4. 编辑 \`.env\` 文件，设置必要的参数
5. 复制compose文件: \`cp latest.yml compose.yaml\`
6. 启动服务: \`docker compose up -d\`

## 注意事项

- 确保离线环境已安装 Docker 和 Docker Compose
- 根据需要的功能，在启动时使用相应的 profiles
- 详细部署说明请参考 Nextcloud AIO 官方文档

## 生成信息

- 生成时间: $(date)
- 下载模式: ${DOWNLOAD_MODE}
- 成功下载: ${SUCCESSFUL_DOWNLOADS} 个镜像
EOF

if [[ ${#FAILED_IMAGES[@]} -gt 0 ]]; then
    echo "- 失败镜像: ${FAILED_IMAGES[*]}" >> "${README_FILE}"
fi

# 显示下载结果
log "下载完成！"
log "成功下载: ${SUCCESSFUL_DOWNLOADS} 个镜像"

if [[ ${#FAILED_IMAGES[@]} -gt 0 ]]; then
    log "失败的镜像:"
    for failed in "${FAILED_IMAGES[@]}"; do
        log "  - ${failed}"
    done
fi

log "输出目录: ${OUTPUT_DIR}"
log "请将 ${OUTPUT_DIR} 目录复制到离线环境中进行部署"

# 显示目录大小
if command -v du &> /dev/null; then
    TOTAL_SIZE=$(du -sh "${OUTPUT_DIR}" | cut -f1)
    log "总大小: ${TOTAL_SIZE}"
fi

log "下载脚本执行完成！"