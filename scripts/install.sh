#!/bin/bash
# PXE 服务器一键安装脚本
# 支持 CentOS/RHEL 7/8/9

set -e

# ============================================
# 配置变量
# ============================================
PXE_SERVER_IP="${PXE_SERVER_IP:-192.168.1.10}"
NETWORK_INTERFACE="${NETWORK_INTERFACE:-eth0}"
DHCP_RANGE_START="${DHCP_RANGE_START:-192.168.1.100}"
DHCP_RANGE_END="${DHCP_RANGE_END:-192.168.1.200}"
GATEWAY="${GATEWAY:-192.168.1.1}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================
# 辅助函数
# ============================================
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        log_error "Cannot detect OS"
        exit 1
    fi

    log_info "Detected OS: $OS $OS_VERSION"

    if [[ ! "$OS" =~ ^(centos|rhel|rocky|almalinux)$ ]]; then
        log_warn "This script is designed for CentOS/RHEL/Rocky/AlmaLinux"
        log_warn "Other distributions may not work properly"
    fi
}

# 安装依赖包
install_packages() {
    log_info "Installing required packages..."

    if [[ "$OS" =~ ^(centos|rhel|rocky|almalinux)$ ]]; then
        yum install -y epel-release
        yum install -y dhcp tftp-server syslinux nginx xinetd vim wget curl
    elif [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        apt update
        apt install -y dnsmasq tftpd-hpa syslinux nginx-common curl
    else
        log_error "Unsupported OS: $OS"
        exit 1
    fi
}

# 创建目录结构
create_directories() {
    log_info "Creating directory structure..."

    mkdir -p /tftpboot
    mkdir -p /tftpboot/pxelinux.cfg
    mkdir -p /tftpboot/centos7
    mkdir -p /tftpboot/centos8
    mkdir -p /tftpboot/ubuntu2004
    mkdir -p /var/www/html/iso
    mkdir -p /var/www/html/ks

    chmod -R 755 /tftpboot
    chown -R nobody:nobody /tftpboot
}

# 复制引导文件
copy_boot_files() {
    log_info "Copying PXE boot files..."

    # 复制 syslinux 文件
    cp /usr/share/syslinux/pxelinux.0 /tftpboot/
    cp /usr/share/syslinux/ldlinux.c32 /tftpboot/
    cp /usr/share/syslinux/menu.c32 /tftpboot/
    cp /usr/share/syslinux/chain.c32 /tftpboot/
    cp /usr/share/syslinux/memdisk /tftpboot/
    cp /usr/share/syslinux/reboot.c32 /tftpboot/
    cp /usr/share/syslinux/poweroff.com /tftpboot/

    # 复制默认启动菜单
    cp "$(dirname "$0")/../configs/default" /tftpboot/pxelinux.cfg/default

    log_info "Boot files copied successfully"
}

# 配置 DHCP
configure_dhcp() {
    log_info "Configuring DHCP server..."

    cat > /etc/dhcp/dhcpd.conf << EOF
# DHCP Configuration for PXE Boot
option domain-name "pxe.local";
option domain-name-servers 8.8.8.8, 8.8.4.4;
default-lease-time 600;
max-lease-time 7200;
ddns-update-style none;
authoritative;

subnet ${PXE_SERVER_IP%.*}.0 netmask 255.255.255.0 {
    range ${DHCP_RANGE_START} ${DHCP_RANGE_END};
    option routers ${GATEWAY};
    option broadcast-address ${PXE_SERVER_IP%.*}.255;
    option subnet-mask 255.255.255.0;
    next-server ${PXE_SERVER_IP};
    filename "pxelinux.0";
}
EOF

    log_info "DHCP configuration completed"
    log_info "DHCP Range: ${DHCP_RANGE_START} - ${DHCP_RANGE_END}"
}

# 配置 TFTP
configure_tftp() {
    log_info "Configuring TFTP server..."

    # 配置 xinetd for tftp
    cat > /etc/xinetd.d/tftp << EOF
service tftp
{
    socket_type     = dgram
    protocol        = udp
    wait            = yes
    user            = root
    server          = /usr/sbin/in.tftpd
    server_args     = -s /tftpboot
    disable         = no
    per_source      = 11
    cps             = 100 2
    flags           = IPv4
}
EOF

    systemctl enable xinetd
    systemctl start xinetd

    log_info "TFTP configuration completed"
}

# 配置 HTTP
configure_http() {
    log_info "Configuring HTTP server..."

    # 复制 nginx 配置
    cp "$(dirname "$0")/../configs/nginx.conf" /etc/nginx/nginx.conf

    # 复制 Kickstart 配置
    cp "$(dirname "$0")/../configs/ks/"*.cfg /var/www/html/ks/ 2>/dev/null || true

    # 创建测试页面
    echo "PXE Installation Server" > /var/www/html/index.html

    systemctl enable nginx
    systemctl start nginx

    log_info "HTTP configuration completed"
}

# 配置防火墙
configure_firewall() {
    log_info "Configuring firewall..."

    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service=dhcp
        firewall-cmd --permanent --add-service=tftp
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-port=69/udp
        firewall-cmd --reload
    elif command -v ufw &> /dev/null; then
        ufw allow 67/udp
        ufw allow 69/udp
        ufw allow 80/tcp
    fi

    log_info "Firewall configuration completed"
}

# 配置 SELinux
configure_selinux() {
    log_info "Configuring SELinux..."

    if command -v setenforce &> /dev/null; then
        setenforce 0
        sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
        log_info "SELinux has been set to permissive mode"
    fi
}

# 启动服务
start_services() {
    log_info "Starting services..."

    systemctl enable dhcpd
    systemctl start dhcpd

    systemctl enable nginx
    systemctl start nginx

    log_info "All services started"
}

# 显示状态
show_status() {
    log_info "========================================"
    log_info "PXE Server Installation Completed!"
    log_info "========================================"
    echo ""
    log_info "Server Configuration:"
    log_info "  PXE Server IP: ${PXE_SERVER_IP}"
    log_info "  DHCP Range: ${DHCP_RANGE_START} - ${DHCP_RANGE_END}"
    log_info "  Gateway: ${GATEWAY}"
    echo ""
    log_info "Services Status:"
    systemctl status dhcpd --no-pager | grep Active
    systemctl status xinetd --no-pager | grep Active
    systemctl status nginx --no-pager | grep Active
    echo ""
    log_info "Next Steps:"
    log_info "1. Add ISO files to /var/www/html/iso/"
    log_info "2. Extract kernel and initrd to /tftpboot/"
    log_info "3. Configure kickstart files in /var/www/html/ks/"
    log_info "4. Create a virtual machine and boot from network"
    echo ""
}

# ============================================
# 主函数
# ============================================
main() {
    log_info "Starting PXE server installation..."

    check_root
    detect_os
    install_packages
    create_directories
    copy_boot_files
    configure_dhcp
    configure_tftp
    configure_http
    configure_firewall
    configure_selinux
    start_services
    show_status

    log_info "Installation completed successfully!"
}

# 运行主函数
main "$@"
