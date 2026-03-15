# Network Setup Documentation

## Overview
This homelab runs on a dual-router network setup spanning 
two physical locations — the main house and a workshop.

---

## Hardware
| Device | Role | Location |
|--------|------|----------|
| TP-Link Archer MR600 | Main router — LTE WAN | House |
| ZTE H288a | AP router — workshop gateway | Workshop |
| Cisco Aironet AIR-CAP3602I-E-K9 | Enterprise WiFi AP | House (planned) |
| Grandstream HT801 | ATA — analog to VoIP | House |
| Panasonic KX-TS880FXW | Corded phone via ZTE VoIP | Workshop |
| Huawei K5161H | 4G LTE backup WAN | Workshop |
| CAT5e 20m | House LAN to workshop WAN | — |
| CAT6 20m | Cisco AP to main router (planned) | — |

---

## Network Topology
```
Internet (LTE)
      │
      ▼
TP-Link Archer MR600 (House) — 192.168.1.0/24
      │
      │ LAN → WAN (CAT5e 20m)
      ▼
ZTE H288a (Workshop) — 192.168.2.0/24
      │
      ├── Server (YOUR_SERVER_IP)
      ├── Desktop PC
      └── Laptop
      
House Devices → 192.168.1.x
      │
      └── Grandstream HT801 (ATA)
            └── Analog telephone → VoIP

[Planned]
TP-Link → CAT6 → Utepo PoE Injector → Cisco Aironet 3602i (WiFi AP)
```

---

## Routing Configuration

### ZTE H288a Routing Table
| Network | Subnet Mask | Gateway | Interface |
|---------|-------------|---------|-----------|
| 0.0.0.0 | 0.0.0.0 | YOUR_TPLINK_GATEWAY_IP | Internet |
| 192.168.1.0 | 255.255.255.0 | 0.0.0.0 | Internet |
| 192.168.2.0 | 255.255.255.0 | 0.0.0.0 | LAN |

### ZTE Static Route
| Name | Egress | Network | Subnet Mask | Gateway |
|------|--------|---------|-------------|---------|
| TP-Link Route | Internet | 192.168.1.0 | 255.255.255.0 | YOUR_TPLINK_GATEWAY_IP |

### TP-Link Archer MR600 Routing Table
| ID | Network | Subnet Mask | Gateway | Interface |
|----|---------|-------------|---------|-----------|
| 1 | 0.0.0.0 | 0.0.0.0 | YOUR_WAN_IP | LTE |
| 2 | YOUR_ISP_NETWORK | 255.255.255.240 | 0.0.0.0 | LTE |
| 3 | 192.168.1.0 | 255.255.255.0 | 0.0.0.0 | LAN & WLAN |
| 4 | 192.168.2.0 | 255.255.255.0 | YOUR_ZTE_WAN_IP | LAN & WLAN |

### TP-Link Static Route
| Network | Subnet Mask | Gateway |
|---------|-------------|---------|
| 192.168.2.0 | 255.255.255.0 | YOUR_ZTE_WAN_IP |

**This static route is critical** — it tells the TP-Link 
that to reach any device on the 192.168.2.0 workshop 
network, traffic must be sent to YOUR_ZTE_WAN_IP (the ZTE's 
WAN IP). Without this route house devices cannot 
communicate with workshop devices or the server.

---

## Port Forwarding / NAT Configuration

### ZTE H288a — Port Forwarding
All services forward to server at YOUR_SERVER_IP:

| Service | Protocol | WAN Port | LAN Port | Status |
|---------|----------|----------|----------|--------|
| Plex | TCP & UDP | 32400 | 32400 | On |
| Jellyfin | TCP & UDP | 8096 | 8096 | On |
| OMV | TCP & UDP | 81 | 81 | On |
| Pi-hole | TCP & UDP | 8080 | 8080 | On |
| Nextcloud | TCP & UDP | 8082 | 8082 | On |

### TP-Link Archer MR600 — NAT Forwarding
| ID | Service | External Port | Internal IP | Internal Port | Protocol |
|----|---------|---------------|-------------|---------------|----------|
| 1 | Plex | 32400 | YOUR_ZTE_WAN_IP | 32400 | TCP |
| 2 | Jellyfin | 8096 | YOUR_ZTE_WAN_IP | 8096 | TCP |
| 3 | OMV | 81 | YOUR_ZTE_WAN_IP | 81 | TCP |
| 4 | Pi-hole | 8080 | YOUR_ZTE_WAN_IP | 8080 | TCP |
| 5 | Nextcloud | 8082 | YOUR_ZTE_WAN_IP | 8082 | TCP |

**Note:** The TP-Link forwards to YOUR_ZTE_WAN_IP (ZTE WAN IP) 
rather than directly to the server. The ZTE then handles 
the second level of forwarding to the actual server at 
YOUR_SERVER_IP — this is double NAT, a consequence of the 
dual-router topology.

---

## VoIP Configuration

### ZTE H288a — Built-in VoIP
The ZTE H288a has a built-in VoIP client configured 
with ISP-provided SIP credentials. This connects to:
- **Panasonic KX-TS880FXW** — single-line integrated 
  corded telephone connected directly to the ZTE's 
  phone port in the workshop

### TP-Link — Grandstream HT801 ATA
The Grandstream HT801 is a compact 1-port FXS analog 
telephone adapter connected to the TP-Link main router. 
It converts analog telephone signals to VoIP, allowing 
a traditional analog phone in the house to make and 
receive calls over the ISP VoIP service.

| Device | Type | Location | Connection |
|--------|------|----------|------------|
| Panasonic KX-TS880FXW | Corded phone | Workshop | ZTE built-in VoIP |
| Grandstream HT801 | ATA adapter | House | TP-Link → ISP VoIP |

Both devices are configured using ISP-provided VoIP 
credentials.

---

## Planned: Cisco Aironet 3602i Integration

Once the Cisco AP autonomous mode conversion is complete 
the AP will be integrated as follows:
```
TP-Link Archer MR600
      │
      │ LAN (CAT6 20m)
      ▼
Utepo PoE Injector NW143-2
      │
      │ PoE (802.3af/at)
      ▼
Cisco Aironet AIR-CAP3602I-E-K9
(Enterprise WiFi — house coverage)
```

The AP will provide dedicated enterprise-grade wireless 
coverage inside the house, replacing the TP-Link's 
built-in WiFi for primary house connectivity. This is 
specifically designed to support the upcoming Frigate 
security camera system with minimal wireless interference.

See [cisco-ap-conversion.md](cisco-ap-conversion.md) 
for the full conversion plan.

---

## Problems Solved

### 1. Pi-hole and LanCache Port 53 Conflict
**Problem:** Both Pi-hole and LanCache DNS needed port 53. 
Changing LanCache's port would break its ability to receive 
DNS queries for gaming domains.

**What didn't work:**
- Changing LanCache to an alternate port
- Port forwarding from Pi-hole to LanCache
- Moving Pi-hole into the LanCache docker-compose file
- Setting Pi-hole upstream DNS to the server IP

**Solution:** Manually added gaming domain DNS records in 
Pi-hole's local DNS records, all pointing to the server IP. 
This makes Pi-hole resolve gaming domains directly to the 
LanCache server without needing to forward DNS traffic.

**Result:** Pi-hole handles network-wide ad blocking while 
LanCache successfully caches game downloads from Steam, 
Epic Games, and others simultaneously.

### 2. House Network Devices Unable to Reach Pi-hole and LanCache
**Problem:** Devices on the house network (TP-Link) could 
not send DNS queries to Pi-hole or LanCache on the server, 
even with the primary DNS set to the server IP and proper 
routing rules configured on both routers.

**Diagnosis:** The ZTE AP router's WAN firewall was blocking 
DNS packets coming from the house network segment.

**Solution:** Enabled DMZ on the ZTE AP router with the 
server as the DMZ host. This tells the ZTE to stop 
filtering incoming traffic and forward it directly to 
the server.

**Result:** All devices across both network segments now 
successfully use Pi-hole for DNS with full ad blocking, 
and gaming devices benefit from LanCache caching.

### 3. Server Losing All Network Connectivity When USB Adapter is Unplugged

**Problem:** The OMV server became completely unreachable
(SSH, web interfaces, ping all failed) whenever the TP-Link
UE300 USB ethernet adapter (`enx00e04c414688`) was unplugged,
even though the onboard NIC (`eno1`) was physically connected
and correctly configured at `192.168.2.150`.

**Background:** The USB adapter was added specifically to
create a Linux bridge (`br1` at `192.168.2.22`) for
EVE-NG/vWLC networking. The onboard NIC `eno1` was the
original and primary server network interface managed by OMV.

**Root cause — asymmetric routing:**
Both `eno1` and `br1` were on the same subnet
(`192.168.2.0/24`). When a device on the network sent
traffic to `192.168.2.150`, packets arrived correctly on
`eno1` — but the server's replies were going out through
`br1` instead, because `br1`'s subnet route appeared first
in the kernel routing table with no metric. This is called
asymmetric routing.

When the USB adapter was unplugged, `br1` went down and
took all outbound traffic with it, making the server appear
completely offline even though `eno1` was fully operational.

Confirmed with `tcpdump`:
```bash
# Requests arriving correctly on eno1
sudo tcpdump -i eno1 -n icmp
# 192.168.2.102 > 192.168.2.150: ICMP echo request

# But replies going out the wrong interface
sudo tcpdump -i br1 -n icmp
# 192.168.2.150 > 192.168.2.102: ICMP echo reply
```

**What didn't work:**
- Removing the gateway line from `/etc/network/interfaces.d/br1`
  — the route kept coming back via NetworkManager
- Adding metric values to br1 via `nmcli` — duplicate routes
  kept reappearing after reboots
- Creating an NM profile for `eno1` — OMV manages `eno1` via
  ifupdown and NM kept marking it as unmanaged
- `ip rule` policy routing — did not override the asymmetric
  routing behaviour in this configuration

**Solution — remove br1 subnet route, use specific host routes:**

The fix was to completely remove the `192.168.2.0/24` subnet
route from `br1` and replace it with only the two specific
host routes that `br1` actually needs to reach:

```bash
# Remove the conflicting subnet route from br1
sudo ip route del 192.168.2.0/24 dev br1

# Add only the specific hosts br1 needs to reach
sudo ip route add 192.168.2.20/32 dev br1 src 192.168.2.22  # EVE-NG
sudo ip route add 192.168.2.25/32 dev br1 src 192.168.2.22  # vWLC
```

Made permanent via NetworkManager:
```bash
sudo nmcli connection modify br1 ipv4.never-default yes
sudo nmcli connection modify br1 +ipv4.routes "192.168.2.20/32 0.0.0.0 50"
sudo nmcli connection modify br1 +ipv4.routes "192.168.2.25/32 0.0.0.0 50"
sudo nmcli connection modify br1 ipv4.route-metric 1000
```

Stopped NetworkManager from treating the USB adapter as a
standalone interface (it belongs to br1 only):
```bash
sudo bash -c 'cat > /etc/NetworkManager/conf.d/unmanaged.conf << EOF
[keyfile]
unmanaged-devices=mac:00:e0:4c:41:46:88
EOF'
```

**Final routing table (correct state):**
```
default via 192.168.2.1 dev eno1 proto static
192.168.2.0/24 dev eno1 proto kernel scope link src 192.168.2.150
192.168.2.20 dev br1 scope link src 192.168.2.22
192.168.2.25 dev br1 scope link src 192.168.2.22
```

**Result:**
- `eno1` is the sole default gateway and handles all server
  traffic
- `br1` handles only EVE-NG (`192.168.2.20`) and vWLC
  (`192.168.2.25`) traffic
- Unplugging the USB adapter no longer affects server
  connectivity — SSH, OMV, Jellyfin, Pi-hole and all other
  services remain fully accessible
- EVE-NG and the Cisco AP/vWLC setup continue to function
  normally when the USB adapter is plugged in

**Key lesson learned:**
When two interfaces share the same subnet, Linux uses
whichever subnet route appears first in the routing table
for outbound traffic regardless of which interface received
the incoming packet. Never assign a full subnet route to a
bridge interface that shares a subnet with the primary NIC
— use specific host routes instead.

---

## Network Expansion — Technicolor TG589vn v3

### Overview
The Technicolor TG589vn v3 was the original workshop 
router before being replaced by the ZTE H288a. It was 
revived to expand available ethernet ports in the 
workshop and create an isolated network segment for 
cybersecurity lab experiments.

### Why It Was Needed
The ZTE H288a had no remaining ethernet ports available 
after connecting:
- Server
- Desktop PC
- Laptop
- Printers (Brother MFC 8460 - Mono Laser Multifunction Printer
  and Canon i-SENSYS MF8280Cw - wireless color laser all-in-one printer)

Rather than purchasing a new switch, the Technicolor 
was repurposed as a network expansion device, providing 
additional ethernet ports and a separate WiFi network 
for the lab segment.

### Hardware Limitations
| Spec | Detail |
|------|--------|
| WiFi | 2.4GHz only (single band) |
| Ethernet speed | 100Mbps max |
| Ports | 4x LAN |

These limitations are acceptable for a cybersecurity 
lab environment where traffic is primarily small 
packets rather than large file transfers.

### Network Integration
The Technicolor connects LAN-to-LAN with the ZTE H288a:
```
ZTE H288a (192.168.2.1)
      │
      │ LAN → LAN
      ▼
Technicolor TG589vn v3 (192.168.2.2)
      │
      ├── Lab Device 1
      ├── Lab Device 2
      └── Lab Device 3 (planned)
```

Operating as an access point on the same subnet as 
the ZTE (192.168.2.0/24), all lab devices are 
reachable from the workshop network while remaining 
logically separated from production services.

### Configuration

| Setting | Value |
|---------|-------|
| Primary IP | YOUR_TECHNICOLOR_IP |
| Secondary IP | 192.168.1.1 (original, kept for reference) |
| Subnet Mask | 255.255.255.0 |
| DHCP Server | Disabled |
| Gateway | YOUR_ZTE_LAN_GATEWAY_IP |
| Primary DNS | YOUR_SERVER_IP (Pi-hole) |
| Secondary DNS | 8.8.8.8 |

### Problem: Persistent Instability (Historical)
**Symptoms:** When previously used as an access point 
the Technicolor would work reliably for days or weeks 
then completely fail after any restart or power outage. 
Every failure required a full factory reset and manual 
reconfiguration.

**What was tried that didn't work:**
- Disabling the firewall
- Disabling Game and Application Sharing
- Various IP address changes

**What temporarily worked:**
Disabling Content Sharing (which included Network 
File Server and UPnP AV Media Server) reduced network 
service conflicts enough that the device was more 
stable — but it still eventually broke after power 
outages.

**Root Cause Identified:**
Two separate issues were causing the instability:

**Issue 1 — IP Address Conflict:**
The Technicolor's server IP (192.168.1.100) fell 
within the TP-Link's DHCP pool range which also 
started at 192.168.1.100. Both devices were claiming 
the same IP address causing an ARP conflict. This 
manifested intermittently because:
- It only surfaced when DHCP leases were renewed
- Power outages forced all devices to request leases 
  simultaneously, guaranteeing the conflict appeared

**Issue 2 — Invalid DHCP Pool Configuration:**
Even with the DHCP server disabled, the pool 
configuration contained invalid and conflicting values:

| Setting | Problematic Value | Problem |
|---------|------------------|---------|
| Subnet Mask | 0.0.0.0 | Invalid — caused routing confusion |
| Gateway | 192.168.1.1 (itself) | Sent devices to wrong gateway |
| Primary DNS | 192.168.1.1 (itself) | DNS requests went nowhere |

Despite the DHCP server being disabled, these values 
were still partially active and caused conflicts when 
the device restarted.

### Solution Applied
**Step 1 — Maintain access throughout:**
Added 192.168.2.2/24 as a second IP address on the 
Technicolor before making any changes. This ensured 
web interface access was maintained even when 
modifying the primary IP — preventing a lockout 
scenario.

**Step 2 — Correct the DHCP pool:**
Updated all pool values to point to the correct 
devices even though the server remains disabled:

| Setting | Old Value | New Value |
|---------|-----------|-----------|
| Subnet Mask | 0.0.0.0 | 255.255.255.0 |
| Server | 192.168.1.1 | YOUR_TECHNICOLOR_IP |
| Gateway | 192.168.1.1 | YOUR_ZTE_LAN_GATEWAY_IP |
| Primary DNS | 192.168.1.1 | YOUR_SERVER_IP |
| Secondary DNS | 0.0.0.0 | 8.8.8.8 |

**Step 3 — Move to correct subnet:**
Changed primary IP from 192.168.1.1 to 
YOUR_TECHNICOLOR_IP placing it correctly on the 
192.168.2.0/24 subnet alongside the ZTE and server.

**Result:** Stable operation confirmed through:
- Multiple web interface restarts
- Physical power cycles
- Simulated power outage scenarios
- Extended operation monitoring

**Key Lesson Learned:**
Disabling a DHCP server does not disable all DHCP 
pool parameters. Always verify and correct the 
complete pool configuration even when the server 
function is turned off, as invalid values can still 
cause network conflicts.
