# 🖥️ Homelab

A self-built home server and network infrastructure project 
running on repurposed hardware. This repository documents 
everything - from the hardware decisions and network 
architecture to the services running in Docker and the 
problems solved along the way.

---

## 🔧 Hardware

### Server
| Component     | Details 
|---------------|---------------------------------------------------------------------------------------
| Motherboard   | Lenovo IQ1X0MS - repurposed from Lenovo ThinkCentre M900 SFF (Machine Type 10FG) 
| Power Supply  | Rewired - repurposed from Lenovo ThinkCentre M58p (Machine Type 9965) 
| Chassis       | Armaggeddon Tron 1X Micro ATX Case 
| OS Drive      | WD 232GB (WDC WD2500AAJS) 
| Storage 1     | Toshiba 1.82TB - LanCache 
| Storage 2     | Seagate 465GB - Nextcloud + GameBackups 
| Storage 3     | Seagate 931GB - Media (Movies, TV, Music) 
| OS            | OpenMediaVault (Debian Bookworm) 

### Origin Story
The server was built from two separate machines - neither 
of which worked on their own. The target machine had no 
SATA power connectors on its PSU, while the donor machine's 
PSU had an incompatible 24-pin ATX connector. Unable to 
afford a new PSU or adapter, the PSU was manually rewired 
to make it compatible. The server has been running 
successfully ever since.


### Physical Location
The server is located in the workshop and is wired directly 
to the ZTE H288a AP router. The following devices are also 
wired to the ZTE in the workshop:

| Device     | Role 
|------------|------------------------------------------------------------------------------------------
| Desktop PC | Primary monitoring and management 
| Laptop     | Troubleshooting - used in workshop and portable enough to troubleshoot inside the house

### Network
| Device                          | Role 
|---------------------------------|---------------------------------------------------------------------
| TP-Link Archer MR600            | Main router (house) 
| ZTE H288a                       | AP router (workshop) 
| CAT5e 20m cable                 | Connects house LAN to workshop WAN 
| Cisco Aironet AIR-CAP3602I-E-K9 | Enterprise WiFi AP (house)
| Utepo PoE Injector NW143-2      | PoE delivery for Cisco AP
| CAT6 20m cable                  | Connects Cisco AP to main router
| Huawei K5161H                   | 4G LTE USB Dongle - backup WAN
|Technicolor TG589vn v3           | Lab network expansion — repurposed as AP/switch (Workshop (lab segment)

### Other Hardware
- **Optical Drive:** Salvaged from Lenovo ThinkCentre M58p 
  for DVD/game disc ripping

---

## 🌐 Network Architecture

Two isolated network segments connected via a 20-metre 
CAT5e cable. The main router's LAN port connects to the 
ZTE's WAN port, creating separate network segments with 
routing rules configured on both routers for controlled 
cross-network communication.

See [docs/network-setup.md](docs/network-setup.md) for 
full details including problems solved and solutions 
implemented.

---

## 🐳 Services

### Docker Containers

| Service | Purpose | Port |
|---------|---------|------|
| Pi-hole | Network-wide ad blocking + DNS | host |
| LanCache | Game download caching (Steam, Epic etc.) | 80, 443 |
| Nextcloud | Self-hosted cloud storage | 8082 |
| Jellyfin | Media streaming server | 8096 |
| Sys-API | Server monitoring (Monitee) | 8081 |
| Portainer | Docker management GUI | 9443 |
| MariaDB | Nextcloud database | 3306 |
| Redis | Nextcloud caching | 6379 |

### Native Services

| Service | Purpose |
|---------|---------|
| Plex Media Server | Media streaming (systemd service) |

See [docs/plex-native-install.md](docs/plex-native-install.md) 
for installation details.

---

## 📁 Repository Structure
```
homelab/
├── docker/
│   ├── lancache/               # LanCache + Pi-hole
│   ├── nextcloud/              # Nextcloud + MariaDB + Redis
│   ├── sys-api/                # Sys-API + configuration
│   └── jellyfin/               # Jellyfin media server
├── scripts/
│   ├── dvd-ripper.sh           # Smart disc ripping script
│   ├── toggle-internet.sh      # WAN failover switching
│   └── test-dongle-speed.sh    # 4G connection testing
└── docs/
    ├── network-setup.md        # Network architecture + troubleshooting
    ├── dvd-ripping.md          # DVD/game ripping setup
    ├──plex-native-install.md   # Plex native installation
    └── cisco-ap-conversion.md  # Cisco AP autonomous mode conversion
```

---

## ⚙️ Notable Configurations

### LanCache Performance Tuning
Custom nginx configurations to solve two specific problems:
- **Timeout issue:** Epic Games would stop caching after 
  a few minutes on slow connections - solved with 3600s 
  timeout configs
- **Throughput issue:** Cached downloads were limited to 
  200-300Mbps instead of full gigabit - solved with buffer 
  and directio tuning, achieving 600-700Mbps

### Pi-hole + LanCache DNS Coexistence
Both services require port 53. Solved by adding gaming 
domains as local DNS records in Pi-hole pointing to the 
server IP, allowing both services to run simultaneously 
without port conflicts.

### Smart DVD Ripper
A custom bash script that automatically detects disc types 
(Video DVD, PS2, PC, Xbox 360) and handles each 
appropriately - ripping movies to MKV for Plex and 
creating ISO images for game emulation.

See [scripts/dvd-ripper.sh](scripts/dvd-ripper.sh) and 
[docs/dvd-ripping.md](docs/dvd-ripping.md)

### 4G LTE Failover & Out-of-Band Management
Manual WAN failover system using a Huawei K5161H 4G 
dongle as a secondary internet path. Provides remote 
server access independent of the main ISP, bypasses 
throttling, and uses iptables NAT for routing.

See [docs/4g-failover.md](docs/4g-failover.md)

---

## Cisco Aironet 3602i - Enterprise WiFi Deployment
Deploying a secondhand enterprise-grade Cisco AP to provide 
wider coverage specifically designed to support the security 
camera system with minimal wireless interference.

See [docs/cisco-ap-conversion.md](docs/cisco-ap-conversion.md) 
for full conversion plan and progress tracker.

---

## 🎯 Goals & Learning

This project was built to develop practical skills in:
- Linux server administration (Debian/OMV)
- Docker and container management
- Network engineering (routing, DNS, VLANs, firewalling)
- Self-hosted services and infrastructure
- Hardware troubleshooting and repurposing

Currently studying: **CISCO Networking Academy** 
(Ekurhuleni Libraries - Cohort 7)

Interests: Network Engineering | Cybersecurity | 
Infrastructure

---

## 🚧 In Progress

### Security Camera System
Setting up AI-powered 24/7 home surveillance using:
- **Frigate** - NVR (Network Video Recorder) for camera management
- **OpenVINO** - Intel's AI inference engine for object 
  and person detection
- Live feeds streamed to kitchen TV for continuous monitoring

### Home Assistant
Planning to deploy Home Assistant for home automation 
and centralized control of all smart devices including 
integration with the security camera system.

### Cybersecurity Home Lab (Planning Phase)
Designing an isolated cybersecurity lab environment 
using the revived Technicolor TG589vn v3 as a network 
expansion device to create a separate lab segment. 
This keeps security experiments isolated from the 
production household network.

Planned capabilities:
- Offensive security practice (red team)
- Defensive monitoring and detection (blue team)
- Isolated from production network to protect 
  household services

See [docs/cybersecurity-lab.md](docs/cybersecurity-lab.md)

## ⚠️ Security Note

All configuration files in this repository have been 
sanitised. Sensitive values such as passwords, IP 
addresses, and disk UUIDs have been replaced with 
placeholders like `YOUR_SERVER_IP`, `YOUR_PASSWORD`, 
and `YOUR_DISK_UUID`. Replace these with your own 
values before deploying.

---

## 📄 License

This project is open source and available under the 

[MIT License](LICENSE).








