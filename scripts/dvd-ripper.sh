#!/bin/bash

# Smart Disc Ripper
# Manual trigger only - Insert disc, then run this script
# Automatically detects disc type and handles accordingly:
# - Video DVDs/Blu-rays -> MakeMKV rip to Plex
# - Data/Game discs -> ISO backup (organized by console type)

# Configuration
DVD_DEVICE="/dev/sr0"
MOVIES_DIR="/srv/YOUR_DISK_UUID/Movies"
GAMES_DIR="/srv/YOUR_DISK_UUID/GameBackups"
LOG_FILE="/var/log/dvd-ripper.log"

# Colors for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Logging function
log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="$timestamp - $1"
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "$message" | sudo tee -a "$LOG_FILE" >/dev/null
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | sudo tee -a "$LOG_FILE" >/dev/null
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $1" | sudo tee -a "$LOG_FILE" >/dev/null
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1" | sudo tee -a "$LOG_FILE" >/dev/null
}

# Check if running as root (for mounting)
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}[NOTE]${NC} Some operations require sudo. You may be prompted for password."
fi

# Clear screen and show banner
clear
echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}        SMART DISC RIPPER v2.3${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""

# Check if disc is present
log "Checking for disc in drive..."
if ! sudo blkid "$DVD_DEVICE" &>/dev/null; then
    error "No disc detected in drive!"
    echo ""
    echo "Please insert a disc and try again."
    exit 1
fi

# Get disc label (store for later use in detection)
RAW_DISC_LABEL=$(sudo blkid -s LABEL -o value "$DVD_DEVICE" 2>/dev/null)
DISC_LABEL=$(echo "$RAW_DISC_LABEL" | sed 's/[^a-zA-Z0-9._-]/_/g')
if [ -z "$DISC_LABEL" ]; then
    DISC_LABEL="DISC_$(date +%Y%m%d_%H%M%S)"
fi

log "Disc detected: $DISC_LABEL"
if [ -n "$RAW_DISC_LABEL" ]; then
    log "Raw label: $RAW_DISC_LABEL"
fi
echo ""

# Check if it's a video DVD by looking for VIDEO_TS
log "Analyzing disc type..."
MOUNT_POINT="/mnt/dvd_check"
sudo mkdir -p "$MOUNT_POINT"

# Variables for detection
IS_VIDEO=false
GAME_TYPE="Other"

# CRITICAL FIX: Check disc label FIRST for Xbox 360 before anything else
if [[ -n "$RAW_DISC_LABEL" ]]; then
    if [[ "$RAW_DISC_LABEL" == *"XGD"* ]] || \
       [[ "$RAW_DISC_LABEL" == *"XBOX"* ]] || \
       [[ "$RAW_DISC_LABEL" == *"360"* ]]; then
        GAME_TYPE="Xbox360"
        IS_VIDEO=false
        log "Detected Xbox 360 game by disc label: $RAW_DISC_LABEL"
        log "Skipping mount check - treating as Xbox 360 game"
    fi
fi

# Only proceed with mount if we haven't already detected Xbox 360 by label
if [ "$GAME_TYPE" != "Xbox360" ]; then
    if sudo mount -o ro "$DVD_DEVICE" "$MOUNT_POINT" 2>/dev/null; then
        # Check for Xbox/Xbox360 signature - THIS MUST BE FIRST!
        if [ -f "$MOUNT_POINT/default.xex" ] || \
           [ -d "$MOUNT_POINT/XBOX360" ] || \
           [ -f "$MOUNT_POINT/default.xbe" ] || \
           [ -f "$MOUNT_POINT/xboxdvd.xex" ] || \
           [ -d "$MOUNT_POINT/content/0000000000000000" ] || \
           [ -f "$MOUNT_POINT/$$SystemUpdate" ]; then
            GAME_TYPE="Xbox360"
            IS_VIDEO=false
            log "Detected: Xbox/Xbox 360 game (found Xbox files)"

        # Check for PS2 signature
        elif [ -f "$MOUNT_POINT/SYSTEM.CNF" ] || \
             sudo ls -1 "$MOUNT_POINT/" 2>/dev/null | grep -q "^SCUS_\|^SLES_\|^SLUS_" || \
             [ -f "$MOUNT_POINT/PS2.DAT" ] || \
             [ -f "$MOUNT_POINT/IOPRP"* ]; then
            GAME_TYPE="PS2"
            IS_VIDEO=false
            log "Detected: PlayStation 2 game"

        # Check for PC game indicators
        elif [ -f "$MOUNT_POINT/autorun.inf" ] || \
             [ -f "$MOUNT_POINT/setup.exe" ] || \
             [ -f "$MOUNT_POINT/SETUP.EXE" ] || \
             [ -f "$MOUNT_POINT/INSTALL.EXE" ] || \
             [ -d "$MOUNT_POINT/APPS" ] || \
             [ -f "$MOUNT_POINT/setup.ini" ]; then
            GAME_TYPE="PC"
            IS_VIDEO=false
            log "Detected: PC game"

        # If no game detected, check for video
        elif [ -d "$MOUNT_POINT/VIDEO_TS" ] || [ -d "$MOUNT_POINT/BDMV" ]; then
            IS_VIDEO=true
            log "Detected: VIDEO DVD/Blu-ray"
        else
            IS_VIDEO=false
            log "Detected: DATA/GAME disc (unknown type)"
        fi

        sudo umount "$MOUNT_POINT" 2>/dev/null
    else
        # If we can't mount, try alternative detection
        log "Attempting alternative detection..."

        # Check for PS2 indicators in label
        if [[ "$RAW_DISC_LABEL" == *"SCUS"* ]] || \
           [[ "$RAW_DISC_LABEL" == *"SLES"* ]] || \
           [[ "$RAW_DISC_LABEL" == *"SLUS"* ]] || \
           [[ "$RAW_DISC_LABEL" == *"PS2"* ]]; then
            IS_VIDEO=false
            GAME_TYPE="PS2"
            log "Detected PS2 game by label: $RAW_DISC_LABEL"
        # Try MakeMKV for video detection
        elif timeout 10 sudo makemkvcon info disc:0 2>&1 | grep -q "Title #"; then
            IS_VIDEO=true
            log "Detected: VIDEO DVD/Blu-ray (via MakeMKV)"
        else
            IS_VIDEO=false
            GAME_TYPE="Other"
            log "Detected: DATA/GAME disc (mount failed, assuming data)"
        fi
    fi
fi

sudo rmdir "$MOUNT_POINT" 2>/dev/null

echo ""
echo -e "${BLUE}==========================================${NC}"

# Process based on disc type
if [ "$IS_VIDEO" = true ]; then
    echo -e "${YELLOW}VIDEO DISC PROCESSING${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""

    # Create final movie directory
    FINAL_DIR="$MOVIES_DIR/$DISC_LABEL"
    sudo mkdir -p "$FINAL_DIR"

    log "Output: $FINAL_DIR"
    log "Starting MakeMKV rip..."
    log "Estimated time: 20-60 minutes..."
    echo ""

    # Rip with MakeMKV
    echo -e "${YELLOW}Ripping in progress...${NC}"
    echo "(This may take a while. Check $LOG_FILE for details)"
    echo ""

    if sudo makemkvcon mkv disc:0 all "$FINAL_DIR" --minlength=300 >> "$LOG_FILE" 2>&1; then
        MKV_COUNT=$(sudo find "$FINAL_DIR" -name "*.mkv" 2>/dev/null | wc -l)

        if [ "$MKV_COUNT" -gt 0 ]; then
            success "Created $MKV_COUNT MKV file(s)"
            sudo chmod -R 755 "$FINAL_DIR"
            sudo chown -R root:users "$FINAL_DIR"
            echo ""
            echo "Files saved to:"
            echo "$FINAL_DIR"
            echo ""
            echo "Contents:"
            sudo ls -lh "$FINAL_DIR"
        else
            error "No MKV files created"
            exit 1
        fi
    else
        error "MakeMKV ripping failed"
        exit 1
    fi

else
    echo -e "${YELLOW}GAME DISC PROCESSING${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""

    log "Game type: $GAME_TYPE"

    # ====== XBOX 360 WARNING ======
    if [ "$GAME_TYPE" = "Xbox360" ]; then
        echo ""
        echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                  ⚠️  WARNING ⚠️                        ║${NC}"
        echo -e "${RED}║              XBOX 360 COPY PROTECTION                  ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}This is an Xbox 360 game disc with XGD copy protection.${NC}"
        echo ""
        echo -e "${RED}⚠ Your current drive can only read 5-7MB of data!${NC}"
        echo -e "  (The small 'video partition' - NOT the actual game)"
        echo ""
        echo -e "${MAGENTA}Why?${NC}"
        echo -e "  Xbox 360 discs use special XGD (Xbox Game Disc) format with"
        echo -e "  hardware-level copy protection. Standard DVD drives physically"
        echo -e "  CANNOT read the game data area (7-8GB)."
        echo ""
        echo -e "${MAGENTA}Solutions for FULL backups:${NC}"
        echo -e "  ${GREEN}Option 1:${NC} Get a compatible drive (Lite-On iHAS124, LG GH24NSB0)"
        echo -e "           with modified firmware"
        echo -e "  ${GREEN}Option 2:${NC} Mod your Xbox 360 (RGH/JTAG) and rip from HDD"
        echo -e "  ${GREEN}Option 3:${NC} Use specialized Xbox backup hardware"
        echo ""
        echo -e "${YELLOW}What this backup WILL contain:${NC}"
        echo -e "  • Disc security info (~5-7MB)"
        echo -e "  • Disc label and metadata"
        echo -e "  ${RED}✗ NOT playable in emulators${NC}"
        echo -e "  ${RED}✗ NOT the actual game data${NC}"
        echo ""
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
        echo ""

        # Ask user if they want to continue
        read -p "Do you want to continue with partial backup? (y/N): " -n 1 -r
        echo ""

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo ""
            warning "Backup cancelled by user"
            echo ""
            echo "Ejecting disc..."
            sudo eject "$DVD_DEVICE" 2>/dev/null
            echo ""
            echo -e "${YELLOW}Tip:${NC} Keep this disc for when you get compatible hardware!"
            echo ""
            exit 0
        fi

        echo ""
        warning "Proceeding with PARTIAL backup (5-7MB only)"
        echo ""
    fi
    # ====== END XBOX 360 WARNING ======

    # Create organized directory structure
    GAME_TYPE_DIR="$GAMES_DIR/$GAME_TYPE"
    sudo mkdir -p "$GAME_TYPE_DIR"

    # Sanitize filename
    SANITIZED_LABEL=$(echo "$DISC_LABEL" | sed 's/[^a-zA-Z0-9._-]/_/g')
    OUTPUT_ISO="$GAME_TYPE_DIR/${SANITIZED_LABEL}.iso"

    # Check if ISO already exists
    if [ -f "$OUTPUT_ISO" ]; then
        log "ISO already exists: $OUTPUT_ISO"
        OUTPUT_ISO="$GAME_TYPE_DIR/${SANITIZED_LABEL}_$(date +%H%M%S).iso"
        log "Using alternate filename: $OUTPUT_ISO"
    fi

    log "Creating ISO backup..."
    log "Output: $OUTPUT_ISO"

    if [ "$GAME_TYPE" = "Xbox360" ]; then
        log "Estimated time: 5-10 seconds (partial backup only)"
    else
        log "Estimated time: 5-15 minutes..."
    fi

    echo ""

    echo -e "${YELLOW}Backup in progress...${NC}"
    echo "(Press Ctrl+C to cancel)"
    echo ""

    # Create ISO using dd with progress
    if sudo dd if="$DVD_DEVICE" of="$OUTPUT_ISO" bs=2048 status=progress 2>&1 | tee -a "$LOG_FILE"; then
        FILE_SIZE=$(sudo du -h "$OUTPUT_ISO" 2>/dev/null | cut -f1)
        echo ""

        if [ "$GAME_TYPE" = "Xbox360" ]; then
            warning "Partial backup created (5-7MB only)"
            echo ""
            echo -e "${YELLOW}⚠ Remember: This is NOT a playable backup!${NC}"
            echo "File size: $FILE_SIZE (should be ~5-7MB)"
        else
            success "ISO created successfully!"
        fi

        log "File: $OUTPUT_ISO"
        log "Size: $FILE_SIZE"
        sudo chmod 644 "$OUTPUT_ISO"
        sudo chown root:users "$OUTPUT_ISO"

        echo ""
        echo -e "${GREEN}✓ Backup complete!${NC}"
        echo "File: $OUTPUT_ISO"
        echo "Size: $FILE_SIZE"
    else
        error "ISO creation failed"
        exit 1
    fi
fi

# Eject disc
echo ""
log "Ejecting disc..."
sudo eject "$DVD_DEVICE" 2>/dev/null

echo ""
echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}PROCESS COMPLETE!${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Remove the disc from the drive"
echo "2. Insert next disc if desired"
echo "3. Run this script again: sudo /usr/local/bin/dvd-ripper.sh"
echo ""
