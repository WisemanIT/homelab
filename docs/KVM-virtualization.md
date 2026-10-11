# KVM Virtualization: EVE-NG and Home Assistant on OpenMediaVault

**Status:** Active. Gaps are marked with `YOUR_...` placeholders to fill from the live configuration. All IPs and MAC addresses are sanitized.

## Summary

The OpenMediaVault server runs two virtual machines under **QEMU/KVM**, managed with libvirt (`virsh`):

| VM | Purpose |
|----|---------|
| EVE-NG | Network emulation for Cisco labs, hosting the vWLC that manages the Cisco AP |
| Home Assistant OS | Home automation, camera integration and alerts |

Both attach to a Linux bridge (`br1`) running on a dedicated **Cudy 1G NIC**, which keeps VM traffic separate from the host's onboard NIC. Docker handles the rest of the services, and VMs are used only where a container does not fit.

---

## Why VMs instead of containers

- **Home Assistant OS** is deployed as a VM to get the full Supervisor, add-on store (Mosquitto, SSH terminal) and update pipeline. The container install does not include these.
- **EVE-NG** is a full appliance that runs its own network device images, so it needs its own virtual machine.

---

## Host prerequisites

| Item | Detail |
|------|--------|
| Host OS | OpenMediaVault (Debian Bookworm) |
| Hypervisor | QEMU/KVM with libvirt |
| CPU | Intel Core i5-6500TE (4 cores) |
| VM NIC | Cudy 1G NIC (`YOUR_CUDY_NIC_INTERFACE`) bridged as `br1` |

EVE-NG runs router and controller images of its own, so it relies on **nested virtualization**. Check it is enabled on the host:

```bash
cat /sys/module/kvm_intel/parameters/nested
# Y or 1 means nested virtualization is on
```

Result: Y

---

## VM inventory

| VM | vCPUs | RAM | Disk | Firmware | Network | Autostart |
|----|-------|-----|------|----------|---------|-----------|
| `homeassistant` | 2 | 2048 MB | virtio qcow2 | UEFI | `br1` (virtio) | Yes |
| `EVE-NG` | 2 | 8192 MB | `YOUR_EVENG_DISK` | vwlc-8.3.102.0 | `br1` | Yes |

### Home Assistant OS

```bash
# Download and extract the HAOS qcow2 image
wget -O /srv/.../haos.qcow2.xz \
  https://github.com/home-assistant/operating-system/releases/download/14.2/haos_ova-14.2.qcow2.xz
xz -d /srv/.../haos.qcow2.xz

# Create the VM bridged to br1
virt-install \
  --name homeassistant \
  --os-variant generic \
  --ram 2048 \
  --vcpus 2 \
  --disk /srv/.../haos.qcow2,bus=virtio \
  --import \
  --network bridge=br1,model=virtio \
  --graphics none \
  --noautoconsole \
  --boot uefi
```

### EVE-NG and the vWLC

EVE-NG hosts the Cisco virtual WLC as a node inside a lab. See [cisco-ap-conversion.md](cisco-ap-conversion.md) for the controller and AP configuration.

---

## Networking

### Bridge on a dedicated NIC

VMs attach to `br1`, a Linux bridge whose physical port is the Cudy NIC:

```
Cudy 1G NIC ──► br1 ──┬── homeassistant (virtio)
                      └── EVE-NG (virtio)
                              └── vWLC (inside EVE-NG)

Onboard NIC (eno1) ──► host services (OMV, Docker, Pi-hole)
```

**Why a bridge and not macvtap.** With macvtap, a VM cannot talk to the host's own physical NIC or to devices that reach the host through it, so the physical AP could not reach the vWLC. A real Linux bridge allows full two-way communication between physical and virtual devices.

**Why a dedicated NIC.** The bridge first ran on a USB Ethernet adapter, which was unstable and was also involved in an asymmetric routing problem on the host. A dedicated Cudy NIC fixed both. The full story is in [asymmetric-routing-kvm-bridge.md](asymmetric-routing-kvm-bridge.md).

### Host routes, not a subnet route

`br1` has host routes only for the VMs it must reach, so the host keeps `eno1` as its single default path:

```bash
nmcli connection modify br1 +ipv4.routes "YOUR_VM_IP/32 0.0.0.0 50"
```

### Fixed MAC addresses and DHCP reservations

libvirt stores each VM's MAC address in its persistent XML, so the address survives reboots. The Cisco 1941 hands out reserved addresses by MAC, so the reservation has to match the right VM:

```bash
# Show a VM's interface and MAC
virsh -c qemu:///system domiflist homeassistant

# Or read the persistent definition
virsh -c qemu:///system dumpxml homeassistant | grep "mac address"
```
---

## Autostart and recovery

Both VMs start with the host so the lab and automations come back after a power outage:

```bash
sudo virsh autostart homeassistant
sudo virsh autostart EVE-NG

# Confirm
virsh list --all --autostart
```

After an outage, bring-up also depends on the network side: DHCP reservations on the 1941 must be saved to startup-config, otherwise the VMs come back with different addresses (see [vlan-segmentation-project.md](vlan-segmentation-project.md)).

---

## Common commands

```bash
# VM state
sudo virsh list --all
sudo virsh start EVE-NG
sudo virsh shutdown homeassistant

# Bridge
bridge link show br1

# Resource use
sudo virsh domstats --cpu-total --balloon homeassistant
```

---

## Problems Solved

### 1. VMs cannot talk to physical devices (macvtap)

**Problem:** The physical AP could not reach the vWLC inside EVE-NG.

**Root cause:** macvtap does not allow communication between a VM and the host's physical NIC path.

**Solution:** Replace macvtap with a Linux bridge (`br1`) and attach the VMs to it.

Details: [cisco-ap-conversion.md](cisco-ap-conversion.md).

### 2. Server unreachable when the VM NIC was unplugged

**Problem:** The host lost all connectivity whenever the USB adapter behind `br1` was removed.

**Root cause:** Asymmetric routing. Both `eno1` and `br1` had subnet routes on the same network.

**Solution:** Host routes only on `br1`, then a dedicated Cudy NIC in place of the USB adapter.

Details: [asymmetric-routing-kvm-bridge.md](asymmetric-routing-kvm-bridge.md).

### 3. Wrong VM got the wrong DHCP reservation

**Problem:** A DHCP reservation on the 1941 pointed at the wrong VM, so Home Assistant and EVE-NG had their MAC addresses mixed up.

**Root cause:** `YOUR_ROOT_CAUSE` (the reservation was written against the wrong VM's MAC).

**Solution:** Read each VM's MAC from libvirt (`domiflist` or `dumpxml`) and correct the bindings.

**Result:** Each VM keeps its reserved address across reboots.

### 4. Services slowing the host as VMs accumulate

**Problem:** The 4-core host slowed down as more services and VMs were added.

**Status:** Open. Moving some workloads, such as local text-to-speech, to a separate machine is being considered. See [Capacity notes](#capacity-notes).

---

## Capacity notes

The host has four cores shared between Docker services, Frigate's inference, and two VMs (one of them running nested lab nodes). The current approach to relieving load:

- Keep VMs small (Home Assistant runs on 2 vCPUs and 2 GB)
- Offload CPU-heavy extras (for example local TTS) to another machine instead of adding more to the host
- Watch per-VM CPU with `virsh domstats` before adding anything new

---

## Lessons learned

- Use a real bridge when VMs must talk to physical neighbours. macvtap isolates them from the host's NIC path.
- Give VMs their own NIC when the host and VMs share a subnet, and keep routes on the bridge specific.
- Check a VM's MAC in libvirt before writing a DHCP reservation, and save the reservation on the router.
- Enable autostart on every VM that automations or labs depend on, then test it with a real reboot.
- A small host runs out of CPU before RAM. Plan what runs where before adding another VM.

---

## Related documentation

- [asymmetric-routing-kvm-bridge.md](asymmetric-routing-kvm-bridge.md): the routing fix and the move to the Cudy NIC
- [cisco-ap-conversion.md](cisco-ap-conversion.md): EVE-NG, vWLC and AP deployment
- [frigate-nvr.md](frigate-nvr.md): Home Assistant VM deployment and camera integration
- [vlan-segmentation-project.md](vlan-segmentation-project.md): VLAN design and DHCP reservations
