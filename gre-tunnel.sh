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

    echo ""
    echo "🔎 Testing Tunnel..."
    echo ""

    ping -c4 $TREMOTE

    if [ $? -ne 0 ]; then
        echo ""
        echo "❌ Tunnel Test Failed!"
        echo "Check other side configuration."
        return
    fi

    echo ""
    echo "✅ Tunnel Test Successful!"

    # ذخیره تنظیمات فقط اگر تست موفق بود
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
    echo "🎉 Tunnel Created, Tested & Saved!"
}
