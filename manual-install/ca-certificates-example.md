# 自定义 CA 证书配置指南

## 概述

Nextcloud AIO 现在支持为 OnlyOffice 容器配置自定义 CA 证书。这对于在企业环境中使用自签名证书或内部 CA 的情况特别有用。

## 配置步骤

### 1. 准备 CA 证书目录

在配置文件中设置 `NEXTCLOUD_TRUSTED_CACERTS_DIR` 变量：

```bash
# 在 nextcloud-aio.conf 中添加或修改
NEXTCLOUD_TRUSTED_CACERTS_DIR="/path/to/your/ca-certificates"
```

### 2. 放置 CA 证书文件

将您的 CA 证书文件放置在指定目录中：

```bash
# 创建证书目录
mkdir -p /path/to/your/ca-certificates

# 复制 CA 证书文件（支持 .crt 和 .pem 格式）
cp your-ca-cert.crt /path/to/your/ca-certificates/
cp another-ca-cert.pem /path/to/your/ca-certificates/

# 设置正确的权限
chmod 644 /path/to/your/ca-certificates/*.crt
chmod 644 /path/to/your/ca-certificates/*.pem
```

### 3. 证书文件格式要求

- 支持的文件扩展名：`.crt`, `.pem`
- 文件必须是 PEM 格式的 X.509 证书
- 文件权限应设置为 644

### 4. 启动容器

使用更新后的启动脚本启动容器：

```bash
./start.sh
```

## 验证配置

### 检查证书安装

启动后，您可以检查 OnlyOffice 容器中的证书安装情况：

```bash
# 进入 OnlyOffice 容器
docker exec -it nextcloud-aio-onlyoffice bash

# 查看已安装的 CA 证书
ls -la /usr/local/share/ca-certificates/

# 检查证书存储更新
cat /etc/ssl/certs/ca-certificates.crt | grep -A 5 -B 5 "YOUR_CA_NAME"
```

### 检查容器日志

查看 OnlyOffice 容器的启动日志：

```bash
docker logs nextcloud-aio-onlyoffice
```

您应该看到类似以下的日志信息：
```
[2024-01-01 12:00:00] OnlyOffice: 发现自定义 CA 证书目录: /mnt/ca-certificates
[2024-01-01 12:00:01] OnlyOffice: 安装 CA 证书: your-ca-cert.crt
[2024-01-01 12:00:02] OnlyOffice: 更新 CA 证书存储...
[2024-01-01 12:00:03] OnlyOffice: 成功安装 1 个自定义 CA 证书
```

## 故障排除

### 常见问题

1. **证书文件未被识别**
   - 确保文件扩展名为 `.crt` 或 `.pem`
   - 检查文件权限是否正确
   - 验证文件是否为有效的 PEM 格式

2. **证书目录未挂载**
   - 检查 `NEXTCLOUD_TRUSTED_CACERTS_DIR` 配置是否正确
   - 确保目录路径存在且可访问

3. **证书更新失败**
   - 查看容器日志获取详细错误信息
   - 验证证书文件的有效性

### 调试命令

```bash
# 检查证书文件格式
openssl x509 -in /path/to/your/ca-certificates/your-cert.crt -text -noout

# 验证证书有效性
openssl verify /path/to/your/ca-certificates/your-cert.crt

# 检查容器挂载
docker inspect nextcloud-aio-onlyoffice | grep -A 10 "Mounts"
```

## 安全注意事项

1. **证书文件权限**：确保证书文件只有必要的读取权限
2. **证书来源**：只安装来自可信来源的 CA 证书
3. **定期更新**：定期检查和更新过期的 CA 证书
4. **备份**：保留 CA 证书的备份副本

## 示例配置

### 企业环境示例

```bash
# nextcloud-aio.conf
NEXTCLOUD_TRUSTED_CACERTS_DIR="/opt/nextcloud/ca-certificates"
ONLYOFFICE_ENABLED="yes"
ONLYOFFICE_SECRET="your-secret-key"

# 证书目录结构
/opt/nextcloud/ca-certificates/
├── company-root-ca.crt
├── company-intermediate-ca.crt
└── internal-services-ca.pem
```

### Docker Compose 环境

如果使用 Docker Compose，确保在 `latest.yml` 中正确配置了卷挂载：

```yaml
volumes:
  - ${NEXTCLOUD_TRUSTED_CACERTS_DIR}:/mnt/ca-certificates:ro
```

## 更新和维护

当需要添加或更新 CA 证书时：

1. 将新证书文件放置在证书目录中
2. 重启 OnlyOffice 容器：
   ```bash
   docker restart nextcloud-aio-onlyoffice
   ```
3. 验证新证书已被正确安装

这样可以确保 OnlyOffice 能够正确验证使用自定义 CA 签发的证书的服务。