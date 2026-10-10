# Cisco Aironet 3602i - WLC-Managed HomeLab Deployment

**Status:** Active. Updated for the VLAN-segmented network (AP and vWLC on the Wireless Infra VLAN) and the dedicated Cudy NIC for virtual machines. Problems that applied to the earlier two-router design are kept in [Problems Encountered and Solutions](#problems-encountered-and-solutions) and marked as superseded where relevant.

## Overview

The Cisco Aironet AIR-CAP3602I-E-K9 is an enterprise-grade dual-band 802.11n wireless access point originally designed to operate under a Cisco Wireless LAN Controller (WLC). This project documents the full deployment of the AP in a homelab environment, managed by a virtual WLC (vWLC) running inside EVE-NG on a QEMU/KVM virtual machine on an OpenMediaVault server.

What started as a plan to convert the AP to autonomous mode was abandoned once a working vWLC solution was achieved. The AP runs in **FlexConnect mode**, with enterprise features including CleanAir spectrum intelligence, beamforming (ClientLink 2.0), band steering and automatic radio resource management active. With local switching enabled on the WLAN, a FlexConnect AP keeps serving clients on its own, so the vWLC can be used for configuration and lab work rather than being needed for day-to-day operation.

---

## Hardware

| Component | Details |
|-----------|---------|
| Access Point | Cisco Aironet AIR-CAP3602I-E-K9 |
| AP Firmware | 8.3.102.0 (CAPWAP/LWAPP mode) |
| AP Serial | `YOUR_AP_SERIAL` |
| AP MAC | `YOUR_AP_MAC` |
| PoE Injector | Utepo NW143-2 (IEEE 802.3af/at) |
| Cable | CAT6 |
| Console Cable | FTDI USB to RJ45 (ordered for troubleshooting, ultimately not needed) |
| Source | Secondhand, fully tested and operational |

---

## Why This AP Was Chosen

- Enterprise-grade hardware provides stronger signal and wider coverage than consumer access points
- Originally selected to support the security camera project (TP-Link Tapo C310 outdoor cameras with Frigate). The cameras have since moved to wired connections; see [Problem 9](#9-intermittent-latency-on-wireless-camera-traffic) and [frigate-nvr.md](frigate-nvr.md)
- Dual-band capability minimises wireless interference
- IEEE 802.3af/at PoE compliance matches the Utepo injector
- Supports Cisco CleanAir, ClientLink 2.0 beamforming and RRM, features not available on consumer APs
- Good hands-on practice for Cisco wireless, alongside CCNA study

---

## Final Architecture

```
Cisco 1941 (inter-VLAN router)
      │  802.1Q trunk
      ▼
Netgear GS724Tv4 (core switch)
      │
      ├── Cisco AP "LivingRoom" ── VLAN 40 Wireless Infra (192.168.40.0/24)
      │     AIR-CAP3602I-E-K9, FlexConnect mode
      │
      ├── Server onboard NIC (eno1) ── VLAN 10 Core
      │     host services, Pi-hole DNS
      │
      └── Server Cudy 1G NIC (br1) ── QEMU/KVM virtual machines
            └── EVE-NG VM
                  └── vWLC (VLAN 40, YOUR_VWLC_IP)
```

---

## Network Environment

| Component | Details |
|-----------|---------|
| Router / inter-VLAN routing | Cisco 1941 (router-on-a-stick), behind the TP-Link Archer MR600 gateway |
| Switch | Netgear GS724Tv4 |
| Wireless Infra VLAN | VLAN 40, 192.168.40.0/24 |
| AP IP | `YOUR_AP_IP` (DHCP reservation on the 1941) |
| vWLC | `YOUR_VWLC_IP`, Cisco AIR-CTVM-K9 v8.3.102.0 inside EVE-NG |
| EVE-NG VM | `YOUR_EVENG_IP`, network lab environment |
| OMV Server | `YOUR_SERVER_IP`, NAS, Docker services and the KVM host |
| VM bridge | `br1` on the Cudy 1G NIC (`YOUR_CUDY_NIC_INTERFACE`) |
| Pi-hole DNS | `YOUR_SERVER_IP`, serves all VLANs |

### VLAN access considerations

The VLAN 40 inbound ACL (`VLAN40-IN`) permits DHCP, traffic to the core VLAN, and the internet, and denies the other internal ranges. That is enough for the AP to:

- obtain its address by DHCP
- resolve `cisco-capwap-controller` through Pi-hole on the core VLAN
- reach the vWLC for CAPWAP (UDP 5246 control, UDP 5247 data)

See [vlan-segmentation-project.md](vlan-segmentation-project.md) for the full VLAN design and ACLs.

### WLANs and VLAN mapping

| WLAN ID | SSID | VLAN | Purpose |
|---------|------|------|---------|
| 1 | `YOUR_SSID` | `YOUR_WLAN_VLAN` | `YOUR_WLAN_PURPOSE` |

---

## Infrastructure Setup

### EVE-NG Networking: Linux Bridge

EVE-NG runs as a KVM virtual machine inside OMV. The original macvtap network configuration prevented the AP (a physical device) from communicating with the vWLC (inside EVE-NG). This was replaced with a proper Linux bridge, first on a USB Ethernet adapter and now on a dedicated **Cudy 1G NIC**.

**Bridge configuration** (`/etc/network/interfaces.d/br1`):

```
auto br1
iface br1 inet static
    address YOUR_BR1_IP
    netmask 255.255.255.0
    # no gateway line: eno1 is the only default route
    # (see asymmetric-routing-kvm-bridge.md)
    bridge_ports YOUR_CUDY_NIC_INTERFACE
    bridge_stp off
    bridge_fd 0
```

The USB-era cron job that re-added the adapter to the bridge every minute is no longer needed, since a fixed NIC does not drop off the bus.

The routing side of this bridge (host routes only, no subnet route) is documented in [asymmetric-routing-kvm-bridge.md](asymmetric-routing-kvm-bridge.md).

### vWLC Inside EVE-NG

The virtual WLC (AIR-CTVM-K9 v8.3.102.0) runs as a node inside an EVE-NG lab. EVE-NG is configured to autostart with the OMV server:

```bash
sudo virsh autostart EVE-NG
```

### Pi-hole DNS: AP Controller Discovery

The AP uses DNS to locate the WLC. A local DNS record was added to Pi-hole:

| Domain | IP | Purpose |
|--------|-----|---------|
| `cisco-capwap-controller` | `YOUR_VWLC_IP` | AP auto-discovery of the WLC |

The 1941's DHCP pool for the Wireless Infra VLAN hands out Pi-hole as the DNS server, so the AP can resolve this record.

---

## vWLC Configuration

### Certificate Compatibility

The AP's Manufacture Installed Certificate (MIC) had expired (AP manufactured around 2012-2013, MIC valid for 10 years). The vWLC's Self-Signed Certificate (SSC) was generated in 2026 when the VM was first created. Both required compatibility settings:

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

### AP Mode: FlexConnect

The AP runs in FlexConnect mode, which was first required to join across routed subnets. Local switching, which lets the AP serve clients independently if the WLC becomes unreachable, is a separate per-WLAN setting and is **off by default**. It is enabled with `config wlan flexconnect local-switching 1 enable` (see [Problem 9](#9-intermittent-latency-on-wireless-camera-traffic)). AP mode command:

```
config ap mode flexconnect YOUR_AP_NAME
```

### WLAN Configuration

```
config wlan create 1 "YOUR_SSID" "YOUR_SSID"
config wlan security wpa akm 802.1x disable 1
config wlan security wpa akm psk enable 1
config wlan security wpa akm psk set-key ascii YOUR_PASSWORD 1
config wlan security wpa enable 1
config wlan security wpa wpa2 enable 1
config wlan enable 1
save config
```

### NTP

```
config time ntp server 1 YOUR_NTP_SERVER_IP
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
| FlexConnect Local Switching | `config wlan flexconnect local-switching 1 enable` | Per-WLAN setting, off by default. When on, the AP switches client traffic locally; when off, client traffic is tunnelled to the WLC over CAPWAP |

---

## Problems Encountered and Solutions

### 1. EVE-NG Network Isolation (macvtap)

**Problem:** The AP (a physical device on the LAN) could not reach the vWLC (a virtual device inside EVE-NG) because macvtap networking prevents communication between the host's physical NIC and virtual machines attached to it.

**Solution:** Added a second NIC and configured a Linux bridge (`br1`) on the OMV host with that NIC as the bridge port. EVE-NG was reconfigured to use the bridge, allowing full bidirectional communication between physical and virtual devices.

**Follow-up:** The second NIC was originally a TP-Link UE300 USB Ethernet adapter. It only behaved on a USB 2.0 port (the `r8152` driver went into a firmware reset loop on USB 3.0) and was involved in a routing problem on the host. It was replaced by a Cudy 1G NIC, which has run without issues since. See [asymmetric-routing-kvm-bridge.md](asymmetric-routing-kvm-bridge.md).

---

### 2. DTLS Handshake Failure: Certificate Date Mismatch

**Problem:** The AP's MIC certificate had expired (manufactured around 2012, certificate valid 10 years). The vWLC SSC was generated in 2026 when the VM was first created. The AP's internal clock was set to 2019 (to work around WLC clock issues), causing the WLC's 2026 SSC to appear "not yet valid" from the AP's perspective. The result was a DTLS alert and handshake termination.

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
config time ntp server 1 YOUR_NTP_SERVER_IP
```

Setting the WLC to the correct real date (2026) made the SSC valid, and the expiry-ignore flags allowed the expired MIC to be accepted.

---

### 3. AP Join Failure: License EULA Not Accepted

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

### 4. AP Not Joining Across Subnets: Wrong AP Mode

**Problem:** In the original two-router design, the AP sat on a different subnet from the WLC. It resolved the WLC through DNS and DTLS completed, but the join was rejected:

```
%LWAPP-3-AP_MODE_NOT_SUPPORTED: AP is not in supported mode. Convert ap mode to flexconnect
```

In Local mode, the AP requires Layer 2 adjacency to the WLC. Across routed subnets, FlexConnect mode is required.

**Solution:**

```
config ap mode flexconnect YOUR_AP_NAME
```

**Status:** The AP stayed in FlexConnect mode, which suits a home environment where the lab server may not always be running.

---

### 5. AP Not Joining Across Subnets: Firewall Blocking CAPWAP (superseded)

**Problem:** In the original design, after converting to FlexConnect mode the AP still wasn't joining. `tcpdump` on the OMV bridge confirmed the AP was resolving `cisco-capwap-controller` correctly, but no CAPWAP packets (UDP 5246) were arriving at the bridge:

```bash
sudo tcpdump -i br1 udp port 5246 -n
# No output: packets never arrived
```

The ZTE router's firewall was set to **High**, blocking inbound UDP traffic from the house network.

**Solution at the time:** Added two UDP port forwarding rules on the ZTE router (UDP 5246 and 5247 to the vWLC).

**Status:** Superseded. The ZTE is no longer in the path between the AP and the vWLC. Both now sit on the Wireless Infra VLAN, and the VLAN 40 ACL allows what they need.

---

### 6. Pi-hole Port 53 Conflict After Reboot

**Problem:** After reboots, Pi-hole failed to start with `failed to create listening socket for port 53: Address in use`. Two separate services were conflicting:

- `systemd-resolved` DNS stub listener (fixed by setting `DNSStubListener=no` in `/etc/systemd/resolved.conf`)
- `dnsmasq` system service (fixed by setting `port=0` in `/etc/dnsmasq.conf` to disable its DNS while preserving DHCP capability; dnsmasq is used by libvirt/KVM for VM networking and should not be fully disabled)

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
config wlan security wpa akm psk set-key ascii YOUR_PASSWORD 1
config wlan enable 1
```

---

### 8. CAPWAP Join Failure: IPv6 on the vWLC

**Problem:** `YOUR_SYMPTOMS` (for example, the AP discovering the controller but failing to complete the join).

**Solution:** IPv6 was disabled globally on the vWLC, after which the AP joined successfully: `YOUR_COMMAND_USED`.

---

### 9. Intermittent Latency on Wireless Camera Traffic

**Problem:** With the Tapo C310 cameras connected to the AP, latency to them was 1-10 ms at night but swung between roughly 200 and 500 ms during the day. Latency was worse again whenever the vWLC was connected to the AP.

**Likely causes (not individually isolated):**

1. **Shared airtime on 2.4 GHz.** The Tapo C310 is a 2.4 GHz-only device, and that band has just three non-overlapping channels. During the day, neighbouring networks, other clients and non-Wi-Fi interference compete for airtime, causing retransmissions and latency spikes. At night the band is quiet. CleanAir and RRM can move channels and adjust power, but they cannot remove contention from networks outside your control.
2. **Client traffic tunnelled through the vWLC.** If the WLAN is not locally switched (the FlexConnect default), every client packet is encapsulated in the CAPWAP data tunnel (UDP 5247) to the controller and back. Here the controller is a software appliance inside a nested VM, which adds extra hops and CPU-bound forwarding. This fits the extra delay seen while the vWLC was connected, and the CAPWAP control traffic (RRM and CleanAir reporting) adds some overhead too.

**How to confirm which WLAN switching mode was in use:**

```
show wlan 1
# check the "FlexConnect Local Switching" line (Enabled / Disabled)
```

`YOUR_SHOW_WLAN_RESULT`

**Fix:** The cameras were moved off Wi-Fi and wired to the switch, which removes both the radio contention and the tunnel. Latency is now `YOUR_MEASURED_WIRED_LATENCY`. See [frigate-nvr.md](frigate-nvr.md) for the camera side.

**Lessons learned**
- Test wireless latency at several times of day. A clean result at night says little about daytime RF conditions.
- Latency-sensitive streams such as NVR cameras belong on wired connections.
- Local switching is a per-WLAN setting that is off by default, so check it rather than assuming FlexConnect mode implies it.
- A virtual controller in the data path is a software bottleneck. Keep client data traffic off it where possible.

---

## Final Status

- [x] Hardware acquired and powered on
- [x] EVE-NG networking fixed with a Linux bridge (`br1`)
- [x] USB Ethernet adapter replaced by a dedicated Cudy 1G NIC
- [x] vWLC deployed and reachable
- [x] AP joins vWLC successfully
- [x] Certificate expiry issues resolved
- [x] Evaluation license activated
- [x] AP running in FlexConnect mode
- [x] IPv6 disabled on the vWLC (join issue resolved)
- [x] WLAN `YOUR_SSID` created with WPA2 PSK
- [x] AP and vWLC placed on the Wireless Infra VLAN (VLAN 40)
- [x] Pi-hole DNS record for controller discovery
- [x] CleanAir enabled (2.4GHz + 5GHz)
- [x] Beamforming / ClientLink 2.0 enabled (2.4GHz + 5GHz)
- [x] Band Select enabled
- [x] TxPower automatic (both bands)
- [x] NTP configured and syncing
- [x] EVE-NG autostart via `virsh autostart`
- [x] Security cameras first served wirelessly, then moved to wired (see [Problem 9](#9-intermittent-latency-on-wireless-camera-traffic) and [frigate-nvr.md](frigate-nvr.md))
- [ ] Console cable arrived (no longer needed, kept for future use)

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

# Pi-hole
sudo systemctl restart pihole-FTL
sudo ss -ulnp | grep :53

# Test AP controller DNS resolution
nslookup cisco-capwap-controller YOUR_SERVER_IP

# Watch CAPWAP traffic
sudo tcpdump -i br1 udp port 5246 -n
```

---

## Notes

- The AP operates in FlexConnect mode, so on WLANs with local switching enabled it continues to serve WiFi clients even if the vWLC is offline. This suits a home environment where the lab server may not always be running.
- The AP's MIC certificate is permanently expired but accepted via `config certificate expiry-ignore mic enable`. This is a known issue documented in Cisco Field Notice FN63942.
- The vWLC SSC is regenerated on first boot and cannot be manually regenerated on this firmware version.
- The evaluation AP license is valid for 12 weeks and supports up to 3000 APs, which is sufficient for home use. Re-activate with `license activate ap-count eval` if it lapses.
- All enterprise WiFi features (CleanAir, beamforming, band steering, RRM) are fully functional despite the expired MIC certificate.
