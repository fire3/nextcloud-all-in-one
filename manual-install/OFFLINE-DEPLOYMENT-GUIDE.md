# Nextcloud AIO 离线部署指南

本指南将帮助您在离线环境中部署 Nextcloud All-in-One (AIO)。

## 概述

离线部署分为两个阶段：
1. **在线环境**：下载所有必需的 Docker 镜像
2. **离线环境**：加载镜像并部署 Nextcloud AIO

## 阶段一：在线环境准备

### 前提条件

- 安装了 Docker 和 Docker Compose 的在线环境
- 足够的磁盘空间（核心镜像约 3GB，完整镜像约 10GB）
- 稳定的网络连接

### 步骤 1：下载镜像

在有网络连接的环境中运行下载脚本：

```bash
# 进入 manual-install 目录
cd nextcloud-all-in-one/manual-install

# 运行下载脚本
./download-images.sh
```

#### 下载选项

**选项 1：只下载核心镜像（推荐用于基本部署）**
```bash
./download-images.sh --core-only
```
包含的服务：
- Apache (Web服务器)
- PostgreSQL (数据库)
- Nextcloud (核心应用)
- Redis (缓存)
- Notify-Push (实时通知)

**选项 2：下载所有镜像（完整功能）**
```bash
./download-images.sh --all
```
额外包含的服务：
- Collabora (在线文档编辑)
- Talk (视频通话)
- Talk Recording (通话录制)
- ClamAV (病毒扫描)
- OnlyOffice (办公套件)
- Imaginary (图像处理)
- FullTextSearch (全文搜索)
- Whiteboard (白板)

### 步骤 2：传输文件

下载完成后，将整个 `nextcloud-aio-images` 目录复制到离线环境：

```bash
# 打包镜像目录
tar -czf nextcloud-aio-offline.tar.gz nextcloud-aio-images/

# 将文件传输到离线环境（使用USB、网络传输等方式）
```

## 阶段二：离线环境部署

### 前提条件

- 安装了 Docker 和 Docker Compose 的离线环境
- 已传输的镜像文件

### 步骤 1：解压文件

```bash
# 解压镜像文件
tar -xzf nextcloud-aio-offline.tar.gz

# 进入目录
cd nextcloud-aio-images
```

### 步骤 2：部署服务

使用提供的离线部署脚本：

```bash
# 完整部署（推荐）
./offline-deploy.sh --full --core-only

# 或者分步执行
./offline-deploy.sh --load-images    # 加载镜像
./offline-deploy.sh --setup-config   # 设置配置
./offline-deploy.sh --deploy         # 部署服务
```

#### 部署模式选择

**核心服务部署**
```bash
./offline-deploy.sh --full --core-only
```

**包含 Collabora 的部署**
```bash
./offline-deploy.sh --full --with-collabora
```

**包含 Talk 的部署**
```bash
./offline-deploy.sh --full --with-talk
```

**完整功能部署**
```bash
./offline-deploy.sh --full --all-features
```

### 步骤 3：配置设置

部署脚本会自动：
1. 复制配置模板到 `.env` 文件
2. 生成随机密码
3. 复制 Docker Compose 配置

**重要配置项需要手动设置：**

编辑 `.env` 文件：
```bash
nano .env
```

必须设置的参数：
```bash
NC_DOMAIN=your-domain.com          # 您的域名
TIMEZONE=Asia/Shanghai             # 时区设置
```

可选配置：
```bash
APACHE_PORT=443                    # HTTPS端口
APACHE_IP_BINDING=0.0.0.0         # IP绑定
NEXTCLOUD_DATADIR=/mnt/ncdata      # 数据目录
```

## 管理命令

### 查看服务状态
```bash
./offline-deploy.sh --status
```

### 停止服务
```bash
./offline-deploy.sh --stop
```

### 重启服务
```bash
docker compose restart
```

### 查看日志
```bash
docker compose logs -f nextcloud-aio-nextcloud
```

## 访问 Nextcloud

部署完成后，您可以通过以下方式访问：

- **URL**: `https://your-domain.com:443` (或您配置的端口)
- **管理员用户名**: `admin`
- **管理员密码**: 在 `.env` 文件中的 `NEXTCLOUD_PASSWORD`

## 故障排除

### 常见问题

**1. 镜像加载失败**
```bash
# 检查镜像文件是否完整
ls -la nextcloud-aio-images/

# 手动加载单个镜像
docker load -i nextcloud-aio-images/aio-nextcloud.tar.gz
```

**2. 服务启动失败**
```bash
# 查看详细日志
docker compose logs

# 检查配置文件
cat .env
```

**3. 无法访问服务**
```bash
# 检查端口是否被占用
netstat -tlnp | grep :443

# 检查防火墙设置
sudo ufw status
```

**4. 数据库连接问题**
```bash
# 重启数据库服务
docker compose restart nextcloud-aio-database

# 检查数据库日志
docker compose logs nextcloud-aio-database
```

### 重新部署

如果需要重新部署：

```bash
# 停止并删除所有容器
docker compose down

# 删除数据卷（注意：这会删除所有数据）
docker volume prune

# 重新部署
./offline-deploy.sh --full
```

## 备份和恢复

### 备份数据
```bash
# 备份数据卷
docker run --rm -v nextcloud_aio_nextcloud_data:/data -v $(pwd):/backup alpine tar czf /backup/nextcloud-data-backup.tar.gz /data

# 备份数据库
docker compose exec nextcloud-aio-database pg_dump -U nextcloud nextcloud_database > nextcloud-db-backup.sql
```

### 恢复数据
```bash
# 恢复数据卷
docker run --rm -v nextcloud_aio_nextcloud_data:/data -v $(pwd):/backup alpine tar xzf /backup/nextcloud-data-backup.tar.gz -C /

# 恢复数据库
docker compose exec -T nextcloud-aio-database psql -U nextcloud nextcloud_database < nextcloud-db-backup.sql
```

## 更新

离线环境的更新需要：
1. 在在线环境下载新版本镜像
2. 传输到离线环境
3. 停止服务，加载新镜像，重启服务

```bash
# 停止服务
./offline-deploy.sh --stop

# 加载新镜像
./offline-deploy.sh --load-images

# 启动服务
./offline-deploy.sh --deploy
```

## 安全建议

1. **定期更新**: 定期在在线环境获取最新镜像
2. **备份策略**: 建立定期备份机制
3. **访问控制**: 配置适当的防火墙规则
4. **SSL证书**: 使用有效的SSL证书
5. **密码安全**: 使用强密码并定期更换

## 支持

如果遇到问题：
1. 查看日志文件：`deploy.log` 和 `download.log`
2. 检查 Docker 和 Docker Compose 版本
3. 参考官方文档：https://github.com/nextcloud/all-in-one
4. 社区支持：https://github.com/nextcloud/all-in-one/discussions

## 文件结构

```
nextcloud-aio-images/
├── *.tar.gz              # 压缩的Docker镜像
├── load-images.sh        # 镜像加载脚本
├── images-manifest.txt   # 镜像清单
├── latest.yml           # Docker Compose配置
├── sample.conf          # 配置模板
├── README.md            # 说明文档
└── download.log         # 下载日志
```

---

**注意**: 此部署方式失去了 AIO 的 Web 管理界面和自动更新功能，但提供了更大的灵活性和对离线环境的支持。