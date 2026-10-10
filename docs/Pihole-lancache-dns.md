# Pi-hole and LanCache DNS Coexistence

**Status:** Active. The design has evolved since the first solution (see [How the design evolved](#how-the-design-evolved)).

## Summary

Pi-hole (network-wide ad blocking and DNS) and LanCache (game download caching) both need to answer DNS queries. LanCache works by returning its own IP for game CDN hostnames, so clients download from the cache instead of the internet. Running both on the same server created a port 53 conflict. The fix is to let Pi-hole be the only DNS server clients talk to, and have it hand the game CDN hostnames to LanCache's DNS.

---

## Background

| Service | Role | Needs |
|---------|------|-------|
| Pi-hole | DNS and ad blocking for every client | Port 53 |
| LanCache DNS | Answers game CDN hostnames with the cache's IP | Clients must be able to reach it for those hostnames |

Clients are given Pi-hole as their only DNS server. If LanCache's DNS is not consulted for game domains, downloads bypass the cache entirely.

---

## Problem

Both services wanted port 53 on the same server, and changing LanCache's port seemed to break its ability to receive DNS queries for gaming domains.

### What didn't work

- Changing LanCache's DNS to an alternate port (clients could not use it directly)
- Port forwarding from Pi-hole to LanCache
- Moving Pi-hole into the LanCache docker-compose file
- Setting Pi-hole's upstream DNS to the server IP

---

## How the design evolved

### Version 1: manual local DNS records

Gaming domains were added by hand to Pi-hole's local DNS records, all pointing to the server IP.

- **Worked:** Pi-hole handled ad blocking while LanCache cached downloads from Steam, Epic Games and others.
- **Drawback:** every CDN hostname had to be maintained manually in Pi-hole.

### Version 2 (current): forward CDN hostnames to LanCache's DNS

LanCache now has its own virtual IP (`YOUR_LANCACHE_IP`) on the server's network interface, and its DNS listens on **port 5053**. Pi-hole stays the only DNS server clients use, and forwards the game CDN hostnames to LanCache's DNS on that port.

```
Client ──► Pi-hole (port 53)
              │
              ├── normal domains ───────► upstream DNS (with ad blocking)
              │
              └── game CDN hostnames ───► LanCache DNS (YOUR_LANCACHE_IP, port 5053)
                                              └── returns the LanCache IP
```

Pi-hole v6 accepts custom dnsmasq lines through its config. An example (replace with your own domain list):

```bash
# Example only: forward one CDN domain to LanCache's DNS on port 5053
sudo pihole-FTL --config misc.dnsmasq_lines '["server=/steamcontent.com/YOUR_LANCACHE_IP#5053"]'
```

Each `server=/domain/ip#port` line sends queries for that domain to LanCache's DNS. The domain list comes from the LanCache project's maintained list of CDN domains.

### Verifying it works

```bash
# A game CDN hostname should resolve to the LanCache IP
dig steamcontent.com @YOUR_PIHOLE_IP

# A normal domain should resolve normally (and ads should still be blocked)
dig example.com @YOUR_PIHOLE_IP
```

---

## Related issue: house devices unable to reach Pi-hole (historical)

**Problem:** Devices on the house network could not send DNS queries to Pi-hole or LanCache on the server, even with the server IP set as primary DNS and routing rules configured on both routers.

**Diagnosis:** The ZTE router's WAN firewall was dropping DNS packets arriving from the house network segment.

**Workaround at the time:** Enabled DMZ on the ZTE with the server as the DMZ host, which stopped the filtering and forwarded traffic straight to the server. All devices then used Pi-hole for DNS.

**Status:** Superseded. The network is now routed by a Cisco 1941 with VLANs, and the ZTE is isolated on its own VLAN. It is no longer in the path between clients and the server, so this workaround is no longer needed.

---

## Result

- Pi-hole provides network-wide ad blocking and local DNS records
- LanCache serves cached game downloads without any port 53 conflict
- Clients only ever need Pi-hole as their DNS server

## Lessons learned

- Keep one DNS server in front of clients and let it forward by domain, instead of trying to run two servers on the same port.
- Forwarding by domain is easier to maintain than duplicating every CDN hostname as a local record.
- A firewall dropping DNS between segments looks exactly like a DNS server problem. Check the path before changing the server.