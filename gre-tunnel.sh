#!/bin/bash

CONFIG_FILE="/etc/gre-tunnel.conf"
SERVICE_NAME="gre-tunnel"

create_tunnel() {

if [ ! -f "$CONFIG_FILE" ]; then
    echo "First time setup..."

    read -p "Local Public IP: " LOCAL
    read -p "Remote Public IP: " REMOTE
    read -p "Local Tunnel IP (70.0.0.1): " TLOCAL
    read -p "Remote Tunnel IP (70.0.0.2): " TREMOTE
    read -p "Tunnel Name (gre1): " TUN

    echo "Detecting MTU..."

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

    cat > $CONFIG_FILE <<EOF
LOCAL=$LOCAL
REMOTE=$REMOTE
TLOCAL=$TLOCAL
TREMOTE=$TREMOTE
TUN=$TUN
MTU=$BEST_MTU
EOF

    echo "Config Saved."
else
    source $CONFIG_FILE
fi

echo "Starting Tunnel..."

sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null
sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null

ip tunnel add $TUN mode gre local $LOCAL remote $REMOTE ttl 255 2>/dev/null
ip addr add $TLOCAL/30 dev $TUN 2>/dev/null
ip link set $TUN mtu $MTU
ip link set $TUN up

ip route add $TREMOTE dev $TUN 2>/dev/null

iptables -t mangle -C FORWARD -o $TUN -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $((MTU-40)) 2>/dev/null || \
iptables -t mangle -A FORWARD -o $TUN -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $((MTU-40))

echo "Tunnel Active."
}

remove_tunnel() {

if [ -f "$CONFIG_FILE" ]; then
    source $CONFIG_FILE
    ip tunnel del $TUN 2>/dev/null
    rm -f $CONFIG_FILE
fi

systemctl stop $SERVICE_NAME 2>/dev/null
systemctl disable $SERVICE_NAME 2>/dev/null
rm -f /etc/systemd/system/$SERVICE_NAME.service

echo "Tunnel Removed."
}

install_service() {

cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=GRE Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash $(realpath $0)
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE_NAME
}

case "$1" in
    remove)
        remove_tunnel
        ;;
    *)
        create_tunnel
        install_service
        ;;
esac
