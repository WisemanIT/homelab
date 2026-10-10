# Frigate NVR - Security Camera System

**Status:** Active. Updated for the VLAN-segmented network: both cameras are now **wired to the switch on the CCTV VLAN**. The earlier wireless setup is kept as history, including the latency problem that led to the change (see [Problem 12](#12-intermittent-latency-on-wireless-cameras-moved-to-wired)).

## Overview

This documents the deployment of Frigate NVR as a self-hosted, AI-powered security camera system integrated with Home Assistant. The system uses an Intel HD 530 iGPU via OpenVINO for hardware-accelerated object detection, two TP-Link Tapo C310 cameras on a dedicated CCTV VLAN, MQTT via Mosquitto for real-time event publishing, and Home Assistant automations for mobile notifications and recording.

The system was upgraded from the default SSDlite MobileNet V2 model (300×300) to a custom-built YOLOv9-t ONNX model (320×320) for improved detection accuracy on person, car, and bus classes.

The cameras were originally connected over Wi-Fi through an enterprise access point. Once the 24-port gigabit switch was installed, they were moved to wired connections to remove intermittent latency.

---

## Initial Deployment

### Why the Cisco AP Was Installed (history)

The Cisco Aironet AIR-CAP3602I-E-K9 was acquired and deployed primarily to provide reliable wireless coverage for the front yard camera, which is too far from the original routers. An enterprise AP was chosen over a consumer alternative for reliability: no disconnections, no stuttering, no latency issues under sustained load.

Before connecting cameras, the AP was validated using Steam Link wireless game streaming (Devil May Cry, Titanfall 2) for 5-7 hour sessions with zero disconnections. This confirmed the AP could handle high-bandwidth, low-latency wireless video.

### Why the cameras are now wired

The AP fixed the original connection problems, but latency to the cameras was inconsistent. It was 1-10 ms at night, fluctuated between 200 and 500 ms during the day, and worsened while the vWLC was connected. Once the switch was in place, both cameras were wired to it. The AP is now wired to the switch too. See [Problem 12](#12-intermittent-latency-on-wireless-cameras-moved-to-wired) for the analysis, and [cisco-ap-conversion.md](cisco-ap-conversion.md) for the AP and vWLC deployment.

### Frigate Initial Deployment

Frigate was deployed as a standalone Docker Compose stack at `/opt/frigate/` (separate from other containers) before cameras arrived, allowing the stack to be tested and configured in advance.

```bash
cd /opt/frigate
docker compose up -d
```

Web UI confirmed healthy at `http://YOUR_SERVER_IP:5000` with OpenVINO detector loaded and Intel GPU detected at 0% idle. Both camera slots showed "No frames received" as expected before physical cameras were connected.

### Home Assistant OS Deployment

HAOS was deployed as a KVM virtual machine (not a Docker container) to get the full Supervisor, add-on store, and update pipeline.

```bash
# Download and extract HAOS qcow2 image
wget -O /srv/.../haos.qcow2.xz \
  https://github.com/home-assistant/operating-system/releases/download/14.2/haos_ova-14.2.qcow2.xz
xz -d /srv/.../haos.qcow2.xz

# Create KVM VM bridged to br1
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

`br1` is the VM bridge, now running on the dedicated Cudy 1G NIC. HAOS received `YOUR_HA_IP` through DHCP (reserved), with MAC address `YOUR_HA_MAC`.

A specific host route was added to `br1` for HAOS, the same pattern as EVE-NG and the vWLC (see [asymmetric-routing-kvm-bridge.md](asymmetric-routing-kvm-bridge.md)):

```bash
nmcli connection modify br1 +ipv4.routes "YOUR_HA_IP/32 0.0.0.0 50"
```

VM autostart enabled to survive power outages:

```bash
virsh autostart homeassistant
```

---

## Hardware

| Device | Role | Notes |
|--------|------|-------|
| OMV server (Lenovo M900 motherboard, 2U rackmount chassis) | NVR host | Runs Frigate and the Home Assistant VM |
| Intel HD 530 iGPU | OpenVINO object detection | On-board |
| TP-Link Tapo C310 (x2) | 2K security cameras | Garage and front yard, wired to the switch |
| Netgear GS724Tv4 | Camera uplinks | Cameras on VLAN 20 (CCTV) |
| Cisco 1941 | Inter-VLAN routing and ACLs | Routes the CCTV VLAN to the server |
| 1 TB surveillance drive | Recordings storage | `YOUR_DISK_UUID` |

---

## Network Topology

```
Tapo C310 "garage" ──┐
                     ├── Netgear GS724Tv4 ── VLAN 20 CCTV (192.168.20.0/24)
Tapo C310 "front"  ──┘          │
                                │ 802.1Q trunk
                                ▼
                         Cisco 1941 (inter-VLAN routing, VLAN20-IN ACL)
                                │
                                ▼
                         VLAN 10 Core (192.168.2.0/24)
                         OMV server (YOUR_SERVER_IP)
                           ├── Frigate (Docker) - port 5000
                           ├── Home Assistant OS (KVM VM) - YOUR_HA_IP:8123
                           └── Mosquitto MQTT Broker (HA add-on) - port 1883
```

The cameras are reachable from the server because the Cisco 1941 routes between VLANs. The CCTV VLAN's inbound ACL lets the cameras reach the core VLAN and the internet, and keeps them from reaching the other internal VLANs. See [vlan-segmentation-project.md](vlan-segmentation-project.md) for the VLAN design and ACLs, and [network-setup.md](network-setup.md) for the network overview.

---

## Software Stack

| Component | Version | Role |
|-----------|---------|------|
| Frigate NVR | 0.17.1 | Object detection, recording, snapshots |
| Home Assistant OS | Latest | Automations, dashboard, notifications |
| Mosquitto Broker | 2.1.2 | MQTT message broker (HA Add-on) |
| Tapo: Camera Control | HACS | Camera integration in HA |
| OpenVINO | Built-in | Hardware-accelerated inference on iGPU |
| YOLOv9-t (ONNX) | Custom build | Object detection model (320×320) |

---

See [docker/frigate/config.yml](../docker/frigate/config.yml) for the full sanitized Frigate configuration.

See [docker/frigate/docker-compose.yml](../docker/frigate/docker-compose.yml) for the Docker Compose deployment file.

---

## Camera Stream Details

| Camera | Stream | Resolution | Codec | Role |
|--------|--------|------------|-------|------|
| Tapo C310 | stream1 | 2304×1296 | H.264 | Record |
| Tapo C310 | stream2 | 640×360 | H.264 | Detect |

Stream specifications confirmed via ffprobe:

```bash
/usr/lib/ffmpeg/7.0/bin/ffprobe -v error -rtsp_transport tcp \
  -show_streams "rtsp://USERNAME:PASSWORD@CAMERA_IP:554/stream1" \
  2>&1 | grep -E "width|height|codec_name"
```

---

## Detection Model

### Original Model

The system initially used Frigate's built-in SSDlite MobileNet V2 model served via OpenVINO:

```yaml
model:
  path: /openvino-model/ssdlite_mobilenet_v2.xml
  width: 300
  height: 300
  input_tensor: nhwc
  input_pixel_format: bgr
```

### Upgraded Model: YOLOv9-t (ONNX)

The model was upgraded to YOLOv9-t exported to ONNX format for better detection accuracy, especially for person and vehicle detection at distance.

#### Building the Model

The model is built via a Docker multi-stage build that clones the YOLOv9 repo, installs dependencies, and exports to ONNX. Run this once on the NVR host:

```bash
docker build . --build-arg MODEL_SIZE=t --build-arg IMG_SIZE=320 \
  --output /opt/frigate/config/model_cache -f- <<'EOF'
FROM python:3.11 AS build
RUN apt-get update && apt-get install --no-install-recommends -y libgl1 cmake \
    && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:0.8.0 /uv /bin/
WORKDIR /yolov9
ADD https://github.com/WongKinYiu/yolov9.git .
RUN uv pip install --system -r requirements.txt
RUN uv pip install --system onnx==1.18.0 onnxruntime onnxscript
ARG MODEL_SIZE
ARG IMG_SIZE
ADD https://github.com/WongKinYiu/yolov9/releases/download/v0.1/yolov9-${MODEL_SIZE}-converted.pt \
    yolov9-${MODEL_SIZE}.pt
RUN sed -i "s/ckpt = torch.load(attempt_download(w), map_location='cpu')/ckpt = torch.load(attempt_download(w), map_location='cpu', weights_only=False)/g" \
    models/experimental.py
RUN python3 export.py --weights ./yolov9-${MODEL_SIZE}.pt --imgsz ${IMG_SIZE} --include onnx
FROM scratch
ARG MODEL_SIZE
ARG IMG_SIZE
COPY --from=build /yolov9/yolov9-${MODEL_SIZE}.onnx /yolov9-${MODEL_SIZE}-${IMG_SIZE}.onnx
EOF
```

Output: `/opt/frigate/config/model_cache/yolov9-t-320.onnx` (~9.3MB)

Available model sizes (MODEL_SIZE arg):

| Size | Parameters | Use case |
|------|-----------|----------|
| t | 2M (tiny) | Low-power hardware like HD 530 |
| s | 7M (small) | Better accuracy, more GPU load |
| m | 20M (medium) | Discrete GPU recommended |

#### Frigate Configuration for YOLOv9

The `model` block must be **top-level** in config.yml, not nested under `detectors`:

```yaml
detectors:
  ov:
    type: openvino
    device: GPU

model:
  model_type: yolo-generic
  width: 320
  height: 320
  input_tensor: nchw
  input_dtype: float
  path: /config/model_cache/yolov9-t-320.onnx
  labelmap_path: /labelmap/coco-80.txt
```

The model_cache directory must also be mounted in docker-compose.yml:

```yaml
volumes:
  - ./config.yml:/config/config.yml
  - ./config/model_cache:/config/model_cache
```

---

## MQTT Setup

### Mosquitto Broker (Home Assistant Add-on)

1. Install **Mosquitto broker** via HA Add-on Store
2. In Add-on Options, add login entry:
   ```yaml
   logins:
     - username: frigate-mqtt
       password: "YOUR_PASSWORD"
   ```
3. Disable **Customize → active** to prevent `/share/mosquitto` directory error on startup
4. Start add-on with **Start on boot** and **Watchdog** enabled
5. HA auto-detects MQTT integration under Settings → Devices & Services

### Frigate MQTT User

- Created manually under HA → Settings → People → Users
- Username: `frigate-mqtt`
- Group: Users (not admin)
- Password must match `config.yml` mqtt.password

### Verifying MQTT Connection

```bash
docker restart frigate && sleep 15 && \
docker logs frigate --since 1m 2>&1 | grep -i mqtt
```

Expected: no `MQTT disconnected` errors after startup.

Live event monitoring via HA: Settings → Devices & Services → MQTT → Configure → Listen to topic: `frigate/#`

---

## Home Assistant Integration

### Tapo: Camera Control (HACS)

Standard HA integrations (TP-Link Smart Home, ONVIF) failed due to SSL handshake errors and, in the original two-subnet layout, cross-subnet routing issues. Tapo: Camera Control installed via HACS resolved both.

**Installation path:** Settings → Add-ons → Advanced SSH & Web Terminal → run HACS install script → restart → HACS → Integrations → search Tapo: Camera Control → download → restart

Both cameras appear as devices with motion detection entities, stream entities, and image snapshot entities.

### Original automations (Tapo motion-based)

#### Security Detect - Front Yard

```
Trigger:  Front Yard Cam Cell Motion Detection → changes TO Detected
Condition: Time between 07:30 and 16:30
Actions:
  1. Camera: Record camera feed
       Target: HD Stream (Front Yard Cam)
       Filename: /media/front_yard_{{ now().strftime('%Y%m%d_%H%M%S') }}.mp4
       Duration: 30 seconds
  2. Send notification → YOUR_MOBILE_DEVICE
       Title: Front Yard Camera Detection
       Message: Person Detected at the Front Yard at {{ now().strftime('%H:%M') }}
```

#### Security Detect - Garage

```
Trigger:  Garage Cam Cell Motion Detection → changes TO Detected
Condition: Time between 07:30 and 16:30
Actions:
  1. Camera: Record camera feed
       Target: HD Stream (Garage Cam)
       Filename: /media/garage_{{ now().strftime('%Y%m%d_%H%M%S') }}.mp4
       Duration: 30 seconds
  2. Send notification → YOUR_MOBILE_DEVICE
       Title: Garage Camera Detection
       Message: Person Detected at the Garage at {{ now().strftime('%H:%M') }}
```

### Later additions

- **go2rtc restreaming (port 8554):** the cameras' firmware allows only one RTSP session at a time. go2rtc holds that single connection and restreams it to Frigate and any other consumer.
- **Storage:** recordings were migrated to a dedicated 1 TB surveillance drive (`YOUR_DISK_UUID`). Recordings and `frigate.db` persist through the `./config:/config` mount.
- **Person-detection alerts:** a WhatsApp message goes to the family group when a person is detected at 75% confidence or higher.
- **Alarm control panel:** `alarm_control_panel.home_security` (manual platform) is integrated with IRIS for voice arm and disarm.

---

## Detector Performance

Confirmed via `frigate/stats` MQTT topic after full startup:

| Metric | Value |
|--------|-------|
| Detector type | OpenVINO (ov) |
| Model | YOLOv9-t ONNX (320×320) |
| Inference speed | ~10-12ms |
| GPU utilisation | Intel VAAPI (HD 530) |
| Garage detection fps | ~3-5 fps |
| Front detection fps | ~1-3 fps |
| Both cameras | detection_enabled: true |

The front camera figure was measured while it was still on Wi-Fi. Re-measure now that it is wired: `YOUR_WIRED_FRONT_FPS`.

Hardware acceleration confirmed active on both ffmpeg processes:

```
-hwaccel vaapi -hwaccel_device /dev/dri/renderD128
```

---

## Problems Solved

### 0. USB Ethernet Adapter Reset Loop (RTL8153 on USB 3.0)

**Problem:** The TP-Link UE300 USB ethernet adapter (`enxYOUR_USB_ADAPTER_MAC`, RTL8153 chip) entered a continuous reset loop when plugged into a USB 3.0 port, causing br1 to lose its physical member interface repeatedly. Symptoms:

```
r8152-cfgselector 2-7: device not accepting address, error -71
r8152 2-7:1.0: Write USB fw fail
r8152 2-7:1.0: Write PLA fw fail
interface index incrementing every few seconds (200, 201, 202...)
```

**Root cause:** The r8152 Linux driver attempts to push firmware to the RTL8153 chip during USB 3.0 (SuperSpeed) enumeration. The USB 3.0 controller timed out during this firmware upload (error -71 = EPROTO), causing the driver to reset and re-enumerate the device in a loop. The adapter works correctly on Windows because Realtek's Windows driver handles firmware differently. ModemManager also worsened the issue by probing the interface as a potential modem on each re-enumeration.

**Solution (two steps):**

1. Move the adapter to a **USB 2.0 port**. On USB 2.0, the driver skips the SuperSpeed firmware upload entirely and the adapter enumerates stably. Confirmed by the adapter moving from Bus 002 (3.0) to Bus 001 (2.0) in `lsusb`.

2. Disable ModemManager to prevent it from probing the adapter:

```bash
sudo systemctl stop ModemManager
sudo systemctl disable ModemManager
```

**Result:** Adapter stable on USB 2.0, with no further reset loops.

**Status:** Superseded. The USB adapter was replaced by a dedicated Cudy 1G NIC, which has run without issues since. See [asymmetric-routing-kvm-bridge.md](asymmetric-routing-kvm-bridge.md).

---

### 1. Frigate Auth Service 502 Errors on Startup

**Problem:** Docker logs flooded with nginx 502 errors on every startup referencing `127.0.0.1:5001/auth`.

**Root cause:** Frigate's internal auth backend (port 5001) starts a few seconds after nginx. Nginx attempts auth requests before the backend is ready, producing 502s.

**Solution:** Not a real error. It resolves itself within about 10 seconds of container startup and is safe to ignore. Filter it out when grepping logs:

```bash
docker logs frigate 2>&1 | grep -v "nginx\|auth\|502\|connect()"
```

---

### 2. Front Yard Camera ffmpeg Process Crash Loop (wireless era)

**Problem:** The front yard camera entered a continuous crash/restart loop with these errors:

```
[aac @ ...] Queue input is backward in time
[vost#0:0/copy @ ...] Non-monotonic DTS; previous: XXXXX, current: XXXXX
frigate.video ERROR: front: Unable to read frames from ffmpeg process
watchdog.front ERROR: Ffmpeg process crashed unexpectedly for front
```

**Root cause:** The camera was sending malformed RTSP timestamps over the wireless path through the Cisco AP. The unstable path introduced just enough disruption to corrupt the timestamp stream, and ffmpeg's default TCP transport could not tolerate it. This was most likely an early symptom of the same wireless instability described in [Problem 12](#12-intermittent-latency-on-wireless-cameras-moved-to-wired).

**Solution:** Added `preset-rtsp-udp` as ffmpeg input args for the front camera:

```yaml
front:
  ffmpeg:
    input_args: preset-rtsp-udp
```

UDP transport is more tolerant of timestamp irregularities and eliminated the crash loop.

**Status:** The camera is now wired, so the wireless path that caused this no longer exists. Review whether the UDP preset is still needed on the wired connection: `YOUR_CURRENT_INPUT_ARGS`.

---

### 3. Mosquitto Broker Crash Loop After Configuration

**Problem:** After adding login credentials to Mosquitto's configuration, the broker entered a continuous restart loop:

```
Error: Unable to open include_dir '/share/mosquitto'
mosquitto version 2.1.2 terminating
```

**Root cause:** The **Customize** section in Mosquitto's Add-on options had `active: true` with `folder: mosquitto`. This instructed Mosquitto to load additional config files from `/share/mosquitto`, a directory that does not exist in a default HA installation.

**Solution:** In HA → Settings → Add-ons → Mosquitto broker → Configuration → Customize section → toggle **active** to **off**. Save and restart the add-on.

**Result:** Mosquitto started cleanly. Frigate connected successfully, confirmed by Mosquitto logs:

```
New client connected from YOUR_SERVER_IP as frigate (u'frigate-mqtt')
```

---

### 4. Frigate MQTT Disconnecting Immediately After Connect

**Problem:** Frigate connected to Mosquitto then disconnected within seconds. Docker logs showed:

```
[frigate.comms.mqtt] ERROR: MQTT disconnected
```

**Root cause:** The `frigate-mqtt` user was created in HA → People → Users but the password set there was not reflected in Mosquitto's Add-on login configuration. Mosquitto authenticated against its own login list, not the HA user database directly.

**Solution:** The Mosquitto Add-on login entry (`logins:` in Add-on Options) must explicitly list the username and password. Setting the password only in HA Users is not sufficient. Both must match.

**Result:** Persistent MQTT connection established. Confirmed via live topic subscription to `frigate/#` in HA MQTT developer tools showing `frigate/stats` payloads every 60 seconds and `frigate/garage/status/detect: online` heartbeats.

---

### 5. TP-Link Smart Home Integration SSL Failure

**Problem:** HA TP-Link Smart Home integration failed to connect to the garage camera with:

```
[SSL: SSLV3_ALERT_HANDSHAKE_FAILURE]
ClientConnectorSSLError on port 443
```

**Root cause:** The Tapo C310 uses a proprietary SSL implementation that is incompatible with the standard TP-Link Smart Home integration's TLS handshake.

**Solution:** Replaced the TP-Link Smart Home integration with **Tapo: Camera Control** (HACS custom integration). It handles Tapo's authentication correctly and exposes full camera entities including motion detection, stream, and snapshots.

**Result:** Both cameras integrated successfully with full entity support in HA.

---

### 6. YOLOv9 ONNX Export: onnxsim Version Conflict

**Problem:** Initial Docker build for YOLOv9 ONNX export failed with:

```
× Failed to download and build onnxsim==0.6.2
╰─▶ Package metadata version 0.4.36 does not match given version 0.6.2
```

**Root cause:** `onnx-simplifier>=0.4.1` resolved to v0.5.0, which pulled in `onnxsim==0.6.2`. The onnxsim package had a broken metadata version mismatch that caused uv to reject it.

**Solution:** Remove `onnx-simplifier` entirely and drop the `--simplify` flag from the export command. The model is slightly larger but fully functional:

```dockerfile
RUN uv pip install --system onnx==1.18.0 onnxruntime onnxscript
RUN python3 export.py --weights ./yolov9-${MODEL_SIZE}.pt \
    --imgsz ${IMG_SIZE} --include onnx
```

---

### 7. YOLOv9 Export: Missing onnxscript Module

**Problem:** After removing onnx-simplifier, the export script failed silently (exit 0, no .onnx file produced). Running the export interactively revealed:

```
ONNX: export failure ❌ 0.2s: No module named 'onnxscript'
```

**Root cause:** PyTorch 2.11 uses `onnxscript` internally for its ONNX export path. The YOLOv9 requirements.txt does not include it, so it was missing from the build environment.

**Solution:** Add `onnxscript` to the pip install step:

```dockerfile
RUN uv pip install --system onnx==1.18.0 onnxruntime onnxscript
```

**Result:** Export completed successfully, producing `yolov9-t.onnx` in `/yolov9/` inside the build container.

---

### 8. YOLOv9 ONNX File Not Found After Successful Build

**Problem:** The Docker build completed without errors but the final COPY step in the scratch stage failed:

```
ERROR: "/yolov9/yolov9-t.onnx": not found
```

**Root cause:** The export script ran but produced no output because `onnxscript` was missing (see Problem 7). The build layer was cached from a previous run where the export also failed silently, so Docker used the cached (empty) layer.

**Solution:** Add `--no-cache` to force a clean rebuild after fixing dependencies, or ensure the pip install layer is invalidated by changing its content. Once `onnxscript` was added, a clean build produced the file correctly.

---

### 9. Frigate model path NoneType Error

**Problem:** After configuring the YOLOv9 model, Frigate crashed on startup with:

```
TypeError: stat: path should be string, bytes, os.PathLike or integer, not NoneType
```

**Root cause:** In Frigate 0.17, the `model` block must be defined at the **top level** of config.yml, not nested inside the `detectors` block. Nesting it under `detectors` caused Frigate to not parse the path at all, leaving it as None.

**Incorrect structure:**

```yaml
detectors:
  ov:
    type: openvino
    device: GPU
    model:           # ← WRONG: nested under detector
      path: /config/model_cache/yolov9-t-320.onnx
```

**Correct structure:**

```yaml
detectors:
  ov:
    type: openvino
    device: GPU

model:               # ← CORRECT: top-level key
  path: /config/model_cache/yolov9-t-320.onnx
```

---

### 10. Frigate Cannot Find Model File (Volume Not Mounted)

**Problem:** After fixing the config structure, Frigate started but immediately crashed with:

```
FileNotFoundError: OpenVINO model file /config/model_cache/yolov9-t-320.onnx not found.
```

**Root cause:** The docker-compose.yml only mounted `./config.yml` as a single file, not the entire `./config/` directory. The `model_cache/` subdirectory was therefore invisible to the container.

**Solution:** Add an explicit volume mount for the model cache directory in docker-compose.yml:

```yaml
volumes:
  - ./config.yml:/config/config.yml
  - ./config/model_cache:/config/model_cache   # ← add this
```

**Result:** Frigate located the model file and the detector started successfully.

---

### 11. Invalid model_type Value

**Problem:** Frigate rejected the config with:

```
Line 14: detectors -> ov -> model -> model_type
Input should be 'dfine', 'rfdetr', 'ssd', 'yolox', 'yolonas' or 'yolo-generic'
```

**Root cause:** The value `model_type: yolov9` is not a valid Frigate model type. Frigate 0.17 uses generic type names.

**Solution:** Use `model_type: yolo-generic` for any YOLOv9 model.

---

### 12. Intermittent Latency on Wireless Cameras (moved to wired)

**Problem:** While the cameras were connected through the Cisco AP, latency to them was 1-10 ms at night but fluctuated between roughly 200 and 500 ms during the day. It got worse again whenever the vWLC was connected to the AP. The latency was measured with `YOUR_MEASUREMENT_METHOD`.

**What the pattern points to:** Two separate effects, which were not isolated from each other:

1. **Shared airtime on 2.4 GHz.** The Tapo C310 is a 2.4 GHz-only camera, and that band has just three non-overlapping channels. During the day, neighbouring networks, other clients and non-Wi-Fi interference compete for airtime, causing retransmissions and latency spikes. At night the band is quiet. Enterprise features such as CleanAir and RRM help with channel and power choices, but cannot remove contention from networks outside your control.
2. **Client traffic tunnelled through the vWLC.** If the WLAN is not locally switched (the FlexConnect default), every client packet is encapsulated in the CAPWAP data tunnel (UDP 5247) to the controller and back. The controller is a software appliance inside a nested VM, so this adds extra hops and CPU-bound forwarding. That fits the extra delay seen while the vWLC was connected. See [cisco-ap-conversion.md](cisco-ap-conversion.md#9-intermittent-latency-on-wireless-camera-traffic) for how to check the switching mode.

The ffmpeg timestamp crash loop on the front camera ([Problem 2](#2-front-yard-camera-ffmpeg-process-crash-loop-wireless-era)) was most likely an early symptom of the same unstable path.

**Solution:** Once the 24-port gigabit switch was installed, both cameras were wired to it on the CCTV VLAN (VLAN 20). With no radio and no tunnel in the path, the causes above no longer apply.

**Result:** Latency to the cameras is now `YOUR_MEASURED_WIRED_LATENCY`, with no day/night variation.

**If this is ever revisited** (to confirm the cause):
- Check `show wlan 1` on the vWLC for the FlexConnect Local Switching setting
- Compare camera latency at midday with the vWLC disconnected against the same test with it connected
- Check 2.4 GHz channel utilisation during the day

---

## Key Lessons Learned

**Wire your cameras where you can:** Wi-Fi latency changes with the time of day and the RF environment, and a clean test at night proves little. For latency-sensitive streams like NVR cameras, a wired connection removes the whole class of problem, and it simplified the network design too.

**Dual-stream camera configuration:** Always use the camera substream (stream2) for detection and the main stream (stream1) for recording. Running detection at full 2K resolution (2304×1296) is unnecessary because the model accepts 320×320 inputs anyway, and detection on 640×360 uses significantly less CPU/GPU.

**ffprobe for stream verification:**

```bash
/usr/lib/ffmpeg/7.0/bin/ffprobe -v error -rtsp_transport tcp \
  -show_streams "rtsp://USER:PASS@IP:554/stream1" \
  2>&1 | grep -E "width|height|codec_name"
```

**MQTT debugging:** The fastest way to confirm Frigate→HA MQTT is working is to subscribe to `frigate/#` in HA's MQTT developer tools. Stats payloads appear every 60 seconds even with no motion. If you see those, the pipeline is healthy.

**Detection enabled state:** After a Frigate restart, `detection_enabled` may default to `false` unless `detect.enabled: true` is explicitly set in config.yml per camera. Always include this to avoid manual re-enabling after reboots.

**YOLOv9 export dependencies:** The YOLOv9 repo's `requirements.txt` is outdated and does not include `onnxscript`, which is required by PyTorch 2.x for ONNX export. Always add it explicitly. The `onnx-simplifier` package is broken in recent versions due to onnxsim metadata issues. Skip it entirely, as the performance difference is negligible.

**Frigate model config structure:** In Frigate 0.17, `model` is always a top-level key. Nesting it under `detectors` is silently ignored, resulting in a NoneType error at runtime.

**Docker volume mounts:** When adding custom model files, always add an explicit volume mount in docker-compose.yml. Mounting only the config file (not the directory) means any subdirectories like `model_cache/` are invisible to the container.

**Debugging silent Docker build failures:** If a Docker RUN step exits 0 but produces no expected output file, run the command interactively in the built image:

```bash
docker build ... -t debug-image
docker run --rm debug-image python3 export.py --weights ...
```

This reveals error messages that were suppressed during the build layer execution.
