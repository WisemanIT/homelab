# Frigate NVR - Security Camera System

## Overview
This documents the deployment of Frigate NVR as a self-hosted,
AI-powered security camera system integrated with Home Assistant.
The system uses an Intel HD 530 iGPU via OpenVINO for hardware-
accelerated object detection, two TP-Link Tapo C310 cameras
across two network segments, MQTT via Mosquitto for real-time
event publishing, and Home Assistant automations for mobile
notifications and recording.

The system was upgraded from the default SSDlite MobileNet V2
model (300×300) to a custom-built YOLOv9-t ONNX model (320×320)
for improved detection accuracy on person, car, and bus classes.

---

## Hardware

| Device | Role | Location |
|--------|------|----------|
| Lenovo ThinkCentre M900 SFF | NVR host server | Workshop |
| Intel HD 530 iGPU | OpenVINO object detection | On-board |
| TP-Link Tapo C310 (x2) | 2K security cameras | Garage + Front Yard |
| ZTE H288a | Gateway for garage camera | Workshop |
| Cisco Aironet AIR-CAP3602I-E-K9 | AP for front yard camera | House |

---

## Network Topology

```
Garage Camera (Tapo C310)
  IP: 192.168.2.XXX
  Connected via: ZTE H288a (192.168.2.0/24)

Front Yard Camera (Tapo C310)
  IP: 192.168.1.XXX
  Connected via: Cisco AP → TP-Link MR600 (192.168.1.0/24)

OMV Server (192.168.2.150)
  └── Frigate (Docker) - port 5000
  └── Home Assistant OS (Docker) - 192.168.2.114:8123
  └── Mosquitto MQTT Broker (HA Add-on) - port 1883
```

Both cameras are reachable from the server because inter-subnet
routing is configured between 192.168.1.0/24 and 192.168.2.0/24
via static routes on both routers. See network-setup.md for
full routing configuration.

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

See [docker/frigate/config.yml](../docker/frigate/config.yml) 
for the full sanitized Frigate configuration.

See [docker/frigate/docker-compose.yml](../docker/frigate/docker-compose.yml) 
for the Docker Compose deployment file.

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
The system initially used Frigate's built-in SSDlite MobileNet V2
model served via OpenVINO:
```yaml
model:
  path: /openvino-model/ssdlite_mobilenet_v2.xml
  width: 300
  height: 300
  input_tensor: nhwc
  input_pixel_format: bgr
```

### Upgraded Model: YOLOv9-t (ONNX)
The model was upgraded to YOLOv9-t exported to ONNX format for
better detection accuracy, especially for person and vehicle
detection at distance.

#### Building the Model
The model is built via a Docker multi-stage build that clones
the YOLOv9 repo, installs dependencies, and exports to ONNX.
Run this once on the NVR host:

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

The `model` block must be **top-level** in config.yml, not nested
under `detectors`:

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
3. Disable **Customize → active** to prevent `/share/mosquitto`
   directory error on startup
4. Start add-on with **Start on boot** and **Watchdog** enabled
5. HA auto-detects MQTT integration under
   Settings → Devices & Services

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

Live event monitoring via HA:
Settings → Devices & Services → MQTT → Configure → Listen to topic: `frigate/#`

---

## Home Assistant Integration

### Tapo: Camera Control (HACS)
Standard HA integrations (TP-Link Smart Home, ONVIF) failed
due to SSL handshake errors and cross-subnet routing issues.
Tapo: Camera Control installed via HACS resolved both issues.

**Installation path:**
Settings → Add-ons → Advanced SSH & Web Terminal →
run HACS install script → restart → HACS → Integrations →
search Tapo: Camera Control → download → restart

Both cameras appear as devices with motion detection entities,
stream entities, and image snapshot entities.

### Automations

#### Security Detect - Front Yard
```
Trigger:  Front Yard Cam Cell Motion Detection → changes TO Detected
Condition: Time between 07:30 and 16:30
Actions:
  1. Camera: Record camera feed
       Target: HD Stream (Front Yard Cam)
       Filename: /media/front_yard_{{ now().strftime('%Y%m%d_%H%M%S') }}.mp4
       Duration: 30 seconds
  2. Send notification → SM-A135F
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
  2. Send notification → SM-A135F
       Title: Garage Camera Detection
       Message: Person Detected at the Garage at {{ now().strftime('%H:%M') }}
```

---

## Detector Performance

Confirmed via `frigate/stats` MQTT topic after full startup:

| Metric | Value |
|--------|-------|
| Detector type | OpenVINO (ov) |
| Model | YOLOv9-t ONNX (320×320) |
| Inference speed | ~10–12ms |
| GPU utilisation | Intel VAAPI (HD 530) |
| Garage detection fps | ~3–5 fps |
| Front detection fps | ~1–3 fps |
| Both cameras | detection_enabled: true |

Hardware acceleration confirmed active on both ffmpeg processes:
```
-hwaccel vaapi -hwaccel_device /dev/dri/renderD128
```

---

## Problems Solved

### 1. Frigate Auth Service 502 Errors on Startup
**Problem:** Docker logs flooded with nginx 502 errors on
every startup referencing `127.0.0.1:5001/auth`.

**Root cause:** Frigate's internal auth backend (port 5001)
starts a few seconds after nginx. Nginx attempts auth
requests before the backend is ready, producing 502s.

**Solution:** Not a real error - self-resolving within ~10
seconds of container startup. Safe to ignore. Filter out
when grepping logs:
```bash
docker logs frigate 2>&1 | grep -v "nginx\|auth\|502\|connect()"
```

---

### 2. Front Yard Camera ffmpeg Process Crash Loop
**Problem:** Front yard camera (192.168.1.XXX) entered a
continuous crash/restart loop with these errors:
```
[aac @ ...] Queue input is backward in time
[vost#0:0/copy @ ...] Non-monotonic DTS; previous: XXXXX, current: XXXXX
frigate.video ERROR: front: Unable to read frames from ffmpeg process
watchdog.front ERROR: Ffmpeg process crashed unexpectedly for front
```

**Root cause:** The camera was sending malformed RTSP
timestamps over the network path through the Cisco AP
(192.168.1.0/24 subnet). The additional network hop
introduced just enough instability to corrupt the timestamp
stream. ffmpeg's default TCP transport could not tolerate it.

**Solution:** Added `preset-rtsp-udp` as ffmpeg input args
for the front camera:
```yaml
front:
  ffmpeg:
    input_args: preset-rtsp-udp
```

UDP transport is more tolerant of timestamp irregularities
and eliminated the crash loop entirely.

**Result:** Front camera stable - no crashes observed after
applying the fix.

---

### 3. Mosquitto Broker Crash Loop After Configuration
**Problem:** After adding login credentials to Mosquitto's
configuration, the broker entered a continuous restart loop:
```
Error: Unable to open include_dir '/share/mosquitto'
mosquitto version 2.1.2 terminating
```

**Root cause:** The **Customize** section in Mosquitto's
Add-on options had `active: true` with `folder: mosquitto`.
This instructed Mosquitto to load additional config files
from `/share/mosquitto` - a directory that does not exist
in a default HA installation.

**Solution:** In HA → Settings → Add-ons → Mosquitto broker
→ Configuration → Customize section → toggle **active** to
**off**. Save and restart the add-on.

**Result:** Mosquitto started cleanly. Frigate connected
successfully confirmed by Mosquitto logs:
```
New client connected from 192.168.2.150 as frigate (u'frigate-mqtt')
```

---

### 4. Frigate MQTT Disconnecting Immediately After Connect
**Problem:** Frigate connected to Mosquitto then disconnected
within seconds. Docker logs showed:
```
[frigate.comms.mqtt] ERROR: MQTT disconnected
```

**Root cause:** The `frigate-mqtt` user was created in
HA → People → Users but the password set there was not
reflected in Mosquitto's Add-on login configuration.
Mosquitto authenticated against its own login list, not
the HA user database directly.

**Solution:** The Mosquitto Add-on login entry
(`logins:` in Add-on Options) must explicitly list the
username and password. Setting the password only in
HA Users is not sufficient - both must match.

**Result:** Persistent MQTT connection established. Confirmed
via live topic subscription to `frigate/#` in HA MQTT
developer tools showing `frigate/stats` payloads every 60
seconds and `frigate/garage/status/detect: online` heartbeats.

---

### 5. TP-Link Smart Home Integration SSL Failure
**Problem:** HA TP-Link Smart Home integration failed to
connect to garage camera with:
```
[SSL: SSLV3_ALERT_HANDSHAKE_FAILURE]
ClientConnectorSSLError on port 443
```

**Root cause:** The Tapo C310 uses a proprietary SSL
implementation that is incompatible with the standard
TP-Link Smart Home integration's TLS handshake.

**Solution:** Replaced TP-Link Smart Home integration with
**Tapo: Camera Control** (HACS custom integration). This
integration handles Tapo's authentication correctly and
exposes full camera entities including motion detection,
stream, and snapshots.

**Result:** Both cameras integrated successfully with full
entity support in HA.

---

### 6. YOLOv9 ONNX Export: onnxsim Version Conflict
**Problem:** Initial Docker build for YOLOv9 ONNX export
failed with:
```
× Failed to download and build onnxsim==0.6.2
╰─▶ Package metadata version 0.4.36 does not match given version 0.6.2
```

**Root cause:** `onnx-simplifier>=0.4.1` resolved to v0.5.0,
which pulled in `onnxsim==0.6.2`. The onnxsim package had a
broken metadata version mismatch that caused uv to reject it.

**Solution:** Remove `onnx-simplifier` entirely and drop the
`--simplify` flag from the export command. The model is
slightly larger but fully functional:
```dockerfile
RUN uv pip install --system onnx==1.18.0 onnxruntime onnxscript
RUN python3 export.py --weights ./yolov9-${MODEL_SIZE}.pt \
    --imgsz ${IMG_SIZE} --include onnx
```

---

### 7. YOLOv9 Export: Missing onnxscript Module
**Problem:** After removing onnx-simplifier, the export
script failed silently (exit 0, no .onnx file produced).
Running the export interactively revealed:
```
ONNX: export failure ❌ 0.2s: No module named 'onnxscript'
```

**Root cause:** PyTorch 2.11 uses `onnxscript` internally
for its ONNX export path. The YOLOv9 requirements.txt does
not include it, so it was missing from the build environment.

**Solution:** Add `onnxscript` to the pip install step:
```dockerfile
RUN uv pip install --system onnx==1.18.0 onnxruntime onnxscript
```

**Result:** Export completed successfully, producing
`yolov9-t.onnx` in `/yolov9/` inside the build container.

---

### 8. YOLOv9 ONNX File Not Found After Successful Build
**Problem:** The Docker build completed without errors but
the final COPY step in the scratch stage failed:
```
ERROR: "/yolov9/yolov9-t.onnx": not found
```

**Root cause:** The export script ran but produced no output
because `onnxscript` was missing (see Problem 7). The build
layer was cached from a previous run where the export also
failed silently, so Docker used the cached (empty) layer.

**Solution:** Add `--no-cache` to force a clean rebuild after
fixing dependencies, or ensure the pip install layer is
invalidated by changing its content. Once `onnxscript` was
added, a clean build produced the file correctly.

---

### 9. Frigate model path NoneType Error
**Problem:** After configuring the YOLOv9 model, Frigate
crashed on startup with:
```
TypeError: stat: path should be string, bytes, os.PathLike or integer, not NoneType
```

**Root cause:** In Frigate 0.17, the `model` block must be
defined at the **top level** of config.yml, not nested inside
the `detectors` block. Nesting it under `detectors` caused
Frigate to not parse the path at all, leaving it as None.

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
**Problem:** After fixing the config structure, Frigate
started but immediately crashed with:
```
FileNotFoundError: OpenVINO model file /config/model_cache/yolov9-t-320.onnx not found.
```

**Root cause:** The docker-compose.yml only mounted
`./config.yml` as a single file, not the entire `./config/`
directory. The `model_cache/` subdirectory was therefore
invisible to the container.

**Solution:** Add an explicit volume mount for the model
cache directory in docker-compose.yml:
```yaml
volumes:
  - ./config.yml:/config/config.yml
  - ./config/model_cache:/config/model_cache   # ← add this
```

**Result:** Frigate located the model file and the detector
started successfully.

---

### 11. Invalid model_type Value
**Problem:** Frigate rejected the config with:
```
Line 14: detectors -> ov -> model -> model_type
Input should be 'dfine', 'rfdetr', 'ssd', 'yolox', 'yolonas' or 'yolo-generic'
```

**Root cause:** The value `model_type: yolov9` is not a valid
Frigate model type. Frigate 0.17 uses generic type names.

**Solution:** Use `model_type: yolo-generic` for any YOLOv9
model.

---

## Key Lessons Learned

**Dual-stream camera configuration:** Always use the camera
substream (stream2) for detection and the main stream
(stream1) for recording. Running detection at full 2K
resolution (2304×1296) is unnecessary - the model accepts
320×320 inputs anyway, and detection on 640×360 uses
significantly less CPU/GPU.

**ffprobe for stream verification:**
```bash
/usr/lib/ffmpeg/7.0/bin/ffprobe -v error -rtsp_transport tcp \
  -show_streams "rtsp://USER:PASS@IP:554/stream1" \
  2>&1 | grep -E "width|height|codec_name"
```

**MQTT debugging:** The fastest way to confirm Frigate→HA
MQTT is working is to subscribe to `frigate/#` in HA's MQTT
developer tools. Stats payloads appear every 60 seconds even
with no motion - if you see those, the pipeline is healthy.

**Detection enabled state:** After a Frigate restart,
`detection_enabled` may default to `false` unless
`detect.enabled: true` is explicitly set in config.yml
per camera. Always include this to avoid manual re-enabling
after reboots.

**YOLOv9 export dependencies:** The YOLOv9 repo's
`requirements.txt` is outdated and does not include
`onnxscript`, which is required by PyTorch 2.x for ONNX
export. Always add it explicitly. The `onnx-simplifier`
package is broken in recent versions due to onnxsim metadata
issues - skip it entirely, the performance difference is
negligible.

**Frigate model config structure:** In Frigate 0.17, `model`
is always a top-level key. Nesting it under `detectors` is
silently ignored, resulting in a NoneType error at runtime.

**Docker volume mounts:** When adding custom model files,
always add an explicit volume mount in docker-compose.yml.
Mounting only the config file (not the directory) means any
subdirectories like `model_cache/` are invisible to the
container.

**Debugging silent Docker build failures:** If a Docker
RUN step exits 0 but produces no expected output file, run
the command interactively in the built image:
```bash
docker build ... -t debug-image
docker run --rm debug-image python3 export.py --weights ...
```
This reveals error messages that were suppressed during the
build layer execution.
