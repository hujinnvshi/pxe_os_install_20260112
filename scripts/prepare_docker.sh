#!/bin/bash
# Docker 部署数据准备脚本
# 用于准备 Docker 容器所需的 TFTP 和 HTTP 数据

set -e

# ============================================
# 配置
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_DIR/data"
TFTP_DIR="$DATA_DIR/tftpboot"
ISO_DIR="$DATA_DIR/iso"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================
# 检查系统
# ============================================
check_requirements() {
    log_info "Checking requirements..."

    # 检查必要命令
    for cmd in wget curl gzip cpio; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Required command '$cmd' not found. Please install it first."
            exit 1
        fi
    done

    log_info "Requirements check passed"
}

# ============================================
# 创建目录结构
# ============================================
create_directories() {
    log_info "Creating directory structure..."

    mkdir -p "$DATA_DIR"
    mkdir -p "$TFTP_DIR/pxelinux.cfg"
    mkdir -p "$ISO_DIR"
    mkdir -p "$TFTP_DIR/centos7"
    mkdir -p "$TFTP_DIR/centos8"
    mkdir -p "$TFTP_DIR/ubuntu2004"
    mkdir -p "$TFTP_DIR/ubuntu2204"

    log_info "Directory structure created"
}

# ============================================
# 下载并准备 Syslinux 引导文件
# ============================================
download_syslinux() {
    log_info "Downloading Syslinux boot files..."

    local SYSLINUX_VERSION="6.03"
    local SYSLINUX_URL="https://kernel.org/pub/linux/utils/boot/syslinux/syslinux-${SYSLINUX_VERSION}.tar.xz"
    local TEMP_DIR=$(mktemp -d)

    cd "$TEMP_DIR"

    # 下载 syslinux
    if [ ! -f "$DATA_DIR/syslinux-${SYSLINUX_VERSION}.tar.xz" ]; then
        log_info "Downloading Syslinux ${SYSLINUX_VERSION}..."
        wget -q --show-progress "$SYSLINUX_URL" -O "$DATA_DIR/syslinux-${SYSLINUX_VERSION}.tar.xz"
    fi

    # 解压
    log_info "Extracting Syslinux..."
    tar -xf "$DATA_DIR/syslinux-${SYSLINUX_VERSION}.tar.xz" -C "$TEMP_DIR"

    # 复制引导文件
    log_info "Copying boot files to TFTP directory..."

    find "$TEMP_DIR/syslinux-${SYSLINUX_VERSION}" -name "pxelinux.0" -exec cp {} "$TFTP_DIR/" \;
    find "$TEMP_DIR/syslinux-${SYSLINUX_VERSION}" -name "ldlinux.c32" -exec cp {} "$TFTP_DIR/" \;
    find "$TEMP_DIR/syslinux-${SYSLINUX_VERSION}" -name "menu.c32" -exec cp {} "$TFTP_DIR/" \;
    find "$TEMP_DIR/syslinux-${SYSLINUX_VERSION}" -name "chain.c32" -exec cp {} "$TFTP_DIR/" \;
    find "$TEMP_DIR/syslinux-${SYSLINUX_VERSION}" -name "memdisk" -exec cp {} "$TFTP_DIR/" \;
    find "$TEMP_DIR/syslinux-${SYSLINUX_VERSION}" -name "reboot.c32" -exec cp {} "$TFTP_DIR/" \;
    find "$TEMP_DIR/syslinux-${SYSLINUX_VERSION}" -name "poweroff.com" -exec cp {} "$TFTP_DIR/" \;
    find "$TEMP_DIR/syslinux-${SYSLINUX_VERSION}" -name "libcom32.c32" -exec cp {} "$TFTP_DIR/" \;
    find "$TEMP_DIR/syslinux-${SYSLINUX_VERSION}" -name "libutil.c32" -exec cp {} "$TFTP_DIR/" \;

    # 清理
    cd - > /dev/null
    rm -rf "$TEMP_DIR"

    log_info "Syslinux boot files prepared"
}

# ============================================
# 从本地系统复制引导文件（备选方案）
# ============================================
copy_local_syslinux() {
    log_info "Attempting to copy Syslinux from local system..."

    local COPIED=0

    # 常见的 syslinux 文件位置
    for SYSLINUX_DIR in /usr/share/syslinux /usr/lib/syslinux /usr/lib/SYSLINUX; do
        if [ -d "$SYSLINUX_DIR" ]; then
            log_info "Found syslinux at $SYSLINUX_DIR"

            cp -f "$SYSLINUX_DIR"/pxelinux.0 "$TFTP_DIR/" 2>/dev/null && COPIED=1
            cp -f "$SYSLINUX_DIR"/ldlinux.c32 "$TFTP_DIR/" 2>/dev/null
            cp -f "$SYSLINUX_DIR"/menu.c32 "$TFTP_DIR/" 2>/dev/null
            cp -f "$SYSLINUX_DIR"/chain.c32 "$TFTP_DIR/" 2>/dev/null
            cp -f "$SYSLINUX_DIR"/memdisk "$TFTP_DIR/" 2>/dev/null
            cp -f "$SYSLINUX_DIR"/reboot.c32 "$TFTP_DIR/" 2>/dev/null
            cp -f "$SYSLINUX_DIR"/poweroff.com "$TFTP_DIR/" 2>/dev/null
            cp -f "$SYSLINUX_DIR"/libcom32.c32 "$TFTP_DIR/" 2>/dev/null
            cp -f "$SYSLINUX_DIR"/libutil.c32 "$TFTP_DIR/" 2>/dev/null

            if [ $COPIED -eq 1 ]; then
                log_info "Successfully copied boot files from $SYSLINUX_DIR"
                return 0
            fi
        fi
    done

    log_warn "Could not find syslinux files on local system"
    return 1
}

# ============================================
# 复制 PXE 启动菜单
# ============================================
copy_boot_menu() {
    log_info "Copying PXE boot menu..."

    cp "$PROJECT_DIR/configs/default" "$TFTP_DIR/pxelinux.cfg/default"

    log_info "Boot menu copied"
}

# ============================================
# 准备 ISO 目录
# ============================================
prepare_iso_directories() {
    log_info "Preparing ISO directories..."

    mkdir -p "$ISO_DIR/centos7"
    mkdir -p "$ISO_DIR/centos8"
    mkdir -p "$ISO_DIR/ubuntu2004"
    mkdir -p "$ISO_DIR/ubuntu2204"

    # 创建说明文件
    cat > "$ISO_DIR/README.txt" << 'EOF'
===================================
PXE ISO 镜像存储目录
===================================

使用方法：
1. 下载系统 ISO 镜像
2. 挂载 ISO: mount -o loop xxx.iso /mnt
3. 复制内容:
   - CentOS/RHEL: cp -r /mnt/* iso/centos7/
   - Ubuntu: cp -r /mnt/* iso/ubuntu2004/
4. 提取内核和 initrd:
   - CentOS/RHEL: cp /mnt/images/pxeboot/vmlinuz tftpboot/centos7/
   - Ubuntu: cp /mnt/casper/vmlinuz tftpboot/ubuntu2004/

注意：
- ISO 镜像可以从官方站点下载
- 也可以使用 add_iso.sh 脚本自动添加
EOF

    log_info "ISO directories prepared"
}

# ============================================
# 创建占位文件说明
# ============================================
create_placeholders() {
    log_info "Creating placeholder files..."

    cat > "$TFTP_DIR/README.txt" << 'EOF'
===================================
PXE TFTP 引导文件目录
===================================

目录说明：
- pxelinux.0: PXE 引导加载器
- pxelinux.cfg/default: 启动菜单配置
- centos7/, centos8/: CentOS 内核和 initrd
- ubuntu2004/, ubuntu2204/: Ubuntu 内核和 initrd

使用 add_iso.sh 脚本自动添加 ISO：
./scripts/add_iso.sh /path/to/iso.iso centos 7

注意：
- 内核和 initrd 文件需要从 ISO 中提取
- 可以手动复制或使用脚本自动处理
EOF

    log_info "Placeholder files created"
}

# ============================================
# 创建快速启动说明
# ============================================
create_quickstart() {
    log_info "Creating quick start guide..."

    cat > "$PROJECT_DIR/Docker-QUICKSTART.md" << 'EOF'
# Docker 部署快速开始

## 前置准备

1. 安装 Docker 和 Docker Compose
2. 准备至少 20GB 可用磁盘空间

## 快速开始

### 1. 准备数据（已自动执行）

```bash
# 运行数据准备脚本
./scripts/prepare_docker.sh
```

### 2. 添加系统 ISO

**方式 A：使用脚本自动添加（推荐）**

```bash
# 添加 CentOS 7
./scripts/add_iso.sh /path/to/CentOS-7-x86_64-Minimal.iso centos 7

# 添加 Ubuntu 20.04
./scripts/add_iso.sh /path/to/ubuntu-20.04.3-live-server-amd64.iso ubuntu 2004
```

**方式 B：手动添加**

```bash
# 挂载 ISO
mkdir -p /mnt/iso
mount -o loop /path/to/centos7.iso /mnt/iso

# 复制到 ISO 目录
cp -r /mnt/iso/* data/iso/centos7/

# 提取内核和 initrd
cp /mnt/iso/images/pxeboot/vmlinuz data/tftpboot/centos7/
cp /mnt/iso/images/pxeboot/initrd.img data/tftpboot/centos7/

# 卸载
umount /mnt/iso
```

### 3. 修改配置

```bash
# 修改 configs/dhcpd.conf 中的网络配置
vim configs/dhcpd.conf

# 修改 configs/default 中的 IP 地址
vim configs/default
```

需要修改的 IP 地址：
- 192.168.1.10 → 你的 PXE 服务器 IP
- 192.168.1.1 → 你的网关地址

### 4. 启动服务

```bash
# 构建并启动所有容器
docker-compose up -d

# 查看容器状态
docker-compose ps

# 查看日志
docker-compose logs -f
```

### 5. 测试

```bash
# 测试 HTTP 服务
curl http://localhost:8080/health

# 测试 TFTP（需要安装 tftp 客户端）
tftp 127.0.0.1 -c get pxelinux.0
```

### 6. 创建虚拟机测试

在 ESXi 或其他虚拟化平台上创建虚拟机：
- 设置从网络启动
- 确保虚拟机网络与 PXE 服务器在同一网络段
- 启动虚拟机

## 故障排查

### DHCP 不工作

```bash
# 查看日志
docker-compose logs dhcpd

# 检查是否有其他 DHCP 服务器
sudo tcpdump -i any port 67
```

### TFTP 连接失败

```bash
# 查看日志
docker-compose logs tftpd

# 检查文件权限
ls -la data/tftpboot/
```

### HTTP 无法访问

```bash
# 查看日志
docker-compose logs httpd

# 检查 Nginx 配置
docker-compose exec httpd nginx -t
```

## 停止服务

```bash
# 停止所有容器
docker-compose down

# 停止并删除数据卷
docker-compose down -v
```

## 重启服务

```bash
# 重启所有服务
docker-compose restart

# 重启单个服务
docker-compose restart dhcpd
```
EOF

    log_info "Quick start guide created"
}

# ============================================
# 显示摘要
# ============================================
show_summary() {
    echo ""
    log_info "=========================================="
    log_info "Docker data preparation completed!"
    log_info "=========================================="
    echo ""
    echo "Directory structure:"
    echo "  TFTP:  $TFTP_DIR"
    echo "  ISO:   $ISO_DIR"
    echo ""
    log_warn "Next steps:"
    echo "  1. Add ISO images using: ./scripts/add_iso.sh <iso-file>"
    echo "  2. Modify configs/dhcpd.conf and configs/default for your network"
    echo "  3. Start containers: docker-compose up -d"
    echo ""
    log_warn "Important:"
    echo "  - Update IP addresses in config files to match your network"
    echo "  - Ensure no other DHCP server is running on the network"
    echo "  - Test with a VM before deploying to production"
    echo ""
}

# ============================================
# 主函数
# ============================================
main() {
    log_info "Starting Docker data preparation..."

    check_requirements
    create_directories

    # 尝试从本地复制引导文件，失败则下载
    if ! copy_local_syslinux; then
        log_warn "Attempting to download Syslinux..."
        download_syslinux
    fi

    copy_boot_menu
    prepare_iso_directories
    create_placeholders
    create_quickstart
    show_summary

    log_info "Preparation completed successfully!"
}

# 运行主函数
main "$@"
