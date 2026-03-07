# Cisco Aironet 3602i - WLC-Managed HomeLab Deployment

## Overview

The Cisco Aironet AIR-CAP3602I-E-K9 is an enterprise-grade dual-band 802.11n wireless access point originally designed to operate under a Cisco Wireless LAN Controller (WLC). This project documents the full deployment of the AP in a homelab environment — managed by a virtual WLC (vWLC) running inside EVE-NG on an OpenMediaVault server, with the AP physically located on a separate network subnet in the house.

What started as a plan to convert the AP to autonomous mode was abandoned once a working vWLC solution was achieved. The AP now runs in **FlexConnect mode**, managed by the vWLC across two routed subnets, with enterprise features including CleanAir spectrum intelligence, beamforming (ClientLink 2.0), band steering, and automatic radio resource management all active.

---

## Hardware

| Component | Details |
|-----------|---------|
| Access Point | Cisco Aironet AIR-CAP3602I-E-K9 |
| AP Firmware | 8.3.102.0 (CAPWAP/LWAPP mode) |
| AP Serial | FGL1918X0DE |
| AP MAC | 74:a2:e6:2d:52:f5 |
| PoE Injector | Utepo NW143-2 (IEEE 802.3af/at) |
| Cable | CAT6e 20m |
| Console Cable | FTDI USB to RJ45 (ordered for troubleshooting, ultimately not needed) |
| Source | Secondhand — fully tested and operational |

---

## Why This AP Was Chosen

- Enterprise-grade hardware provides stronger signal and wider coverage than consumer access points
- Specifically selected to support an upcoming security camera system project (TP-Link Tapo C310P2 outdoor wireless cameras)
- Dual-band capability minimises wireless interference for wireless cameras
- IEEE 802.3af/at PoE compliance matches the Utepo injector perfectly
- Supports Cisco CleanAir, ClientLink 2.0 beamforming, and RRM — features not available on consumer APs

---

## Final Architecture

```
House (192.168.1.x)                    Workshop (192.168.2.x)
─────────────────────                  ──────────────────────────────────────
Cisco AP "LivingRoom"                  OMV Server (192.168.2.150)
  192.168.1.112                          └── EVE-NG VM (192.168.2.20)
  AIR-CAP3602I-E-K9                            └── vWLC (192.168.2.25)
  FlexConnect mode                       └── Pihole DNS
  Broadcasts: Afrihost TM               ZTE Router LAN (192.168.2.1)
       │
       │ CAT6
       ▼
TP-Link MR600 (192.168.1.1)
       │
       │ WAN (192.168.1.2)
       ▼
ZTE H288a Router
  └── Port Forwards: UDP 5246/5247 → 192.168.2.25
```

---

## Network Environment

| Component | Details |
|-----------|---------|
| Main Router | TP-Link Archer MR600 — house network 192.168.1.x |
| Secondary Router | ZTE H288a — workshop network 192.168.2.x |
| ZTE WAN IP | 192.168.1.2 (connected to TP-Link LAN) |
| OMV Server | 192.168.2.150 — NAS, Docker services, EVE-NG KVM host |
| EVE-NG VM | 192.168.2.20 — network lab environment |
| vWLC | 192.168.2.25 — Cisco AIR-CTVM-K9 v8.3.102.0 inside EVE-NG |
| USB Bridge | TP-Link UE300 adapter (enx00e04c414688) as br1 at 192.168.2.22 |
| AP Final IP | 192.168.1.112 (DHCP reserved on TP-Link) |
| Pihole DNS | 192.168.2.150 — serves both subnets |

### Inter-Network Routing

| Router | Static Route | Via |
|--------|-------------|-----|
| TP-Link (house) | 192.168.2.0/24 | 192.168.1.2 (ZTE WAN) |
| ZTE (workshop) | 192.168.1.0/24 | 192.168.1.1 (TP-Link) |

---

## Infrastructure Setup

### EVE-NG Networking — Linux Bridge

EVE-NG runs as a KVM virtual machine inside OMV. The original macvtap network configuration prevented the AP (physical device) from communicating with the vWLC (inside EVE-NG). This was replaced with a proper Linux bridge using a secondary USB ethernet adapter.

**Bridge configuration** (`/etc/network/interfaces.d/br1`):
```
auto br1
iface br1 inet static
    address 192.168.2.22
    netmask 255.255.255.0
    gateway 192.168.2.1
    bridge_ports enx00e04c414688
    bridge_stp off
    bridge_fd 0
    post-up ip link set enx00e04c414688 master br1 || true
```

A cron job at `/etc/cron.d/br1-persist` runs every minute to re-add the USB adapter to the bridge if it disconnects:
```
* * * * * root ip link set enx00e04c414688 master br1 2>/dev/null
```

### vWLC Inside EVE-NG

The virtual WLC (AIR-CTVM-K9 v8.3.102.0) runs as a node inside an EVE-NG lab. EVE-NG is configured to autostart with the OMV server:
```bash
sudo virsh autostart EVE-NG
```

### Pihole DNS — AP Controller Discovery

The AP uses DNS to locate the WLC across subnets. A local DNS record was added to Pihole:

| Domain | IP | Purpose |
|--------|-----|---------|
| `cisco-capwap-controller` | 192.168.2.25 | AP auto-discovery of WLC |

The TP-Link router's DHCP server is configured to hand out Pihole (192.168.2.150) as the primary DNS server for the house network, ensuring the AP can resolve this record.

### ZTE Port Forwarding — CAPWAP Through Firewall

The ZTE router's firewall (set to High) blocked CAPWAP traffic from the house network reaching the vWLC. Two UDP port forwarding rules were added:

| Name | Protocol | WAN Port | LAN Host | LAN Port |
|------|----------|----------|----------|----------|
| CAPWAP-Control | UDP | 5246 | 192.168.2.25 | 5246 |
| CAPWAP-Data | UDP | 5247 | 192.168.2.25 | 5247 |

---

## vWLC Configuration

### Certificate Compatibility

The AP's Manufacture Installed Certificate (MIC) had expired (AP manufactured ~2012-2013, MIC valid for 10 years). The vWLC's Self-Signed Certificate (SSC) was generated in 2026 when the VM was first created. Both required compatibility settings:

```
config certificate compatibility on
config certificate expiry-ignore mic enable
config certificate expiry-ignore ssc enable
```

### Licensing

The vWLC evaluation license EULA was not accepted by default, causing every AP join attempt to fail silently with `LICENSE_ACQUIRE_ERR`. Fix:

```
license activate ap-count eval
save config
reset system
```

### AP Mode — FlexConnect

The AP was converted to FlexConnect mode to allow operation across subnets (AP on 192.168.1.x, WLC on 192.168.2.x). In FlexConnect mode the AP also continues to serve clients independently if the WLC becomes unreachable:

```
config ap mode flexconnect AP74a2.e62d.52f5
```

### WLAN Configuration

```
config wlan create 1 "Afrihost TM" "Afrihost TM"
config wlan security wpa akm 802.1x disable 1
config wlan security wpa akm psk enable 1
config wlan security wpa akm psk set-key ascii <password> 1
config wlan security wpa enable 1
config wlan security wpa wpa2 enable 1
config wlan enable 1
save config
```

### NTP

```
config time ntp server 1 196.4.160.4
save config
```

---

## Enabled Enterprise Features

| Feature | Command | What It Does |
|---------|---------|--------------|
| CleanAir (2.4GHz) | `config 802.11b cleanair enable network` | Detects RF interference from microwaves, baby monitors, cordless phones, jammers etc. Triggers automatic channel changes |
| CleanAir (5GHz) | `config 802.11a cleanair enable network` | Same spectrum intelligence on 5GHz band |
| Beamforming / ClientLink 2.0 (2.4GHz) | `config 802.11b beamforming global enable` | Focuses the radio signal toward connected client devices for improved range and throughput |
| Beamforming / ClientLink 2.0 (5GHz) | `config 802.11a beamforming global enable` | Same on 5GHz |
| Band Select | `config wlan band-select allow enable 1` | Steers dual-band capable devices to 5GHz automatically |
| TxPower Auto (both bands) | `config 802.11b/a txPower global auto` | Automatically adjusts transmit power for optimal coverage |
| RRM Channel Auto (both bands) | Already enabled by default | Automatically selects the least congested WiFi channel |
| FlexConnect Local Switching | Enabled by default in FlexConnect mode | AP handles client traffic locally without hairpinning through WLC |

---

## Problems Encountered & Solutions

### 1. EVE-NG Network Isolation (macvtap)

**Problem:** The AP (physical device on the LAN) could not reach the vWLC (virtual device inside EVE-NG) because macvtap networking prevents communication between the host's physical NIC and virtual machines attached to it.

**Solution:** Added a secondary USB ethernet adapter (TP-Link UE300) and configured a Linux bridge (br1) on the OMV host, attaching the USB adapter as the bridge port. EVE-NG was reconfigured to use this bridge interface, allowing full bidirectional communication between physical and virtual devices.

---

### 2. DTLS Handshake Failure — Certificate Date Mismatch

**Problem:** The AP's MIC certificate had expired (manufactured ~2012, cert valid 10 years). The vWLC SSC was generated in 2026 when the VM was first created. The AP's internal clock was set to 2019 (to work around WLC clock issues), causing the WLC's 2026 SSC to appear as "not yet valid" from the AP's perspective — resulting in a DTLS alert and handshake termination.

**Debug output that revealed it:**
```
Verify User Certificate: X509 Cert Verification result text: certificate has expired
Verify User Certificate: Warning: Certificate has expired, but allowed & continuing
```

**Solution:**
```
config certificate compatibility on
config certificate expiry-ignore mic enable  
config certificate expiry-ignore ssc enable
config time manual 03/06/26 12:00:00
config time ntp server 1 196.4.160.4
```

Setting the WLC to the correct real date (2026) made the SSC valid, and enabling expiry-ignore flags allowed the expired MIC to be accepted.

---

### 3. AP Join Failure — License EULA Not Accepted

**Problem:** Even after DTLS completed successfully, every join request failed. The `show msglog` command revealed the actual cause:

```
%LWAPP-3-LICENSE_ACQUIRE_ERR: Failed to acquire license from the licensing module, maximum APs Joined 0/3000
```

The evaluation license existed but its EULA had never been accepted, so the licensing module refused to grant AP slots despite showing 3000 capacity.

**Solution:**
```
license activate ap-count eval
save config
reset system
```

---

### 4. AP Not Joining From House Network — Wrong AP Mode

**Problem:** After moving the AP to the house network (192.168.1.x), it resolved the WLC via DNS and DTLS completed, but the join was rejected. The WLC log showed:

```
%LWAPP-3-AP_MODE_NOT_SUPPORTED: AP is not in supported mode. Convert ap mode to flexconnect
```

In Local mode, the AP requires Layer 2 adjacency to the WLC. Across routed subnets, FlexConnect mode is required.

**Solution:**
```
config ap mode flexconnect AP74a2.e62d.52f5
```

---

### 5. AP Not Joining From House Network — ZTE Firewall Blocking CAPWAP

**Problem:** After converting to FlexConnect mode, the AP still wasn't joining when in the house. `tcpdump` on the OMV bridge confirmed the AP was resolving `cisco-capwap-controller` correctly and getting back 192.168.2.25, but no CAPWAP packets (UDP 5246) were arriving at the bridge:

```bash
sudo tcpdump -i br1 udp port 5246 -n
# No output — packets never arrived
```

The ZTE router's firewall was set to **High**, blocking inbound UDP traffic from the house network.

**Solution:** Added two UDP port forwarding rules on the ZTE router:
- UDP 5246 → 192.168.2.25 (CAPWAP control)
- UDP 5247 → 192.168.2.25 (CAPWAP data)

---

### 6. Pihole Port 53 Conflict After Reboot

**Problem:** After reboots, Pihole failed to start with `failed to create listening socket for port 53: Address in use`. Two separate services were conflicting:

- `systemd-resolved` DNS stub listener (fixed by setting `DNSStubListener=no` in `/etc/systemd/resolved.conf`)
- `dnsmasq` system service (fixed by setting `port=0` in `/etc/dnsmasq.conf` to disable its DNS while preserving DHCP capability — dnsmasq is used by libvirt/KVM for VM networking and should not be fully disabled)

---

### 7. WLAN PSK Configuration Error

**Problem:** Attempting to set a PSK password failed:
```
ERROR: PSK and/or FT-PSK should be configured on WLAN 1
```

The default WLAN was created with 802.1x (RADIUS) authentication enabled instead of PSK.

**Solution:** Disable 802.1x first, then enable PSK:
```
config wlan disable 1
config wlan security wpa akm 802.1x disable 1
config wlan security wpa akm psk enable 1
config wlan security wpa akm psk set-key ascii <password> 1
config wlan enable 1
```

---

## Final Status

- [x] Hardware acquired and powered on
- [x] EVE-NG networking fixed with Linux bridge (br1)
- [x] vWLC deployed and reachable at 192.168.2.25
- [x] AP joins vWLC successfully
- [x] Certificate expiry issues resolved
- [x] Evaluation license activated
- [x] AP converted to FlexConnect mode
- [x] WLAN "Afrihost TM" created with WPA2 PSK
- [x] AP deployed in house at 192.168.1.112
- [x] Cross-subnet routing configured on both routers
- [x] CAPWAP port forwarding configured on ZTE
- [x] Pihole DNS record for controller discovery
- [x] CleanAir enabled (2.4GHz + 5GHz)
- [x] Beamforming / ClientLink 2.0 enabled (2.4GHz + 5GHz)
- [x] Band Select enabled
- [x] TxPower automatic (both bands)
- [x] NTP configured and syncing
- [x] AP autostart via EVE-NG autostart + virsh autostart
- [ ] Console cable arrived (no longer needed — kept for future use)
- [ ] Security cameras (TP-Link Tapo C310P2) — next project

---

## Useful Commands Reference

### WLC CLI
```
show ap summary
show ap config general LivingRoom
show client summary
show wlan summary
show 802.11b cleanair air-quality summary
show 802.11a cleanair air-quality summary
show certificate compatibility
show license summary
show msglog
show time
undebug all
save config
```

### OMV Server
```bash
# EVE-NG VM management
sudo virsh list --all
sudo virsh start EVE-NG

# Bridge status
bridge link show br1
sudo ip link set enx00e04c414688 master br1   # re-add if dropped

# Pihole
sudo systemctl restart pihole-FTL
sudo ss -ulnp | grep :53

# Test AP controller DNS resolution
nslookup cisco-capwap-controller 192.168.2.150

# Watch CAPWAP traffic
sudo tcpdump -i br1 udp port 5246 -n
```

---

## Notes

- The AP operates in FlexConnect mode — it continues to serve WiFi clients even if the vWLC is offline, making it suitable for a home environment where the lab server may not always be running
- The AP's MIC certificate is permanently expired but accepted via `config certificate expiry-ignore mic enable` — this is a known issue documented in Cisco Field Notice FN63942
- The vWLC SSC is regenerated on first boot and cannot be manually regenerated on this firmware version
- The evaluation AP license is valid for 12 weeks and supports up to 3000 APs — sufficient for home use; re-activate with `license activate ap-count eval` if it lapses
- All enterprise WiFi features (CleanAir, beamforming, band steering, RRM) are fully functional despite the expired MIC certificate
