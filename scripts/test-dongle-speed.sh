#!/bin/bash

DONGLE_IF="enx001e101f0000"
DONGLE_IP=$(ip -4 addr show $DONGLE_IF | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

echo "=========================================="
echo "    4G DONGLE SPEED TEST"
echo "=========================================="
echo "Interface: $DONGLE_IF"
echo "IP Address: $DONGLE_IP"
echo "=========================================="
echo ""

# Test 1: Ping latency
echo "📡 Testing Latency..."
ping -I $DONGLE_IF -c 5 8.8.8.8 | tail -2
echo ""

# Test 2: DNS resolution speed
echo "🔍 Testing DNS..."
time nslookup google.com 8.8.8.8 > /dev/null 2>&1
echo ""

# Test 3: Download speed test (using wget)
echo "⬇️  Testing Download Speed (100MB file)..."
wget --bind-address=$DONGLE_IP \
     --output-document=/dev/null \
     --report-speed=bits \
     http://speedtest.tele2.net/100MB.zip 2>&1 | \
     grep -E "saved|/s"
echo ""

# Test 4: Speedtest-cli (if installed)
if command -v speedtest-cli &> /dev/null; then
    echo "🚀 Running Speedtest.net Test..."
    speedtest-cli --source $DONGLE_IP --simple
else
    echo "ℹ️  speedtest-cli not installed. Install with:"
    echo "   sudo apt-get install speedtest-cli"
fi

echo ""
echo "=========================================="
echo "Test completed!"
echo "=========================================="