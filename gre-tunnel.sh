#!/bin/bash

# ======= تنظیمات تونل =======
LOCAL="YOUR_LOCAL_PUBLIC_IP"
REMOTE="YOUR_REMOTE_PUBLIC_IP"
TLOCAL="70.0.0.1"
TREMOTE="70.0.0.2"
TUN="gre1"

# مسیر اسکریپت برای crontab
SCRIPT_PATH=$(realpath "$0")
# اضافه کردن به crontab اگر هنوز نیست
(crontab -l 2>/dev/null | grep -F "$SCRIPT_PATH") || (crontab -l 2>/dev/null; echo "@reboot $SCRIPT_PATH") | crontab -

echo "🔍 Detecting Best MTU..."

# پیدا کردن بیشترین سایز بدون Fragment
MTU=1472
while true; do
    ping -c1 -M do -s $MTU $REMOTE &>/dev/null
    if [ $? -ne 0 ]; then
        MTU=$((MTU-10))
    else
        break
    fi
done

# کم کردن Overhead GRE (24 بایت)
BEST_MTU=$((MTU-24))

echo "Best MTU Found: $BEST_MTU"

echo "⚙ Configuring Kernel..."

sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null
sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null

echo "🛠 Creating GRE Tunnel..."

ip tunnel add $TUN mode gre local $LOCAL remote $REMOTE ttl 255 2>/dev/null
ip addr add $TLOCAL/30 dev $TUN 2>/dev/null
ip link set $TUN mtu $BEST_MTU 2>/dev/null
ip link set $TUN up 2>/dev/null

ip route add $TREMOTE dev $TUN 2>/dev/null

echo "🔧 Setting MSS Clamp..."

iptables -t mangle -A FORWARD -o $TUN -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $((BEST_MTU-40))

echo ""
echo "✅ Tunnel Created"
echo "MTU: $BEST_MTU"
echo ""
echo "Testing Tunnel..."
ping -c4 $TREMOTE
