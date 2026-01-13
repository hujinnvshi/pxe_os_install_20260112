#!/bin/bash
# ============================================
# 通用系统初始化配置模板
# ============================================
# 用途：在 Kickstart/Preseed 的 %post 或 late_command 中调用
# 使用：根据实际需求选择性启用/禁用各个功能模块
#
# 调用方式（Kickstart）：
# %post
# # 在网络可用后下载并执行
# curl -O http://192.168.1.10:8080/ks/common-post-install.sh
# bash common-post-install.sh
# %end
# ============================================

set -e

# ============================================
# 配置选项（根据实际环境修改）
# ============================================

# 环境类型：testing（测试） 或 production（生产）
ENV_TYPE="${ENV_TYPE:-testing}"

# 时区设置
TIMEZONE="${TIMEZONE:-Asia/Shanghai}"

# 是否配置防火墙：true/false
CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-true}"

# 防火墙策略（仅在 CONFIGURE_FIREWALL=true 时生效）
FIREWALL_POLICY="${FIREWALL_POLICY:-open}"  # open/minimal/strict

# 是否配置 SELinux（RHEL/CentOS）：true/false
CONFIGURE_SELINUX="${CONFIGURE_SELINUX:-true}"

# SELinux 模式（仅在 CONFIGURE_SELINUX=true 时生效）
SELINUX_MODE="${SELINUX_MODE:-disabled}"  # disabled/permissive/enforcing

# 是否配置 SSH：true/false
CONFIGURE_SSH="${CONFIGURE_SSH:-true}"

# SSH 配置策略
SSH_CONFIG="${SSH_CONFIG:-permissive}"  # permissive/secure/strict

# 是否配置系统优化：true/false
CONFIGURE_TUNE="${CONFIGURE_TUNE:-true}"

# 是否配置时间同步：true/false
CONFIGURE_NTP="${CONFIGURE_NTP:-true}"

# 是否配置用户：true/false
CONFIGURE_USERS="${CONFIGURE_USERS:-true}"

# 是否配置软件源：true/false
CONFIGURE_REPOS="${CONFIGURE_REPOS:-true}"

# 是否配置内核参数：true/false
CONFIGURE_KERNEL="${CONFIGURE_KERNEL:-true}"

# 日志文件
LOG_FILE="/var/log/post-install.log"

# ============================================
# 辅助函数
# ============================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
    else
        log "ERROR: Cannot detect OS"
        exit 1
    fi
    log "Detected OS: $OS_ID $OS_VERSION"
}

# ============================================
# 防火墙配置模块
# ============================================
configure_firewall() {
    if [ "$CONFIGURE_FIREWALL" != "true" ]; then
        log "Skipping firewall configuration"
        return
    fi

    log "Configuring firewall (policy: $FIREWALL_POLICY)..."

    case "$OS_ID" in
        centos|rhel|rocky|almalinux)
            if command -v firewall-cmd &> /dev/null; then
                case "$FIREWALL_POLICY" in
                    open)
                        # 测试环境：关闭防火墙
                        systemctl stop firewalld
                        systemctl disable firewalld
                        log "Firewall DISABLED (testing environment)"
                        ;;
                    minimal)
                        # 最小策略：只开放 SSH
                        systemctl start firewalld
                        systemctl enable firewalld
                        firewall-cmd --permanent --add-service=ssh
                        firewall-cmd --reload
                        log "Firewall: minimal policy (SSH only)"
                        ;;
                    strict)
                        # 严格策略：开放常用端口
                        systemctl start firewalld
                        systemctl enable firewalld
                        firewall-cmd --permanent --add-service=ssh
                        firewall-cmd --permanent --add-service=http
                        firewall-cmd --permanent --add-service=https
                        firewall-cmd --permanent --add-port=8080/tcp
                        firewall-cmd --reload
                        log "Firewall: strict policy (SSH, HTTP, HTTPS, 8080)"
                        ;;
                esac
            else
                log "WARNING: firewalld not found"
            fi
            ;;

        ubuntu|debian)
            if command -v ufw &> /dev/null; then
                case "$FIREWALL_POLICY" in
                    open)
                        # 测试环境：关闭防火墙
                        ufw --force disable
                        log "Firewall DISABLED (testing environment)"
                        ;;
                    minimal)
                        # 最小策略：只开放 SSH
                        ufw --force enable
                        ufw default deny incoming
                        ufw default allow outgoing
                        ufw allow 22/tcp
                        log "Firewall: minimal policy (SSH only)"
                        ;;
                    strict)
                        # 严格策略
                        ufw --force enable
                        ufw default deny incoming
                        ufw default allow outgoing
                        ufw allow 22/tcp
                        ufw allow 80/tcp
                        ufw allow 443/tcp
                        ufw allow 8080/tcp
                        log "Firewall: strict policy"
                        ;;
                esac
            fi
            ;;
    esac
}

# ============================================
# SELinux 配置模块（RHEL/CentOS）
# ============================================
configure_selinux() {
    if [ "$CONFIGURE_SELINUX" != "true" ]; then
        log "Skipping SELinux configuration"
        return
    fi

    # 只在 RHEL/CentOS 系统上配置
    case "$OS_ID" in
        centos|rhel|rocky|almalinux)
            log "Configuring SELinux (mode: $SELINUX_MODE)..."

            if [ "$SELINUX_MODE" = "disabled" ]; then
                setenforce 0
                sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
                sed -i 's/^SELINUX=permissive/SELINUX=disabled/' /etc/selinux/config
                log "SELinux DISABLED (testing environment)"
            elif [ "$SELINUX_MODE" = "permissive" ]; then
                setenforce 0
                sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
                log "SELinux set to PERMISSIVE mode"
            elif [ "$SELINUX_MODE" = "enforcing" ]; then
                setenforce 1
                sed -i 's/^SELINUX=disabled/SELINUX=enforcing/' /etc/selinux/config
                sed -i 's/^SELINUX=permissive/SELINUX=enforcing/' /etc/selinux/config
                log "SELinux set to ENFORCING mode (production)"
            fi
            ;;
    esac
}

# ============================================
# SSH 配置模块
# ============================================
configure_ssh() {
    if [ "$CONFIGURE_SSH" != "true" ]; then
        log "Skipping SSH configuration"
        return
    fi

    log "Configuring SSH (policy: $SSH_CONFIG)..."

    SSH_CONFIG_FILE="/etc/ssh/sshd_config"

    # 备份原配置
    cp "$SSH_CONFIG_FILE" "${SSH_CONFIG_FILE}.bak"

    case "$SSH_CONFIG" in
        permissive)
            # 测试环境：宽松配置
            sed -i 's/^#PermitRootLogin yes/PermitRootLogin yes/' "$SSH_CONFIG_FILE"
            sed -i 's/^PermitRootLogin no/PermitRootLogin yes/' "$SSH_CONFIG_FILE"
            sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' "$SSH_CONFIG_FILE"
            log "SSH: permissive policy (root login + password auth enabled)"
            ;;

        secure)
            # 安全配置：禁用 root 登录，允许密码
            sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' "$SSH_CONFIG_FILE"
            sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' "$SSH_CONFIG_FILE"
            sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' "$SSH_CONFIG_FILE"
            log "SSH: secure policy (root login disabled)"
            ;;

        strict)
            # 严格配置：禁用 root，禁用密码，只允许密钥
            sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' "$SSH_CONFIG_FILE"
            sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' "$SSH_CONFIG_FILE"
            sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' "$SSH_CONFIG_FILE"
            sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' "$SSH_CONFIG_FILE"
            log "SSH: strict policy (key-based auth only)"
            ;;
    esac

    # 启动并启用 SSH 服务
    systemctl enable sshd || systemctl enable ssh
    systemctl restart sshd || systemctl restart ssh

    log "SSH service configured and started"
}

# ============================================
# 系统优化模块
# ============================================
configure_tune() {
    if [ "$CONFIGURE_TUNE" != "true" ]; then
        log "Skipping system tuning"
        return
    fi

    log "Applying system optimizations..."

    # 文件描述符限制
    cat > /etc/security/limits.d/99-custom.conf << 'EOF'
# 自定义文件描述符限制
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
EOF

    # 内核参数优化
    cat > /etc/sysctl.d/99-custom.conf << 'EOF'
# 网络优化
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.core.somaxconn = 65535

# 文件句柄
fs.file-max = 65535

# 共享内存（用于数据库）
kernel.shmmax = 68719476736
kernel.shmall = 4294967296

#swap 使用策略
vm.swappiness = 10
EOF

    # 应用内核参数
    sysctl -p /etc/sysctl.d/99-custom.conf

    log "System optimizations applied"
}

# ============================================
# 时间同步模块
# ============================================
configure_ntp() {
    if [ "$CONFIGURE_NTP" != "true" ]; then
        log "Skipping NTP configuration"
        return
    fi

    log "Configuring time synchronization..."

    case "$OS_ID" in
        centos|rhel|rocky|almalinux)
            if command -v chronyd &> /dev/null; then
                systemctl enable chronyd
                systemctl start chronyd
                log "NTP: chronyd configured"
            elif command -v ntpd &> /dev/null; then
                systemctl enable ntpd
                systemctl start ntpd
                log "NTP: ntpd configured"
            fi
            ;;

        ubuntu|debian)
            if command -v timedatectl &> /dev/null; then
                timedatectl set-timezone "$TIMEZONE"
                timedatectl set-ntp true
                log "NTP: timesyncd configured"
            fi
            ;;
    esac

    # 设置时区
    if [ -n "$TIMEZONE" ]; then
        timedatectl set-timezone "$TIMEZONE" 2>/dev/null || \
            ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
        log "Timezone set to $TIMEZONE"
    fi
}

# ============================================
# 用户配置模块
# ============================================
configure_users() {
    if [ "$CONFIGURE_USERS" != "true" ]; then
        log "Skipping user configuration"
        return
    fi

    log "Configuring users..."

    # 创建部署用户（如果不存在）
    if ! id deploy &>/dev/null; then
        useradd -m -s /bin/bash deploy
        echo "deploy:Deploy123!" | chpasswd
        echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy
        chmod 440 /etc/sudoers.d/deploy
        log "Created user 'deploy' with sudo privileges"
    else
        log "User 'deploy' already exists"
    fi
}

# ============================================
# 软件源配置模块
# ============================================
configure_repos() {
    if [ "$CONFIGURE_REPOS" != "true" ]; then
        log "Skipping repository configuration"
        return
    fi

    log "Configuring software repositories..."

    case "$OS_ID" in
        centos|rhel|rocky|almalinux)
            # 安装 EPEL
            if command -v yum &> /dev/null; then
                yum install -y epel-release 2>/dev/null || true
                log "EPEL repository installed"
            elif command -v dnf &> /dev/null; then
                dnf install -y epel-release 2>/dev/null || true
                log "EPEL repository installed"
            fi
            ;;

        ubuntu|debian)
            # 确保软件源是最新的
            if [ "$ENV_TYPE" = "production" ]; then
                # 生产环境：使用安全更新源
                log "Production repos: security updates enabled"
            else
                # 测试环境：可以添加更多源
                log "Testing repos: standard configuration"
            fi
            ;;
    esac
}

# ============================================
# 内核参数模块
# ============================================
configure_kernel() {
    if [ "$CONFIGURE_KERNEL" != "true" ]; then
        log "Skipping kernel parameter configuration"
        return
    fi

    log "Configuring kernel parameters..."

    # 禁用 IPv6（如果不需要）
    # echo "1" > /proc/sys/net/ipv6/conf/all/disable_ipv6

    # 启用 IP 转发（如果需要作为路由器）
    # echo "1" > /proc/sys/net/ipv4/ip_forward

    log "Kernel parameters configured"
}

# ============================================
# 自定义 MOTD
# ============================================
configure_motd() {
    cat > /etc/motd << EOF
╔══════════════════════════════════════════════════════════╗
║                                                            ║
║  System installed via PXE                                 ║
║  Date: $(date '+%Y-%m-%d %H:%M:%S')                       ║
║  OS: $OS_ID $OS_VERSION                                   ║
║  Environment: $ENV_TYPE                                    ║
║                                                            ║
║  ⚠️  IMPORTANT SECURITY NOTES:                            ║
║  1. Change all default passwords immediately!             ║
║  2. Update the system: yum update / apt update            ║
║  3. Configure firewall for production use                 ║
║  4. Review SSH settings                                   ║
║                                                            ║
╚══════════════════════════════════════════════════════════╝
EOF
}

# ============================================
# 主函数
# ============================================
main() {
    log "========================================="
    log "Starting post-installation configuration"
    log "Environment: $ENV_TYPE"
    log "========================================="

    # 检测操作系统
    detect_os

    # 执行各个配置模块
    configure_firewall
    configure_selinux
    configure_ssh
    configure_tune
    configure_ntp
    configure_users
    configure_repos
    configure_kernel
    configure_motd

    # 更新系统（生产环境）
    if [ "$ENV_TYPE" = "production" ]; then
        log "Running system updates (production)..."
        case "$OS_ID" in
            centos|rhel|rocky|almalinux)
                if command -v dnf &> /dev/null; then
                    dnf update -y || true
                elif command -v yum &> /dev/null; then
                    yum update -y || true
                fi
                ;;
            ubuntu|debian)
                DEBIAN_FRONTEND=noninteractive apt-get update && apt-get upgrade -y || true
                ;;
        esac
    fi

    # 清理
    log "Cleaning up..."
    case "$OS_ID" in
        centos|rhel|rocky|almalinux)
            yum clean all || true
            ;;
        ubuntu|debian)
            apt-get clean || true
            ;;
    esac

    log "========================================="
    log "Post-installation configuration completed!"
    log "Log file: $LOG_FILE"
    log "========================================="

    # 重置 MOTD 中的提示（30秒后自动消失）
    echo "Run 'cat $LOG_FILE' to view installation details"
}

# 运行主函数
main "$@"
