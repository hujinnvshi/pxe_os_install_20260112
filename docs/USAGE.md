# PXE 系统使用指南

本指南详细介绍如何使用 PXE 网络安装系统进行操作系统的自动化部署。

## 目录

1. [基础操作](#基础操作)
2. [添加新系统](#添加新系统)
3. [自定义安装配置](#自定义安装配置)
4. [高级功能](#高级功能)
5. [实际案例](#实际案例)
6. [故障排查](#故障排查)

---

## 基础操作

### 启动和停止服务

#### Docker 部署

```bash
# 启动所有服务
docker-compose up -d

# 停止所有服务
docker-compose down

# 重启服务
docker-compose restart

# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f [service_name]
```

#### 本地安装

```bash
# 启动服务
sudo systemctl start dhcpd tftp nginx

# 停止服务
sudo systemctl stop dhcpd tftp nginx

# 重启服务
sudo systemctl restart dhcpd tftp nginx

# 查看服务状态
sudo systemctl status dhcpd tftp nginx
```

### 检查服务健康状态

```bash
# 检查 HTTP 服务
curl http://192.168.1.10:8080/health

# 检查 DHCP 日志
sudo journalctl -u dhcpd -f

# 检查 TFTP 端口
sudo netstat -ulp | grep 69

# 检查 Nginx 状态
sudo systemctl status nginx
```

---

## 添加新系统

### 方式一：使用脚本自动添加（推荐）

```bash
# 添加 CentOS 7
./scripts/add_iso.sh /path/to/CentOS-7-x86_64-Minimal.iso centos 7

# 添加 CentOS Stream 8
./scripts/add_iso.sh /path/to/CentOS-Stream-8-x86_64-boot.iso centos 8

# 添加 Ubuntu 20.04
./scripts/add_iso.sh /path/to/ubuntu-20.04.3-live-server-amd64.iso ubuntu 2004

# 添加 Ubuntu 22.04
./scripts/add_iso.sh /path/to/ubuntu-22.04-live-server-amd64.iso ubuntu 2204
```

### 方式二：手动添加

#### 步骤 1：挂载 ISO

```bash
# 创建挂载点
sudo mkdir -p /mnt/iso

# 挂载 ISO
sudo mount -o loop /path/to/centos7.iso /mnt/iso
```

#### 步骤 2：复制 ISO 内容

```bash
# Docker 部署
sudo cp -r /mnt/iso/* data/iso/centos7/

# 本地安装
sudo cp -r /mnt/iso/* /var/www/html/iso/centos7/
```

#### 步骤 3：提取内核和 initrd

**CentOS/RHEL:**

```bash
# Docker 部署
sudo cp /mnt/iso/images/pxeboot/vmlinuz data/tftpboot/centos7/
sudo cp /mnt/iso/images/pxeboot/initrd.img data/tftpboot/centos7/

# 本地安装
sudo cp /mnt/iso/images/pxeboot/vmlinuz /tftpboot/centos7/
sudo cp /mnt/iso/images/pxeboot/initrd.img /tftpboot/centos7/
```

**Ubuntu/Debian:**

```bash
# Docker 部署
sudo cp /mnt/iso/casper/vmlinuz data/tftpboot/ubuntu2004/
sudo cp /mnt/iso/casper/initrd data/tftpboot/ubuntu2004/initrd.img

# 本地安装
sudo cp /mnt/iso/casper/vmlinuz /tftpboot/ubuntu2004/
sudo cp /mnt/iso/casper/initrd /tftpboot/ubuntu2004/initrd.img
```

#### 步骤 4：添加启动菜单项

编辑 `configs/default`（Docker）或 `/tftpboot/pxelinux.cfg/default`（本地安装）：

```conf
LABEL my-custom-os
    MENU LABEL ^9. Install My Custom OS
    KERNEL myos/vmlinuz
    APPEND initrd=myos/initrd.img ks=http://192.168.1.10:8080/ks/myos-ks.cfg quiet
```

#### 步骤 5：卸载 ISO

```bash
sudo umount /mnt/iso
```

---

## 自定义安装配置

### 修改 Kickstart 配置（CentOS/RHEL）

#### 1. 编辑 Kickstart 文件

```bash
vim configs/ks/centos7-ks.cfg
```

#### 2. 常见配置修改

**修改 root 密码：**

```bash
# 生成加密密码
./scripts/gen_ks.sh "newpassword"

# 编辑 ks.cfg，替换 rootpw 行
rootpw --iscrypted $1$generated_hash...
```

**修改分区方案：**

```Kickstart
# 自动分区
autopart --type=lvm

# 或手动分区
part /boot --fstype=xfs --size=500
part swap --size=2048
part pv.01 --size=1 --grow
volgroup centos pv.01
logvol / --fstype=xfs --name=root --vgname=centos --size=10240 --grow
```

**添加软件包：**

```Kickstart
%packages
@core
vim
git
docker
nginx
%end
```

**添加安装后脚本：**

```Kickstart
%post
#!/bin/bash
# 安装后执行
yum update -y
systemctl enable sshd
echo "Custom post-install script" > /root/post-install.log
%end
```

### 修改 Preseed 配置（Ubuntu/Debian）

#### 1. 编辑 Preseed 文件

```bash
vim configs/ks/ubuntu2004-preseed.cfg
```

#### 2. 常见配置修改

**修改用户密码：**

```conf
d-i passwd/user-password password YourNewPassword123
d-i passwd/user-password-again password YourNewPassword123
```

**修改分区：**

```conf
d-i partman-auto/method string lvm
d-i partman-auto/expert_recipe string \
    boot-root :: \
        512 512 512 ext4 \
            $primary{ } \
            $bootable{ } \
            method{ format } \
            format{ } \
            use_filesystem{ } \
            filesystem{ ext4 } \
            mountpoint{ /boot } \
        . \
        10240 5120 -1 ext4 \
            $lvmok{ } \
            method{ format } \
            format{ } \
            use_filesystem{ } \
            filesystem{ ext4 } \
            mountpoint{ / } \
        .
```

**添加软件包：**

```conf
d-i pkgsel/include string \
    openssh-server \
    vim \
    git \
    docker.io \
    nginx
```

---

## 高级功能

### 为特定机器定制配置

通过 MAC 地址绑定，为不同机器提供不同的安装配置：

#### 方法 1：使用 PXE 配置文件

创建基于 MAC 地址的配置文件：

```bash
# 文件名格式：01-<MAC地址，小写，横线分隔>
# 例如：MAC 地址 00:0C:29:XX:XX:XX
vim data/tftpboot/pxelinux.cfg/01-00-0c-29-xx-xx-xx
```

内容示例：

```conf
DEFAULT custom-install
TIMEOUT 10

LABEL custom-install
    MENU LABEL Custom Installation for This Machine
    KERNEL centos7/vmlinuz
    APPEND initrd=centos7/initrd.img ks=http://192.168.1.10:8080/ks/custom-machine-ks.cfg

LABEL local-boot
    MENU LABEL Boot from Local Disk
    LOCALBOOT 0
```

#### 方法 2：使用 DHCP 固定 IP

编辑 `configs/dhcpd.conf`：

```conf
host webserver-01 {
    hardware ethernet 00:0c:29:xx:xx:xx;
    fixed-address 192.168.1.101;
    option host-name "webserver-01";
    option routers 192.168.1.1;
    next-server 192.168.1.10;
    filename "pxelinux.0";
}
```

### 动态 Kickstart 配置

使用 CGI 脚本动态生成 Kickstart 配置：

#### 1. 在启动菜单中使用动态 URL

```conf
LABEL centos7-dynamic
    MENU LABEL Install CentOS 7 (Dynamic Config)
    KERNEL centos7/vmlinuz
    APPEND initrd=centos7/initrd.img ks=http://192.168.1.10:8080/cgi-bin/ks.py?mac=00:0c:29:xx:xx:xx
```

#### 2. 创建 CGI 脚本

```python
#!/usr/bin/env python3
import cgi
import os

def generate_kickstart(mac_addr):
    # 根据配置生成 Kickstart
    ks_config = f"""
# Generated for MAC: {mac_addr}
install
url --url="http://192.168.1.10:8080/iso/centos7"
lang en_US.UTF-8
keyboard us
network --bootproto=dhcp
rootpw --iscrypted $1$default_password
autopart --type=lvm

%packages
@core
vim
%end

%post
#!/bin/bash
echo "Installed for MAC: {mac_addr}" > /root/install-info.txt
%end
"""
    return ks_config

print("Content-Type: text/plain\n")
form = cgi.FieldStorage()
mac = form.getvalue('mac', 'unknown')
print(generate_kickstart(mac))
```

### 多网络段支持

为不同网络段提供 PXE 服务：

编辑 `configs/dhcpd.conf`：

```conf
# 网络 1：192.168.1.0/24
subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    option routers 192.168.1.1;
    next-server 192.168.1.10;
    filename "pxelinux.0";
}

# 网络 2：10.0.0.0/24
subnet 10.0.0.0 netmask 255.255.255.0 {
    range 10.0.0.100 10.0.0.200;
    option routers 10.0.0.1;
    next-server 10.0.0.10;
    filename "pxelinux.0";
}
```

---

## 实际案例

### 案例 1：批量部署 Web 服务器

**需求**：部署 10 台 Web 服务器，统一配置

**方案**：

1. **创建 Kickstart 配置**

```bash
vim configs/ks/webserver-ks.cfg
```

```Kickstart
install
url --url="http://192.168.1.10:8080/iso/centos7"
lang en_US.UTF-8
keyboard us
network --bootproto=dhcp --hostname=webserver

# 分区配置
clearpart --all --initlabel
part /boot --fstype=xfs --size=1024
part swap --size=4096
part / --fstype=xfs --grow --size=1

# 软件包
%packages
@core
@web-server
@mysql-client
vim
git
%end

# 安装后配置
%post
#!/bin/bash
# 安装额外软件
yum install -y epel-release
yum install -y htop nginx

# 配置防火墙
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# 启动服务
systemctl enable nginx
systemctl start nginx

# 配置完成标记
echo "$(date) Web server installed via PXE" > /root/install-info.txt
%end

reboot
```

2. **添加启动菜单项**

编辑 `configs/default`：

```conf
LABEL webserver-batch
    MENU LABEL ^W. Install Web Server (Batch)
    KERNEL centos7/vmlinuz
    APPEND initrd=centos7/initrd.img ks=http://192.168.1.10:8080/ks/webserver-ks.cfg quiet
```

3. **批量创建虚拟机**

使用 ESXi 或其他虚拟化平台批量创建虚拟机，设置从网络启动即可。

### 案例 2：为不同部门定制系统

**需求**：研发部、测试部、运维部需要不同的软件配置

**方案**：

为每个部门创建独立的 Kickstart 配置：

```bash
# 研发部
configs/ks/dev-ks.cfg          # 包含开发工具
# 测试部
configs/ks/qa-ks.cfg           # 包含测试工具
# 运维部
configs/ks/ops-ks.cfg          # 包含监控工具
```

在启动菜单中分别添加选项：

```conf
LABEL dev-dept
    MENU LABEL ^D. Install for Dev Department
    KERNEL centos7/vmlinuz
    APPEND initrd=centos7/initrd.img ks=http://192.168.1.10:8080/ks/dev-ks.cfg

LABEL qa-dept
    MENU LABEL ^Q. Install for QA Department
    KERNEL centos7/vmlinuz
    APPEND initrd=centos7/initrd.img ks=http://192.168.1.10:8080/ks/qa-ks.cfg

LABEL ops-dept
    MENU LABEL ^O. Install for OPS Department
    KERNEL centos7/vmlinuz
    APPEND initrd=centos7/initrd.img ks=http://192.168.1.10:8080/ks/ops-ks.cfg
```

---

## 故障排查

### 常见问题及解决方案

#### 1. 客户端无法获取 IP

**症状**：客户端启动后一直等待 DHCP

**排查步骤**：

```bash
# 检查 DHCP 服务是否运行
sudo systemctl status dhcpd
docker-compose logs dhcpd

# 检查端口是否监听
sudo netstat -ulp | grep :67

# 检查日志
sudo tail -f /var/log/messages | grep dhcpd

# 抓包分析
sudo tcpdump -i any port 67
```

**可能原因**：
- DHCP 服务未启动
- 网络中有其他 DHCP 服务器冲突
- 防火墙阻止了 DHCP 流量

**解决方案**：

```bash
# 启动服务
sudo systemctl start dhcpd

# 关闭其他 DHCP 服务器
# 或配置 PXE DHCP 只响应特定请求（使用 class "PXE"）

# 配置防火墙
sudo firewall-cmd --add-service=dhcp --permanent
sudo firewall-cmd --reload
```

#### 2. TFTP 连接失败

**症状**：获取 IP 后无法下载引导文件

**排查步骤**：

```bash
# 检查 TFTP 服务
sudo systemctl status tftp
docker-compose logs tftpd

# 测试 TFTP 连接
tftp 192.168.1.10 -c get pxelinux.0

# 检查文件权限
ls -la /tftpboot/pxelinux.0
# 应该可读：-rw-r--r--

# 检查文件存在
ls -la /tftpboot/pxelinux.0
ls -la /tftpboot/ldlinux.c32
```

**可能原因**：
- TFTP 服务未启动
- 文件权限不正确
- 文件不存在

**解决方案**：

```bash
# 修复文件权限
sudo chmod 644 /tftpboot/*
sudo chown nobody:nobody /tftpboot/*

# 重启服务
sudo systemctl restart tftp
```

#### 3. Kickstart 文件无法下载

**症状**：内核启动后无法获取安装配置

**排查步骤**：

```bash
# 测试 HTTP 访问
curl http://192.168.1.10:8080/ks/centos7-ks.cfg

# 检查 Nginx 配置
sudo nginx -t
sudo systemctl status nginx

# 查看访问日志
sudo tail -f /var/log/nginx/access.log

# 检查防火墙
sudo firewall-cmd --list-all
```

**可能原因**：
- HTTP 服务未启动
- 配置文件路径错误
- 防火墙阻止访问

**解决方案**：

```bash
# 启动 HTTP 服务
sudo systemctl start nginx

# 修复配置文件路径
# 确保 configs/ks/ 目录正确

# 配置防火墙
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --reload
```

#### 4. 安装过程中断

**症状**：安装到一半失败

**排查步骤**：

- 查看虚拟机控制台输出
- 检查 Kickstart/Preseed 配置语法
- 检查网络连接
- 查看安装日志

**解决方案**：

```bash
# 验证 Kickstart 语法
ksvalidator /path/to/ks.cfg

# 检查 ISO 镜像完整性
sha256sum /path/to/iso

# 使用手动安装模式测试
# 在启动菜单选择 Manual Install
```

#### 5. 虚拟机反复重启

**症状**：安装完成后一直重启

**原因**：Kickstart 配置中有 `reboot` 命令

**解决方案**：

编辑 Kickstart 文件，移除或修改：
```Kickstart
# 注释掉这一行
# reboot

# 或改为关机
poweroff
```

### 日志收集

当遇到问题时，收集以下日志有助于诊断：

```bash
# 收集脚本
#!/bin/bash

LOG_DIR="/tmp/pxe-debug-$(date +%Y%m%d%H%M%S)"
mkdir -p "$LOG_DIR"

# DHCP 日志
sudo journalctl -u dhcpd > "$LOG_DIR/dhcpd.log"

# TFTP 日志
sudo journalctl -u tftp > "$LOG_DIR/tftp.log"

# Nginx 日志
sudo tail -n 100 /var/log/nginx/access.log > "$LOG_DIR/nginx-access.log"
sudo tail -n 100 /var/log/nginx/error.log > "$LOG_DIR/nginx-error.log"

# 服务状态
sudo systemctl status dhcpd > "$LOG_DIR/dhcpd-status"
sudo systemctl status tftp > "$LOG_DIR/tftp-status"
sudo systemctl status nginx > "$LOG_DIR/nginx-status"

# 网络状态
sudo netstat -tulpn > "$LOG_DIR/netstat.log"

# 配置文件
cp /etc/dhcp/dhcpd.conf "$LOG_DIR/"
cp /etc/nginx/nginx.conf "$LOG_DIR/"

echo "Logs collected to: $LOG_DIR"
```

---

## 最佳实践

1. **测试先行**：在大规模部署前，先用虚拟机测试配置
2. **版本控制**：将配置文件纳入 Git 管理
3. **文档记录**：记录每次修改和遇到的问题
4. **定期备份**：备份工作配置文件
5. **分阶段部署**：先部署到测试环境，再生产环境
6. **监控日志**：实时监控安装日志，及时发现问题
7. **安全加固**：安装完成后立即修改默认密码
8. **网络隔离**：生产环境使用独立网络段

---

## 参考资源

- [Red Hat Kickstart 文档](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_installation/index)
- [Ubuntu Preseed 文档](https://help.ubuntu.com/lts/installation-guide/amd64/apbs05.html)
- [Syslinux/PXELINUX 文档](https://wiki.syslinux.org/wiki/index.php?title=PXELINUX)
- [PXE 规范](https://www.intel.com/content/www/us/en/support/articles/000005600/boards-and-kits.html)
