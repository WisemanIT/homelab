# Security Stack: Vaultwarden, CrowdSec, Nginx Proxy Manager & Tailscale

**Status:** Active.

A self-hosted password manager and an intrusion-detection/prevention layer sitting behind a single reverse proxy, with Tailscale for private remote access, all running on the homelab server (Debian 12 / OpenMediaVault, Docker).

> **Note on placeholders:** IPs, domains, keys and hashes in this document are sanitized. Replace `YOUR_SERVER_IP`, `your-domain.duckdns.org`, `YOUR_BOUNCER_KEY`, `YOUR_ARGON2_HASH` and `YOUR_TAILSCALE_IP` with real values.

---

## 1. Overview

| Component | Role | How it runs |
|---|---|---|
| **Nginx Proxy Manager (NPM)** | Reverse proxy, TLS termination, wildcard Let's Encrypt cert | Docker (`/opt/nginx-proxy-manager/`) |
| **Vaultwarden** | Self-hosted Bitwarden-compatible password manager | Docker (`/opt/vaultwarden/`) |
| **CrowdSec** | Reads logs, detects attacks (SSH brute force, HTTP abuse), issues ban decisions | Docker (`/opt/crowdsec/`) |
| **CrowdSec firewall bouncer** | Enforces CrowdSec's decisions as firewall drops | Native package (apt), systemd service |
| **Tailscale** | Private remote access to the homelab without opening ports | Native package, systemd service |

### Architecture

```
                 Internet
                    │
            ┌───────▼────────┐
            │ Firewall       │◄──── ipset: crowdsec-blacklists-0
            │ (CROWDSEC_CHAIN│      (banned IPs dropped here)
            │  via iptables- │
            │  nft)          │
            └───────┬────────┘
                    │ 80 / 443
            ┌───────▼────────┐        logs
            │ Nginx Proxy    ├──────────────┐
            │ Manager        │              │
            └───────┬────────┘              ▼
                    │              ┌─────────────────┐   decisions   ┌────────────────────┐
            ┌───────▼────────┐     │ CrowdSec        ├──────────────►│ Firewall bouncer   │
            │ Vaultwarden    │     │ (LAPI :8080)    │◄──────────────┤ (polls every ~10s) │
            │ + other apps   │     └────────▲────────┘   API key     └────────────────────┘
            └────────────────┘              │
                                   /var/log/auth.log (SSH etc.)
```

**Flow:** NPM and the host write logs → CrowdSec parses them and matches attack scenarios → a ban decision is created → the bouncer polls CrowdSec's local API, pushes banned IPs into an ipset → the firewall drops packets from those IPs. The bouncer's chain is jumped to from `INPUT`, which covers traffic to the host itself such as SSH. Whether it also covers traffic to Docker-published ports like NPM's needs checking: see [section 5.6](#56-coverage-of-docker-published-ports-verify).

**Remote path (separate from the public one):**

```
Remote device ──► Tailscale tunnel (WireGuard) ──► server (subnet router) ──► home LAN
```

See [section 6](#6-remote-access-tailscale).

### Directory layout

```
/opt/
├── nginx-proxy-manager/
│   ├── data/            # NPM config + logs (data/logs)
│   └── letsencrypt/     # certificates
├── vaultwarden/
│   ├── docker-compose.yml
│   └── data/            # vault database, RSA keys (BACK THIS UP)
├── crowdsec/
│   ├── docker-compose.yml
│   ├── config/          # /etc/crowdsec (incl. acquis.yaml)
│   └── data/
```

---

## 2. Nginx Proxy Manager

NPM fronts every web service on the server. It terminates TLS with a **wildcard certificate** for `*.your-domain.duckdns.org` (DNS challenge via DuckDNS), so each service just gets a proxy host like `vault.your-domain.duckdns.org`.

- Ports published: `80`, `443`, and `82 → 81` (admin UI).
- NPM listens on the server's own address, while LanCache has its own virtual IP, so both can use ports 80 and 443 on the same host.
- Per-host access/error logs are written to `/opt/nginx-proxy-manager/data/logs/` as `proxy-host-N_access.log` / `proxy-host-N_error.log`. CrowdSec reads these.

### Split DNS

Pi-hole answers the wildcard domain with the server's LAN address, so devices at home reach services directly instead of going out through the internet and back. Pi-hole v6 takes this as a custom dnsmasq line:

```bash
# Example only. "misc.dnsmasq_lines" is one array: this command REPLACES it,
# so include every line that is already there (for example the LanCache forwards).
sudo pihole-FTL --config misc.dnsmasq_lines '["address=/your-domain.duckdns.org/YOUR_SERVER_IP"]'
```

`address=/domain/ip` matches the domain and every subdomain, which is what makes it a wildcard. Containers that must resolve these names (Uptime Kuma, for example) need `dns:` pointing at Pi-hole in their compose file, otherwise Docker's resolver returns the public address instead.

---

## 3. Vaultwarden

### 3.1 Generate the admin token hash

The `/admin` panel is protected by `ADMIN_TOKEN`. Use an Argon2id hash, not plain text. The command needs an interactive terminal, so `-it` is required:

```bash
docker run --rm -it vaultwarden/server /vaultwarden hash
```

Enter a password twice and copy the **entire** output string, from `$argon2id$v=19$...` to the end. (Widen the terminal first so nothing wraps or gets cut off.)

### 3.2 Compose file

`/opt/vaultwarden/docker-compose.yml`:

```yaml
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    environment:
      DOMAIN: "https://vault.your-domain.duckdns.org"
      SIGNUPS_ALLOWED: "false"      # "true" only while creating your first account
      WEBSOCKET_ENABLED: "true"
      # Every "$" in the hash is doubled to "$$" (see Problems & Solutions)
      ADMIN_TOKEN: "$$argon2id$$v=19$$m=65540,t=3,p=4$$YOUR_SALT$$YOUR_HASH"
    volumes:
      - ./data:/data
    ports:
      - "8087:80"
```

```bash
cd /opt/vaultwarden
sudo docker compose up -d
sudo docker logs vaultwarden --tail 20
```

The "plain text ADMIN_TOKEN is insecure" notice should be **gone** from the logs.

### 3.3 HTTPS is mandatory

Browsing to `http://YOUR_SERVER_IP:8087` shows:

> *You are not using a secure context which is required for the Subtle Crypto API to work. You need to enable HTTPS!*

The web vault does all its client-side encryption with the browser's WebCrypto (`SubtleCrypto`) API, which only works over HTTPS or `localhost`. So the NPM proxy host must exist **before** you can log in or create an account.

### 3.4 NPM proxy host

In NPM → Hosts → Proxy Hosts → Add:

| Field | Value |
|---|---|
| Domain Names | `vault.your-domain.duckdns.org` |
| Scheme | `http` |
| Forward Hostname / IP | `YOUR_SERVER_IP` |
| Forward Port | `8087` |
| Websockets Support | **On** (needed for live sync) |
| SSL | Wildcard certificate, Force SSL on |

### 3.5 First-run checklist

1. Open `https://vault.your-domain.duckdns.org` and create your account (a strong master password is the one thing that cannot be recovered).
2. Set `SIGNUPS_ALLOWED: "false"` and run `sudo docker compose up -d` to recreate the container.
3. Confirm `/admin` is reachable using the password you hashed in 3.1.
4. Back up `/opt/vaultwarden/data/` (it holds the vault database).

---

## 4. CrowdSec

CrowdSec does the **detection**: it parses logs and decides who is malicious. It blocks nothing by itself; that is the bouncer's job (section 5).

### 4.1 Compose file

`/opt/crowdsec/docker-compose.yml`:

```yaml
services:
  crowdsec:
    image: crowdsecurity/crowdsec:latest
    container_name: crowdsec
    restart: unless-stopped
    environment:
      COLLECTIONS: "crowdsecurity/linux crowdsecurity/sshd crowdsecurity/nginx"
      GID: "4"        # must match the host's "adm" group (see Problems & Solutions)
    volumes:
      - ./config:/etc/crowdsec
      - ./data:/var/lib/crowdsec/data
      - /var/log/auth.log:/var/log/auth.log:ro
      - /opt/nginx-proxy-manager/data/logs:/var/log/nginx:ro
    ports:
      - "8080:8080"   # local API (the bouncer connects here)
```

```bash
mkdir -p /opt/crowdsec/{config,data}
cd /opt/crowdsec
sudo docker compose up -d
```

> `docker compose pull` only downloads the image. You must run `up -d` before `docker exec` can find the container.

### 4.2 Log acquisition

Mounting the logs is not enough; CrowdSec must be told which files to read and which parser to use. `/opt/crowdsec/config/acquis.yaml` (replace the placeholder `/does/not/exist` entry):

```yaml
---
filenames:
  - /var/log/nginx/*access.log
labels:
  type: nginx
---
filenames:
  - /var/log/nginx/*error.log
labels:
  type: nginx
---
filenames:
  - /var/log/auth.log
labels:
  type: syslog
```

Recreate afterwards: `sudo docker compose up -d --force-recreate`.

### 4.3 Host prerequisite: `auth.log`

Debian 12 only writes `/var/log/auth.log` if rsyslog has a rule for it. `/etc/rsyslog.d/50-default.conf` must contain:

```
auth,authpriv.*                /var/log/auth.log
```

Then `sudo systemctl restart rsyslog` and test with `logger -p auth.info "test"`. The file should exist as a **regular file** (`-rw-r----- root adm`), not a directory.

### 4.4 Verify parsing

```bash
sudo docker logs crowdsec --tail 50
sudo docker exec -it crowdsec cscli metrics
```

Good signs:
- `Starting tail ...` lines for each `proxy-host-N_*.log` and `auth.log`
- An *Acquisition Metrics* table with non-zero "Lines read"
- Parser hits for `crowdsecurity/nginx-logs`, `http-logs` and `syslog-logs`

> Generic syslog lines show as "unparsed" in the acquisition table. That is expected: only real SSH events (logins/failures) match the `sshd` scenarios.

### 4.5 Generate the bouncer API key

```bash
sudo docker exec -it crowdsec cscli bouncers add firewall-bouncer
```

The key is shown **once**. Store it somewhere safe (password manager), not in the repo.

---

## 5. Firewall bouncer

### 5.1 Why native, not Docker

There is no official CrowdSec Docker image for the firewall bouncer (`crowdsecurity/cs-firewall-bouncer` does not exist on Docker Hub). It also needs deep host access to netfilter, so the supported route is the native apt package.

### 5.2 Install

```bash
curl -s https://install.crowdsec.net | sudo sh
sudo apt install crowdsec-firewall-bouncer-iptables -y
```

The installer prints *"cscli/crowdsec is not present, please set the API key manually"*. That is expected, because CrowdSec runs in a container, not on the host.

### 5.3 Configure

`/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml`:

```yaml
api_url: http://127.0.0.1:8080/
api_key: YOUR_BOUNCER_KEY
mode: iptables
```

```bash
sudo systemctl restart crowdsec-firewall-bouncer
sudo systemctl status crowdsec-firewall-bouncer
sudo docker exec -it crowdsec cscli bouncers list
```

`bouncers list` should show `firewall-bouncer` as valid with a recent "Last API pull".

### 5.4 How it appears on Debian 12

Debian 12 uses nftables with an `iptables-nft` compatibility layer. This changes what you see:

| Thing | Name / where |
|---|---|
| Chain | `CROWDSEC_CHAIN` (underscore, not a hyphen), in the `ip filter` table, jumped to from `INPUT` |
| ipset | `crowdsec-blacklists-0` (note the `-0` suffix) |
| `iptables -L CROWDSEC-CHAIN` | Fails with *"incompatible, use 'nft' tool"*. Use `nft` or `ipset` instead |
| `nft list tables` | No `inet crowdsec` table exists, because iptables mode lives inside `ip filter` |

```bash
sudo nft list table ip filter | grep -A 3 CROWDSEC
sudo ipset list crowdsec-blacklists-0
```

### 5.5 End-to-end test

```bash
# Ban a dummy IP for 2 minutes
sudo docker exec -it crowdsec cscli decisions add --ip 1.2.3.4 --duration 2m --reason "bouncer test"
sleep 12
sudo ipset list crowdsec-blacklists-0     # 1.2.3.4 should be listed under Members

# Remove it and confirm it disappears
sudo docker exec -it crowdsec cscli decisions delete --ip 1.2.3.4
sleep 12
sudo ipset list crowdsec-blacklists-0     # Number of entries: 0
```

Result: the ban appeared within seconds and was removed just as fast, which confirms detection → decision → firewall enforcement works.

### 5.6 Coverage of Docker-published ports (verify)

The test above proves the ban list is populated and cleared. It does not prove that a banned IP is blocked from reaching NPM.

The bouncer's chain is jumped to from `INPUT`, which handles traffic addressed to the host itself (SSH, for example). Ports published by Docker work differently: packets are NAT'd to the container and travel through the **`FORWARD`** path, where Docker's `DOCKER-USER` chain is evaluated first. `INPUT` rules never see that traffic.

Check which chains jump to the CrowdSec chain:

```bash
sudo nft list ruleset | grep -B3 -A1 -i crowdsec
```

If only `INPUT` shows up, add the Docker path to the bouncer config and restart it:

```yaml
iptables_chains:
  - INPUT
  - DOCKER-USER
```

Then test with a device that is not your admin session (a phone on mobile data, for example): ban its public IP for two minutes, try to load `https://vault.your-domain.duckdns.org`, and confirm the request times out. Delete the decision afterwards. Do not ban the IP you are managing the server from.

Result: `YOUR_RESULT`

---

## 6. Remote access: Tailscale

Tailscale gives private access to the homelab from anywhere over an encrypted WireGuard tunnel. Admin interfaces and internal services can then stay off the public internet, and the only things exposed publicly are the services deliberately forwarded on the router (`YOUR_PUBLIC_SERVICES`).

### 6.1 How it is set up

- Installed natively on the server (not in Docker), so it can manage routing and the network interface. Tailscale address: `YOUR_TAILSCALE_IP`.
- The server acts as a **subnet router**, advertising the internal subnets (`YOUR_ADVERTISED_SUBNETS`), so remote devices can reach LAN hosts that do not run Tailscale themselves.

```bash
# Allow the server to forward traffic (once)
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# Advertise the subnets
sudo tailscale up --advertise-routes=YOUR_ADVERTISED_SUBNETS
```

Advertised routes must also be **approved in the Tailscale admin console** before they work.

```bash
# Verify
tailscale status
tailscale ip -4
```

### 6.2 How remote devices reach services

| What | How |
|---|---|
| The server itself | Its Tailscale address or MagicDNS name |
| Other LAN devices | Through the advertised subnet routes |
| Web services behind NPM | `https://vault.your-domain.duckdns.org`, as long as the name resolves to an address the device can reach: `YOUR_REMOTE_DNS_SETUP` |

### 6.3 Things to be aware of

- **Remote access inherits what the server can reach.** Subnet routers masquerade by default, so remote traffic arrives on the LAN from the server's own address. In the VLAN design that means it is subject to the VLAN 10 inbound ACL, which currently permits everything except the ZTE subnet. Only advertise the subnets remote devices actually need.
- **CrowdSec and the tailnet.** SSH over Tailscale appears in `auth.log` with a `100.x` source address. CrowdSec's default whitelist covers private ranges, but I believe not Tailscale's `100.64.0.0/10` range, so a mistyped password over the tunnel could ban your own remote access. Check with `docker exec crowdsec cscli parsers inspect crowdsecurity/whitelists` and add the range if it is missing.
- **Tailscale does not cover everything.** It secures remote access to the homelab. It is not in the path of outbound traffic such as qBittorrent's peer connections (see section 10).

### 6.4 Hardening status

| Setting | Status |
|---|---|
| Multi-factor authentication on the account that owns the tailnet | `YOUR_STATUS` |
| Access controls (ACLs) limiting which devices can use the advertised routes | `YOUR_STATUS` |
| Node key expiry left enabled | `YOUR_STATUS` |
| Only the required subnets advertised | `YOUR_STATUS` |

---

## 7. Problems & Solutions

| # | Problem | Cause | Fix |
|---|---|---|---|
| 1 | `docker run ... vaultwarden hash` panicked with `No such device or address` | The command prompts for a password and needs a TTY | Add `-it` |
| 2 | Hash pasted into compose started mid-string and was invalid | Terminal output wrapped/scrolled and only part was copied | Widen the terminal and copy the full `$argon2id$v=19$...` string |
| 3 | Compose warned `The "argon2id" variable is not set` (also `v`, `m`, ...) and Vaultwarden still logged the plain-text token notice | Compose treats every `$` as the start of a variable | Escape each `$` as `$$` in the value |
| 4 | Vaultwarden at `http://IP:8087` showed the "not a secure context" error | WebCrypto requires HTTPS | Access it through the NPM proxy host with the wildcard cert |
| 5 | `docker exec crowdsec ...` returned *No such container* | `docker compose pull` does not start anything | Run `docker compose up -d` |
| 6 | CrowdSec metrics showed only the Local API table | `acquis.yaml` still held the `/does/not/exist` placeholder and the NPM log mount was a placeholder path | Point the mount at `/opt/nginx-proxy-manager/data/logs` and write a real `acquis.yaml` |
| 7 | Log said *"/var/log/auth.log is a directory, ignoring it"* | The host path didn't exist when a container first bind-mounted it, so Docker created an empty **directory** there | `sudo rmdir /var/log/auth.log`, make sure rsyslog writes the file, then `docker compose down && up -d` |
| 8 | rsyslog did not recreate `auth.log` after restart | The `auth,authpriv.*` rule was missing from `50-default.conf` | Add the rule, restart rsyslog, test with `logger -p auth.info` |
| 9 | Container couldn't read `auth.log` (`root:adm`, mode 640) | `GID` in the compose file (`1000`) didn't match the host `adm` group | `getent group adm` returned `4`, so set `GID: "4"` |
| 10 | `docker compose up` failed: *pull access denied for crowdsecurity/cs-firewall-bouncer* | That image doesn't exist | Install `crowdsec-firewall-bouncer-iptables` via apt |
| 11 | Couldn't find the bouncer's rules: `iptables -L CROWDSEC-CHAIN` errored and `ipset list crowdsec-blacklists` was empty | nftables backend, chain is `CROWDSEC_CHAIN`, set is `crowdsec-blacklists-0` | Use `nft list table ip filter` and `ipset list crowdsec-blacklists-0` |

---

## 8. Useful commands

```bash
# What is CrowdSec seeing / doing?
sudo docker exec -it crowdsec cscli metrics
sudo docker exec -it crowdsec cscli alerts list
sudo docker exec -it crowdsec cscli decisions list
sudo docker exec -it crowdsec cscli scenarios list
sudo docker exec -it crowdsec cscli bouncers list

# Manually ban / unban
sudo docker exec -it crowdsec cscli decisions add --ip <IP> --duration 24h --reason "manual"
sudo docker exec -it crowdsec cscli decisions delete --ip <IP>

# Update detection rules
sudo docker exec -it crowdsec cscli hub update
sudo docker exec -it crowdsec cscli hub upgrade

# Bouncer
sudo systemctl status crowdsec-firewall-bouncer
sudo ipset list crowdsec-blacklists-0

# Tailscale
tailscale status
tailscale ip -4
```

---

## 9. Secrets handling

- Keep real values out of git: the Vaultwarden `ADMIN_TOKEN` hash, the bouncer API key, any Tailscale auth keys, and any `.env` files. Add them to `.gitignore` or commit only `*.example` versions.
- The Vaultwarden `data/` directory and `/opt/crowdsec/config/` are the two things worth backing up.

---

## 10. Not implemented / future work

- **OpenResty (nginx-layer) CrowdSec bouncer: skipped for now.** It would give per-request, per-site blocking and CAPTCHA remediation, but NPM would have to be replaced by a third-party fork that bundles the Lua bouncer. Running an unofficial image in front of every service (Vaultwarden included) was judged not worth the risk. The firewall bouncer blocks banned IPs for host-level traffic, and for Docker-published ports once the check in [section 5.6](#56-coverage-of-docker-published-ports-verify) is done.
- **Web UI for CrowdSec.** Everything is currently managed with `cscli`. The built-in `cscli dashboard` (Metabase) is deprecated; options are the hosted CrowdSec Console or a self-hosted third-party UI such as `crowdsec-web-ui`.
- **Bind the CrowdSec API to localhost.** The compose file publishes `8080:8080` on all interfaces. Since the bouncer talks to `127.0.0.1:8080`, changing it to `127.0.0.1:8080:8080` removes the exposure.
- **Torrent traffic is not behind a VPN.** The plan is a `gluetun` container with qBittorrent attached via `network_mode: "service:gluetun"` for a killswitch, but it is on hold until a suitable VPN provider is chosen. Tailscale does not cover this: it only secures remote access to the homelab and is not in the path of qBittorrent's peer traffic.
- **Tailscale access controls.** Restrict which devices can use the advertised routes once the set of remote devices settles.
- **Unrelated apt warning.** The CrowdSec installer output included *"The repository 'packages.openmediavault.org/public sandworm' no longer has a Release file"*. It did not affect the install but the OMV apt source should be checked.

---

## 11. Related documentation

- [vlan-segmentation-project.md](vlan-segmentation-project.md): network-level segmentation and ACLs
- [pihole-lancache-dns.md](pihole-lancache-dns.md): Pi-hole and LanCache DNS design
- [network-setup.md](network-setup.md): network overview and published services
