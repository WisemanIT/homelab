# 4G LTE Failover & Out-of-Band Management

## Overview
A manual WAN failover system using a 4G LTE USB dongle 
as a secondary internet connection for the homelab server. 
This provides out-of-band management access and ISP 
throttling bypass through a completely independent 
network path.

## Hardware
| Component | Details 
|-----------|---------------------------------------------------------------------------
| Dongle    | Huawei K5161H 4G LTE USB Dongle 
| USB ID    | 12d1:1591 (Huawei Technologies) 
| Interface | enx001e101f0000 
| Gateway   | 192.168.9.1 

## Why This Was Set Up

### Out-of-Band Management
The primary reason for this setup is to maintain remote 
access to the server through a completely independent 
network path. If the main ISP router fails, loses 
internet, or gets misconfigured, the server remains 
accessible via 4G — allowing remote diagnosis and 
recovery from anywhere.

### ISP Throttling
The main ISP throttles speeds significantly based on 
data usage:
- 250GB used → throttled to 20Mbps
- 500GB used → throttled to 10Mbps
- 1TB used → throttled to 1Mbps

The 4G dongle provides full speed access to the server 
regardless of the main ISP throttle state. Mobile data 
can also be purchased remotely via phone if the dongle 
runs out.

### Additional Benefits
- **Maintenance flexibility** — main router can be taken 
  offline without losing server connectivity
- **Independent DNS path** — server bypasses local 
  network entirely when on 4G
- **Cost controlled** — manually toggled, only consumes 
  mobile data when needed

---

## Scripts

### toggle-internet.sh
Switches the server's default internet route between 
the main ISP and the 4G dongle.
```bash
# Switch to 4G dongle
sudo /usr/local/bin/toggle-internet.sh 4g

# Switch back to main ISP
sudo /usr/local/bin/toggle-internet.sh isp
```

**What it does:**
- Removes existing default routes
- Adds new default route via selected interface
- Sets route metrics (lower = higher priority)
- Configures iptables NAT masquerading rules
- Enables IP forwarding between interfaces

### test-dongle-speed.sh
Tests the 4G dongle connection speed and latency.
```bash
sudo /usr/local/bin/test-dongle-speed.sh
```

**Tests performed:**
- Ping latency to 8.8.8.8
- DNS resolution speed
- Download speed via 100MB test file
- Speedtest.net via speedtest-cli (Must be installed)

---

## How It Works

### Network Interfaces
| Interface       | Role 
|-----------------|--------------------------------------------------------------------------
| eno1            | LAN — connected to ZTE H288a 
| enx001e101f0000 | WAN — 4G LTE dongle 

### Routing Logic
When switching to 4G the script:
1. Removes the default route via the LAN gateway 
   (YOUR_LAN_GATEWAY_IP)
2. Brings up the dongle interface
3. Adds a new default route via the dongle gateway 
   (YOUR_DONGLE_GATEWAY_IP) with metric 10
4. Configures NAT so LAN traffic can route through 
   the dongle

When switching back to ISP:
1. Removes the dongle default route
2. Adds the LAN default route back via YOUR_LAN_GATEWAY_IP 
   with metric 1

### iptables NAT Rules
The following rules allow the server and connected 
LAN devices to use the dongle for internet:
```bash
# Allow outbound traffic through dongle
iptables -t nat -A POSTROUTING -o enx001e101f0000 -j MASQUERADE

# Allow LAN to dongle forwarding
iptables -A FORWARD -i eno1 -o enx001e101f0000 -j ACCEPT

# Allow established connections back
iptables -A FORWARD -i enx001e101f0000 -o eno1 \
  -m state --state RELATED,ESTABLISHED -j ACCEPT
```

---

## Status
- [x] Dongle acquired and configured
- [x] Toggle script working
- [x] Speed test script working
- [x] Out-of-band access verified
- [ ] Automatic failover (future improvement)

## Future Improvements
- Implement automatic failover using a monitoring 
  script that detects when the main ISP goes down 
  and switches to 4G automatically
- Set up automatic switching back to ISP when 
  connectivity is restored
