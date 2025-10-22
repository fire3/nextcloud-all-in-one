# Nextcloud AIO 自定义 CA 证书部署指南

本指南详细介绍如何在 Nextcloud AIO 环境中部署自定义 CA 证书，特别是针对 OnlyOffice 容器的证书注入。

## 概述

Nextcloud AIO 现在支持两种方式处理自定义 CA 证书：

1. **外部挂载方式**：将证书目录挂载到容器中（推荐用于大多数场景）
2. **镜像嵌入方式**：将证书直接嵌入到 OnlyOffice 镜像中（适用于特殊部署需求）

## 方式一：外部挂载方式（推荐）

### 1. 准备证书文件

```bash
# 创建证书目录
mkdir -p /opt/nextcloud-ca-certificates

# 复制您的 CA 证书文件
cp your-company-ca.crt /opt/nextcloud-ca-certificates/
cp internal-ca.pem /opt/nextcloud-ca-certificates/

# 设置正确的权限
chmod 644 /opt/nextcloud-ca-certificates/*.crt
chmod 644 /opt/nextcloud-ca-certificates/*.pem
```

### 2. 配置 Nextcloud AIO

编辑配置文件 `nextcloud-aio.conf`：

```bash
# 设置证书目录路径
NEXTCLOUD_TRUSTED_CACERTS_DIR="/opt/nextcloud-ca-certificates"

# 启用 OnlyOffice（如果需要）
ONLYOFFICE_ENABLED="yes"
ONLYOFFICE_SECRET="your-secure-secret-key"
```

### 3. 部署服务

```bash
# 运行标准部署
./start.sh
```

## 方式二：镜像嵌入方式

### 1. 准备证书文件

```bash
# 创建证书目录
mkdir -p /opt/ca-certificates-for-build

# 复制证书文件
cp *.crt /opt/ca-certificates-for-build/
cp *.pem /opt/ca-certificates-for-build/

# 验证证书文件
ls -la /opt/ca-certificates-for-build/
```

### 2. 构建自定义镜像

#### 使用镜像修改脚本

```bash
# 基本用法
./modify-onlyoffice-image.sh -c /opt/ca-certificates-for-build

# 指定自定义镜像名称
./modify-onlyoffice-image.sh \
  -c /opt/ca-certificates-for-build \
  -t my-company-onlyoffice:latest

# 强制重新构建
./modify-onlyoffice-image.sh \
  -c /opt/ca-certificates-for-build \
  -t my-company-onlyoffice:latest \
  -f

# 使用不同的源镜像
./modify-onlyoffice-image.sh \
  -s onlyoffice/documentserver:latest \
  -c /opt/ca-certificates-for-build \
  -t my-custom-onlyoffice:latest
```

#### 验证自定义镜像

```bash
# 检查镜像是否创建成功
docker images | grep onlyoffice

# 运行临时容器验证证书
docker run --rm -it my-company-onlyoffice:latest bash -c "ls -la /etc/ssl/certs/ | grep -E '\.(crt|pem)$'"
```

### 3. 使用集成部署脚本

#### 一键部署（推荐）

```bash
# 自动构建镜像并部署
./deploy-with-custom-ca.sh -c /opt/ca-certificates-for-build

# 使用自定义镜像名称
./deploy-with-custom-ca.sh \
  -c /opt/ca-certificates-for-build \
  -t my-company-onlyoffice:latest
```

#### 分步部署

```bash
# 第一步：只构建镜像
./deploy-with-custom-ca.sh \
  --only-build-image \
  -c /opt/ca-certificates-for-build \
  -t my-company-onlyoffice:latest

# 第二步：使用已构建的镜像部署
./deploy-with-custom-ca.sh --skip-image-build
```

## 高级配置

### 1. 多环境部署

#### 开发环境
```bash
./deploy-with-custom-ca.sh \
  -c /opt/dev-ca-certificates \
  -t nextcloud-onlyoffice-dev:latest
```

#### 生产环境
```bash
./deploy-with-custom-ca.sh \
  -c /opt/prod-ca-certificates \
  -t nextcloud-onlyoffice-prod:latest
```

### 2. 证书更新流程

当 CA 证书需要更新时：

```bash
# 1. 更新证书文件
cp new-ca-cert.crt /opt/ca-certificates-for-build/

# 2. 重新构建镜像
./modify-onlyoffice-image.sh \
  -c /opt/ca-certificates-for-build \
  -t my-company-onlyoffice:$(date +%Y%m%d) \
  -f

# 3. 更新配置文件
echo 'ONLYOFFICE_CUSTOM_IMAGE="my-company-onlyoffice:'$(date +%Y%m%d)'"' >> nextcloud-aio.conf

# 4. 重启服务
./stop.sh
./start.sh
```

### 3. 批量镜像管理

```bash
# 创建多个版本的镜像
for env in dev staging prod; do
  ./modify-onlyoffice-image.sh \
    -c /opt/${env}-ca-certificates \
    -t nextcloud-onlyoffice-${env}:latest
done

# 清理旧镜像
docker images | grep "nextcloud-onlyoffice" | grep "days ago" | awk '{print $3}' | xargs docker rmi
```

## 故障排除

### 1. 常见问题

#### 证书未生效
```bash
# 检查证书是否正确安装
docker exec nextcloud-aio-onlyoffice ls -la /etc/ssl/certs/ | grep your-cert

# 检查证书存储是否更新
docker exec nextcloud-aio-onlyoffice update-ca-certificates --verbose
```

#### 镜像构建失败
```bash
# 检查证书文件格式
openssl x509 -in /opt/ca-certificates-for-build/your-cert.crt -text -noout

# 检查文件权限
ls -la /opt/ca-certificates-for-build/
```

#### 容器启动失败
```bash
# 查看详细日志
docker logs nextcloud-aio-onlyoffice

# 检查镜像是否存在
docker image inspect your-custom-image:latest
```

### 2. 调试命令

```bash
# 进入容器检查证书
docker exec -it nextcloud-aio-onlyoffice bash

# 在容器内验证证书
openssl s_client -connect your-internal-service:443 -CApath /etc/ssl/certs/

# 检查证书链
openssl verify -CApath /etc/ssl/certs/ /etc/ssl/certs/your-cert.crt
```

### 3. 日志分析

```bash
# OnlyOffice 启动日志
docker logs nextcloud-aio-onlyoffice 2>&1 | grep -i certificate

# 系统证书更新日志
docker exec nextcloud-aio-onlyoffice journalctl -u ca-certificates

# 网络连接测试
docker exec nextcloud-aio-onlyoffice curl -v https://your-internal-service
```

## 最佳实践

### 1. 证书管理

- **版本控制**：为证书文件建立版本控制
- **定期更新**：建立证书更新计划和流程
- **备份策略**：定期备份证书文件和配置

### 2. 安全考虑

- **权限控制**：确保证书文件具有适当的权限（644）
- **访问限制**：限制对证书目录的访问
- **审计日志**：记录证书更新和使用情况

### 3. 部署策略

- **测试环境**：先在测试环境验证证书配置
- **渐进部署**：采用蓝绿部署或滚动更新
- **回滚计划**：准备快速回滚方案

## 示例脚本

### 自动化部署脚本

```bash
#!/bin/bash
# auto-deploy-with-ca.sh

set -e

CA_DIR="/opt/company-ca-certificates"
IMAGE_NAME="company-nextcloud-onlyoffice:$(date +%Y%m%d)"

echo "开始自动化部署..."

# 1. 验证证书文件
if [ ! -d "$CA_DIR" ] || [ -z "$(ls -A $CA_DIR/*.{crt,pem} 2>/dev/null)" ]; then
    echo "错误：证书目录为空或不存在"
    exit 1
fi

# 2. 构建自定义镜像
echo "构建自定义镜像..."
./modify-onlyoffice-image.sh -c "$CA_DIR" -t "$IMAGE_NAME" -f

# 3. 部署服务
echo "部署服务..."
export ONLYOFFICE_CUSTOM_IMAGE="$IMAGE_NAME"
./start.sh

# 4. 验证部署
echo "验证部署..."
sleep 30
if docker ps | grep -q nextcloud-aio-onlyoffice; then
    echo "部署成功！"
else
    echo "部署失败，请检查日志"
    exit 1
fi
```

### 证书更新脚本

```bash
#!/bin/bash
# update-certificates.sh

set -e

OLD_IMAGE=$(docker inspect nextcloud-aio-onlyoffice --format='{{.Config.Image}}' 2>/dev/null || echo "")
NEW_IMAGE="company-nextcloud-onlyoffice:$(date +%Y%m%d)"

echo "更新 CA 证书..."

# 1. 停止服务
./stop.sh

# 2. 构建新镜像
./modify-onlyoffice-image.sh -c /opt/company-ca-certificates -t "$NEW_IMAGE" -f

# 3. 更新配置
sed -i "s|ONLYOFFICE_CUSTOM_IMAGE=.*|ONLYOFFICE_CUSTOM_IMAGE=\"$NEW_IMAGE\"|" nextcloud-aio.conf

# 4. 启动服务
./start.sh

# 5. 清理旧镜像
if [ -n "$OLD_IMAGE" ] && [ "$OLD_IMAGE" != "$NEW_IMAGE" ]; then
    docker rmi "$OLD_IMAGE" || true
fi

echo "证书更新完成！"
```

## 支持和反馈

如果您在使用过程中遇到问题，请：

1. 查看本指南的故障排除部分
2. 检查 Docker 和容器日志
3. 验证证书文件格式和权限
4. 提交 Issue 时请包含详细的错误信息和环境描述

---

*本指南涵盖了 Nextcloud AIO 自定义 CA 证书部署的所有主要场景。根据您的具体需求选择合适的部署方式。*