# Plex Media Server — Native Installation

## Overview
Plex Media Server is installed natively on the host system 
as a systemd service rather than as a Docker container. 
This was a deliberate choice to avoid containerization 
overhead for a media server that benefits from direct 
hardware access.

## Installation
Plex was installed directly from the official Plex 
repository for Debian:
```bash
# Add Plex repository
curl https://downloads.plex.tv/plex-keys/PlexSign.key \
  | sudo apt-key add -
echo deb https://downloads.plex.tv/repo/deb public main \
  | sudo tee /etc/apt/sources.list.d/plexmediaserver.list

# Install
sudo apt update
sudo apt install plexmediaserver
```

## Service Management
Plex runs as a systemd service and starts automatically 
on boot.
```bash
# Check status
systemctl status plexmediaserver

# Start/Stop/Restart
sudo systemctl start plexmediaserver
sudo systemctl stop plexmediaserver
sudo systemctl restart plexmediaserver
```

## Media Library Location
Media files are stored on a dedicated hard drive:

| Library | Path |
|---------|------|
| Movies | `/srv/YOUR_DISK_UUID/Movies/` |
| TV Shows | `/srv/YOUR_DISK_UUID/TVShows/` |
| Music | `/srv/YOUR_DISK_UUID/Music/` |
| Game Backups | `/srv/YOUR_DISK_UUID/GameBackups/` |

## Access
Plex is accessible via browser at:
```
http://YOUR_SERVER_IP:32400/web
```

## Notes
- Media is shared with Jellyfin which uses the same 
  library directories
- DVD ripping outputs directly to the Movies directory 
  which Plex and jellyfin scans automatically