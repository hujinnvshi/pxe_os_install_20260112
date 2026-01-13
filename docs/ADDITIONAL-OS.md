# 扩展操作系统支持文档

本文档说明如何在当前 PXE 系统中添加对其他操作系统的支持。

## 🐘 Kali Linux 支持

### ✅ 完全支持（已包含配置）

Kali Linux 基于 Debian，可以直接使用 Preseed 自动化安装。

#### 快速开始

**1. 下载 Kali Linux ISO**

```bash
wget https://cdimage.kali.org/kali-2023.x/kali-linux-2023.x-installer-amd64.iso
```

**2. 添加到 PXE 系统**

```bash
# Docker 部署
./scripts/add_iso.sh /path/to/kali-linux-*.iso kali 2023

# 或手动添加
mount -o loop kali-linux-*.iso /mnt
cp -r /mnt/* data/iso/kali2023/
cp /mnt/install.amd/vmlinuz data/tftpboot/kali2024/
cp /mnt/install.amd/initrd.gz data/tftpboot/kali2024/initrd.img
umount /mnt
```

**3. 添加启动菜单项**

编辑 `configs/default`：

```conf
LABEL kali-auto
    MENU LABEL ^K. Install Kali Linux (Automated)
    KERNEL kali2024/vmlinuz
    APPEND initrd=kali2024/initrd.img auto=true url=http://192.168.1.10:8080/ks/kali-preseed.cfg quiet hostname=kali
```

**4. 配置文件已准备**

配置文件位置：`configs/ks/kali-preseed.cfg`

默认设置：
- 用户名：`kali`
- 密码：`kali`（安装后需立即修改）
- 自动安装 SSH 服务器
- 包含基础安全工具

---

## 🪟 Windows 系统支持

### ⚠️ 技术可行但复杂度高

Windows PXE 安装需要额外的组件和配置。

### 原理

```
Windows PXE 安装流程：
┌─────────────────────────────────────────┐
│ 1. DHCP → 分配 IP                       │
│    next-server: PXE 服务器              │
│    filename: pxeboot.com               │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│ 2. TFTP → 下载 WinPE 文件               │
│    - pxeboot.com                        │
│    - boot.sdi                           │
│    - boot.wim (~300MB)                  │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│ 3. WinPE 启动 → Windows 预安装环境      │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│ 4. 加载 autounattend.xml                │
│    自动化配置                           │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│ 5. SMB 共享 → 下载 install.wim (~4GB)   │
│    安装 Windows                         │
└─────────────────────────────────────────┘
```

### 实现方案

#### 方案 A：使用 Windows Deployment Services (WDS)

**优点**：微软官方方案，稳定可靠
**缺点**：需要 Windows Server 环境

**步骤**：

1. **在 Windows Server 上安装 WDS**

```powershell
# 安装 WDS 角色
Install-WindowsFeature -Name WDS -IncludeManagementTools

# 配置 WDS
wdsutil /initialize-server /remInst:"D:\RemoteInstall"
wdsutil /start-server
```

2. **添加 Windows 启动镜像**

```powershell
# 导入 boot.wim
wdsutil /add-bootimage /imagepath:D:\sources\boot.wim /architecture:x64

# 导入 install.wim
wdsutil /add-image /imagefile:D:\sources\install.wim /architecture:x64
```

3. **配置 DHCP 选项**

```conf
# 在 configs/dhcpd.conf 中添加
class "PXEClient" {
    match if substring (option vendor-class-identifier, 0, 9) = "PXEClient";
}

option space PXE;
option PXE.mtftp-ip    code 1 = ip-address;
option PXE.mtftp-cport code 2 = unsigned integer 16;
option PXE.mtftp-sport code 3 = unsigned integer 16;
option PXE.mtftp-tmout code 4 = unsigned integer 8;
option PXE.mtftp-delay code 5 = unsigned integer 8;

option PXE.discovery-control code 6 = unsigned integer 8;
option PXE.discovery-mcast-addr code 7 = ip-address;

site-option-space "PXEClient";
option architecture-type code 93 = unsigned integer 16;
option last-entry code 255 = unsigned integer 8;

# 为 Windows 指定 WDS 服务器
subnet 192.168.1.0 netmask 255.255.255.0 {
    option routers 192.168.1.1;
    next-server 192.168.1.20;  # WDS 服务器 IP
    filename "boot\\x64\\pxeboot.com";
}
```

#### 方案 B：使用 FOG Project

**优点**：开源，跨平台，支持 Windows 和 Linux
**缺点**：需要额外部署

**FOG Project** 是一个专门用于克隆和部署的开源解决方案：

```bash
# 在 Linux 服务器上安装 FOG
git clone https://github.com/FOGProject/fogproject.git
cd fogproject/bin
sudo ./installfog.sh
```

FOG 提供的功能：
- ✅ Windows 镜像部署
- ✅ Linux 镜像部署
- ✅ 磁盘克隆
- ✅ Web 管理界面
- ✅ 任务调度

#### 方案 A：手动配置（在 Linux 上）

**需要组件**：

1. **准备 WinPE 引导文件**

```bash
# 需要 Windows 环境（或 Wine）
# 从 Windows ADK 提取文件：
# - boot.wim
# - boot.sdi
# - pxeboot.com

# 放到 TFTP 目录
cp boot.wim /tftpboot/windows/
cp boot.sdi /tftpboot/windows/
cp pxeboot.com /tftpboot/windows/
```

2. **配置 PXE 启动菜单**

```conf
LABEL windows10
    MENU LABEL ^W. Install Windows 10
    KERNEL windows/pxeboot.com
    APPEND -
```

3. **创建 autounattend.xml**

```xml
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <SetupUILanguage>
                <UILanguage>en-US</UILanguage>
            </SetupUILanguage>
            <InputLocale>en-US</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UserLocale>en-US</UserLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <UserData>
                <ProductKey>
                    <Key></Key>  # 如果有批量许可密钥
                    <WillShowUI>OnError</WillShowUI>
                </ProductKey>
                <AcceptEula>true</AcceptEula>
            </UserData>
        </component>
    </settings>

    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <ComputerName>*</ComputerName>
            <TimeZone>China Standard Time</TimeZone>
        </component>
    </settings>

    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>1</ProtectYourPC>
                <SkipMachineOOBE>true</SkipMachineOOBE>
                <SkipUserOOBE>true</SkipUserOOBE>
            </OOBE>
            <UserAccounts>
                <AdministratorPassword>
                    <Value>YourPassword123</Value>
                    <PlainText>true</PlainText>
                </AdministratorPassword>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Name>deploy</Name>
                        <DisplayName>Deploy User</DisplayName>
                        <Description>Deploy user account</Description>
                        <Group>Administrators</Group>
                        <Password>
                            <Value>DeployPassword123!</Value>
                            <PlainText>true</PlainText>
                        </Password>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
        </component>
    </settings>
</unattend>
```

4. **设置 SMB 共享**

```bash
# 安装 Samba
apt-get install samba

# 配置 /etc/samba/smb.conf
[windows-share]
    path = /data/iso/windows10
    browsable = yes
    read only = yes
    guest ok = yes

# 启动 Samba
systemctl enable smbd nmbd
systemctl start smbd nmbd
```

5. **复制 Windows 安装文件**

```bash
# 挂载 Windows ISO
mount -o loop Win10.iso /mnt

# 复制到 SMB 共享目录
cp -r /mnt/* /data/iso/windows10/

# 确保 install.wim 可访问
ls -lh /data/iso/windows10/sources/install.wim
```

### Windows PXE 的挑战

| 挑战 | 描述 | 解决方案 |
|------|------|----------|
| **文件大** | boot.wim ~300MB, install.wim ~4GB+ | 使用千兆网络，优化传输 |
| **需要 SMB** | Windows 安装需要 SMB 协议 | 配置 Samba 服务器 |
| **许可证** | 需要正版 Windows 许可 | 使用批量许可（MAK/KMS） |
| **配置复杂** | autounattend.xml 非常复杂 | 参考微软文档，使用工具生成 |
| **引导文件** | 需要 Windows 环境制作 WinPE | 使用 Windows ADK |
| **维护困难** | Windows 更新频繁，需要维护镜像 | 定期更新 install.wim |

---

## 📊 支持的操作系统对比

| 操作系统 | 支持程度 | 实现难度 | 配置文件 | 文件大小 |
|---------|---------|---------|---------|---------|
| **CentOS/RHEL 7/8/9** | ✅ 完全支持 | 简单 | Kickstart | ~50MB |
| **Rocky/AlmaLinux** | ✅ 完全支持 | 简单 | Kickstart | ~50MB |
| **Ubuntu 20.04/22.04** | ✅ 完全支持 | 简单 | Preseed | ~50MB |
| **Debian 10/11/12** | ✅ 完全支持 | 简单 | Preseed | ~50MB |
| **Kali Linux** | ✅ 完全支持 | 简单 | Preseed | ~50MB |
| **Windows 10/11** | ⚠️ 需要额外配置 | 复杂 | autounattend.xml | ~4GB+ |
| **Windows Server** | ⚠️ 需要额外配置 | 复杂 | autounattend.xml | ~4GB+ |
| **Fedora** | ✅ 完全支持 | 简单 | Kickstart | ~60MB |
| **openSUSE** | ✅ 完全支持 | 中等 | AutoYAST | ~60MB |

---

## 🎯 推荐方案

### 对于 Windows 系统

**不推荐在当前 PXE 系统中直接集成**，原因：

1. ✅ 复杂度太高，需要大量额外工作
2. ✅ 需要维护 Windows 镜像（~4GB）
3. ✅ 需要额外的 SMB 服务
4. ✅ 许可证问题
5. ✅ 使用频率可能不高

**推荐的替代方案**：

1. **使用虚拟机模板**（推荐）
   - 预先配置好 Windows 虚拟机
   - 使用 vCenter/ESXi 的克隆功能
   - 或使用 sysprep + 模板部署

2. **使用专业工具**
   - **FOG Project**（免费）
   - **Windows Deployment Services**（需要 Windows Server）
   - **SCCM**（企业级）

3. **手动安装**
   - 对于少量 Windows 机器，手动安装可能更高效

### 对于 Kali Linux

**强烈推荐集成**，因为：

1. ✅ 已经支持（配置文件已创建）
2. ✅ 实现简单，与 Ubuntu/Debian 相同
3. ✅ 适合渗透测试、安全培训场景
4. ✅ 文件小，安装快

---

## 📝 总结

### 当前项目状态

| 功能 | 状态 | 说明 |
|------|------|------|
| Linux 系统 | ✅ 完善 | CentOS/RHEL/Ubuntu/Debian/Kali 均支持 |
| Windows 系统 | ❌ 未集成 | 需要大量额外工作，不推荐 |
| 文档 | ✅ 完整 | 包含 Kali 配置和 Windows 说明 |

### 如果确实需要 Windows

**建议**：单独部署 WDS 或 FOG Project，专门用于 Windows 部署，保持 Linux PXE 系统的简洁性。

**架构建议**：

```
┌─────────────────────────────────────────┐
│           管理网络                       │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────────┐    ┌──────────────┐ │
│  │ Linux PXE    │    │ Windows WDS  │ │
│  │              │    │              │ │
│  │ - CentOS     │    │ - Win10/11   │ │
│  │ - Ubuntu     │    │ - WinServer  │ │
│  │ - Kali       │    │              │ │
│  └──────────────┘    └──────────────┘ │
│                                         │
└─────────────────────────────────────────┘
```

这样可以：
- ✅ 保持系统简洁
- ✅ 各司其职，互不干扰
- ✅ 便于维护
- ✅ 降低复杂度

---

## 🔗 参考资源

### Kali Linux
- [Kali Linux 官方文档](https://www.kali.org/docs/)
- [Debian Preseed 文档](https://www.debian.org/releases/stable/amd64/apbs02.html)

### Windows PXE
- [Windows ADK 下载](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install)
- [Windows Unattend 参考](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/index)
- [FOG Project](https://fogproject.org/)
