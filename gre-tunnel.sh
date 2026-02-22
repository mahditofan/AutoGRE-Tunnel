#!/bin/bash

CONFIG_DIR="/etc/gre-tunnel"
CONFIG_FILE="$CONFIG_DIR/config"
SERVICE_FILE="/etc/systemd/system/gre-tunnel.service"

mkdir -p $CONFIG_DIR

create_tunnel() {

read -p "Local Public IP: " LOCAL
read -p "Remote Public IP: " REMOTE
read -p "Local Tunnel IP (30.0.0.1): " TLOCAL
read -p "Remote Tunnel IP (30.0.0.2): " TREMOTE
read -p "Tunnel Name (gre1): " TUN

echo "🔍 Detecting Best MTU..."

MTU=1472
while true; do
    ping -c1 -M do -s $MTU $REMOTE &>/dev/null
    if [ $? -ne 0 ]; then
        MTU=$((MTU-10))
    else
        break
    fi
done

BEST_MTU=$((MTU-24))

echo "Best MTU Found: $BEST_MTU"

echo "⚙ Configuring Kernel..."

sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null
sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null

echo "🛠 Creating GRE Tunnel..."

ip tunnel add $TUN mode gre local $LOCAL remote $REMOTE ttl 255
ip addr add $TLOCAL/30 dev $TUN
ip link set $TUN mtu $BEST_MTU
ip link set $TUN up

ip route add $TREMOTE dev $TUN

echo "🔧 Setting MSS Clamp..."

iptables -t mangle -A FORWARD -o $TUN -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $((BEST_MTU-40))

echo ""
echo "✅ Tunnel Created"
echo "MTU: $BEST_MTU"
echo ""
echo "Testing Tunnel..."
ping -c4 $TREMOTE

# ذخیره تنظیمات برای ریبوت
cat > $CONFIG_FILE <<EOF
LOCAL=$LOCAL
REMOTE=$REMOTE
TLOCAL=$TLOCAL
TREMOTE=$TREMOTE
TUN=$TUN
MTU=$BEST_MTU
EOF

create_service

echo ""
echo "✅ Saved & Service Enabled"
}

delete_tunnel() {

if [ ! -f $CONFIG_FILE ]; then
    echo "No tunnel found."
    return
fi

source $CONFIG_FILE

ip tunnel del $TUN 2>/dev/null
iptables -t mangle -D FORWARD -o $TUN -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $((MTU-40)) 2>/dev/null

systemctl stop gre-tunnel 2>/dev/null
systemctl disable gre-tunnel 2>/dev/null

rm -f $SERVICE_FILE
rm -f $CONFIG_FILE

echo "❌ Tunnel Deleted"
}

create_service() {

cat > $SERVICE_FILE <<EOF
[Unit]
Description=GRE Tunnel Auto Start
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '
source $CONFIG_FILE
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null
sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null
ip tunnel add \$TUN mode gre local \$LOCAL remote \$REMOTE ttl 255
ip addr add \$TLOCAL/30 dev \$TUN
ip link set \$TUN mtu \$MTU
ip link set \$TUN up
ip route add \$TREMOTE dev \$TUN
iptables -t mangle -A FORWARD -o \$TUN -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss \$((MTU-40))
'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gre-tunnel
}

menu() {

clear
echo "=============================="
echo "      GRE Tunnel Manager"
echo "=============================="
echo "1) Create Tunnel"
echo "2) Delete Tunnel"
echo "0) Exit"
echo ""
read -p "Select: " choice

case $choice in
1) create_tunnel ;;
2) delete_tunnel ;;
0) exit ;;
*) echo "Invalid Option" ;;
esac
}

menu
