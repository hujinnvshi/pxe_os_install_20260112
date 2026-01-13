# 系统初始化配置使用指南

## 📋 概述

本项目提供了一个**模块化、可配置**的系统初始化脚本，可以在安装后自动配置系统。

### 特点

- ✅ **模块化设计** - 每个功能模块可独立启用/禁用
- ✅ **环境区分** - 支持测试环境和生产环境不同配置
- ✅ **跨平台支持** - 适配 CentOS/RHEL/Ubuntu/Debian
- ✅ **安全性控制** - 提供宽松/安全/严格三种策略
- ✅ **完全可控** - 所有配置通过环境变量控制

---

## 🎯 快速开始

### 方式一：在 Kickstart 中使用（推荐）

编辑 Kickstart 配置文件（如 `centos7-ks.cfg`）：

```Kickstart
%post --log=/root/ks-post.log
#!/bin/bash

# 设置环境变量
export ENV_TYPE="testing"              # testing 或 production
export FIREWALL_POLICY="open"          # open/minimal/strict
export SSH_CONFIG="permissive"         # permissive/secure/strict
export SELINUX_MODE="disabled"         # disabled/permissive/enforcing

# 下载并执行配置脚本
curl -O http://192.168.1.10:8080/ks/common-post-install.sh
bash common-post-install.sh

%end
```

### 方式二：在 Preseed 中使用（Ubuntu/Debian）

编辑 Preseed 配置文件（如 `ubuntu2004-preseed.cfg`）：

```conf
# 在 late_command 中设置环境变量
d-i preseed/late_command string \
    in-target wget -O /root/common-post-install.sh http://192.168.1.10:8080/ks/common-post-install.sh; \
    in-target /bin/bash -c "export ENV_TYPE=testing FIREWALL_POLICY=open SSH_CONFIG=permissive SELINUX_MODE=disabled && bash /root/common-post-install.sh"
```

---

## ⚙️ 配置选项详解

### 环境变量配置

所有配置都通过环境变量控制：

| 环境变量 | 默认值 | 可选值 | 说明 |
|---------|-------|--------|------|
| `ENV_TYPE` | testing | testing / production | 环境类型 |
| `TIMEZONE` | Asia/Shanghai | 任何有效时区 | 系统时区 |
| `CONFIGURE_FIREWALL` | true | true / false | 是否配置防火墙 |
| `FIREWALL_POLICY` | open | open / minimal / strict | 防火墙策略 |
| `CONFIGURE_SELINUX` | true | true / false | 是否配置 SELinux |
| `SELINUX_MODE` | disabled | disabled / permissive / enforcing | SELinux 模式 |
| `CONFIGURE_SSH` | true | true / false | 是否配置 SSH |
| `SSH_CONFIG` | permissive | permissive / secure / strict | SSH 配置策略 |
| `CONFIGURE_TUNE` | true | true / false | 是否优化系统 |
| `CONFIGURE_NTP` | true | true / false | 是否配置时间同步 |
| `CONFIGURE_USERS` | true | true / false | 是否配置用户 |
| `CONFIGURE_REPOS` | true | true / false | 是否配置软件源 |
| `CONFIGURE_KERNEL` | true | true / false | 是否配置内核参数 |

---

## 📦 预设配置模板

### 模板 1：测试环境（开发/测试）

**特点**：关闭所有安全限制，方便开发调试

```bash
ENV_TYPE="testing"
FIREWALL_POLICY="open"              # 关闭防火墙
SELINUX_MODE="disabled"             # 关闭 SELinux
SSH_CONFIG="permissive"             # 允许 root 登录 + 密码认证
```

**适用场景**：
- 开发环境
- 测试环境
- 学习实验
- 内网隔离环境

**Kickstart 示例**：

```Kickstart
%post
export ENV_TYPE="testing"
export FIREWALL_POLICY="open"
export SELINUX_MODE="disabled"
export SSH_CONFIG="permissive"

curl -O http://192.168.1.10:8080/ks/common-post-install.sh
bash common-post-install.sh
%end
```

---

### 模板 2：最小安全配置（内网生产）

**特点**：基本安全措施，适合受信任的内网

```bash
ENV_TYPE="production"
FIREWALL_POLICY="minimal"           # 只开放 SSH
SELINUX_MODE="permissive"           # SELinux 宽松模式
SSH_CONFIG="secure"                 # 禁用 root，允许密码
```

**适用场景**：
- 内网生产环境
- 受信任的私有网络
- 需要一定安全的内部系统

**Kickstart 示例**：

```Kickstart
%post
export ENV_TYPE="production"
export FIREWALL_POLICY="minimal"
export SELINUX_MODE="permissive"
export SSH_CONFIG="secure"

curl -O http://192.168.1.10:8080/ks/common-post-install.sh
bash common-post-install.sh
%end
```

---

### 模板 3：严格安全配置（公网生产）

**特点**：最高安全级别，适合公网暴露的服务器

```bash
ENV_TYPE="production"
FIREWALL_POLICY="strict"            # 开放必要端口
SELINUX_MODE="enforcing"            # SELinux 强制模式
SSH_CONFIG="strict"                 # 禁用密码，只允许密钥
```

**适用场景**：
- 公网 Web 服务器
- 数据库服务器
- 对外服务系统
- 高安全要求环境

**Kickstart 示例**：

```Kickstart
%post
export ENV_TYPE="production"
export FIREWALL_POLICY="strict"
export SELINUX_MODE="enforcing"
export SSH_CONFIG="strict"

curl -O http://192.168.1.10:8080/ks/common-post-install.sh
bash common-post-install.sh
%end
```

---

## 🔧 各模块详细说明

### 1. 防火墙配置模块

**FIREWALL_POLICY 选项**：

| 策略 | 说明 | 开放端口 | 适用环境 |
|------|------|---------|---------|
| `open` | 完全关闭防火墙 | 所有端口 | 测试环境 |
| `minimal` | 最小策略 | SSH (22) | 内网生产 |
| `strict` | 严格策略 | SSH, HTTP, HTTPS, 8080 | 公网生产 |

**执行的操作**：

```bash
# CentOS/RHEL
- open:        systemctl stop/disable firewalld
- minimal:     firewall-cmd --add-service=ssh
- strict:      firewall-cmd --add-service={ssh,http,https} --add-port=8080/tcp

# Ubuntu/Debian
- open:        ufw disable
- minimal:     ufw allow 22/tcp
- strict:      ufw allow 22/tcp,80/tcp,443/tcp,8080/tcp
```

---

### 2. SELinux 配置模块

**SELINUX_MODE 选项**：

| 模式 | 说明 | 安全性 | 适用环境 |
|------|------|--------|---------|
| `disabled` | 完全禁用 | 低 | 测试环境 |
| `permissive` | 宽松模式（只警告） | 中 | 调试阶段 |
| `enforcing` | 强制模式 | 高 | 生产环境 |

**执行的操作**：

```bash
# disabled
setenforce 0
sed -i 's/SELINUX=.*$/SELINUX=disabled/' /etc/selinux/config

# permissive
setenforce 0
sed -i 's/SELINUX=.*$/SELINUX=permissive/' /etc/selinux/config

# enforcing
setenforce 1
sed -i 's/SELINUX=.*$/SELINUX=enforcing/' /etc/selinux/config
```

---

### 3. SSH 配置模块

**SSH_CONFIG 选项**：

| 策略 | Root 登录 | 密码认证 | 说明 |
|------|----------|---------|------|
| `permissive` | ✅ 允许 | ✅ 允许 | 测试环境 |
| `secure` | ❌ 禁止 | ✅ 允许 | 一般生产 |
| `strict` | ❌ 禁止 | ❌ 禁止 | 高安全要求 |

**执行的操作**：

```bash
# permissive
PermitRootLogin yes
PasswordAuthentication yes

# secure
PermitRootLogin no
PasswordAuthentication yes

# strict
PermitRootLogin no
PasswordAuthentication no
```

**注意**：`strict` 模式需要预先配置 SSH 公钥。

---

### 4. 系统优化模块

**自动应用的优化**：

```bash
# 文件描述符限制
* soft nofile 65535
* hard nofile 65535

# 网络优化
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 65535

# Swap 使用策略
vm.swappiness = 10
```

---

### 5. 时间同步模块

**自动配置**：

- CentOS/RHEL: 启用 `chronyd` 或 `ntpd`
- Ubuntu/Debian: 启用 `systemd-timesyncd`
- 设置时区为 `Asia/Shanghai`（可自定义）

---

### 6. 用户配置模块

**自动创建的用户**：

```bash
用户名: deploy
密码: Deploy123!
权限: sudo NOPASSWD
```

⚠️ **生产环境请立即修改默认密码！**

---

## 📝 实际使用案例

### 案例 1：Web 服务器集群

**需求**：
- 部署 10 台 Web 服务器
- 需要开放 HTTP/HTTPS
- 禁用 root 登录
- 允许密码认证（过渡期）

**配置**：

```Kickstart
%post --log=/root/ks-post.log
#!/bin/bash

export ENV_TYPE="production"
export FIREWALL_POLICY="strict"        # 开放 HTTP/HTTPS
export SELINUX_MODE="enforcing"       # 启用 SELinux
export SSH_CONFIG="secure"            # 禁用 root，允许密码

curl -O http://192.168.1.10:8080/ks/common-post-install.sh
bash common-post-install.sh

# 额外的 Web 服务器配置
yum install -y nginx
systemctl enable nginx
systemctl start nginx

%end
```

---

### 案例 2：数据库服务器

**需求**：
- 部署 3 台数据库服务器
- 只开放 SSH（从管理机访问）
- 最高安全级别
- 优化数据库性能

**配置**：

```Kickstart
%post --log=/root/ks-post.log
#!/bin/bash

export ENV_TYPE="production"
export FIREWALL_POLICY="minimal"       # 只开放 SSH
export SELINUX_MODE="enforcing"       # SELinux 强制
export SSH_CONFIG="strict"            # 只允许密钥认证

curl -O http://192.168.1.10:8080/ks/common-post-install.sh
bash common-post-install.sh

# 数据库优化
echo "vm.swappiness = 1" >> /etc/sysctl.d/99-custom.conf
sysctl -p /etc/sysctl.d/99-custom.conf

%end
```

---

### 案例 3：开发测试环境

**需求**：
- 快速部署测试服务器
- 无安全限制
- 方便调试

**配置**：

```Kickstart
%post
export ENV_TYPE="testing"
export FIREWALL_POLICY="open"         # 关闭防火墙
export SELINUX_MODE="disabled"        # 关闭 SELinux
export SSH_CONFIG="permissive"        # 允许 root + 密码

curl -O http://192.168.1.10:8080/ks/common-post-install.sh
bash common-post-install.sh

# 安装开发工具
yum install -y vim git htop tmux
%end
```

---

## 🎛️ 高级用法

### 自定义配置文件

创建自定义配置文件：

```bash
# /root/custom-config.sh
export ENV_TYPE="production"
export FIREWALL_POLICY="minimal"
export SELINUX_MODE="enforcing"
export SSH_CONFIG="secure"

# 执行主脚本
bash /root/common-post-install.sh
```

### 分阶段执行

在 Kickstart 中分阶段执行：

```Kickstart
%post --log=/root/ks-post-stage1.log
# 阶段 1：基础配置
export CONFIGURE_FIREWALL="true"
export CONFIGURE_SELINUX="true"
curl -O http://192.168.1.10:8080/ks/common-post-install.sh
bash common-post-install.sh
%end

%post --log=/root/ks-post-stage2.log
# 阶段 2：应用配置
yum install -y nginx mysql
systemctl enable nginx mysql
%end
```

### 结合其他脚本

```Kickstart
%post
# 先执行通用配置
curl -O http://192.168.1.10:8080/ks/common-post-install.sh
bash common-post-install.sh

# 再执行自定义脚本
curl -O http://192.168.1.10:8080/ks/custom-app-setup.sh
bash custom-app-setup.sh
%end
```

---

## ⚠️ 安全注意事项

### 生产环境必做

1. **修改默认密码**
   ```bash
   passwd deploy
   ```

2. **配置 SSH 密钥**
   ```bash
   ssh-copy-id -i ~/.ssh/id_rsa.pub user@server
   ```

3. **审查防火墙规则**
   ```bash
   firewall-cmd --list-all    # CentOS
   ufw status                 # Ubuntu
   ```

4. **检查 SELinux 状态**
   ```bash
   getenforce
   ```

5. **查看安装日志**
   ```bash
   cat /var/log/post-install.log
   ```

---

## 🔍 故障排查

### 脚本执行失败

**检查日志**：
```bash
cat /var/log/post-install.log
```

**手动测试**：
```bash
# 下载脚本
curl -O http://192.168.1.10:8080/ks/common-post-install.sh

# 设置环境变量测试
export ENV_TYPE="testing"
bash -x common-post-install.sh  # -x 显示详细执行过程
```

### 特定模块失败

**只执行某个模块**：
```bash
# 只配置防火墙
export CONFIGURE_FIREWALL="true"
export CONFIGURE_SELINUX="false"
export CONFIGURE_SSH="false"
# ... 其他模块设置为 false
bash common-post-install.sh
```

---

## 📚 参考资源

- [Kickstart 语法](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_installation/kickstart-commands-and-options-reference)
- [Preseed 语法](https://www.debian.org/releases/stable/amd64/apbs02.html)
- [SELinux 配置](https://selinuxproject.org/page/Main_Page)
- [Firewalld 指南](https://firewalld.org/documentation/)
