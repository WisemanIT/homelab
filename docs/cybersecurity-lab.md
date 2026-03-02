# Cybersecurity Home Lab

## Overview
A planned isolated cybersecurity lab environment built 
on repurposed hardware, designed to practice offensive 
and defensive security techniques without risking the 
production household network.

## Design Philosophy
The production homelab server now runs critical 
household services including DNS (Pi-hole), cloud 
storage (Nextcloud), media streaming, security cameras 
(planned), and home automation (planned). Keeping 
cybersecurity experiments on a completely separate 
network segment ensures that lab activities cannot 
affect household services.

## Network Isolation
The lab runs on its own network segment via the 
revived Technicolor TG589vn v3, connected to the 
ZTE H288a workshop network but logically separated 
from production services.
```
ZTE H288a (Workshop) — 192.168.2.0/24
      │
      ├── Server (YOUR_SERVER_IP) — Production
      ├── Desktop — Management  
      └── Technicolor TG589vn v3 (YOUR_TECHNICOLOR_IP)
                │ Lab Segment
                ├── [Planned] Kali Linux — Attacker
                ├── [Planned] Target machines
                └── [Planned] Security Onion — Defender
```

## Hardware

### Technicolor TG589vn v3 — Revived
This router was the original workshop router before 
being replaced by the ZTE H288a. It was revived to 
solve two problems:
- No available ethernet ports on the ZTE
- Need for an isolated lab network segment

**The troubleshooting story:**

The Technicolor had a persistent problem when used 
previously as an access point — it would work for 
days or weeks then completely break after any restart 
or power outage, requiring a full reset and 
reconfiguration every time.

**Root cause identified:**
The DHCP pool configuration was causing conflicts 
even with the DHCP server disabled:

Original problematic configuration:
- Start Address: 192.168.1.64
- End Address: 192.168.1.253
- Subnet Mask: 0.0.0.0 (invalid)
- Server: 192.168.1.1
- Gateway: 192.168.1.1 (pointing to itself)
- Primary DNS: 192.168.1.1 (pointing to itself)

Problems with this configuration:
1. Invalid subnet mask of 0.0.0.0 caused routing 
   confusion
2. Gateway and DNS pointing to itself meant any 
   leaked DHCP responses sent devices to the wrong 
   gateway
3. Server IP conflicted with TP-Link DHCP pool 
   which started at 192.168.1.100

**Fix applied:**
1. Added 192.168.2.2/24 as a second IP address 
   before making changes — maintaining access to 
   the web interface throughout the process
2. Reconfigured DHCP pool correctly:

| Setting | Value |
|---------|-------|
| Start Address | YOUR_LAB_DHCP_START |
| End Address | YOUR_LAB_DHCP_END |
| Subnet Mask | 255.255.255.0 |
| Server | YOUR_TECHNICOLOR_IP |
| Gateway | YOUR_ZTE_LAN_GATEWAY_IP |
| Primary DNS | YOUR_SERVER_IP (Pi-hole) |
| Secondary DNS | 8.8.8.8 |

**Result:** Stable operation confirmed through 
multiple restart, power cycle, and simulated 
power outage tests.

**Key lesson:** Disabling a DHCP server does not 
necessarily disable all DHCP pool parameters. 
Always verify the full pool configuration even 
when the server function is disabled.

See [network-setup.md](network-setup.md)

---

## Planned Software Stack

### Offensive (Red Team)
| Tool | Purpose |
|------|---------|
| Kali Linux | Primary penetration testing OS |
| Parrot OS | Lightweight alternative |

### Defensive (Blue Team)
| Tool | Purpose |
|------|---------|
| Security Onion | Network security monitoring |
| Wazuh | SIEM and intrusion detection |

### Practice Targets
| Tool | Purpose |
|------|---------|
| DVWA | Damn Vulnerable Web Application |
| WebGoat | OWASP security practice |
| VulnHub machines | Realistic vulnerable systems |

---

## Planned Hardware
Monitoring secondhand HP thin clients for 
cost-effective lab machines. Thin clients are 
ideal for this use case:
- Low power consumption (10-20W each)
- Small form factor — stackable
- Sufficient performance for Linux and light VMs
- Very affordable

---

## Future Vision
Once the lab is established and security monitoring 
tools are configured, the goal is to extend passive 
monitoring to the production network using a network 
tap or SPAN port (requires managed switch). This 
would allow the lab's defensive tools to monitor 
production traffic without being on the production 
network — essentially a home SOC (Security 
Operations Center).

This capability would provide:
- Real-time threat detection across all home networks
- Remote security monitoring
- Incident response capability from anywhere
- Practical SOC analyst experience

---

## Status
- [x] Technicolor revived and stable
- [x] Lab network segment created
- [x] DHCP conflict resolved
- [ ] Thin clients acquired
- [ ] Kali Linux deployed
- [ ] First vulnerable target running
- [ ] Security Onion deployed
- [ ] Passive production monitoring configured
```
