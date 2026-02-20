#!/bin/bash

CONFIG_DIR="/etc/gre-manager"
CONFIG_FILE="$CONFIG_DIR/config"
SERVICE_FILE="/etc/systemd/system/gre-tunnel.service"

mkdir -p $CONFIG_DIR

create_tunnel() {

    read -p "Local Public IP: " LOCAL
    read -p "Remote Public IP: " REMOTE
    read -p "Local Tunnel IP (70.0.0.1): " TLOCAL
    read -p "Remote Tunnel IP (70.0.0.2): " TREMOTE
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

    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null
    sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null

    ip tunnel add $TUN mode gre local $LOCAL remote $REMOTE ttl 255
    ip addr add $TLOCAL/30 dev $TUN
    ip link set $TUN mtu $BEST_MTU
    ip link set $TUN up
    ip route add $TREMOTE dev $TUN

    iptables -t mangle -A FORWARD -o $TUN -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $((BEST_MTU-40))

    # ذخیره تنظیمات
    cat > $CONFIG_FILE <<EOF
LOCAL=$LOCAL
REMOTE=$REMOTE
TLOCAL=$TLOCAL
TREMOTE=$TREMOTE
TUN=$TUN
MTU=$BEST_MTU
EOF

    create_service

    echo "✅ Tunnel Created & Saved!"
}

delete_tunnel() {

    if [ ! -f $CONFIG_FILE ]; then
        echo "No tunnel found!"
        return
    fi

    source $CONFIG_FILE

    ip tunnel del $TUN
    iptables -t mangle -D FORWARD -o $TUN -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $((MTU-40)) 2>/dev/null

    systemctl stop gre-tunnel
    systemctl disable gre-tunnel
    rm -f $SERVICE_FILE
    rm -f $CONFIG_FILE

    echo "❌ Tunnel Deleted!"
}

status_tunnel() {
    if [ ! -f $CONFIG_FILE ]; then
        echo "No tunnel configured."
        return
    fi

    source $CONFIG_FILE

    ip a show $TUN
    echo ""
    ping -c2 $TREMOTE
}

create_service() {

cat > $SERVICE_FILE <<EOF
[Unit]
Description=GRE Tunnel
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '
source $CONFIG_FILE
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
echo "     GRE Tunnel Manager"
echo "=============================="
echo "1) Create Tunnel"
echo "2) Delete Tunnel"
echo "3) Status"
echo "0) Exit"
echo ""

read -p "Select: " choice

case $choice in
1) create_tunnel ;;
2) delete_tunnel ;;
3) status_tunnel ;;
0) exit ;;
*) echo "Invalid Option" ;;
esac
}

menu
