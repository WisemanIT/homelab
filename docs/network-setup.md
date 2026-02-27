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

