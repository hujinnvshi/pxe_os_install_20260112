#!/bin/bash
# PXE 系统测试脚本
# 用于测试 PXE 服务的各个组件是否正常工作

set -e

# ============================================
# 配置
# ============================================
PXE_SERVER_IP="${PXE_SERVER_IP:-192.168.1.10}"
HTTP_PORT="${HTTP_PORT:-8080}"
TFTP_PORT="${TFTP_PORT:-69}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 测试结果统计
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# ============================================
# 辅助函数
# ============================================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
}

log_fail() {
    echo -e "${RED}[✗]${NC} $1"
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# ============================================
# 测试函数
# ============================================

# 测试命令是否存在
test_command() {
    local cmd=$1
    if command -v $cmd &> /dev/null; then
        log_success "$cmd is installed"
        return 0
    else
        log_fail "$cmd is not installed"
        return 1
    fi
}

# 测试 DHCP 服务
test_dhcp() {
    print_header "Testing DHCP Service"

    # 检查 DHCP 进程
    if pgrep -x "dhcpd" > /dev/null; then
        log_success "DHCP daemon is running"
    else
        log_fail "DHCP daemon is not running"
    fi

    # 检查 DHCP 端口
    if netstat -ulp | grep -q ":67"; then
        log_success "DHCP is listening on port 67"
    else
        log_fail "DHCP is not listening on port 67"
    fi

    # 检查配置文件语法
    if [ -f "/etc/dhcp/dhcpd.conf" ]; then
        if dhcpd -t -cf /etc/dhcp/dhcpd.conf 2>&1 | grep -q "OK"; then
            log_success "DHCP configuration is valid"
        else
            log_fail "DHCP configuration has errors"
        fi
    else
        log_warn "DHCP config file not found (may be Docker deployment)"
    fi
}

# 测试 TFTP 服务
test_tftp() {
    print_header "Testing TFTP Service"

    # 检查 TFTP 进程
    if pgrep -x "in.tftpd" > /dev/null || pgrep -x "tftpd" > /dev/null; then
        log_success "TFTP daemon is running"
    else
        log_warn "TFTP daemon may not be running (check Docker)"
    fi

    # 检查 TFTP 端口
    if netstat -ulp | grep -q ":$TFTP_PORT"; then
        log_success "TFTP is listening on port $TFTP_PORT"
    else
        log_fail "TFTP is not listening on port $TFTP_PORT"
    fi

    # 测试 TFTP 连接
    if command -v tftp &> /dev/null; then
        TEMP_FILE=$(mktemp)
        if tftp $PXE_SERVER_IP -c get pxelinux.0 $TEMP_FILE 2>/dev/null; then
            if [ -s $TEMP_FILE ]; then
                log_success "TFTP can download pxelinux.0"
            else
                log_fail "TFTP downloaded empty file"
            fi
            rm -f $TEMP_FILE
        else
            log_fail "TFTP cannot download pxelinux.0"
        fi
    else
        log_warn "TFTP client not installed, skipping download test"
    fi
}

# 测试 HTTP 服务
test_http() {
    print_header "Testing HTTP Service"

    # 检查 Nginx 进程
    if pgrep -x "nginx" > /dev/null || docker ps | grep -q "pxe-http"; then
        log_success "HTTP server is running"
    else
        log_fail "HTTP server is not running"
    fi

    # 测试 HTTP 连接
    if curl -s -o /dev/null -w "%{http_code}" http://$PXE_SERVER_IP:$HTTP_PORT/health | grep -q "200"; then
        log_success "HTTP health check endpoint is accessible"
    else
        log_fail "HTTP health check endpoint failed"
    fi

    # 测试 Kickstart 文件访问
    if curl -s -f http://$PXE_SERVER_IP:$HTTP_PORT/ks/centos7-ks.cfg > /dev/null; then
        log_success "Kickstart files are accessible"
    else
        log_fail "Cannot access Kickstart files"
    fi

    # 测试 ISO 目录访问
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$PXE_SERVER_IP:$HTTP_PORT/iso/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        log_success "ISO directory is accessible"
    else
        log_warn "ISO directory returned HTTP code $HTTP_CODE"
    fi
}

# 测试文件结构
test_file_structure() {
    print_header "Testing File Structure"

    # 检查 TFTP 文件
    local tftp_paths=("/tftpboot/pxelinux.0" "data/tftpboot/pxelinux.0")
    local found=0
    for path in "${tftp_paths[@]}"; do
        if [ -f "$path" ]; then
            log_success "Found pxelinux.0 at $path"
            ((found++))
            break
        fi
    done
    if [ $found -eq 0 ]; then
        log_fail "pxelinux.0 not found"
    fi

    # 检查启动菜单
    local menu_paths=("/tftpboot/pxelinux.cfg/default" "data/tftpboot/pxelinux.cfg/default" "configs/default")
    found=0
    for path in "${menu_paths[@]}"; do
        if [ -f "$path" ]; then
            log_success "Found PXE menu at $path"
            ((found++))
            break
        fi
    done
    if [ $found -eq 0 ]; then
        log_fail "PXE menu not found"
    fi

    # 检查 Kickstart 配置
    local ks_count=$(find configs/ks -name "*.cfg" 2>/dev/null | wc -l)
    if [ $ks_count -gt 0 ]; then
        log_success "Found $ks_count Kickstart/Preseed config files"
    else
        log_fail "No Kickstart config files found"
    fi
}

# 测试网络连接
test_network() {
    print_header "Testing Network Connectivity"

    # 测试 ICMP
    if ping -c 1 -W 2 $PXE_SERVER_IP > /dev/null 2>&1; then
        log_success "Can ping PXE server ($PXE_SERVER_IP)"
    else
        log_fail "Cannot ping PXE server ($PXE_SERVER_IP)"
    fi

    # 测试 DNS
    if [ -n "$(host -W 2 $PXE_SERVER_IP 2>/dev/null)" ]; then
        log_success "DNS resolution works"
    else
        log_warn "DNS resolution may have issues"
    fi
}

# 测试配置文件
test_configs() {
    print_header "Testing Configuration Files"

    # 检查 DHCP 配置
    if [ -f "configs/dhcpd.conf" ]; then
        log_success "DHCP config exists"
    else
        log_fail "DHCP config missing"
    fi

    # 检查 Nginx 配置
    if [ -f "configs/nginx.conf" ]; then
        log_success "Nginx config exists"
        if command -v nginx &> /dev/null; then
            if nginx -t -c configs/nginx.conf 2>&1 | grep -q "successful"; then
                log_success "Nginx config is valid"
            else
                log_fail "Nginx config has errors"
            fi
        fi
    else
        log_fail "Nginx config missing"
    fi

    # 检查 PXE 菜单
    if [ -f "configs/default" ]; then
        log_success "PXE menu config exists"
        if grep -q "KERNEL" configs/default && grep -q "APPEND" configs/default; then
            log_success "PXE menu has valid entries"
        else
            log_fail "PXE menu may be invalid"
        fi
    else
        log_fail "PXE menu config missing"
    fi
}

# 测试 Docker 部署
test_docker() {
    print_header "Testing Docker Deployment"

    if ! command -v docker &> /dev/null; then
        log_warn "Docker not installed, skipping Docker tests"
        return
    fi

    # 检查 Docker 是否运行
    if docker ps > /dev/null 2>&1; then
        log_success "Docker daemon is running"
    else
        log_fail "Docker daemon is not running"
        return
    fi

    # 检查 PXE 容器
    local containers=("pxe-dhcp" "pxe-tftp" "pxe-http")
    for container in "${containers[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            log_success "Container $container is running"
        else
            log_warn "Container $container is not running"
        fi
    done

    # 检查数据卷
    if [ -d "data/tftpboot" ]; then
        log_success "Docker data directory exists"
    else
        log_warn "Docker data directory missing (run prepare_docker.sh)"
    fi
}

# 生成测试报告
generate_report() {
    print_header "Test Report"
    echo ""
    echo "Total Tests: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed. Please check the output above.${NC}"
        return 1
    fi
}

# ============================================
# 主函数
# ============================================
main() {
    echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   PXE System Test Suite              ║${NC}"
    echo -e "${BLUE}║   PXE 系统测试工具                    ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
    echo ""
    echo "PXE Server: $PXE_SERVER_IP"
    echo "HTTP Port: $HTTP_PORT"
    echo "TFTP Port: $TFTP_PORT"
    echo ""

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --server-ip)
                PXE_SERVER_IP="$2"
                shift 2
                ;;
            --http-port)
                HTTP_PORT="$2"
                shift 2
                ;;
            --test)
                TEST_TYPE="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --server-ip IP    PXE server IP address (default: 192.168.1.10)"
                echo "  --http-port PORT  HTTP port (default: 8080)"
                echo "  --test TYPE       Run specific test (dhcp|tftp|http|all)"
                echo "  -h, --help        Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # 运行测试
    if [ -z "$TEST_TYPE" ] || [ "$TEST_TYPE" = "all" ]; then
        test_network
        test_configs
        test_dhcp
        test_tftp
        test_http
        test_file_structure
        test_docker
    else
        case $TEST_TYPE in
            dhcp) test_dhcp ;;
            tftp) test_tftp ;;
            http) test_http ;;
            network) test_network ;;
            configs) test_configs ;;
            docker) test_docker ;;
            *)
                echo "Unknown test type: $TEST_TYPE"
                exit 1
                ;;
        esac
    fi

    # 生成报告
    generate_report
}

# 运行主函数
main "$@"
