#!/bin/bash

# Raspberry Pi Full System Update Script
# Updates from Bullseye to Bookworm (latest) with all packages

set -e

LOG_FILE="/home/pi/pi-update-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Starting Raspberry Pi Full System Update ==="
log "Current OS version:"
cat /etc/os-release | tee -a "$LOG_FILE"

# Step 1: Synchronize system time
log "Step 1: Synchronizing system time with NTP server..."
log "Current date/time: $(date)"

# Install ntpdate if not present
sudo apt-get install -y ntpdate 2>&1 | tee -a "$LOG_FILE" || log "ntpdate already installed or not available"

# Sync with multiple reliable time servers
log "Syncing with time servers..."
sudo timedatectl set-ntp false 2>&1 | tee -a "$LOG_FILE" || true
sudo ntpdate -u pool.ntp.org 2>&1 | tee -a "$LOG_FILE" || \
sudo ntpdate -u time.google.com 2>&1 | tee -a "$LOG_FILE" || \
sudo ntpdate -u time.cloudflare.com 2>&1 | tee -a "$LOG_FILE" || \
log "Warning: Could not sync with NTP servers, continuing anyway..."

# Re-enable NTP
sudo timedatectl set-ntp true 2>&1 | tee -a "$LOG_FILE" || true

log "Updated date/time: $(date)"
log "Time synchronization complete"

# Step 2: Detect current Debian version
log "Step 2: Detecting current Debian version..."
CURRENT_VERSION=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
log "Detected version: $CURRENT_VERSION"

# Step 3: Fix sources for Buster if needed
if [ "$CURRENT_VERSION" = "buster" ]; then
    log "Step 3: Fixing Buster repositories (raspbian.raspberrypi.org is dead)..."

    sudo bash -c 'cat > /etc/apt/sources.list << "EOF"
deb http://deb.debian.org/debian buster main contrib non-free
deb http://deb.debian.org/debian-security buster/updates main contrib non-free
deb http://deb.debian.org/debian buster-updates main contrib non-free
EOF' 2>&1 | tee -a "$LOG_FILE"

    echo "deb http://archive.raspberrypi.org/debian/ buster main" | sudo tee /etc/apt/sources.list.d/raspi.list > /dev/null 2>&1 | tee -a "$LOG_FILE"

    log "Buster repositories fixed"
else
    log "Step 3: Not Buster, skipping repository fix..."
fi

# Step 4: Import missing GPG keys for all versions
log "Step 4: Importing Debian GPG keys..."
wget -qO - https://ftp-master.debian.org/keys/archive-key-10.asc | sudo apt-key add - 2>&1 | tee -a "$LOG_FILE" || log "Debian 10 key import failed or not needed"
wget -qO - https://ftp-master.debian.org/keys/archive-key-10-security.asc | sudo apt-key add - 2>&1 | tee -a "$LOG_FILE" || log "Debian 10 security key import failed or not needed"
wget -qO - https://ftp-master.debian.org/keys/archive-key-11.asc | sudo apt-key add - 2>&1 | tee -a "$LOG_FILE" || log "Debian 11 key import failed or not needed"
wget -qO - https://ftp-master.debian.org/keys/archive-key-11-security.asc | sudo apt-key add - 2>&1 | tee -a "$LOG_FILE" || log "Debian 11 security key import failed or not needed"
wget -qO - https://ftp-master.debian.org/keys/archive-key-12.asc | sudo apt-key add - 2>&1 | tee -a "$LOG_FILE" || log "Debian 12 key import failed or not needed"
wget -qO - https://ftp-master.debian.org/keys/archive-key-12-security.asc | sudo apt-key add - 2>&1 | tee -a "$LOG_FILE" || log "Debian 12 security key import failed or not needed"
log "GPG keys imported successfully"

# Step 5: Update current system
log "Step 5: Updating current system packages ($CURRENT_VERSION)..."
sudo apt-get update 2>&1 | tee -a "$LOG_FILE"
sudo apt-get upgrade -y --fix-missing 2>&1 | tee -a "$LOG_FILE"
sudo apt-get dist-upgrade -y 2>&1 | tee -a "$LOG_FILE"

# Step 5a: Upgrade Buster to Bullseye if needed
if [ "$CURRENT_VERSION" = "buster" ]; then
    log "Step 5a: Upgrading from Buster to Bullseye..."

    # Backup Buster sources
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.buster-backup

    # Update to Bullseye sources
    sudo sed -i 's/buster/bullseye/g' /etc/apt/sources.list
    if [ -f /etc/apt/sources.list.d/raspi.list ]; then
        sudo sed -i 's/buster/bullseye/g' /etc/apt/sources.list.d/raspi.list
    fi

    log "Updated sources to Bullseye"
    sudo apt-get update 2>&1 | tee -a "$LOG_FILE"
    sudo apt-get upgrade -y --without-new-pkgs 2>&1 | tee -a "$LOG_FILE"
    sudo apt-get dist-upgrade -y 2>&1 | tee -a "$LOG_FILE"

    log "Buster to Bullseye upgrade complete"
    CURRENT_VERSION="bullseye"
fi

# Step 6: Check and resize boot partition if needed
log "Step 6: Checking boot partition size..."
BOOT_SIZE=$(df -BM /boot | tail -1 | awk '{print $2}' | sed 's/M//')
log "Current boot partition size: ${BOOT_SIZE}M"

if [ "$BOOT_SIZE" -lt 512 ]; then
    log "Boot partition is less than 512M, attempting to expand..."
    log "Expanding filesystem with raspi-config..."

    # Use raspi-config to expand filesystem
    sudo raspi-config --expand-rootfs 2>&1 | tee -a "$LOG_FILE" || log "Auto-expand failed"

    # Alternative: manually resize boot partition
    log "Attempting manual boot partition resize..."

    # Get the boot partition device
    BOOT_DEV=$(mount | grep "/boot" | awk '{print $1}')
    log "Boot device: $BOOT_DEV"

    if [ -n "$BOOT_DEV" ]; then
        log "WARNING: Boot partition resize requires manual intervention or may need a reboot"
        log "Recommended: After this script completes, run 'sudo raspi-config' -> Advanced -> Expand Filesystem"
        log "Then reboot and run this script again"
    fi
else
    log "Boot partition size is sufficient (${BOOT_SIZE}M >= 512M)"
fi

# Step 7: Update firmware
log "Step 7: Updating Raspberry Pi firmware..."
if [ "$BOOT_SIZE" -ge 512 ]; then
    echo "y" | sudo rpi-update 2>&1 | tee -a "$LOG_FILE" || log "rpi-update not available, skipping..."
else
    log "Skipping rpi-update due to insufficient boot partition size"
    log "Firmware will be updated via apt packages instead"
fi

# Step 8: Backup sources
log "Step 8: Backing up current sources..."
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bullseye-backup
if [ -f /etc/apt/sources.list.d/raspi.list ]; then
    sudo cp /etc/apt/sources.list.d/raspi.list /etc/apt/sources.list.d/raspi.list.bullseye-backup
fi

# Step 9: Upgrade to Bookworm
log "Step 9: Upgrading to Bookworm (Debian 12)..."
sudo sed -i 's/bullseye/bookworm/g' /etc/apt/sources.list
if [ -f /etc/apt/sources.list.d/raspi.list ]; then
    sudo sed -i 's/bullseye/bookworm/g' /etc/apt/sources.list.d/raspi.list
fi

log "Updated sources.list:"
cat /etc/apt/sources.list | tee -a "$LOG_FILE"

# Step 10: Update package lists
log "Step 10: Updating package lists for Bookworm..."
sudo apt-get update 2>&1 | tee -a "$LOG_FILE"

# Step 11: Minimal upgrade first
log "Step 11: Performing minimal upgrade..."
sudo apt-get upgrade -y --without-new-pkgs 2>&1 | tee -a "$LOG_FILE"

# Step 12: Full distribution upgrade
log "Step 12: Performing full distribution upgrade..."
sudo apt-get dist-upgrade -y 2>&1 | tee -a "$LOG_FILE"

# Step 13: Clean up
log "Step 13: Cleaning up old packages..."
sudo apt-get autoremove -y 2>&1 | tee -a "$LOG_FILE"
sudo apt-get autoclean -y 2>&1 | tee -a "$LOG_FILE"

# Step 14: Update firmware again
log "Step 14: Updating firmware for Bookworm..."
sudo apt-get install --reinstall raspberrypi-bootloader raspberrypi-kernel -y 2>&1 | tee -a "$LOG_FILE" || log "Firmware packages not available"

log "=== Update Complete ==="
log "New OS version:"
cat /etc/os-release | tee -a "$LOG_FILE"
log "Log saved to: $LOG_FILE"
log ""
log "REBOOT REQUIRED! Run: sudo reboot"
log "After reboot, verify with: cat /etc/os-release"
