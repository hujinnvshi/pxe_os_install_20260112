#!/bin/bash
# 添加系统 ISO 到 PXE 服务器

set -e

# ============================================
# 配置
# ============================================
ISO_DIR="/var/www/html/iso"
TFTP_DIR="/tftpboot"
HTTP_URL_PREFIX="http://192.168.1.10:8080/iso"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# 检查参数
if [ $# -lt 1 ]; then
    echo "Usage: $0 <iso-file> [distro-name] [version]"
    echo "Example: $0 /path/to/CentOS-7-x86_64-Minimal.iso centos 7"
    exit 1
fi

ISO_PATH="$1"
DISTRO="${2:-centos}"
VERSION="${3:-7}"

if [ ! -f "$ISO_PATH" ]; then
    echo "Error: ISO file not found: $ISO_PATH"
    exit 1
fi

log_info "Processing ISO: $ISO_PATH"
log_info "Distro: $DISTRO, Version: $VERSION"

# 创建挂载点
MOUNT_POINT=$(mktemp -d)
trap "umount $MOUNT_POINT 2>/dev/null; rm -rf $MOUNT_POINT" EXIT

# 挂载 ISO
log_info "Mounting ISO..."
mount -o loop "$ISO_PATH" "$MOUNT_POINT"

# 复制 ISO 内容到 HTTP 目录
TARGET_DIR="${ISO_DIR}/${DISTRO}${VERSION}"
log_info "Copying ISO files to $TARGET_DIR..."
mkdir -p "$TARGET_DIR"
cp -r "$MOUNT_POINT"/* "$TARGET_DIR/"

# 提取内核和 initrd 到 TFTP 目录
TFTP_TARGET="${TFTP_DIR}/${DISTRO}${VERSION}"
mkdir -p "$TFTP_TARGET"

log_info "Extracting kernel and initrd..."
if [ -f "$MOUNT_POINT/images/pxeboot/vmlinuz" ]; then
    cp "$MOUNT_POINT/images/pxeboot/vmlinuz" "$TFTP_TARGET/"
    cp "$MOUNT_POINT/images/pxeboot/initrd.img" "$TFTP_TARGET/"
elif [ -d "$MOUNT_POINT/casper" ]; then
    # Ubuntu/Debian
    cp "$MOUNT_POINT/casper/vmlinuz" "$TFTP_TARGET/"
    cp "$MOUNT_POINT/casper/initrd" "$TFTP_TARGET/initrd.img"
else
    echo "Warning: Cannot find kernel and initrd"
fi

log_info "ISO added successfully!"
log_info "HTTP URL: ${HTTP_URL_PREFIX}/${DISTRO}${VERSION}"
log_info "TFTP Path: ${TFTP_TARGET}"

# 卸载 ISO
umount "$MOUNT_POINT"
