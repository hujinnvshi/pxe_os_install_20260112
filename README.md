# PXE 网络安装自动化系统

基于 PXE + Kickstart/Preseed 的操作系统自动化网络安装系统。

## 功能特性

- 支持 PXE 网络引导启动
- 支持 CentOS/RHEL/Ubuntu/Debian 等多个系统
- 支持完全自动化安装（通过 Kickstart/Preseed）
- 支持自定义分区、网络配置、软件包选择
- 支持 MAC 地址绑定，为不同机器定制配置
- 提供一键部署脚本和 Docker 部署方式
- 提供 Web 管理界面（可选）

## 系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        PXE 客户端                                │
│                    (虚拟机/物理机)                               │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                        PXE 流程                                  │
│  DHCP Discover → DHCP Offer → TFTP Request → Boot Menu          │
└────────────────────┬────────────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        ▼            ▼            ▼
┌──────────────┐ ┌────────────┐ ┌──────────────┐
│  DHCP Server │ │ TFTP Server│ │ HTTP Server  │
│   (端口 67)  │ │  (端口 69) │ │  (端口 80)   │
├──────────────┤ ├────────────┤ ├──────────────┤
│ 分配 IP      │ │ pxelinux.0 │ │ ISO 镜像     │
│ 指定 TFTP    │ │ vmlinuz    │ │ Kickstart    │
│ 指定引导文件 │ │ initrd.img │ │ 配置文件     │
└──────────────┘ └────────────┘ └──────────────┘
```

## 目录结构

```
pxe_os_install_20260112/
├── README.md              # 项目说明文档
├── docker-compose.yml     # Docker 编排文件
├── scripts/               # 部署和管理脚本
│   ├── install.sh        # 一键安装脚本
│   ├── setup.sh          # 初始化配置脚本
│   ├── add_iso.sh        # 添加系统 ISO
│   └── gen_ks.sh         # 生成 Kickstart 配置
├── configs/              # 配置文件模板
│   ├── dhcpd.conf       # DHCP 配置模板
│   ├── default          # PXE 启动菜单模板
│   ├── nginx.conf       # Nginx 配置
│   └── ks/              # Kickstart 配置模板
│       ├── centos7-ks.cfg
│       ├── centos8-ks.cfg
│       └── ubuntu20-ks.cfg
├── docker/              # Docker 相关文件
│   ├── Dockerfile.dhcp
│   ├── Dockerfile.tftp
│   └── Dockerfile.http
├── templates/           # 其他配置模板
│   └── ...
├── docs/                # 文档
│   ├── ARCHITECTURE.md   # 架构说明
│   ├── INSTALL.md        # 安装指南
│   └── USAGE.md          # 使用指南
└── tests/               # 测试脚本
    └── test_pxe.sh
```

## 快速开始

### 方式一：Docker 部署（推荐）

```bash
# 1. 克隆项目
git clone <repo_url>
cd pxe_os_install_20260112

# 2. 准备 ISO 文件
mkdir -p data/iso
cp /path/to/CentOS-7-x86_64-Minimal.iso data/iso/

# 3. 启动所有服务
docker-compose up -d

# 4. 查看日志
docker-compose logs -f
```

### 方式二：本地安装

```bash
# 1. 运行安装脚本
sudo ./scripts/install.sh

# 2. 添加 ISO 镜像
sudo ./scripts/add_iso.sh /path/to/centos7.iso

# 3. 启动所有服务
sudo systemctl enable dhcpd tftp nginx
sudo systemctl start dhcpd tftp nginx

# 4. 检查服务状态
sudo systemctl status dhcpd tftp nginx
```

## 配置说明

### 网络配置

编辑 `configs/dhcpd.conf`：

```conf
subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    option routers 192.168.1.1;
    next-server 192.168.1.10;    # TFTP 服务器 IP
    filename "pxelinux.0";        # 引导文件名
}
```

### 启动菜单配置

编辑 `configs/default`：

```conf
DEFAULT menu.c32
MENU TITLE PXE Boot Menu

LABEL centos7
    MENU LABEL Install CentOS 7
    KERNEL centos7/vmlinuz
    APPEND initrd=centos7/initrd.img ks=http://192.168.1.10/ks/centos7-ks.cfg
```

### Kickstart 配置

编辑 `configs/ks/centos7-ks.cfg`，自定义安装参数：

```Kickstart
install
url --url="http://192.168.1.10/iso/centos7"
lang en_US.UTF-8
keyboard us
network --bootproto=dhcp
rootpw --iscrypted $6$...
autopart --type=lvm

%packages
@core
vim
git
%end

%post
#!/bin/bash
# 安装后脚本
yum update -y
%end
```

## 支持的系统

| 系统 | 版本 | Kickstart/Preseed | 状态 |
|------|------|-------------------|------|
| CentOS | 7/8/9 | Kickstart | ✓ |
| RHEL | 7/8/9 | Kickstart | ✓ |
| Ubuntu | 18.04/20.04/22.04 | Preseed | ✓ |
| Debian | 10/11/12 | Preseed | ✓ |
| Rocky Linux | 8/9 | Kickstart | ✓ |
| AlmaLinux | 8/9 | Kickstart | ✓ |

## 使用示例

### 1. 创建虚拟机进行 PXE 安装

在 ESXi 上创建虚拟机时：
- 硬盘：至少 20GB
- 内存：至少 2GB
- 网络：连接到与 PXE 服务器相同的网络
- 启动顺序：设置网络启动优先

### 2. 物理机 PXE 安装

- 开机时按 F12（或其他键）选择网络启动
- 选择 PXE 启动项
- 从菜单中选择要安装的系统

### 3. 为特定机器定制配置

创建 `configs/pxelinux.cfg/01-<MAC地址>`：

```conf
DEFAULT centos7-custom
LABEL centos7-custom
    KERNEL centos7/vmlinuz
    APPEND initrd=centos7/initrd.img ks=http://192.168.1.10/ks/custom-ks.cfg
```

## 故障排查

### 客户端无法获取 IP

```bash
# 检查 DHCP 服务
sudo systemctl status dhcpd
sudo tail -f /var/log/messages | grep dhcpd

# 检查防火墙
sudo firewall-cmd --list-all
sudo firewall-cmd --add-service=dhcp --permanent
```

### TFTP 连接失败

```bash
# 检查 TFTP 服务
sudo systemctl status tftp
sudo netstat -ulp | grep 69

# 测试 TFTP 连接
tftp 192.168.1.10 -c get pxelinux.0
```

### Kickstart 文件无法下载

```bash
# 检查 HTTP 服务
curl http://192.168.1.10/ks/centos7-ks.cfg

# 检查 Nginx 配置
sudo nginx -t
```

## 开发计划

- [ ] Web 管理界面
- [ ] 支持动态生成 Kickstart 配置
- [ ] 支持机器注册和管理
- [ ] 安装日志记录和查询
- [ ] 集成 ESXi API 自动创建虚拟机
- [ ] 支持 UEFI 启动

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！
