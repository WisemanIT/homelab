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
| Console Cable | FTDI USB to RJ45 Console Cable (ordered, pending arrival) |
| Source | Secondhand - fully tested and operational |

## Why This AP Was Chosen
- Enterprise-grade hardware provides stronger signal and 
  wider coverage than consumer access points
- Specifically selected to support the upcoming security 
  camera system project (TP-Link Tapo C310P2 outdoor wireless cameras)
- Dual-band capability minimises wireless interference 
  for wireless cameras
- IEEE 802.3af/at PoE compliance matches the Utepo 
  injector perfectly

## Final Location
The AP will be installed inside the house, connected 
directly to the TP-Link Archer MR600 main router via 
the CAT6 cable through the Utepo PoE injector.

---

## Network Environment
| Component | Details |
|-----------|---------|
| Main Router | TP-Link Archer MR600 (house network - 192.168.1.x) |
| AP Router | ZTE H288a (workshop network - 192.168.2.x) |
| TFTP Server | OpenMediaVault server at YOUR_SERVER_IP_ADDRESS |
| AP Reserved IP | CISCO_RESERVERD_IP_ADDRESS (MAC: CISCO_AP_MAC_ADDRESS) |

> **Note:** Conversion will be performed on the workshop network 
> (ZTE side) where the TFTP server resides to avoid cross-subnet 
> TFTP complications. Once converted, the AP will be moved to 
> its final location on the house network.

---

## TFTP Server Setup (Completed)

TFTP server configured on the OMV homelab server at YOUR_SERVER_IP_ADDRESS.

### Installation
```bash
sudo apt install tftpd-hpa -y
```

### Configuration
```bash
sudo nano /etc/default/tftpd-hpa
```

```
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure"
```

### Directory Setup
```bash
sudo mkdir -p /srv/tftp
sudo chown tftp:tftp /srv/tftp
sudo chmod 777 /srv/tftp
```

### IOS Image
The autonomous IOS image has been downloaded and placed in the TFTP directory:
```
/srv/tftp/ap3g2-k9w7-tar.153-3.JPJ3.tar
```

Correct file permissions set:
```bash
sudo chown tftp:tftp /srv/tftp/ap3g2-k9w7-tar.153-3.JPJ3.tar
```

---

## SSH Access Discovery

During initial testing, SSH was found to work using legacy key exchange algorithms.
The AP in CAPWAP mode requires the following SSH flags:

```bash
ssh -oKexAlgorithms=+diffie-hellman-group1-sha1 \
    -oHostKeyAlgorithms=+ssh-rsa \
    -c aes128-cbc \
    Cisco@CISCO_RESERVERD_IP_ADDRESS
```

> **Note:** Default credentials after factory reset were not accepted via SSH.
> A console cable is required for initial access to set credentials and 
> run the conversion command.

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
- [x] Autonomous IOS image (`ap3g2-k9w7-tar.153-3.JPJ3.tar`) stored on TFTP server
- [x] TFTP server running on the local network (YOUR_SERVER_IP_ADDRESS)
- [x] PoE injector to power the AP
- [x] AP MAC address identified (CISCO_AP_MAC_ADDRESS)
- [x] Static IP reserved for AP (CISCO_RESERVERD_IP_ADDRESS)
- [ ] FTDI console cable (ordered, pending arrival)

### Conversion Steps

**Step 1 - Connect the AP in the workshop**

Connect the AP to the PoE injector and connect the 
injector to the workshop network (ZTE H288a side). 
The AP will attempt to contact a WLC and fail — this is expected.

**Step 2 - Connect console cable**

Connect the FTDI console cable from the AP's RJ45 console port 
to a USB port on your Linux machine. Install minicom:

```bash
sudo apt install minicom -y
```

Connect to the AP console:
```bash
sudo minicom -D /dev/ttyUSB0 -b 9600
```

**Step 3 - Access the AP CLI and set credentials**

Once connected via console, set a password to enable SSH/Telnet access:
```
ap> enable
ap# configure terminal
ap(config)# line vty 0 4
ap(config-line)# password cisco
ap(config-line)# login
ap(config-line)# end
```

**Step 4 - Verify current IOS version**
```
ap# show version
```
Note the current LWAPP image version before proceeding.

**Step 5 - Push autonomous IOS via TFTP**

From the AP CLI, initiate the TFTP transfer:
```
ap# archive download-sw /overwrite /force-reload tftp://YOUR_SERVER_IP_ADDRESS/ap3g2-k9w7-tar.153-3.JPJ3.tar
```

**Step 6 - Wait for reload**

The AP will download the image, flash it, and 
automatically reboot. This takes a few minutes. 
Do not power off during this process.

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
- [x] Autonomous IOS image stored on TFTP server
- [x] TFTP server configured and running
- [x] AP received and powered on
- [x] AP MAC address identified (CISCO_AP_MAC_ADDRESS)
- [x] Static IP reserved on ZTE router (CISCO_RESERVERD_IP_ADDRESS)
- [x] SSH access method confirmed (legacy key exchange required)
- [ ] Console cable arrived
- [ ] IOS flashed successfully
- [ ] Autonomous mode verified
- [ ] AP configured and deployed in house
- [ ] Security cameras (TP-Link Tapo C310P2) connected

---

## Notes
- All conversion work will be done in the workshop 
  before moving the AP to its final location
- Once deployed the AP will provide dedicated wireless 
  coverage inside the house for the security camera system
- The enterprise-grade hardware is specifically chosen 
  to support the upcoming Frigate + OpenVINO security 
  camera system with minimal interference
- AP in CAPWAP mode self-assigns 172.27.73.196 during 
  WLC discovery phase — this is normal behaviour and 
  resolves after factory reset
