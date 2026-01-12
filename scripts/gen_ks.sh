#!/bin/bash
# 生成加密的 root 密码（用于 Kickstart 配置）

if [ -z "$1" ]; then
    echo "Usage: $0 <password>"
    echo "Example: $0 MyPassword123"
    exit 1
fi

PASSWORD="$1"

# 生成 MD5 加密密码（适用于 Kickstart）
ENCRYPTED=$(openssl passwd -1 "$PASSWORD")

echo "Encrypted password for Kickstart:"
echo "$ENCRYPTED"
echo ""
echo "Add this to your kickstart file:"
echo "rootpw --iscrypted $ENCRYPTED"
