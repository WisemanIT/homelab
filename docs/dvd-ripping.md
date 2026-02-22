# DVD Ripping Setup

## Overview
A custom automated disc ripping solution built to digitize 
a personal collection of movies, TV shows, and game discs 
for use with Plex, Jellyfin and emulators.

## Hardware
- **Optical Drive:** SMD,DT,SATA,H/H,x16 salvaged from 
  a Lenovo ThinkCentre M58p MT (M9965-A9u)
- **Connected to:** HomeNasServer via SATA

## Software
- **MakeMKV** — for ripping video DVDs to MKV format
- **dd** — for creating ISO images of game discs
- **Custom script:** `/usr/local/bin/dvd-ripper.sh`

## How to Use
Insert disc into drive, then run:
```bash
sudo /usr/local/bin/dvd-ripper.sh
```

## What the Script Does
The script automatically detects the disc type and handles 
it accordingly:

- **Video DVDs/Blu-rays** → Ripped to MKV using MakeMKV, 
  saved to Movies directory for Plex
- **PS2 games** → ISO image created and saved to 
  GameBackups/PS2/
- **PC games** → ISO image created and saved to 
  GameBackups/PC/
- **Xbox 360 games** → Detected and warned about copy 
  protection (partial backup only, not playable)

## Disc Detection Logic
The script identifies disc types using multiple methods:

1. Disc label inspection (checks for XGD, XBOX, SCUS etc.)
2. Filesystem mounting and file signature checking
   - Xbox 360: looks for `default.xex`, `XBOX360/` folder
   - PS2: looks for `SYSTEM.CNF`, SCUS/SLES/SLUS prefixes
   - PC: looks for `autorun.inf`, `setup.exe`
   - Video: looks for `VIDEO_TS/` or `BDMV/` folders
3. MakeMKV fallback detection for video discs

## What Worked
- Movie and TV show DVDs → ripped successfully to Plex
- PS2 game discs → ISO images created successfully

## Known Limitations
### Xbox 360 Copy Protection
Xbox 360 discs use XGD (Xbox Game Disc) format with 
hardware-level copy protection. Standard DVD drives can 
only read approximately 5-7MB of data (the video 
partition), not the actual game data (7-8GB).

**Solutions for full Xbox 360 backups:**
- Compatible drive (Lite-On iHAS124 or LG GH24NSB0) 
  with modified firmware
- RGH/JTAG modded Xbox 360 console
- Specialized Xbox backup hardware

## Logs
Ripping activity is logged to:
```
/var/log/dvd-ripper.log
```
View live logs with:
```bash
tail -f /var/log/dvd-ripper.log
```

## Credits
Script developed collaboratively with AI assistance. 
Core logic, disc detection approach, and troubleshooting 
decisions designed and tested by the author.