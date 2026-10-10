# Network Overview

> Current-state summary of the homelab network. Detailed write-ups live in their own documents (see [Related documentation](#related-documentation)). All host, WAN and ISP addresses are replaced with `YOUR_...` placeholders.

## Summary

The network is a **routed, VLAN-segmented design** built around a Cisco 1941 router and a 24-port gigabit managed switch. The TP-Link Archer MR600 remains the internet-facing gateway (LTE WAN). Behind it, the Cisco 1941 acts as the Layer 3 boundary and inter-VLAN router (router-on-a-stick), and every device is wired to the switch and placed on a VLAN according to its role.

---

## Hardware

| Device | Role |
|--------|------|
| TP-Link Archer MR600 | Main router and internet gateway (LTE WAN) |
| Cisco 1941 | Inter-VLAN router, DHCP per VLAN, ACLs, NAT overload |
| Netgear GS724Tv4 | 24-port gigabit managed core switch (802.1Q trunk to the 1941) |
| 24-port Cat5e patch panel | Structured cabling to the switch |
| ZTE H288a | Isolated segment (VLAN 60) for the telephone and untrusted devices, with its own downstream subnet |
| Cisco Aironet AIR-CAP3602I-E-K9 | Enterprise Wi-Fi AP (FlexConnect), managed from a vWLC lab in EVE-NG |
| Grandstream HT801 | Analog-to-VoIP adapter |
| Panasonic KX-TS880FXW | Corded phone on the ZTE's built-in VoIP |
| 2x Tapo C310 | IP cameras (Frigate NVR) |
| Brother MFC-8460, Canon i-SENSYS MF8280Cw | Printers |
| Lenovo ThinkCentre M900 SFF | Main server (Docker services, VMs) |

---

## Topology

```
Internet (LTE)
      │
      ▼
TP-Link Archer MR600  (gateway)
      │
      ▼
Cisco 1941  (inter-VLAN router)
      │  802.1Q trunk (Gi0/1.10 / .20 / .30 / .40 / .50 / .60)
      ▼
Netgear GS724Tv4  (core switch)
      │
      ├── VLAN 10  Core ........... Desktop, Laptop, Server, VMs
      ├── VLAN 20  CCTV ........... 2x Tapo C310
      ├── VLAN 30  VoIP ........... Grandstream HT801
      ├── VLAN 40  Wireless Infra . Cisco AP 3602i, vWLC
      ├── VLAN 50  Printers ....... Brother, Canon
      └── VLAN 60  ZTE segment .... ZTE H288a
                                      └── downstream subnet 192.168.3.0/24
                                          (phone and untrusted devices)
```

---

## VLAN and IP plan

| VLAN | Name | Subnet | Devices |
|------|------|--------|---------|
| 10 | Core | 192.168.2.0/24 | Desktop, laptop, server, VMs (native/untagged on the trunk) |
| 20 | CCTV | 192.168.20.0/24 | Tapo C310 cameras |
| 30 | VoIP | 192.168.30.0/24 | Grandstream HT801 |
| 40 | Wireless Infra | 192.168.40.0/24 | Cisco AP 3602i, vWLC |
| 50 | Printers | 192.168.50.0/24 | Brother, Canon |
| 60 | ZTE segment | 192.168.60.0/24 | ZTE H288a WAN/uplink |
| n/a | ZTE downstream | 192.168.3.0/24 | Devices behind the ZTE (routed via the ZTE) |

Each VLAN has its own DHCP pool on the 1941. Static devices use reservations or static addressing outside the pool.

### Why the ZTE has its own VLAN (VLAN 60)

The ZTE H288a originally sat on VLAN 10 while serving a second subnet (192.168.3.0/24) behind it. That created two problems, most visibly with **Wake-on-LAN** from the 192.168.3.x side to sleeping machines on VLAN 10:

1. **Wake-on-LAN relies on Layer 2 broadcasts.** A magic packet is a broadcast, and broadcasts do not cross a routed boundary. A sender on 192.168.3.x is behind the ZTE (a routed hop), so its broadcast never reaches the VLAN 10 broadcast domain.
2. **Directed broadcasts are not forwarded by default.** Sending to 192.168.2.255 from another subnet needs the router to convert a unicast into a broadcast on the target network, which Cisco IOS disables by default (`no ip directed-broadcast`).

It also broke the convention of **one VLAN = one subnet**, which keeps broadcast domains, ACLs and troubleshooting predictable. Moving the ZTE into its own VLAN gives it a clean boundary: its uplink is a single subnet on VLAN 60, and the 192.168.3.0/24 network behind it is reached by a static route.


---

## Inter-VLAN access policy

Enforced with inbound ACLs on each 1941 subinterface (full details in the VLAN segmentation doc).

| Source | Core (VLAN 10) | Other internal VLANs | Internet |
|--------|----------------|----------------------|----------|
| VLAN 10 Core | n/a | Allowed | Allowed |
| VLAN 20/30/40/50 (IoT and infrastructure) | Allowed | **Denied** | Allowed |
| VLAN 60 / ZTE downstream | **Denied** | **Denied** | Allowed |

IoT VLANs can reach the core services they depend on (DNS, DHCP, NVR, controller) and the internet, but not each other.

---

## Routing


### Cisco 1941

| Type | Destination | Next hop / Interface |
|------|-------------|----------------------|
| Connected | 192.168.2.0/24 | Gi0/1.10 |
| Connected | 192.168.20.0/24 | Gi0/1.20 |
| Connected | 192.168.30.0/24 | Gi0/1.30 |
| Connected | 192.168.40.0/24 | Gi0/1.40 |
| Connected | 192.168.50.0/24 | Gi0/1.50 |
| Connected | 192.168.60.0/24 | Gi0/1.60 |
| Static | 192.168.3.0/24 | `YOUR_ZTE_UPLINK_IP` (ZTE on VLAN 60) |
| Static (default) | 0.0.0.0/0 | `YOUR_MR600_LAN_IP` |

### TP-Link Archer MR600

| Type | Destination | Next hop / Interface |
|------|-------------|----------------------|
| Default | 0.0.0.0/0 | LTE (`YOUR_WAN_IP`) |
| Connected |  192.168.1.0/24 | LAN |
| Static | Internal VLAN subnets (if required) | `YOUR_1941_WAN_IP` |

### ZTE H288a

| Type | Destination | Next hop / Interface |
|------|-------------|----------------------|
| Default | 0.0.0.0/0 | `YOUR_1941_VLAN60_GATEWAY` |
| Connected | 192.168.3.0/24 | LAN |

---

## NAT and port forwarding

- The 1941 performs **NAT overload** for the internal VLAN subnets using a single ACL (`NAT-INTERNET`). It denies internal-to-internal traffic so only internet-bound traffic is translated.
- Services published to the internet are forwarded on the MR600 to the server (`YOUR_SERVER_IP`):

| Service | Protocol | External port | Internal port |
|---------|----------|---------------|---------------|
| `YOUR_SERVICE` | TCP | `YOUR_PORT` | `YOUR_PORT` |

> Earlier versions of this network used two cascaded routers and double NAT. That has been removed.

---

## DNS and core services

- **Pi-hole** provides network-wide DNS and ad blocking, with local DNS records for internal services.
- **LanCache** caches game downloads. Pi-hole forwards CDN hostnames to LanCache's DNS.
- **Nginx Proxy Manager** terminates HTTPS for internal services with a wildcard Let's Encrypt certificate on a DuckDNS domain (nas-iris.duckdns.org).
- **Uptime Kuma** monitors services and feeds alerts into Home Assistant.

---

## VoIP

| Device | Location | Connection |
|--------|----------|------------|
| Panasonic KX-TS880FXW | ZTE segment | ZTE built-in VoIP client (ISP SIP credentials) |
| Grandstream HT801 | VLAN 30 | Analog phone to VoIP via ISP service |

SIP credentials are ISP-provided and not stored in this repository.

---

## Remote access

- **Tailscale** runs on the server and advertises the internal subnets, giving secure access from outside without opening management ports.
- Public exposure is limited to the forwarded services listed above.

---

## Changes since the original design

| Change | Reason |
|--------|--------|
| Added Cisco 1941 and VLAN segmentation | Isolate IoT, cameras, VoIP and printers; hands-on CCNA practice |
| Retired the Technicolor TG589vn v3 | Replaced by a 24-port gigabit switch: far more ports and 1 Gbps instead of 100 Mbps |
| ZTE H288a moved to its own VLAN (60) | One VLAN, one subnet; clean boundary and Wake-on-LAN troubleshooting |
| Removed double NAT | Single routed path to the internet |
| Added Pi-hole local DNS records for LanCache | Replaces the earlier port 53 workaround |

---

## Related documentation

- VLAN segmentation and network hardening: [vlan-segmentation-project.md](vlan-segmentation-project.md)
- Cisco AP conversion: [cisco-ap-conversion.md](cisco-ap-conversion.md)
- 4G failover: [4g-failover.md](4g-failover.md)
- Frigate NVR: [frigate-nvr.md](frigate-nvr.md)

**Planned write-ups** (moved out of the old network setup document):

- Pi-hole and LanCache DNS design
- Asymmetric routing fix on the server (`br1` host routes)
- Troubleshooting history: ZTE DMZ workaround and the retired Technicolor segment
