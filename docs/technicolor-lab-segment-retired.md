# Technicolor TG589vn v3: Lab Network Expansion (Retired)

**Status:** Retired. The 24-port gigabit managed switch replaced it, providing far more ports and 1 Gbps instead of 100 Mbps. This document is kept as a record of the troubleshooting, which produced lessons that still apply.

## Summary

The Technicolor TG589vn v3, the original workshop router before the ZTE H288a, was revived to add ethernet ports and to create a separate segment for cybersecurity lab experiments. It worked for days or weeks and then failed after any restart or power outage, needing a factory reset each time. Two configuration problems were responsible: an IP address conflict with a DHCP pool, and invalid values left in the (disabled) DHCP pool configuration.

---

## Why it was needed

The ZTE H288a had no free ethernet ports after connecting:

- Server
- Desktop PC
- Laptop
- Printers (Brother MFC-8460 mono laser multifunction and Canon i-SENSYS MF8280Cw wireless colour laser all-in-one)

Rather than buying a switch, the Technicolor was repurposed as a network expansion device, adding ports and a separate Wi-Fi network for the lab segment.

## Hardware limitations

| Spec | Detail |
|------|--------|
| Wi-Fi | 2.4 GHz only (single band) |
| Ethernet speed | 100 Mbps max |
| Ports | 4x LAN |

These limits were acceptable for lab traffic, which is mostly small packets rather than large transfers.

---

## Network integration

The Technicolor connected LAN-to-LAN with the ZTE and acted as an access point on the same subnet:

```
ZTE H288a
      │
      │ LAN → LAN
      ▼
Technicolor TG589vn v3
      │
      ├── Lab Device 1
      ├── Lab Device 2
      └── Lab Device 3 (planned)
```

All lab devices were reachable from the workshop network while remaining logically separate from production services.

### Configuration

| Setting | Value |
|---------|-------|
| Primary IP | 192.168.2.2 |
| Subnet mask | 255.255.255.0 |
| DHCP server | Disabled |
| DHCP range | 192.168.2.200 - 192.168.2.253 |
| Gateway | 192.168.2.1 |
| Primary DNS | 192.168.2.150 (Pi-hole) |
| Secondary DNS | 8.8.8.8 |

---

## Problem: persistent instability

**Symptoms:** As an access point, the Technicolor worked reliably for days or weeks, then failed completely after any restart or power outage. Every failure required a full factory reset and manual reconfiguration.

### What didn't work

- Disabling the firewall
- Disabling Game and Application Sharing
- Various IP address changes

### What helped temporarily

Disabling Content Sharing (Network File Server and UPnP AV Media Server) reduced service conflicts and made the device more stable, but it still broke after power outages.

---

## Root cause

The Technicolor's DHCP configuration did not match the network it was plugged into. Although it was meant to be an access point on the MR600's network, its DHCP pool still held values from its previous setup:

| Setting | Value on the MR600's network |
|---------|------------------------------|
| Subnet mask | 255.255.255.0 |
| Server | 192.168.1.2 (itself) |
| Gateway | 192.168.1.1 |
| DHCP pool | 192.168.1.100 - 192.168.1.253 (the same range as the MR600) |
| Primary DNS | 192.168.2.150 (a different subnet) |
| Secondary DNS | 0.0.0.0 (invalid) |

After a restart, the Technicolor's DHCP server behaved in one of two ways:

1. **It served no clients.** Devices on the Technicolor got no usable address from either router and showed "unidentified network".
2. **It served clients from a pool that overlapped the MR600's.** Two DHCP servers on one subnet then handed out the same addresses, causing IP conflicts.

Both outcomes come from the same fault, a DHCP pool that was invalid and overlapped another server's range. It surfaced after restarts and power outages because the DHCP service starts fresh and every device requests a lease at once. Disabling Content Sharing reduced the symptoms but did not address the cause.

---

## Solution

**Step 1: keep access throughout.** Added a second IP address on the Technicolor before changing anything. This kept the web interface reachable while the primary IP was modified and avoided a lockout.

**Step 2: correct the DHCP pool.** Updated every pool value to match the network the device now sits on and moved the pool out of the other router’s range:

| Setting | Old value | New value |
|---------|-----------|-----------|
| Subnet mask | 255.255.255.0 | 255.255.255.0 |
| Server | 192.168.1.2 | 192.168.2.2 |
| Gateway | 192.168.1.1 | 192.168.2.1 |
| DHCP pool | 192.168.1.100 - 192.168.1.253| 192.168.2.200 - 192.168.2.253 |
| Primary DNS | 192.168.2.150 | 192.168.2.150 |
| Secondary DNS | 0.0.0.0 | 8.8.8.8 |

**Step 3: move to the correct subnet.** Changed the primary IP from its original address to 192.168.2.2, placing it on the same subnet as the ZTE and the server, outside the pool.

## Result

Stable operation, confirmed through:

- Multiple web interface restarts
- Physical power cycles
- Simulated power outages
- Extended monitoring

---

## Why it was retired

The problems were solved, but the device was still limited to four 100 Mbps ports and a single-band Wi-Fi radio. The network was rebuilt around a 24-port gigabit managed switch and a Cisco 1941 with VLANs, which made the Technicolor unnecessary. It also could not provide real isolation for lab traffic, which VLANs now handle properly.

## Lessons learned

- A disabled or unused DHCP server can still hold stale pool settings. Check them before connecting the device to a different network.
- Two DHCP servers on one subnet cause conflicts or no service at all. Make sure only one is active, and that any pool on a secondary device doesn’t overlap the main one.
- Intermittent faults that appear only after power outages often point to what happens when every device renews its lease at once.
- Add a second management IP before changing a device's primary address, so a mistake doesn't lock you out.
