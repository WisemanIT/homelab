# VLAN Segmentation & Network Hardening — Cisco 1941 / GS724Tv4

Follow-up to the [Cisco 1941 core router migration](./cisco-1941-integration.md). With the patch panel cable issue resolved, this phase moved the network from a single flat LAN into five segmented VLANs, added inter-VLAN access control, hardened remote management, and worked through a long list of second-order issues the migration surfaced along the way.

## 1. Goal

- Segment the network by device type/trust level instead of one flat `192.168.2.0/24`.
- Move inter-VLAN routing fully onto the Cisco 1941 (router-on-a-stick via 802.1Q subinterfaces).
- Restrict lateral movement between IoT/single-purpose VLANs while keeping the core (desktop/laptop/server/VM) fully trusted.
- Enable SSH management on the 1941 so future changes don't require the console cable.

## 2. Final VLAN Scheme

| VLAN | Name | Subnet | Devices |
|---|---|---|---|
| 10 | Core | 192.168.2.0/24 | Desktop, Laptop, Server (eno1), VM (ens3), ZTE H288a uplink |
| 20 | CCTV | 192.168.20.0/24 | 2x Tapo C310 cameras |
| 30 | VoIP | 192.168.30.0/24 | Grandstream HT801 |
| 40 | Wireless Infra | 192.168.40.0/24 | Cisco AP (AIR-CAP3602I), joined to self-hosted vWLC |
| 50 | Printers | 192.168.50.0/24 | Brother printer, Canon MF8280Cw |
| — | (behind VLAN 10, not its own VLAN) | 192.168.3.0/24 | Devices behind the ZTE H288a (isolated downstream segment) |

VLAN 10 is the **native/untagged VLAN** on the trunk between the switch and the router — this matters, see the native VLAN mismatch issue below.

## 3. Switch Configuration (Netgear GS724Tv4)

- Created VLANs 10/20/30/40/50 under Switching → VLAN → Advanced.
- Assigned each device port as an **untagged** member of its target VLAN, with matching **PVID**.
- Port facing the router (trunk port) set to:
  - **Tagged** member of VLANs 20/30/40/50
  - **Untagged** member of VLAN 10 (native)
  - **PVID 10**
- Ports were migrated off VLAN 1 one at a time, testing connectivity after each move, with the trunk port migrated last and the laptop deliberately left on the old working config until everything else was validated — this gave a fallback path to the switch UI in case a change went wrong.

## 4. Router Configuration (Cisco 1941)

### 4.1 Subinterfaces (router-on-a-stick)

```
interface GigabitEthernet0/1
 description LAN - inter-VLAN core
 no ip address
 no shutdown

interface GigabitEthernet0/1.10
 description CORE-VLAN10 (native)
 encapsulation dot1Q 10 native
 ip address 192.168.2.1 255.255.255.0
 ip nat inside
 ip virtual-reassembly in

interface GigabitEthernet0/1.20
 description CCTV-VLAN20
 encapsulation dot1Q 20
 ip address 192.168.20.1 255.255.255.0
 ip nat inside
 ip virtual-reassembly in

interface GigabitEthernet0/1.30
 description VOIP-VLAN30
 encapsulation dot1Q 30
 ip address 192.168.30.1 255.255.255.0
 ip nat inside
 ip virtual-reassembly in

interface GigabitEthernet0/1.40
 description WIRELESS-VLAN40
 encapsulation dot1Q 40
 ip address 192.168.40.1 255.255.255.0
 ip nat inside
 ip virtual-reassembly in

interface GigabitEthernet0/1.50
 description PRINTERS-VLAN50 (helper-address relay for Canon scan on Gig0/1.10)
 encapsulation dot1Q 50
 ip address 192.168.50.1 255.255.255.0
 ip nat inside
 ip virtual-reassembly in
```

### 4.2 DHCP pools (one per VLAN)

```
ip dhcp excluded-address 192.168.2.1 192.168.2.99
ip dhcp excluded-address 192.168.2.200 192.168.2.254
ip dhcp excluded-address 192.168.2.150
ip dhcp excluded-address 192.168.20.1 192.168.20.10
ip dhcp excluded-address 192.168.30.1 192.168.30.10
ip dhcp excluded-address 192.168.40.1 192.168.40.10
ip dhcp excluded-address 192.168.50.1 192.168.50.10

ip dhcp pool LAN-POOL
 network 192.168.2.0 255.255.255.0
 default-router 192.168.2.1
 dns-server 192.168.2.150 8.8.8.8
 lease 7

ip dhcp pool HA-VM
 host 192.168.2.101 255.255.255.0
 hardware-address <HA VM's virtio MAC>
 default-router 192.168.2.1
 dns-server 192.168.2.150 8.8.8.8

ip dhcp pool CCTV-POOL
 network 192.168.20.0 255.255.255.0
 default-router 192.168.20.1
 dns-server 192.168.2.150 8.8.8.8
 lease 7

ip dhcp pool VOIP-POOL
 network 192.168.30.0 255.255.255.0
 default-router 192.168.30.1
 dns-server 192.168.2.150 8.8.8.8
 lease 7

ip dhcp pool WIRELESS-POOL
 network 192.168.40.0 255.255.255.0
 default-router 192.168.40.1
 dns-server 192.168.2.150 8.8.8.8
 lease 7

ip dhcp pool PRINTERS-POOL
 network 192.168.50.0 255.255.255.0
 default-router 192.168.50.1
 dns-server 192.168.2.150 8.8.8.8
 lease 7
```

### 4.3 NAT (covers every internal subnet, including the ZTE's downstream range)

```
ip nat inside source list NAT-INTERNET interface GigabitEthernet0/0 overload

ip access-list extended NAT-INTERNET
 deny ip 192.168.2.0 0.0.0.255 192.168.0.0 0.0.255.255
 deny ip 192.168.3.0 0.0.0.255 192.168.0.0 0.0.255.255
 deny ip 192.168.20.0 0.0.0.255 192.168.0.0 0.0.255.255
 deny ip 192.168.30.0 0.0.0.255 192.168.0.0 0.0.255.255
 deny ip 192.168.40.0 0.0.0.255 192.168.0.0 0.0.255.255
 deny ip 192.168.50.0 0.0.0.255 192.168.0.0 0.0.255.255
 permit ip 192.168.2.0 0.0.0.255 any
 permit ip 192.168.3.0 0.0.0.255 any
 permit ip 192.168.20.0 0.0.0.255 any
 permit ip 192.168.30.0 0.0.0.255 any
 permit ip 192.168.40.0 0.0.0.255 any
 permit ip 192.168.50.0 0.0.0.255 any
```

The `deny` lines exempt internal-to-internal traffic from translation (so inter-VLAN routing isn't mangled by NAT); the `permit` lines allow each subnet's internet-bound traffic to be translated and go out `GigabitEthernet0/0`.

### 4.4 ZTE H288a routing (isolated downstream segment)

- ZTE's uplink interface: static `192.168.2.5`, gateway `192.168.2.1`, DNS `192.168.2.150` — sits on VLAN 10 like any core device.
- ZTE's own LAN side: `192.168.3.0/24` (`192.168.3.1` gateway, DHCP range `.100`–`.199`) for downstream devices (phone/untrusted).

```
ip route 192.168.3.0 255.255.255.0 192.168.2.5
```

Downstream ZTE devices get NAT'd internet access via the `permit ip 192.168.3.0 ...` line above, while being explicitly walled off from every other internal subnet by `VLAN10-IN` (see §5).

### 4.5 Inter-VLAN Access Control

Design: VLAN 10 (core) is trusted and can reach anywhere, **except** the ZTE's downstream subnet, which is fully isolated even from a "trusted" position. VLANs 20/30/40/50 can reach the core (for their respective integrations — Frigate, HA/SIP registration, the vWLC, print/scan) and the internet, but **cannot reach each other**.

```
ip access-list extended VLAN10-IN
 deny ip 192.168.3.0 0.0.0.255 192.168.0.0 0.0.255.255
 permit ip any any

ip access-list extended VLAN20-IN
 5 permit udp any eq 68 any eq 67
 permit ip 192.168.20.0 0.0.0.255 192.168.2.0 0.0.0.255
 deny ip 192.168.20.0 0.0.0.255 192.168.0.0 0.0.255.255
 permit ip 192.168.20.0 0.0.0.255 any

ip access-list extended VLAN30-IN
 5 permit udp any eq 68 any eq 67
 permit ip 192.168.30.0 0.0.0.255 192.168.2.0 0.0.0.255
 deny ip 192.168.30.0 0.0.0.255 192.168.0.0 0.0.255.255
 permit ip 192.168.30.0 0.0.0.255 any

ip access-list extended VLAN40-IN
 5 permit udp any eq 68 any eq 67
 permit ip 192.168.40.0 0.0.0.255 192.168.2.0 0.0.0.255
 deny ip 192.168.40.0 0.0.0.255 192.168.0.0 0.0.255.255
 permit ip 192.168.40.0 0.0.0.255 any

ip access-list extended VLAN50-IN
 5 permit udp any eq 68 any eq 67
 permit ip 192.168.50.0 0.0.0.255 192.168.2.0 0.0.0.255
 deny ip 192.168.50.0 0.0.0.255 192.168.0.0 0.0.255.255
 permit ip 192.168.50.0 0.0.0.255 any

interface GigabitEthernet0/1.10
 ip access-group VLAN10-IN in
interface GigabitEthernet0/1.20
 ip access-group VLAN20-IN in
interface GigabitEthernet0/1.30
 ip access-group VLAN30-IN in
interface GigabitEthernet0/1.40
 ip access-group VLAN40-IN in
interface GigabitEthernet0/1.50
 ip access-group VLAN50-IN in
```

The `permit udp any eq 68 any eq 67` line (sequence 5, evaluated first) is required in every non-core VLAN's inbound ACL — see the DHCP-breakage issue below for why.

### 4.6 Cross-subnet broadcast relay (Canon MF8280Cw scan)

```
ip forward-protocol udp 8612

interface GigabitEthernet0/1.10
 ip helper-address 192.168.50.11
```

Only needed on the VLAN 10 subinterface — see the printer/scan section below for why direction matters here.

### 4.7 SSH management

```
ip domain name <redacted local domain>
crypto key generate rsa modulus 2048
ip ssh version 2
ip ssh time-out 60
ip ssh authentication-retries 3

username wiseman privilege 15 secret <redacted>
line vty 0 4
 login local
 transport input ssh
 exec-timeout 10 0
```

## 5. Issues Encountered & Resolutions

This project surfaced a long chain of issues — most triggered by the interface restructuring (splitting one flat `GigabitEthernet0/1` into five subinterfaces) silently dropping interface-level config that doesn't carry over automatically in IOS.

### 5.1 Post-outage: entire DHCP config lost
A power outage hit before `copy running-config startup-config` had been run after building the DHCP pool. On reload, interfaces came back fine (they were saved), but the DHCP pool, exclusions, and a manual reservation were gone entirely (`show ip dhcp server statistics` showed 0 pools). **Lesson:** save immediately after any config that isn't purely interface-level.

### 5.2 DHCP host-pool reservation missing gateway/DNS options
A manual host reservation (`ip dhcp pool HA-VM`) only specified the address and MAC — it did **not** inherit `default-router`/`dns-server` from the network pool it happened to fall inside. The reserved device got a valid IP but no gateway or DNS, producing "Network unreachable" despite a technically successful DHCP lease. **Fix:** every host pool needs its own explicit `default-router` and `dns-server` lines.

### 5.3 MAC mix-up between two VMs sharing a bridge
Two KVM VMs (Home Assistant and EVE-NG) on the same bridge (`br1`) were confused during a DHCP reservation — the wrong MAC (EVE-NG's) was initially used for HA's reservation, pulled from a stale ARP entry. Confirmed correct MACs via:
```
virsh -c qemu:///system domiflist <domain>
virsh -c qemu:///system dumpxml <domain> | grep -A1 "mac address"
```
(Note: `virsh` without `-c qemu:///system` connects to a per-user session scope and will show zero domains if the VMs are defined system-wide — a common gotcha.)

### 5.4 `ip nat inside`/`outside` lost when splitting the interface
Converting `GigabitEthernet0/1` from a single addressed interface into a trunk with subinterfaces did **not** carry `ip nat inside` over to the new subinterfaces (interface-level NAT direction doesn't inherit to children). Separately, `ip nat outside` on `GigabitEthernet0/0` was also found missing at one point during the same session. **Fix:** re-apply `ip nat inside`/`outside` explicitly on every relevant interface after any interface restructuring, and confirm with `show ip nat statistics` (empty `Outside interfaces:`/`Inside interfaces:` lines are the tell).

### 5.5 NAT overload statement itself went missing
Even with ACL and interface tags correct, `show ip nat translations` stayed completely empty and `show run | include ip nat inside source` returned nothing — the actual `ip nat inside source list NAT-INTERNET interface GigabitEthernet0/0 overload` statement (a global command, unrelated to any interface split) had been lost at some point. Re-adding it immediately produced real translations. **Lesson:** after any suspicious NAT behavior, check for the presence of this specific line — it's easy to assume it's fine because the ACL and interface tags look correct.

### 5.6 NAT ACL only covered one VLAN
The original NAT ACL only had a `permit` line for the original `192.168.2.0/24` subnet. Adding four new VLANs without adding matching `permit` lines meant those VLANs' `ip nat inside` tags were present, but NAT had no rule to translate their traffic — silently blackholing all internet-bound traffic from `20.0/24`, `30.0/24`, `40.0/24`, `50.0/24`. Fixed by rewriting the ACL with a `permit` line per subnet (see §4.3).

### 5.7 Native VLAN mismatch (switch vs. router)
The router's `Gig0/1.10` subinterface was configured with the `encapsulation dot1Q 10 native` keyword, meaning it expects VLAN 10 to arrive **untagged**. The switch's trunk port was initially set to send VLAN 10 **tagged** (with VLAN 1 left as the untagged/native VLAN by default). Result: the router's native/untagged channel and the switch's native/untagged channel disagreed about which VLAN "untagged" meant — VLAN 10 traffic never matched the router's native subinterface correctly. Fixed by setting VLAN 10 to **untagged** on the trunk port and giving it **PVID 10**, matching the router's native declaration. **Lesson:** native VLAN must be explicitly agreed on both ends — it's not automatic just because one side says "native."

### 5.8 PVID left at default after removing a port from VLAN 1
When migrating a port off VLAN 1's untagged membership, the port's **PVID** (which controls how untagged frames get classified) needs to be updated to match at the same time. Removing VLAN 1 membership without updating PVID caused total connectivity loss on that port — untagged frames were still being classified into VLAN 1, which the port was no longer part of, so they were silently dropped. **Fix:** VLAN membership and PVID must be changed together, not as separate steps.

### 5.9 Switch management access lost after VLAN 1 was vacated
Once every port (including the trunk) was migrated off VLAN 1, the switch's management interface — which defaults to VLAN 1 — had no path in or out anymore. Recovered via a spare unused port still on the old config, or would otherwise require console/serial access. **Lesson:** move the switch's management VLAN to the new core VLAN (10) *before* fully vacating VLAN 1, or keep one port on VLAN 1 deliberately until this is done.

### 5.10 Static IP addresses left over from the old flat network
Devices with hardcoded static IPs (cameras, at the time) kept their old `192.168.2.x` config after being moved to a new VLAN's switch port — since the device's own static config doesn't know its physical network changed. Symptom looked identical to a broken switch port. **Fix:** any statically-addressed device needs its IP/gateway manually updated to match its new VLAN when it's moved — a switch-side VLAN change alone doesn't touch a device's own network config.

### 5.11 Home Assistant TTS/announce silently failing (separate from VLAN work)
`assist_satellite.announce` calls appeared to succeed (no error, "worked" in the UI) but produced no audio, while live voice conversation with the assistant worked perfectly. Root cause: HA's `internal_url` in `configuration.yaml` was hardcoded to a stale IP (`192.168.2.114`) from a previous reconfiguration that was never updated — some playback paths fetch audio via this URL over HTTP rather than the live streaming socket used during conversation. Fixed by updating `internal_url` to HA's current address and restarting HA.

### 5.12 NetAlertX false "IP changed"/"down" alerts after enabling SNMP discovery
Two separate causes:
- **Router "IP changes":** the 1941's subinterfaces all share one physical MAC (subinterfaces don't get unique MACs). SNMP-based ARP polling sees that one MAC "at" five different IPs (one per VLAN gateway), which NetAlertX's single-IP-per-device model misreads as the router's address repeatedly changing.
- **Camera false "offline":** cameras are only visible cross-VLAN via the router's SNMP-polled ARP table, and Cisco's ARP entries age out after 4 hours of inactivity. A gap between a stale ARP entry expiring and the next successful poll can read as a device outage that never actually happened.

### 5.13 Printer/scanner cross-VLAN breakage (two separate protocols, two separate fixes)
- **Printing** broke because the print queue had been set up via network auto-discovery (mDNS/WSD), which doesn't cross VLAN boundaries. Fixed by re-adding the printer via a direct IP-based TCP/IP port instead of auto-discovery.
- **Scanning** (Canon MF8280Cw) uses a proprietary broadcast-based protocol (Canon MFNP/BJNP, UDP port 8612) for discovery, and this specific model does **not** support SMB scan-to-folder (confirmed via the device's own error message — that feature is model-gated even within the same product family). Two things were needed:
  1. `ip helper-address` on the client-side VLAN (10) subinterface, relaying UDP/8612 to the printer's static IP — since the client PC initiates the discovery broadcast, not the printer.
  2. Even with the relay in place, Canon's scan utility appears to cache device discovery locally per-PC. A brand-new device (e.g., a laptop that had never scanned to this printer before) needed a **one-time** physical presence on the printer's own VLAN to complete initial discovery/pairing, after which it worked normally from its regular VLAN. The helper-address relay alone did not substitute for this first-contact pairing.

### 5.14 SSH negotiation failures from a modern OpenSSH client
IOS 15.1's SSH implementation only offers legacy algorithms across every negotiation phase, which current OpenSSH clients disable by default:
- Key exchange: only `diffie-hellman-group14-sha1` and older offered
- Cipher: only CBC-mode ciphers offered
- Host key: only `ssh-rsa` offered
- MAC: only `hmac-sha1` and older offered

Each had to be explicitly re-enabled client-side, one at a time, as each failure surfaced the next:
```
ssh -oKexAlgorithms=+diffie-hellman-group14-sha1 -oCiphers=+aes128-cbc -oHostKeyAlgorithms=+ssh-rsa -oMACs=+hmac-sha1 -l <user> 192.168.2.1
```
This is a hard platform ceiling (IOS/hardware age), not a config error — there's no router-side fix beyond what's already set. An `~/.ssh/config` `Host` alias was used to avoid retyping this, though PowerShell/OpenSSH sessions had some friction getting the alias to resolve consistently (worth using PuTTY, or serial-over-SSH via COM ports, as an alternative if this becomes annoying — this project ultimately moved to using SSH in place of the serial console cable entirely).

### 5.15 ACLs blocking DHCP itself
After adding inter-VLAN ACLs (§4.5), devices on VLANs 20/30/40/50 stopped receiving DHCP leases entirely. Cause: a DHCP client's initial DISCOVER packet has source `0.0.0.0`, destination `255.255.255.255` — it doesn't yet have an address in its "own" subnet, so it matched none of the subnet-scoped `permit` lines in each VLAN's inbound ACL and was silently dropped by the implicit deny. **Fix:** add an explicit `permit udp any eq 68 any eq 67` as the first (lowest sequence number) entry in every VLAN's ACL, so DHCP negotiation is allowed before the client has an IP that would otherwise match the later, subnet-specific rules.

### 5.16 Cable "crosstalk" fault — tester limitations, not the cable itself (partially)
A handheld continuity cable tester showed the HT801's cable as fully normal (all 8 wires lit in correct order), but the switch's own port diagnostic (TDR-based) reported crosstalk. A basic continuity tester only checks wire order/continuity and cannot detect signal-quality issues like crosstalk, which stem from things like excessive untwisting at the termination — invisible to a simple LED tester even on a correctly-ordered cable. Root cause turned out to be a genuine bad crimp at the patch panel end; re-terminating it resolved the fault. **Lesson:** a continuity-only tester passing is not proof of full electrical health — a mismatch between it and a managed switch's own cable diagnostic should be trusted in the switch's favor, and testing with matched master/remote tester units at both ends (rather than one tester end + a device on the other) gives a more reliable result.

## 6. Outstanding / Future Work

- Build a written device inventory (name, MAC, VLAN, static/reserved IP) — several issues this project hit (HA/EVE-NG MAC mix-up, stale `internal_url`, DHCP binding conflicts) trace back to relying on memory/assumption instead of a canonical reference.
- Consider whether VLAN 10's `permit ip any any` policy is still desired long-term, or whether core devices should eventually get their own tighter restrictions.
- MR600 web UI is still only reachable from a device directly on its own subnet (`192.168.1.x`) — not yet worked around.
- Confirm NetAlertX offline-detection grace period/threshold is tuned to tolerate normal ARP cache aging on SNMP-sourced (cross-VLAN) devices, rather than flagging false downtime.

---
*IP addresses shown are internal/private (RFC1918) and specific to this local network. Passwords, enable secrets, and external hostnames have been redacted or omitted.*
