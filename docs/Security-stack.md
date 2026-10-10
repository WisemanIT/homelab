# Security Stack: Vaultwarden, Nginx Proxy Manager, CrowdSec and Remote Access

**Status:** Active. Gaps are marked with `YOUR_...` placeholders to fill from the live configuration. All hostnames, IPs, tokens and keys are sanitized.

## Summary

The homelab's security services work as layers on top of the VLAN segmentation:

- **Nginx Proxy Manager (NPM)** puts HTTPS in front of internal services using a wildcard Let's Encrypt certificate.
- **Vaultwarden** is a self-hosted password manager (Bitwarden-compatible) served only over HTTPS.
- **CrowdSec** detects hostile behaviour in logs and blocks offenders at the host firewall.
- **Tailscale** provides remote access without exposing management ports to the internet.

---

## How the layers fit together

| Layer | Tool | What it protects against |
|-------|------|--------------------------|
| Network segmentation | VLANs and ACLs on the Cisco 1941 | Lateral movement between IoT, cameras, printers and core |
| DNS filtering | Pi-hole | Ads, trackers and known-bad domains |
| Encrypted access | Nginx Proxy Manager with wildcard TLS | Credentials and sessions travelling in clear text |
| Credential management | Vaultwarden | Weak and reused passwords |
| Intrusion prevention | CrowdSec with firewall bouncer | Brute force and abusive hosts |
| Remote access | Tailscale | Exposing admin interfaces to the internet |
| Availability monitoring | Uptime Kuma | Silent failures of any of the above |

```
Client ──► Pi-hole (DNS) ──► YOUR_SERVER_IP
                                 │
                                 ▼
                      Nginx Proxy Manager (80/443)
                        │ wildcard TLS certificate
                        ├── vault.YOUR_DOMAIN.duckdns.org ──► Vaultwarden
                        └── other.YOUR_DOMAIN.duckdns.org ──► other services

Host firewall (iptables) ◄── CrowdSec firewall bouncer ◄── CrowdSec engine (Docker)
                                                              └── reads host auth log
```

---

## Nginx Proxy Manager and TLS

### Role

NPM is the single entry point for HTTPS to internal web services. Each service gets a proxy host with a friendly name, and every proxy host uses the same wildcard certificate.

NPM is bound to the server's own address (`YOUR_SERVER_IP`), while LanCache is bound to a separate virtual IP. That lets both use ports 80 and 443 on the same machine.

### Domain and certificate

- A **DuckDNS** domain (`YOUR_DOMAIN.duckdns.org`) provides the name.
- A **wildcard Let's Encrypt certificate** (`*.YOUR_DOMAIN.duckdns.org`) is issued through NPM. Wildcards require the DNS challenge, so NPM uses the DuckDNS provider with an API token (`YOUR_DUCKDNS_TOKEN`, never committed).
- One certificate covers every service subdomain, so adding a service needs no new certificate.

### Keeping internal traffic internal (split DNS)

Pi-hole answers the wildcard domain with the server's LAN address, so clients at home reach services directly instead of looping out through the internet. Pi-hole v6 takes this as a custom dnsmasq line:

```bash
# Example only: resolve the domain and all subdomains to the server
sudo pihole-FTL --config misc.dnsmasq_lines '["address=/YOUR_DOMAIN.duckdns.org/YOUR_SERVER_IP"]'
```

The `address=/domain/ip` form matches the domain and every subdomain, which is what makes it a wildcard.

### Proxy hosts

| Hostname | Upstream | TLS |
|----------|----------|-----|
| `vault.YOUR_DOMAIN.duckdns.org` | `YOUR_VAULTWARDEN_UPSTREAM` | Wildcard certificate, force SSL |
| `YOUR_SERVICE.YOUR_DOMAIN.duckdns.org` | `YOUR_UPSTREAM` | Wildcard certificate, force SSL |

---

## Vaultwarden

### Why it sits behind HTTPS

The Bitwarden web vault and apps rely on browser cryptography that only works in a secure context, so Vaultwarden has to be served over HTTPS (localhost aside). Putting it behind NPM with the wildcard certificate solves that and keeps the login page, vault data and admin page off clear text.

### Admin token

The admin page is protected by an **Argon2id-hashed token** instead of a plain string, so the secret never sits in the compose file in readable form.

```bash
# Generate the hash (enter a strong passphrase when prompted)
docker exec -it vaultwarden /vaultwarden hash
```

The hash goes into the compose file as `ADMIN_TOKEN`:

```yaml
services:
  vaultwarden:
    image: vaultwarden/server:latest
    environment:
      # Every "$" in the hash is doubled to "$$" for Docker Compose
      ADMIN_TOKEN: '$$argon2id$$v=19$$m=65540,t=3,p=4$$YOUR_SALT$$YOUR_HASH'
```

### Hardening status

| Setting | Status |
|---------|--------|
| Admin token hashed with Argon2id | Done |
| Served over HTTPS only (through NPM) | Done |
| Open sign-ups disabled | `YOUR_STATUS` |
| Two-factor authentication on accounts | `YOUR_STATUS` |
| Data volume backed up | `YOUR_STATUS` |

---

## CrowdSec

### How it is deployed

CrowdSec is split into a detector and an enforcer:

| Component | Where it runs | Job |
|-----------|---------------|-----|
| CrowdSec engine | Docker container | Reads logs, detects attacks, and publishes decisions through its local API |
| Firewall bouncer (`crowdsec-firewall-bouncer-iptables`) | Host, installed with `apt` | Pulls decisions and blocks the offending IPs in iptables |

```bash
# Enforcer on the host
sudo apt install crowdsec-firewall-bouncer-iptables
```

The bouncer authenticates to the engine with an API key:

```bash
# Create the key on the engine, then place it in the bouncer's config
docker exec crowdsec cscli bouncers add firewall-bouncer
# api_url: YOUR_LAPI_URL
# api_key: YOUR_API_KEY
```

### What it watches

The engine reads the host's authentication log so that repeated failed logins (for example against SSH) become decisions. The log is mounted read-only and declared in the acquisition config:

```yaml
# docker-compose.yml (excerpt)
volumes:
  - /var/log/auth.log:/var/log/auth.log:ro
```

```yaml
# acquis.yaml
filenames:
  - /var/log/auth.log
labels:
  type: syslog
```

Collections installed: `YOUR_COLLECTIONS` (for example `crowdsecurity/linux` for SSH).

### Verifying it works

```bash
# Is the engine reading the log?
docker exec crowdsec cscli metrics

# Are there active decisions, and is the bouncer connected?
docker exec crowdsec cscli decisions list
docker exec crowdsec cscli bouncers list

# Is the firewall rule in place?
sudo iptables -S | grep -i crowdsec
```

### Worth checking: Docker-published ports

Traffic to ports published by Docker is forwarded through the `FORWARD` path rather than `INPUT`, so a bouncer that only hooks `INPUT` protects the host itself but may not filter containerised services. If services such as NPM are meant to be covered, confirm which chains the bouncer attaches to: `YOUR_BOUNCER_CHAINS`.

---

## Remote access: Tailscale and DuckDNS

- **Tailscale** runs on the server and advertises the internal subnets (`YOUR_ADVERTISED_SUBNETS`), so authorised devices can reach home services from anywhere without any port being forwarded.

  ```bash
  sudo tailscale up --advertise-routes=YOUR_ADVERTISED_SUBNETS
  ```

  Advertised routes must be approved in the Tailscale admin console, and the server needs IP forwarding enabled.
- **DuckDNS** keeps `YOUR_DOMAIN.duckdns.org` pointed at the home connection and acts as the DNS-challenge provider for the wildcard certificate.
- Public exposure is limited to the services deliberately forwarded on the MR600 (see [network-setup.md](network-setup.md)).

---

## Problems Solved

### 1. Vaultwarden admin token breaks in Docker Compose

**Problem:** The Argon2id-hashed admin token did not work when placed in the compose file.

**Root cause:** The hash is full of `$` characters, and Docker Compose treats `$` as the start of a variable to interpolate, so the value was silently mangled.

**Solution:** Double every `$` to `$$` in the compose file so Compose passes a literal `$` through.

**Result:** The hashed token is accepted and the admin page is protected by it.

---

### 2. Vaultwarden needs HTTPS

**Problem:** The vault would not work properly over plain HTTP on the LAN.

**Root cause:** Bitwarden clients require a secure context for their cryptography.

**Solution:** Served Vaultwarden through Nginx Proxy Manager with the wildcard Let's Encrypt certificate, with Pi-hole split DNS keeping LAN clients on the local address.

---

### 3. CrowdSec cannot read the host auth log (permissions)

**Problem:** The CrowdSec container could not read `/var/log/auth.log`, so nothing from the host reached the engine.

**Root cause:** The log's group ownership did not match what the container process was allowed to read (a wrong group ID).

**Solution:** `YOUR_FIX` (for example, giving the container the host's log group with `group_add`).

---

### 4. CrowdSec mounts a directory instead of the log file

**Problem:** After fixing the permissions, the engine still reported no log data.

**Root cause:** When a bind-mount's host path does not exist at startup, Docker creates it as an **empty directory**. The container then saw a directory where it expected a file.

**Solution:** Make sure the real log file exists on the host before starting the container, remove the stray directory, and recreate the container.

**Result:** CrowdSec reads `auth.log` and reports parsed lines in `cscli metrics`.

---

## Lessons learned

- Compose interpolates `$` everywhere. Anything containing dollar signs (hashes, passwords) must be escaped as `$$`.
- A bind-mount to a missing file silently becomes a directory. Create files before mounting them, and when something "mounts but is empty", check for that first.
- Detection without enforcement does nothing. CrowdSec needs both the engine and a bouncer, and the bouncer must cover the traffic paths you care about.
- A wildcard certificate plus split DNS gives every service HTTPS with no per-service certificate work and no hairpin through the internet.

---

## Related documentation

- [vlan-segmentation-project.md](vlan-segmentation-project.md): network-level segmentation and ACLs
- [pihole-lancache-dns.md](pihole-lancache-dns.md): Pi-hole and LanCache DNS design
- [network-setup.md](network-setup.md): network overview and published services