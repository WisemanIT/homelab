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
| Primary IP | 192.168.1.2 |
| Subnet mask | 255.255.255.0 |
| DHCP server | Disabled |
| DHCP range | 192.168.1.100 - 192.168.1.253 |
| Gateway | 192.168.1.1 |
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

Two separate problems were causing the instability.

### Issue 1: IP address conflict

The Technicolor's own address fell inside the main router's DHCP pool range (the pool started at that same address), so the router could hand the address out to another device. Both devices then claimed the same IP.

This appeared intermittently because it only surfaced when DHCP leases were renewed. After a power outage every device requested a lease at once, which made the conflict almost certain.

### Issue 2: invalid DHCP pool configuration

Even with the DHCP server disabled, the pool configuration held invalid and conflicting values:

| Setting | Problem value | Problem |
|---------|---------------|---------|
| Subnet mask | 0.0.0.0 | Invalid; caused routing confusion |
| Gateway | The Technicolor itself | Sent devices to the wrong gateway |
| Primary DNS | The Technicolor itself | DNS requests went nowhere |

On this firmware, these values were still partially active after a restart, which caused the conflicts.

---

## Solution

**Step 1: keep access throughout.** Added a second IP address on the Technicolor before changing anything. This kept the web interface reachable while the primary IP was modified and avoided a lockout.

**Step 2: correct the DHCP pool.** Updated every pool value to point at the right devices, even though the server stays disabled:

| Setting | Old value | New value |
|---------|-----------|-----------|
| Subnet mask | 0.0.0.0 | 255.255.255.0 |
| Server | Itself | 192.168.2.2 |
| Gateway | Itself | 192.168.2.1 |
| DHCP pool | 192.168.1.100 - 192.168.1.253| 192.168.2.200 - 192.168.2.253 |
| Primary DNS | Itself | 192.168.2.150 |
| Secondary DNS | 0.0.0.0 | 8.8.8.8 |

**Step 3: move to the correct subnet.** Changed the primary IP from its original address to 192.168.2.2, placing it on the same subnet as the ZTE and the server, outside the other router's DHCP pool.

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

- Disabling a DHCP server does not necessarily disable its pool parameters. Check and correct the whole pool configuration even when the server function is off.
- A device's own static address must sit outside any DHCP pool on the network.
- Intermittent faults that appear only after power outages often point to what happens when every device renews its lease at once.
- Add a second management IP before changing a device's primary address, so a mistake doesn't lock you out.
