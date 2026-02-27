# Cisco Aironet 3602i - Autonomous Mode Conversion

## Overview
The Cisco Aironet AIR-CAP3602I-E-K9 is an enterprise-grade 
dual-band 802.11n wireless access point originally designed 
to operate under a Cisco Wireless LAN Controller (WLC). 
Since a WLC is not available in this homelab environment, 
the AP will be converted from controller-based (LWAPP) mode 
to autonomous (standalone) mode by flashing a different 
IOS image.

## Hardware
| Component | Details |
|-----------|---------|
| Access Point | Cisco Aironet AIR-CAP3602I-E-K9 |
| PoE Injector | Utepo NW143-2 (IEEE 802.3af/at) |
| Cable | CAT6 20m |
| Source | Secondhand - fully tested and operational |

## Why This AP Was Chosen
- Enterprise-grade hardware provides stronger signal and 
  wider coverage than consumer access points
- Specifically selected to support the upcoming security 
  camera system project
- Dual-band capability minimises wireless interference 
  for wireless cameras
- IEEE 802.3af/at PoE compliance matches the Utepo 
  injector perfectly

## Planned Final Location
The AP will be installed inside the house, connected 
directly to the TP-Link Archer MR600 main router via 
the CAT6 cable through the Utepo PoE injector.

---

## Conversion Plan

### What is Autonomous Mode?
Cisco APs ship in two modes:
- **LWAPP/CAPWAP mode** - requires a Wireless LAN 
  Controller (WLC) to function. Without a controller 
  the AP cannot serve any clients.
- **Autonomous mode** - the AP operates independently 
  as a standalone device with its own configuration, 
  no controller required.

Converting from controller mode to autonomous mode 
requires flashing a different IOS image onto the AP.

### Prerequisites
- Autonomous IOS image for the 3602i 
  (already stored on the homelab server)
- TFTP server running on the local network 
  (already configured on the homelab server)
- PoE injector to power the AP
- Direct ethernet connection to the AP

### Conversion Steps

**Step 1 - Connect the AP in the workshop**

Connect the AP to the PoE injector and connect the 
injector to the workshop network. The AP will attempt 
to contact a WLC and fail - this is expected.

**Step 2 - Identify the AP's IP address**

Once the AP boots and gets an IP from DHCP, find it:
```bash
# Check DHCP leases on the router
```

**Step 3 - Access the AP via SSH**
```bash
ssh <AP_IP_ADDRESS>
```

Default credentials for a fresh Cisco AP:
```
Username: Cisco
Password: Cisco
```

**Step 4 - Verify current IOS version**
```
ap# show version
```
Note the current LWAPP image version before proceeding.

**Step 5 - Push autonomous IOS via TFTP**

From the AP CLI, initiate the TFTP transfer:
```
ap# archive download-sw /overwrite /reload 
tftp://<SERVER_IP>/<IOS_IMAGE_FILENAME>
```

Replace `<SERVER_IP>` with the homelab server IP and 
`<IOS_IMAGE_FILENAME>` with the actual filename of the 
autonomous IOS image stored on the server.

**Step 6 - Wait for reload**

The AP will download the image, flash it, and 
automatically reboot. This takes a few minutes. Do not power off during this process.

**Step 7 - Verify autonomous mode**

After reboot, SSH back into the AP and verify:
```
ap# show version
```
The IOS description should now show autonomous mode.

**Step 8 - Configure the AP**

Basic autonomous AP configuration:
```
ap# configure terminal
ap(config)# hostname HomeAP
ap(config)# interface Dot11Radio0
ap(config-if)# ssid YOUR_NETWORK_NAME
ap(config-if)# authentication open
ap(config-if)# no shutdown
```

---

## Status
- [x] Hardware acquired
- [x] Autonomous IOS image stored on server
- [x] TFTP server configured
- [ ] AP received and powered on
- [ ] IP address identified
- [ ] Telnet/SSH access confirmed
- [ ] IOS flashed successfully
- [ ] Autonomous mode verified
- [ ] AP configured and deployed in house
- [ ] Security camera system connected

---

## Notes
- All conversion work will be done in the workshop 
  before moving the AP to its final location
- Once deployed the AP will provide dedicated wireless 
  coverage inside the house
- The enterprise-grade hardware is specifically chosen 
  to support the upcoming Frigate + OpenVINO security 
  camera system with minimal interference
