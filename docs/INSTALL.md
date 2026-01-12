# PXE 安装指南

## 前置准备

### 1. 硬件/服务器要求

- **PXE 服务器**：
  - CPU: 2核或以上
  - 内存: 2GB 或以上
  - 磁盘: 至少 50GB（用于存放 ISO 镜像）
  - 网络: 与待安装机器在同一网络段

- **网络环境**：
  - 确保网络中没有其他 DHCP 服务器（会冲突）
  - 或者配置独立的网络段用于 PXE 安装

### 2. 系统要求

- **操作系统**：CentOS/RHEL 7/8/9 或 Rocky Linux/AlmaLinux
- **权限**：需要 root 权限
- **网络接口**：确认网络接口名称（如 eth0, ens33 等）

---

## 方式一：Docker 部署（推荐）

### 步骤 1：安装 Docker

```bash
# CentOS/RHEL
sudo yum install -y docker
sudo systemctl enable docker
sudo systemctl start docker

# Ubuntu/Debian
sudo apt update
sudo apt install -y docker.io docker-compose
sudo systemctl enable docker
sudo systemctl start docker
```

### 步骤 2：准备配置

```bash
cd pxe_os_install_20260112

# 修改配置文件
vim configs/dhcpd.conf  # 修改网络配置
vim configs/default     # 修改启动菜单
```

### 步骤 3：准备 ISO 文件

```bash
# 创建 ISO 目录
mkdir -p data/iso

# 复制 CentOS 7 ISO
cp /path/to/CentOS-7-x86_64-Minimal.iso data/iso/

# 挂载并提取文件
mkdir -p /mnt/centos7
mount -o loop data/iso/CentOS-7-x86_64-Minimal.iso /mnt/centos7
mkdir -p data/iso/centos7
cp -r /mnt/centos7/* data/iso/centos7/
umount /mnt/centos7

# 提取内核和 initrd
mkdir -p data/tftpboot/centos7
cp data/iso/centos7/images/pxeboot/vmlinuz data/tftpboot/centos7/
cp data/iso/centos7/images/pxeboot/initrd.img data/tftpboot/centos7/
```

### 步骤 4：启动服务

```bash
# 构建并启动所有容器
docker-compose up -d

# 查看容器状态
docker-compose ps

# 查看日志
docker-compose logs -f
```

### 步骤 5：测试

```bash
# 测试 HTTP 服务
curl http://localhost:8080/health

# 测试 TFTP
tftp 127.0.0.1 -c get pxelinux.0
```

---

## 方式二：本地安装

### 步骤 1：修改配置

编辑 `scripts/install.sh`，修改以下参数：

```bash
# 修改为你的网络配置
PXE_SERVER_IP="192.168.1.10"           # PXE 服务器 IP
NETWORK_INTERFACE="eth0"                # 网络接口名
DHCP_RANGE_START="192.168.1.100"        # DHCP 起始 IP
DHCP_RANGE_END="192.168.1.200"          # DHCP 结束 IP
GATEWAY="192.168.1.1"                   # 网关地址
```

### 步骤 2：运行安装脚本

```bash
cd pxe_os_install_20260112
sudo ./scripts/install.sh
```

### 步骤 3：添加系统 ISO

```bash
# 添加 CentOS 7
sudo ./scripts/add_iso.sh /path/to/CentOS-7-x86_64-Minimal.iso centos 7

# 添加 Ubuntu 20.04
sudo ./scripts/add_iso.sh /path/to/ubuntu-20.04.3-live-server-amd64.iso ubuntu 2004
```

### 步骤 4：配置 Kickstart

编辑 `/var/www/html/ks/centos7-ks.cfg`，修改 root 密码等配置：

```bash
# 生成加密密码
./scripts/gen_ks.sh "yourpassword"

# 编辑 Kickstart 文件
sudo vim /var/www/html/ks/centos7-ks.cfg
```

### 步骤 5：启动虚拟机测试

1. 在 ESXi 上创建虚拟机
2. 设置从网络启动
3. 启动虚拟机
4. 应该看到 PXE 启动菜单
5. 选择要安装的系统

---

## 配置说明

### DHCP 配置

```bash
sudo vim /etc/dhcp/dhcpd.conf
```

关键配置项：
- `range`: IP 地址池范围
- `option routers`: 网关地址
- `next-server`: TFTP 服务器 IP
- `filename`: 引导文件名

### PXE 启动菜单

```bash
sudo vim /tftpboot/pxelinux.cfg/default
```

可以添加或修改启动项。

### Kickstart 配置

```bash
sudo vim /var/www/html/ks/centos7-ks.cfg
```

主要配置区域：
- 分区配置
- 网络配置
- 软件包选择
- 安装后脚本

---

## 故障排查

### 1. 客户端无法获取 IP

```bash
# 检查 DHCP 服务
sudo systemctl status dhcpd

# 检查日志
sudo tail -f /var/log/messages | grep dhcpd

# 测试 DHCP
sudo dhcpd -d -cf /etc/dhcp/dhcpd.conf eth0
```

### 2. TFTP 连接失败

```bash
# 检查 TFTP 服务
sudo systemctl status xinetd

# 检查端口
sudo netstat -ulp | grep 69

# 测试 TFTP
echo "test" > /tmp/test.txt
sudo mv /tmp/test.txt /tftpboot/
tftp 192.168.1.10 -c get test.txt
```

### 3. HTTP 无法访问

```bash
# 检查 Nginx
sudo systemctl status nginx

# 测试访问
curl http://192.168.1.10/ks/centos7-ks.cfg

# 检查配置
sudo nginx -t
```

### 4. 虚拟机无法启动

- 确认虚拟机网络与 PXE 服务器在同一网络
- 检查 ESXi 虚拟交换机配置
- 确认虚拟机启动顺序设置正确

---

## 安全建议

1. **生产环境建议**：
   - 使用独立的网络段进行 PXE 安装
   - 安装完成后禁用或限制 DHCP 服务
   - 使用防火墙限制访问
   - 定期更新系统和软件包

2. **密码安全**：
   - 使用强密码
   - 不要在 Kickstart 文件中使用明文密码
   - 安装后立即修改默认密码
