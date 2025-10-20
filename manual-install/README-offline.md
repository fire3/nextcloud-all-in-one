# Nextcloud AIO 离线部署脚本

这套脚本提供了在离线环境中部署 Nextcloud AIO 的完整解决方案，不依赖 Docker Compose，使用 `docker run` 命令直接管理容器。

## 前置要求

1. **操作系统**: Linux (推荐 Ubuntu 20.04+ 或 Debian 11+)
2. **用户权限**: 必须使用 root 用户运行
3. **Docker**: 已安装并运行 Docker 服务
4. **镜像文件**: 已通过 `download-images.sh` 下载并使用 `load-images.sh` 加载所需的 Docker 镜像

## 脚本说明

### 1. setup.sh - 初始设置脚本
交互式配置 Nextcloud AIO 的所有环境变量和设置。

**功能特性:**
- 🔧 交互式配置向导
- 🔐 自动生成安全密码
- ✅ 输入验证和检查
- 📁 自动创建必要目录
- 💾 保存配置到 `nextcloud-aio.conf`

**使用方法:**
```bash
sudo ./setup.sh
```

### 2. start.sh - 容器启动脚本
按正确的依赖顺序启动所有 Nextcloud AIO 容器。

**功能特性:**
- 🚀 按依赖顺序启动容器
- 🔗 自动创建 Docker 网络和卷
- ⏱️ 等待容器健康检查
- 🧹 清理旧容器
- 📊 显示启动结果

**使用方法:**
```bash
sudo ./start.sh
```

### 3. stop.sh - 容器停止脚本
优雅地停止所有 Nextcloud AIO 容器。

**功能特性:**
- 🛑 按依赖顺序优雅停止
- ⏰ 可配置停止超时时间
- 🗑️ 可选删除容器和网络
- 💪 支持强制停止模式

**使用方法:**
```bash
# 仅停止容器
sudo ./stop.sh

# 停止并删除容器
sudo ./stop.sh --remove

# 停止容器，删除容器和网络
sudo ./stop.sh --cleanup

# 强制并行停止所有容器
sudo ./stop.sh --force
```

### 4. status.sh - 状态检查脚本
显示详细的容器运行状态和系统信息。

**功能特性:**
- 📊 容器状态和健康检查
- 💾 资源使用情况
- 🌐 网络和端口状态
- 📁 存储卷信息
- 📝 最近日志摘要

**使用方法:**
```bash
# 显示完整状态
sudo ./status.sh

# 显示简化状态
sudo ./status.sh --simple

# 显示状态和日志
sudo ./status.sh --logs

# 显示系统资源
sudo ./status.sh --resources

# 显示配置信息
sudo ./status.sh --config
```

## 部署流程

### 第一次部署

1. **准备镜像文件**
   ```bash
   # 在有网络的环境中下载镜像
   ./download-images.sh
   
   # 将镜像文件传输到离线环境
   # 在离线环境中加载镜像
   ./load-images.sh
   ```

2. **初始设置**
   ```bash
   sudo ./setup.sh
   ```
   按照提示配置：
   - 域名和端口
   - 管理员密码
   - 数据目录
   - 可选功能（ClamAV、Collabora、OnlyOffice、Talk等）

3. **启动服务**
   ```bash
   sudo ./start.sh
   ```

4. **检查状态**
   ```bash
   sudo ./status.sh
   ```

5. **访问 Nextcloud**
   打开浏览器访问: `https://your-domain:port`

### 日常管理

```bash
# 查看状态
sudo ./status.sh

# 停止服务
sudo ./stop.sh

# 启动服务
sudo ./start.sh

# 重启服务
sudo ./stop.sh && sudo ./start.sh
```

## 配置文件

所有配置保存在 `nextcloud-aio.conf` 文件中，包括：

- **基础配置**: 域名、端口、密码
- **目录配置**: 数据目录、挂载目录
- **功能开关**: 各种可选功能的启用状态
- **安全密钥**: 自动生成的各种服务密钥

## 目录结构

```
manual-install/
├── setup.sh              # 初始设置脚本
├── start.sh               # 启动脚本
├── stop.sh                # 停止脚本
├── status.sh              # 状态检查脚本
├── nextcloud-aio.conf     # 配置文件（运行setup.sh后生成）
├── download-images.sh     # 镜像下载脚本
├── load-images.sh         # 镜像加载脚本
├── sample.conf            # 配置示例文件
├── latest.yml             # Docker Compose配置参考
└── README-offline.md      # 本文档
```

## 容器架构

### 核心容器
- **nextcloud-aio-apache**: Web服务器和反向代理
- **nextcloud-aio-nextcloud**: Nextcloud主应用
- **nextcloud-aio-database**: PostgreSQL数据库
- **nextcloud-aio-redis**: Redis缓存
- **nextcloud-aio-notify-push**: 实时通知服务

### 可选容器
- **nextcloud-aio-clamav**: 防病毒扫描
- **nextcloud-aio-collabora**: 在线办公套件
- **nextcloud-aio-onlyoffice**: 另一个办公套件选择
- **nextcloud-aio-talk**: 视频通话和聊天
- **nextcloud-aio-talk-recording**: 通话录制
- **nextcloud-aio-imaginary**: 图像处理服务
- **nextcloud-aio-fulltextsearch**: 全文搜索
- **nextcloud-aio-whiteboard**: 在线白板

## 网络配置

- **Docker网络**: `nextcloud-aio`
- **默认端口**: 443 (HTTPS)
- **Talk端口**: 3478 (如果启用)

## 存储配置

### Docker卷
- `nextcloud_aio_nextcloud`: Nextcloud应用数据
- `nextcloud_aio_database`: 数据库数据
- `nextcloud_aio_redis`: Redis数据
- `nextcloud_aio_apache`: Apache配置

### 主机挂载
- 用户数据目录: 存储用户上传的文件
- 挂载目录: 外部存储挂载点

## 故障排除

### 常见问题

1. **容器启动失败**
   ```bash
   # 查看容器日志
   docker logs nextcloud-aio-nextcloud
   
   # 检查容器状态
   sudo ./status.sh --logs
   ```

2. **端口冲突**
   ```bash
   # 检查端口占用
   netstat -tuln | grep :443
   
   # 修改配置文件中的端口
   nano nextcloud-aio.conf
   ```

3. **权限问题**
   ```bash
   # 确保数据目录权限正确
   chown -R www-data:www-data /path/to/nextcloud/data
   ```

4. **内存不足**
   ```bash
   # 检查系统资源
   sudo ./status.sh --resources
   
   # 禁用不需要的可选功能
   nano nextcloud-aio.conf
   ```

### 日志查看

```bash
# 查看所有容器日志
docker logs nextcloud-aio-nextcloud
docker logs nextcloud-aio-database
docker logs nextcloud-aio-apache

# 实时查看日志
docker logs -f nextcloud-aio-nextcloud
```

## 备份和恢复

### 备份
```bash
# 停止服务
sudo ./stop.sh

# 备份数据目录
tar -czf nextcloud-backup-$(date +%Y%m%d).tar.gz /path/to/nextcloud/data

# 备份数据库
docker run --rm -v nextcloud_aio_database:/data -v $(pwd):/backup alpine tar czf /backup/database-backup-$(date +%Y%m%d).tar.gz /data

# 重新启动服务
sudo ./start.sh
```

### 恢复
```bash
# 停止服务
sudo ./stop.sh --cleanup

# 恢复数据目录
tar -xzf nextcloud-backup-YYYYMMDD.tar.gz -C /

# 恢复数据库
docker run --rm -v nextcloud_aio_database:/data -v $(pwd):/backup alpine tar xzf /backup/database-backup-YYYYMMDD.tar.gz -C /

# 重新启动服务
sudo ./start.sh
```

## 安全建议

1. **防火墙配置**
   ```bash
   # 只开放必要端口
   ufw allow 443/tcp
   ufw allow 3478/tcp  # 如果启用Talk
   ```

2. **SSL证书**
   - 使用有效的SSL证书
   - 定期更新证书

3. **定期更新**
   - 定期下载最新镜像
   - 备份后更新容器

4. **监控**
   - 定期检查容器状态
   - 监控系统资源使用

## 支持

如果遇到问题，请：

1. 查看容器日志
2. 检查系统资源
3. 验证配置文件
4. 参考官方文档

---

**注意**: 这些脚本专为离线环境设计，确保在运行前已正确加载所有必需的Docker镜像。