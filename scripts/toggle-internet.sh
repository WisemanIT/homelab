#!/bin/bash

# Replace these with your actual gateway IPs
LAN_GATEWAY="YOUR_LAN_GATEWAY_IP"        # e.g. 192.168.x.1
DONGLE_GATEWAY="YOUR_DONGLE_GATEWAY_IP"  # e.g. 192.168.x.1

DONGLE_IF="enx001e101f0000"
LAN_IF="eno1"
MODE="$1"

if [ -z "$MODE" ]; then
    echo "Usage: $0 [4g|isp]"
    echo "  4g  - Use 4G dongle for NAS internet"
    echo "  isp - Use ISP via router for NAS internet"
    exit 1
fi

echo "Switching NAS internet mode to: $MODE"

if [ "$MODE" = "4g" ]; then
    echo "→ Using 4G dongle"

    # Remove any existing default routes
    ip route del default via $LAN_GATEWAY dev $LAN_IF 2>/dev/null || true

    # Bring up dongle interface
    ip link set $DONGLE_IF up
    nmcli connection up enx001e101f0000 2>/dev/null || true

    # Wait for DHCP
    sleep 3

    # Ensure dongle route has priority (lower metric = higher priority)
    ip route del default via $DONGLE_GATEWAY dev $DONGLE_IF 2>/dev/null || true
    ip route add default via $DONGLE_GATEWAY dev $DONGLE_IF metric 10

    # Ensure NAT rules are active
    iptables -t nat -C POSTROUTING -o $DONGLE_IF -j MASQUERADE 2>/dev/null || \
        iptables -t nat -A POSTROUTING -o $DONGLE_IF -j MASQUERADE

    iptables -C FORWARD -i $LAN_IF -o $DONGLE_IF -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i $LAN_IF -o $DONGLE_IF -j ACCEPT

    iptables -C FORWARD -i $DONGLE_IF -o $LAN_IF -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i $DONGLE_IF -o $LAN_IF -m state --state RELATED,ESTABLISHED -j ACCEPT

    echo "Done. NAS now using 4G dongle."

elif [ "$MODE" = "isp" ]; then
    echo "→ Using ISP via H288A"

    # Remove dongle routes
    ip route del default via $DONGLE_GATEWAY dev $DONGLE_IF 2>/dev/null || true

    # Ensure ISP route is present
    ip route del default via $LAN_GATEWAY dev $LAN_IF 2>/dev/null || true
    ip route add default via $LAN_GATEWAY dev $LAN_IF metric 1

    # Remove NAT rules for dongle (optional - can leave them for when needed)
    # iptables -t nat -D POSTROUTING -o $DONGLE_IF -j MASQUERADE 2>/dev/null || true
    # iptables -D FORWARD -i $LAN_IF -o $DONGLE_IF -j ACCEPT 2>/dev/null || true
    # iptables -D FORWARD -i $DONGLE_IF -o $LAN_IF -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

    echo "Done. NAS now using ISP internet."

else
    echo "Invalid mode: $MODE"
    echo "Use '4g' or 'isp'"
    exit 1
fi

echo ""
echo "Current default routes:"
ip route show | grep default