# 🖥️ Homelab

A self-built home server and network infrastructure project running on repurposed hardware. This repository documents everything - from the hardware decisions and network architecture to the services running in Docker and the problems solved along the way.

---

## ⭐ Highlights

- **VLAN segmentation and network hardening** on a Cisco 1941 and a Netgear GS724Tv4: router-on-a-stick, per-VLAN DHCP, ACLs, NAT overload and SSH management. See [docs/vlan-segmentation-project.md](docs/vlan-segmentation-project.md).
- **Self-hosted security stack:** Vaultwarden behind HTTPS, CrowdSec with a firewall bouncer, and Tailscale for remote access.
- **Monitoring and automation:** Uptime Kuma integrated with Home Assistant, with voice and WhatsApp alerts.
- **Virtualization:** QEMU/KVM hosting EVE-NG (Cisco labs) and Home Assistant OS on a dedicated NIC.
- **Hardware repurposing:** a server built from two non-working machines and rewired power supplies, now rack-mounted.

---

## 🔧 Hardware

### Server
| Component     | Details
|---------------|---------------------------------------------------------------------------------------
| Motherboard   | Lenovo IQ1X0MS - repurposed from Lenovo ThinkCentre M900 SFF (Machine Type 10FG)
| Chassis       | Amplicon 2U rackmount server chassis
| Power Supply  | Rewired - the PSU supplied with the Amplicon chassis
| OS Drive      | WD 232GB (WDC WD2500AAJS)
| Storage 1     | Toshiba 1.82TB - LanCache
| Storage 2     | Seagate 465GB - Nextcloud + GameBackups
| Storage 3     | Seagate 931GB - Media (Movies, TV, Music)
| Network       | Onboard NIC for the host + Cudy 1G NIC dedicated to the QEMU/KVM virtual machines
| OS            | OpenMediaVault (Debian Bookworm)

### Rack
| Item | Details
|------|--------
| Cabinet | 9U server cabinet
| Server | Amplicon 2U rackmount chassis

### Origin Story
The server was originally built from two separate machines - neither of which worked on their own. The target machine had no SATA power connectors on its PSU, while the donor machine's PSU had an incompatible 24-pin ATX connector. Unable to afford a new PSU or adapter, the PSU was manually rewired to make it compatible.

The build has since moved from a micro ATX tower into a **2U rackmount chassis** inside a **9U server cabinet**. The power supply that came with the Amplicon chassis needed the same treatment, so it was rewired in the same way as the earlier Lenovo ThinkCentre M58p unit. The server has been running successfully ever since.

### Dedicated NIC for Virtual Machines
The EVE-NG and Home Assistant VMs (QEMU/KVM) originally reached the network through a USB Ethernet adapter, which caused repeated stability problems. It was replaced with a **Cudy 1G NIC** dedicated to the VMs, keeping VM traffic separate from the host's onboard NIC. It has run without issues since.

### Workstations
| Device     | Role
|------------|------------------------------------------------------------------------------------------
| Desktop PC | Primary monitoring and management
| Laptop     | Troubleshooting - portable enough to use around the house

### Network
| Device                          | Role
|---------------------------------|---------------------------------------------------------------------
| TP-Link Archer MR600            | Main router and internet gateway (LTE)
| Cisco 1941                      | Inter-VLAN router, per-VLAN DHCP, ACLs, NAT (also used for CCNA practice)
| Netgear GS724Tv4                | 24-port gigabit managed core switch (802.1Q trunk to the 1941)
| 24-port Cat5e patch panel       | Structured cabling to the switch
| ZTE H288a                       | Isolated segment (VLAN 60) for the telephone and untrusted devices
| Cisco Aironet AIR-CAP3602I-E-K9 | Enterprise WiFi AP (FlexConnect), lab managed by a vWLC in EVE-NG
| Utepo PoE Injector NW143-2      | PoE delivery for Cisco AP
| Grandstream HT801               | Analog-to-VoIP adapter
| Huawei K5161H                   | 4G LTE USB Dongle - backup WAN
| TP-Link Tapo C310 (x2)          | 2K security cameras (CCTV VLAN)
| Brother MFC-8460, Canon MF8280Cw | Printers (printer VLAN)

### Other Hardware
- **Optical Drive:** Salvaged from Lenovo ThinkCentre M58p for DVD/game disc ripping

---

## 🌐 Network Architecture

The network is **VLAN-segmented and routed by a Cisco 1941** (router-on-a-stick) sitting behind the TP-Link MR600, which remains the internet gateway. Every device is wired to the Netgear GS724Tv4 gigabit switch and placed on a VLAN according to its role.

| VLAN | Name | Subnet | Devices |
|------|------|--------|---------|
| 10 | Core | 192.168.2.0/24 | Desktop, laptop, server, VMs |
| 20 | CCTV | 192.168.20.0/24 | Tapo C310 cameras |
| 30 | VoIP | 192.168.30.0/24 | Grandstream HT801 |
| 40 | Wireless Infra | 192.168.40.0/24 | Cisco AP 3602i, vWLC |
| 50 | Printers | 192.168.50.0/24 | Brother, Canon |
| 60 | ZTE segment | `YOUR_VLAN60_SUBNET` | ZTE H288a (phone and untrusted devices) |

Inbound ACLs on each VLAN keep the IoT and infrastructure VLANs from reaching each other. They can reach the core services they depend on and the internet, while the ZTE segment is blocked from the internal ranges.

- [docs/network-setup.md](docs/network-setup.md) - network overview, routing and NAT
- [docs/vlan-segmentation-project.md](docs/vlan-segmentation-project.md) - the full VLAN segmentation and hardening project

---

## 🐳 Services

Most services run as Docker containers. Home Assistant OS and EVE-NG run as QEMU/KVM virtual machines, and Plex runs natively.

### Infrastructure and Networking
| Service | Purpose |
|---------|---------|
| Pi-hole | Network-wide ad blocking + DNS |
| LanCache | Game download caching (Steam, Epic etc.) |
| Nginx Proxy Manager | Reverse proxy with wildcard HTTPS certificate |
| Tailscale | Secure remote access |
| Uptime Kuma | Service monitoring and alerting |
| NetAlertX | Network device monitoring |
| Portainer | Docker management GUI |
| Sys-API | Server monitoring (Monitee) |
| NUT | UPS monitoring |

### Security
| Service | Purpose |
|---------|---------|
| Vaultwarden | Self-hosted password manager |
| CrowdSec | Intrusion detection with firewall bouncer |

### Storage and Cloud
| Service | Purpose |
|---------|---------|
| Nextcloud (+ MariaDB, Redis) | Self-hosted cloud storage |
| Immich | Photo and video backup |
| Stirling PDF | PDF tools |

### Media
| Service | Purpose |
|---------|---------|
| Jellyfin | Media streaming server (Intel iGPU transcoding) |
| Plex Media Server | Media streaming (native systemd service) |
| Sonarr, Radarr, Lidarr, Prowlarr | Media automation |
| qBittorrent, slskd, MeTube | Downloaders |
| ntfy | Notifications |

### Surveillance, Automation and Virtualization
| Service | Purpose |
|---------|---------|
| Frigate NVR | AI-powered security camera NVR |
| Home Assistant OS (KVM VM) | Home automation, camera integration and alerts |
| IRIS | Voice assistant built on Home Assistant |
| EVE-NG (KVM VM) | Network emulation for Cisco labs |
| vWLC (inside EVE-NG) | Wireless LAN controller for the Cisco AP |

See [docs/plex-native-install.md](docs/plex-native-install.md) for the native Plex installation details.

---

## 📁 Repository Structure
```
homelab/
├── docker/
│   ├── lancache/               # LanCache + Pi-hole
│   ├── nextcloud/              # Nextcloud + MariaDB + Redis
│   ├── sys-api/                # Sys-API + configuration
│   ├── jellyfin/               # Jellyfin media server
│   └── frigate/                # Frigate NVR + config
├── scripts/
│   ├── dvd-ripper.sh           # Smart disc ripping script
│   ├── toggle-internet.sh      # WAN failover switching
│   └── test-dongle-speed.sh    # 4G connection testing
└── docs/
    ├── network-setup.md                # Network overview, routing + NAT
    ├── vlan-segmentation-project.md    # VLAN segmentation + network hardening
    ├── dvd-ripping.md                  # DVD/game ripping setup
    ├── plex-native-install.md          # Plex native installation
    ├── cisco-ap-conversion.md          # Cisco AP deployment
    ├── cybersecurity-lab.md            # Cybersecurity lab design
    ├── 4g-failover.md                  # 4G LTE failover setup
    └── frigate-nvr.md                  # Frigate NVR + Home Assistant security system
```

---

## ⚙️ Notable Configurations

### VLAN Segmentation and Network Hardening
Replaced a flat network with six VLANs routed by a Cisco 1941 and trunked to a Netgear GS724Tv4.

- **Design:** router-on-a-stick subinterfaces, one DHCP pool per VLAN, a single NAT overload ACL
- **Hardening:** inbound ACLs per VLAN, IoT VLANs isolated from each other, SSH management replacing the console cable
- **Troubleshooting:** DHCP lost after a power outage, native VLAN mismatches, ACLs blocking DHCP, false monitoring alerts caused by shared subinterface MACs, and a bad patch-panel crimp that only the switch's cable diagnostics caught

See [docs/vlan-segmentation-project.md](docs/vlan-segmentation-project.md)

### LanCache Performance Tuning
Custom nginx configurations to solve two specific problems:
- **Timeout issue:** Epic Games would stop caching after a few minutes on slow connections - solved with 3600s timeout configs
- **Throughput issue:** Cached downloads were limited to 200-300Mbps instead of full gigabit - solved with buffer and directio tuning, achieving 600-700Mbps

### Pi-hole + LanCache DNS Coexistence
Both services need to answer DNS. Pi-hole serves all clients, while LanCache's DNS runs separately on its own address and port, and Pi-hole forwards the gaming CDN hostnames to it. This lets both run side by side without a port 53 conflict.

### Server Network Stability
The server runs VMs through a bridge on a dedicated NIC. Early on, a bridge sharing a subnet with the onboard NIC caused asymmetric routing, which made the server unreachable whenever the USB adapter was unplugged. The fix was host-only routes on the bridge, and the USB adapter has since been replaced by a dedicated Cudy 1G NIC.

### Smart DVD Ripper
A custom bash script that automatically detects disc types (Video DVD, PS2, PC, Xbox 360) and handles each appropriately - ripping movies to MKV for Plex and creating ISO images for game emulation.

See [scripts/dvd-ripper.sh](scripts/dvd-ripper.sh) and [docs/dvd-ripping.md](docs/dvd-ripping.md)

### 4G LTE Failover and Out-of-Band Management
Manual WAN failover system using a Huawei K5161H 4G dongle as a secondary internet path. Provides remote server access independent of the main ISP, bypasses throttling, and uses iptables NAT for routing.

See [docs/4g-failover.md](docs/4g-failover.md)

### Frigate NVR - AI Security Camera System
Self-hosted NVR running on the server using Intel HD 530 iGPU via OpenVINO for hardware-accelerated object detection. Two TP-Link Tapo C310 cameras sit on a dedicated CCTV VLAN. Integrated with Home Assistant for notifications and automated recording triggered by detection events.

- **Detector:** OpenVINO on Intel HD 530 (~10-12ms inference)
- **Cameras:** 2K recording (2304×1296) via stream1, 640×360 detection via stream2
- **Restreaming:** go2rtc works around the cameras' single-RTSP-session limit
- **MQTT:** Mosquitto broker in HA publishing Frigate events
- **Automations:** Detection → notification + clip to phone

See [docs/frigate-nvr.md](docs/frigate-nvr.md) for full setup, configuration, and problems solved.

### Cisco Aironet 3602i - Enterprise WiFi
Cisco AP deployed via CAPWAP to a virtual WLC (vWLC 8.3) running in EVE-NG, on the Wireless Infra VLAN. It runs in FlexConnect mode day to day, and the vWLC is kept for lab and configuration work.

See [docs/cisco-ap-conversion.md](docs/cisco-ap-conversion.md) for full deployment details.

---

## 🎯 Goals & Learning

This project was built to develop practical skills in:
- Linux server administration (Debian/OMV)
- Docker and container management
- Virtualization (QEMU/KVM, EVE-NG)
- Network engineering (VLANs, inter-VLAN routing, ACLs, NAT, DNS, firewalling)
- Self-hosted services and infrastructure security
- Hardware troubleshooting and repurposing
- AI/ML inference (OpenVINO, object detection)
- Home automation (Home Assistant, MQTT)

Currently studying: **Cisco Networking Academy** (Ekurhuleni Libraries - Cohort 7), working toward the CCNA.

Interests: Network Engineering | Cybersecurity | Infrastructure

---

## 🚧 In Progress

### Network Hardening Follow-ups
- Written device inventory (name, MAC, VLAN, IP)
- Tightening the VLAN 10 ACL
- Enabling the `securityk9` license on the Cisco 1941 for zone-based firewall and VPN labs

### Cybersecurity Home Lab (Planning Phase)
Designing an isolated cybersecurity lab environment so security experiments stay separate from the production household network. The original design was built around a Technicolor TG589vn v3, which has since been retired, so the plan is being revisited for the VLAN-segmented network.

Planned capabilities:
- Offensive security practice (red team)
- Defensive monitoring and detection (blue team)
- Isolated from production network to protect household services

See [docs/cybersecurity-lab.md](docs/cybersecurity-lab.md)

---

## ⚠️ Security Note

All configuration files in this repository have been sanitised. Sensitive values such as passwords, IP addresses, and disk UUIDs have been replaced with placeholders like `YOUR_SERVER_IP`, `YOUR_PASSWORD`, and `YOUR_DISK_UUID`. Replace these with your own values before deploying.

---

## 📄 License

This project is open source and available under the [MIT License](LICENSE).
