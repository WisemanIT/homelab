# Asymmetric Routing on the Server (KVM Bridge on the Same Subnet)

**Status:** Resolved. The VM bridge (`br1`) now runs on a dedicated Cudy 1G NIC, which replaced the original USB Ethernet adapter (see [Follow-up](#follow-up-replacing-the-usb-adapter-with-a-cudy-1g-nic)).

## Summary

The server became completely unreachable whenever the USB Ethernet adapter used for the VM bridge was unplugged, even though the onboard NIC was connected and correctly configured. The cause was **asymmetric routing**: two interfaces on the same subnet, with replies leaving through the wrong one. The fix was to remove the bridge's subnet route and give it only the specific host routes it needs.

---

## Background

| Interface | Purpose | Managed by |
|-----------|---------|------------|
| `eno1` | Onboard NIC, primary server interface | OpenMediaVault (ifupdown) |
| `br1` | Linux bridge for the EVE-NG and vWLC virtual machines | NetworkManager |
| USB adapter (`enxYOUR_USB_ADAPTER_MAC`) | Physical port of `br1` | Not managed separately |

Both `eno1` and `br1` had addresses on the same subnet (`192.168.2.0/24`).

## Symptoms

- SSH, web interfaces and ping to the server all failed when the USB adapter was unplugged
- `eno1` was physically connected and showed the correct address
- Everything came back when the adapter was plugged in again

---

## Diagnosis

Requests from other devices arrived correctly on `eno1`, but the server's replies went out through `br1`. This is asymmetric routing.

The kernel had a subnet route for `192.168.2.0/24` on both interfaces. `br1`'s route appeared first in the routing table with no metric, so it was used for outbound traffic regardless of which interface received the request. When the USB adapter was unplugged, `br1` went down and took the server's outbound traffic with it.

Confirmed with `tcpdump`:

```bash
# Requests arriving correctly on eno1
sudo tcpdump -i eno1 -n icmp
# YOUR_CLIENT_IP > YOUR_SERVER_IP: ICMP echo request

# But replies leaving on the wrong interface
sudo tcpdump -i br1 -n icmp
# YOUR_SERVER_IP > YOUR_CLIENT_IP: ICMP echo reply
```

---

## What didn't work

- Removing the gateway line from `/etc/network/interfaces.d/br1`: the route kept coming back via NetworkManager
- Adding metric values to `br1` with `nmcli`: duplicate routes reappeared after reboots
- Creating a NetworkManager profile for `eno1`: OMV manages `eno1` through ifupdown, so NetworkManager kept marking it unmanaged
- `ip rule` policy routing: did not override the asymmetric behaviour in this configuration

---

## Solution

Remove the `192.168.2.0/24` subnet route from `br1` and replace it with only the specific host routes `br1` needs to reach.

```bash
# Remove the conflicting subnet route from br1
sudo ip route del 192.168.2.0/24 dev br1

# Add only the specific hosts br1 needs to reach
sudo ip route add YOUR_EVENG_IP/32 dev br1 src YOUR_BR1_IP   # EVE-NG
sudo ip route add YOUR_VWLC_IP/32 dev br1 src YOUR_BR1_IP    # vWLC
```

Made permanent through NetworkManager:

```bash
sudo nmcli connection modify br1 ipv4.never-default yes
sudo nmcli connection modify br1 +ipv4.routes "YOUR_EVENG_IP/32 0.0.0.0 50"
sudo nmcli connection modify br1 +ipv4.routes "YOUR_VWLC_IP/32 0.0.0.0 50"
sudo nmcli connection modify br1 ipv4.route-metric 1000
```

Stopped NetworkManager from treating the physical NIC as a standalone interface (it belongs to `br1` only):

```bash
sudo bash -c 'cat > /etc/NetworkManager/conf.d/unmanaged.conf << EOF
[keyfile]
unmanaged-devices=mac:YOUR_NIC_MAC_ADDRESS
EOF'
```

### Final routing table

```
default via YOUR_GATEWAY_IP dev eno1 proto static
192.168.2.0/24 dev eno1 proto kernel scope link src YOUR_SERVER_IP
YOUR_EVENG_IP dev br1 scope link src YOUR_BR1_IP
YOUR_VWLC_IP dev br1 scope link src YOUR_BR1_IP
```

### Verifying the fix

```bash
# Replies to a client should leave through eno1
ip route get YOUR_CLIENT_IP

# Unplug the VM NIC: the server must stay reachable over SSH, OMV and its services
```

---

## Result

- `eno1` is the sole default gateway and handles all server traffic
- `br1` carries only EVE-NG and vWLC traffic
- Unplugging the VM NIC no longer affects server connectivity
- EVE-NG and the Cisco AP/vWLC setup keep working normally when the NIC is present

---

## Follow-up: replacing the USB adapter with a Cudy 1G NIC

The USB adapter (a TP-Link UE300) caused more than the routing problem. It only behaved on a USB 2.0 port, because on USB 3.0 the `r8152` driver went into a firmware reset loop. It was always the weakest link in the VM networking.

It was replaced with a **Cudy 1G NIC** dedicated to the QEMU/KVM virtual machines (EVE-NG and Home Assistant). `br1` now sits on that NIC, and it has run without issues since.

**Migration notes**
- The `unmanaged-devices` entry is keyed by MAC address, so it must reference the Cudy NIC's MAC rather than the old adapter's.
- The interface name changes with the hardware (`YOUR_CUDY_NIC_INTERFACE`), so check any config that names it.
- Re-check the routing table afterwards: the host routes on `br1` and the single default route on `eno1` should look exactly as above.

---

## Lessons learned

- When two interfaces share a subnet, Linux uses whichever subnet route appears first for outbound traffic, regardless of which interface received the incoming packet.
- Never give a bridge a full subnet route when it shares that subnet with the primary NIC. Use specific host routes instead.
- A USB network adapter is a poor foundation for infrastructure. A dedicated NIC removed both the driver instability and a fragile dependency.
