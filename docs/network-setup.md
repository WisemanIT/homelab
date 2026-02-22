# Network Setup Documentation

## Overview
This homelab runs on a dual-router network setup spanning 
two physical locations — the main house and a workshop.

## Hardware
- **Main Router:** TP-Link Archer MR600 (house)
- **AP Router:** ZTE H288a (workshop)
- **Connection:** 20-metre CAT5e Ethernet cable from main 
  router LAN port to ZTE WAN port
- **Server IP:** YOUR_SERVER_IP

## Network Topology
The two routers create isolated network segments:
- **House network:** Connected to TP-Link Archer MR600
- **Workshop network:** Connected to ZTE H288a

Routing rules are configured on both routers to allow 
controlled communication between segments, enabling:
- Workshop devices to access the internet
- Cross-network device communication
- Access to web interfaces on both routers

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