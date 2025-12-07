#!/bin/bash

# Assumptions: Run as survon (non-root); Pi OS Lite armhf (RPi 3B v1.2); repos on master (no git; use curl for tarballs/zips).
# Flags: --skip-<step> (e.g., --skip-apt-update to skip that function).
# Steps: Each in named function; controller downloads pre-built binary instead of building.
# Spinner: Simple animation during non-interactive steps. No spinner for interactive steps.

set -e  # Exit on error.

# Version info
INSTALLER_VERSION="1.0.1"
INSTALLER_URL="https://raw.githubusercontent.com/survon/survon-os/master/scripts/install.sh"

# Check for updates before proceeding
check_installer_updates() {
  # If running via pipe, always use latest version
  if [ "$0" = "bash" ] || [ "$0" = "sh" ] || [ "$0" = "-bash" ]; then
    echo "Running via curl | bash - using latest version automatically."
    return 0
  fi

  echo "Checking for installer updates..."

  # Download latest installer to temp file
  if curl -s -L "$INSTALLER_URL" -o /tmp/install_latest.sh 2>/dev/null; then
    # Calculate hashes only if running from a file
    if command -v sha256sum >/dev/null 2>&1; then
      current_hash=$(sha256sum "$0" | cut -d' ' -f1)
      latest_hash=$(sha256sum /tmp/install_latest.sh | cut -d' ' -f1)

      if [ "$current_hash" != "$latest_hash" ]; then
        echo "================================================"
        echo "A newer version of the installer is available."
        echo "Current hash: ${current_hash:0:8}..."
        echo "Latest hash:  ${latest_hash:0:8}..."
        echo "================================================"
        echo ""
        read -p "Update and run the latest installer? (y/n): " update_choice

        if [ "$update_choice" = "y" ] || [ "$update_choice" = "Y" ]; then
          echo "Updating installer..."
          cp /tmp/install_latest.sh ~/install.sh
          chmod +x ~/install.sh
          echo "Installer updated. Restarting with new version..."
          exec ~/install.sh "$@"
        else
          echo "Continuing with current installer version..."
        fi
      else
        echo "You have the latest installer version."
      fi
    else
      # Fallback if sha256sum not available - just check file size
      current_size=$(stat -c%s "$0" 2>/dev/null || stat -f%z "$0" 2>/dev/null || echo "0")
      latest_size=$(stat -c%s /tmp/install_latest.sh 2>/dev/null || stat -f%z /tmp/install_latest.sh 2>/dev/null || echo "1")

      if [ "$current_size" != "$latest_size" ]; then
        echo "Installer may be outdated (size difference detected)."
        read -p "Download latest version? (y/n): " update_choice

        if [ "$update_choice" = "y" ] || [ "$update_choice" = "Y" ]; then
          cp /tmp/install_latest.sh ~/install.sh
          chmod +x ~/install.sh
          exec ~/install.sh "$@"
        fi
      fi
    fi

    rm -f /tmp/install_latest.sh
  else
    echo "================================================"
    echo "Could not fetch updates (offline or network issue)."
    echo "Using cached local version..."
    echo "================================================"
  fi
}

# Parse flags (skip per step)
SKIP_APT_UPDATE=0
SKIP_INSTALL_DEPS=0
SKIP_BLE_CONFIG=0
SKIP_INSTALL_RUSTUP=0
SKIP_DOWNLOAD_RUNTIME=0
SKIP_MODEL_SELECTION=0
SKIP_FETCH_BINARY=0  # New step for binary download
SKIP_FETCH_SURVON_SH=0
SKIP_SET_CRONTAB=0
SKIP_CLEANUP=0
SKIP_UPDATE_CHECK=0
SKIP_BLUEZ_CONFIG=0
SKIP_BLE_TEST=0
SKIP_DBUS_PERMS=0
SKIP_TERMINAL_COLORS=0
SKIP_DOWNLOAD_JUKEBOX_AUDIO=0

DEFAULT_MODEL_URL="https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q3_K_S.gguf"
DEFAULT_MODEL_NAME="phi3-mini.gguf"

MODEL_NAME=$DEFAULT_MODEL_NAME
STR_SKIP_RE_FLAG="[Skipped]. Received flag"

for arg in "$@"; do
  case $arg in
    --skip-apt-update) SKIP_APT_UPDATE=1 ;;
    --skip-install-deps) SKIP_INSTALL_DEPS=1 ;;
    --skip-install-rustup) SKIP_INSTALL_RUSTUP=1 ;;
    --skip-download-runtime) SKIP_DOWNLOAD_RUNTIME=1 ;;
    --skip-model-selection) SKIP_MODEL_SELECTION=1 ;;
    --skip-fetch-binary) SKIP_FETCH_BINARY=1 ;;  # New flag
    --skip-fetch-survon-sh) SKIP_FETCH_SURVON_SH=1 ;;
    --skip-set-crontab) SKIP_SET_CRONTAB=1 ;;
    --skip-cleanup) SKIP_CLEANUP=1 ;;
    --skip-dbus-perms) SKIP_DBUS_PERMS=1 ;;
    --skip-bluez-config) SKIP_BLUEZ_CONFIG=1 ;;
    --skip-ble-test) SKIP_BLE_TEST=1 ;;
    --skip-terminal-colors) SKIP_TERMINAL_COLORS=1 ;;
    --skip-download-jukebox-audio) SKIP_DOWNLOAD_JUKEBOX_AUDIO=1 ;;

    # unused
    --skip-ble-config) SKIP_BLE_CONFIG=1 ;;
    --skip-update-check) SKIP_UPDATE_CHECK=1 ;;
  esac
done

# Spinner function (background animation while step runs; like Node spinner lib)
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    local spinstr=$temp${spinstr%"${temp}"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

# Step 1: Update system
apt_update() {
  sudo apt update && sudo apt upgrade -y > /dev/null 2>&1
}

# Step 2: Install deps (minimal for binary execution)
install_deps() {
  sudo apt-get install -y \
        curl \
        bc \
        libasound2-dev \
        pkg-config \
        git \
        bluez \
        bluez-tools \
        libbluetooth-dev \
        libdbus-1-dev \
        libglib2.0-dev \
        libical-dev \
        libreadline-dev > /dev/null 2>&1
}

configure_bluez_for_btleplug() {
  echo "Configuring BlueZ for btleplug..."

  # Check BlueZ version
  BLUEZ_VERSION=$(bluetoothctl --version 2>&1 | grep -oP '\d+\.\d+' | head -1 || echo "0.0")
  echo "Detected BlueZ version: $BLUEZ_VERSION"

  # Enable experimental features
  echo "Enabling BlueZ experimental features..."

  # Backup original config
  sudo cp /lib/systemd/system/bluetooth.service /lib/systemd/system/bluetooth.service.backup 2>/dev/null || true

  # Add experimental flag if not present
  if ! grep -q "ExecStart=.*--experimental" /lib/systemd/system/bluetooth.service 2>/dev/null; then
    sudo sed -i 's|ExecStart=/usr/libexec/bluetooth/bluetoothd|ExecStart=/usr/libexec/bluetooth/bluetoothd --experimental|' \
      /lib/systemd/system/bluetooth.service 2>/dev/null || \
    sudo sed -i 's|ExecStart=/usr/lib/bluetooth/bluetoothd|ExecStart=/usr/lib/bluetooth/bluetoothd --experimental|' \
      /lib/systemd/system/bluetooth.service 2>/dev/null || true
  fi

  # Reload and restart bluetooth
  sudo systemctl daemon-reload
  sudo systemctl restart bluetooth

  # Add user to bluetooth group
  sudo usermod -a -G bluetooth $USER

  echo "BlueZ configured. You may need to reboot for full effect."
}

test_ble() {
  echo "Testing BLE setup..."

  # Check if hci0 exists
  if hciconfig hci0 2>/dev/null | grep -q "UP RUNNING"; then
    echo "✅ hci0 is up and running"
  else
    echo "⚠️  hci0 not found, attempting to bring it up..."
    sudo hciconfig hci0 up 2>/dev/null || echo "❌ Could not activate hci0"
  fi

  # Check Bluetooth service
  if systemctl is-active --quiet bluetooth; then
    echo "✅ Bluetooth service is active"
  else
    echo "❌ Bluetooth service is not running"
    sudo systemctl start bluetooth
  fi

  echo "BLE test complete"
}

configure_dbus_permissions() {
  echo "Configuring DBus permissions for BlueZ..."

  # Create DBus policy file
  sudo tee /etc/dbus-1/system.d/bluetooth-user.conf > /dev/null << 'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="survon">
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
  </policy>
</busconfig>
EOF

  # Reload DBus and bluetooth
  sudo systemctl reload dbus
  sudo systemctl restart bluetooth

  echo "DBus permissions configured"
}

# Step 4: Install Rustup (optional, skipped if binary used)
install_rustup() {
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y > /dev/null 2>&1
  source $HOME/.cargo/env
}

# Step 5: Download runtime-base-rust (for source, if needed)
download_runtime() {
  curl -L https://github.com/survon/runtime-base-rust/archive/master.tar.gz -o runtime-base-rust.tar.gz
  tar -xzf runtime-base-rust.tar.gz -C $HOME
  rm -rf $HOME/runtime-base-rust  # Clean old if exists
  mv $HOME/runtime-base-rust-master $HOME/runtime-base-rust
  rm runtime-base-rust.tar.gz

  if [ -d "$HOME/runtime-base-rust/modules" ]; then
    # Create modules directory if it doesn't exist
    mkdir -p $HOME/modules

    # Copy core and wasteland, overwriting conflicts but preserving user additions
    cp -r $HOME/runtime-base-rust/modules/* $HOME/modules/

    echo "Copied modules to $HOME/modules/"
  fi
}

configure_terminal_colors() {
  echo "Configuring terminal for 256 colors..."

  # Add TERM=xterm-256color to .bashrc if not already present
  if ! grep -q "export TERM=xterm-256color" $HOME/.bashrc; then
    echo "" >> $HOME/.bashrc
    echo "# Enable 256 color support for terminal" >> $HOME/.bashrc
    echo "export TERM=xterm-256color" >> $HOME/.bashrc
  fi

  # Also set it immediately for current session
  export TERM=xterm-256color

  echo "Terminal configured for 256 colors"
}

# Step 6: Model selection/download/set env
interactive_model_selection() {
  # Create models directory in home - where the app will likely look for them
  MODEL_DIR="$HOME/bundled/models"
  mkdir -p "$MODEL_DIR"
  cd "$MODEL_DIR"

  # Detect Pi model for recommendation
  PI_MODEL=$(cat /proc/cpuinfo | grep "Model" | head -1 | awk -F': ' '{print $2}')
  PI_RAM=$(free -m | awk 'NR==2{print $2}')

  echo "========================================"
  echo "Detected: $PI_MODEL"
  echo "Available RAM: ${PI_RAM}MB"
  echo "========================================"
  echo ""

  # Recommend based on hardware
  if [ "$PI_RAM" -lt 2000 ]; then
    echo "⚠️  RECOMMENDATION: Skip model download for Pi 3B"
    echo "   Your system will use fast search-only mode (no LLM)"
    echo "   This is perfect for 1GB RAM and gives instant responses"
    echo ""
  else
    echo "✅ RECOMMENDATION: Download model for Pi 4/5"
    echo "   Your system has enough RAM for the summarizer mode"
    echo "   This gives humanized, natural language responses"
    echo ""
  fi

  echo "Select model:"
  echo "1. phi3-mini.gguf (Q3_K_S, ~1.3GB) - Recommended for Pi 4/5"
  echo "2. Skip download (search-only mode) - Recommended for Pi 3B"
  echo "3. Custom URL"
  read -p "Choice: " model_choice < /dev/tty

  if [ "$model_choice" == "1" ]; then
    echo "Downloading Phi-3 Mini Q3_K_S to $MODEL_DIR..."
    echo "This will take 5-10 minutes depending on your connection."
    curl -L -o "$MODEL_NAME" "$DEFAULT_MODEL_URL"
    if [ $? -ne 0 ]; then
      echo "Failed to download model. Check disk space and internet connection."
      echo "The system will fall back to search-only mode."
    else
      echo "Model downloaded successfully!"
      # Update config to use summarizer mode
      LLM_CONFIG="$HOME/modules/core/survon_llm/config.yml"
      if [ -f "$LLM_CONFIG" ]; then
        sed -i 's/model: "search"/model: "summarizer"/' "$LLM_CONFIG"
        echo "Updated LLM config to use summarizer mode."
      fi
    fi
  elif [ "$model_choice" == "2" ]; then
    echo "Skipping model download - using search-only mode."
    echo "This is the recommended configuration for Pi 3B."
    # Don't download anything, config already defaults to "search"
  elif [ "$model_choice" == "3" ]; then
    read -p "Enter URL to your model: " custom_url < /dev/tty
    MODEL_NAME=$(basename "$custom_url")
    echo "Downloading custom model to $MODEL_DIR..."
    curl -L -o "$MODEL_NAME" "$custom_url"
    if [ $? -ne 0 ]; then
      echo "Failed to download model."
      echo "The system will fall back to search-only mode."
    else
      echo "Custom model downloaded successfully!"
      # Update config to use summarizer mode
      LLM_CONFIG="$HOME/modules/core/survon_llm/config.yml"
      if [ -f "$LLM_CONFIG" ]; then
        sed -i 's/model: "search"/model: "summarizer"/' "$LLM_CONFIG"
        echo "Updated LLM config to use summarizer mode."
      fi
    fi
  else
    echo "Invalid choice. Defaulting to search-only mode."
  fi

  # Set environment variables for model location
  sed -i "/export LLM_MODEL_NAME=/d" $HOME/.bashrc 2>/dev/null || true
  sed -i "/export LLM_MODEL_PATH=/d" $HOME/.bashrc 2>/dev/null || true
  echo "export LLM_MODEL_NAME=\"$MODEL_NAME\"" >> $HOME/.bashrc
  echo "export LLM_MODEL_PATH=\"$MODEL_DIR/$MODEL_NAME\"" >> $HOME/.bashrc
  source $HOME/.bashrc

  if [ -f "$MODEL_DIR/$MODEL_NAME" ]; then
    echo "Model ready at: $MODEL_DIR/$MODEL_NAME"
  else
    echo "No model installed - using search-only mode"
  fi
}

# Step 6.5: Optional audio download for Jukebox
download_jukebox_audio() {
  AUDIO_DIR="$HOME/modules/core/big_band_mix/audio"

  echo "========================================"
  echo "   Optional: Jukebox Audio Download    "
  echo "========================================"
  echo ""
  echo "The Jukebox module includes a Big Band Mix album"
  echo "but the audio files need to be downloaded separately."
  echo ""
  echo "Collection: Big Band Mix (Recordings 1935-1945)"
  echo "Source: Internet Archive (Public Domain)"
  echo "Size: ~117MB (25 tracks)"
  echo ""
  echo "Download options:"
  echo "1. Download now (~5-10 minutes)"
  echo "2. Skip (you can download manually later)"
  echo ""
  read -p "Choice: " audio_choice < /dev/tty

  if [ "$audio_choice" == "1" ]; then
    echo ""
    echo "Downloading Big Band Mix audio files..."
    echo "This will take 5-10 minutes depending on your connection."

    # Create audio directory if it doesn't exist
    mkdir -p "$AUDIO_DIR"
    cd "$AUDIO_DIR"

    # Download the zip file
    echo "Downloading archive..."
    if curl -L "https://archive.org/compress/BigBandMixRecordings1935-1945/formats=VBR%20MP3&file=/BigBandMixRecordings1935-1945.zip" -o BigBandMix.zip; then
      echo "Download complete. Extracting files..."

      # Extract the files
      if unzip -q BigBandMix.zip; then
        # Clean up zip file
        rm BigBandMix.zip

        # Count the audio files
        AUDIO_COUNT=$(find . -type f \( -name "*.mp3" -o -name "*.wav" -o -name "*.flac" -o -name "*.ogg" \) | wc -l)

        echo "✅ Successfully extracted $AUDIO_COUNT audio files"
        echo "   Location: $AUDIO_DIR"
      else
        echo "❌ Failed to extract archive. Check disk space."
        rm -f BigBandMix.zip
      fi
    else
      echo "❌ Failed to download audio files."
      echo "   You can download them manually later using:"
      echo "   cd $AUDIO_DIR"
      echo "   curl -L 'https://archive.org/compress/BigBandMixRecordings1935-1945/formats=VBR%20MP3&file=/BigBandMixRecordings1935-1945.zip' -o BigBandMix.zip"
      echo "   unzip BigBandMix.zip"
    fi
  elif [ "$audio_choice" == "2" ]; then
    echo "Skipping audio download."
    echo ""
    echo "To download manually later, run these commands:"
    echo "  cd $AUDIO_DIR"
    echo "  curl -L 'https://archive.org/compress/BigBandMixRecordings1935-1945/formats=VBR%20MP3&file=/BigBandMixRecordings1935-1945.zip' -o BigBandMix.zip"
    echo "  unzip BigBandMix.zip"
    echo "  rm BigBandMix.zip"
  else
    echo "Invalid choice. Skipping audio download."
  fi

  cd $HOME
}

# Step 7: Fetch pre-built binary from GitHub releases
fetch_binary() {
  # Create bin directory if it doesn't exist
  sudo mkdir -p /usr/local/bin

  echo "Downloading pre-built binary from GitHub..."
  # Download the armv7 binary from latest release
  # The release.yml uploads it as runtime-base-rust (no extension)
  curl -L https://github.com/survon/runtime-base-rust/releases/latest/download/runtime-base-rust \
    -o /tmp/runtime-base-rust

  if [ $? -ne 0 ]; then
    echo "Failed to download binary. Check if a release exists on GitHub."
    exit 1
  fi

  sudo mv /tmp/runtime-base-rust /usr/local/bin/runtime-base-rust
  sudo chmod +x /usr/local/bin/runtime-base-rust

  echo "Binary installed to /usr/local/bin/runtime-base-rust"
}

# Step 8: Fetch survon.sh and create module manager
fetch_survon_sh() {
  curl -O https://raw.githubusercontent.com/survon/survon-os/master/scripts/survon.sh
  mv survon.sh $HOME/survon.sh
  chmod +x $HOME/survon.sh

  # Create module_manager.sh
  cat > $HOME/module_manager.sh << 'EOF'
#!/bin/bash
MODULES_DIR="/home/survon/modules/wasteland"
mkdir -p "$MODULES_DIR"

show_installed_wasteland_modules() {
    echo "=== Installed Wasteland Modules ==="
    if [ -d "$MODULES_DIR" ]; then
        for module_dir in "$MODULES_DIR"/*; do
            if [ -d "$module_dir" ] && [ -f "$module_dir/config.yml" ]; then
                module_name=$(basename "$module_dir")
                desc=$(grep "description:" "$module_dir/config.yml" 2>/dev/null | cut -d':' -f2- | sed 's/^ *//')
                [ -z "$desc" ] && desc="No description"
                echo " [$module_name] - $desc"
            fi
        done
    fi
    echo ""
}

while true; do
    echo "========================================"
    echo "    Survon Wasteland Module Manager     "
    echo "========================================"
    echo "1. Show installed Wasteland modules"
    echo "2. Back to main menu"
    echo ""
    read -p "Select option: " choice

    case $choice in
        1) show_installed_wasteland_modules; read -p "Press Enter to continue..." ;;
        2) exit 0 ;;
        *) echo "Invalid option." ;;
    esac
    clear
done
EOF
  chmod +x $HOME/module_manager.sh

  # Create boot selector script
  cat > $HOME/boot_selector.sh << 'EOF'
#!/bin/bash
# boot_selector.sh - Simple reliable boot selector

clear
echo "========================================="
echo "         SURVON OS BOOT LOADER          "
echo "========================================="
echo ""
echo "Starting Survon Runtime in 5 seconds..."
echo ""
echo "Press [S] for Survon OS Menu"
echo "Press [M] for Maintenance Mode"
echo ""

# Simple 5 second timeout with single key detection
if read -r -s -n 1 -t 5 key; then
    case "$key" in
        "s"|"S")
            clear
            echo "Entering Survon OS Menu..."
            cd /home/survon
            /home/survon/survon.sh
            # When survon.sh exits, exit to bash
            exit 0
            ;;
        "m"|"M")
            clear
            echo "Maintenance Mode"
            echo "=============="
            echo "Type 'survon.sh' for menu, 'runtime-base-rust' for app"
            echo ""
            exit 0
            ;;
        *)
            # Any other key - boot immediately
            ;;
    esac
fi

# Default: boot into runtime
clear
echo "Starting Survon Runtime..."
cd /home/survon
exec /usr/local/bin/runtime-base-rust
EOF
  chmod +x $HOME/boot_selector.sh
}

# Step 8: Set crontab
set_crontab() {
  # Remove old crontab entry if exists
  crontab -l 2>/dev/null | grep -v "survon.sh" | crontab - 2>/dev/null || true

  # Setup auto-login instead
  echo "Setting up auto-login for boot loader..."

  # Enable auto-login using raspi-config in non-interactive mode
  sudo raspi-config nonint do_boot_behaviour B2

  # Add boot selector to .bashrc if not already there
  if ! grep -q "boot_selector.sh" $HOME/.bashrc; then
    cat >> $HOME/.bashrc << 'EOF'

# Auto-run boot selector only on console login (not SSH)
if [ -z "$SSH_CLIENT" ] && [ -z "$SSH_TTY" ]; then
    exec /home/survon/boot_selector.sh
fi
EOF
  fi
}

# Step 9: Cleanup
cleanup() {
  cd $HOME
  rm -rf runtime-base-rust llama.cpp
}

# Controller (pipeline; execute or skip each step with spinner for non-interactive)
echo "Starting installation..."

# Check for updates first
check_installer_updates "$@"

# Ensure installer is saved locally for survon.sh to use
if [ ! -f "$HOME/install.sh" ]; then
  echo "Downloading installer to home directory..."
  curl -L "$INSTALLER_URL" -o "$HOME/install.sh"
  chmod +x "$HOME/install.sh"
elif [ "$0" != "$HOME/install.sh" ] && [ "$0" != "bash" ]; then
  # If running from somewhere else (not piped), copy it
  cp "$0" "$HOME/install.sh"
  chmod +x "$HOME/install.sh"
fi

echo "Step 1 - Update Unix System: "
if [ $SKIP_APT_UPDATE -eq 0 ]; then
  echo -n "[Updating]... "
  apt_update & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-apt-update"
fi

echo "Step 2 - Install System Libraries: "
if [ $SKIP_INSTALL_DEPS -eq 0 ]; then
  echo -n "[Installing]... "
  install_deps & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-install-deps"
fi

echo "Step 2.5 - Configure Terminal Colors: "
if [ $SKIP_TERMINAL_COLORS -eq 0 ]; then
  echo -n "[Configuring]... "
  configure_terminal_colors & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-terminal-colors"
fi

echo "Step 3 - Configure BlueZ for btleplug: "
if [ $SKIP_BLUEZ_CONFIG -eq 0 ]; then
  echo -n "[Configuring]... "
  configure_bluez_for_btleplug & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-bluez-config"
fi

echo "Step 3.25 - Configure DBus Permissions: "
if [ $SKIP_DBUS_PERMS -eq 0 ]; then
  echo -n "[Configuring]... "
  configure_dbus_permissions & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-dbus-perms"
fi

echo "Step 3.5 - Test BLE Setup: "
if [ $SKIP_BLE_TEST -eq 0 ]; then
  test_ble
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-ble-test"
fi

echo "Step 4 - Update Rust: "
if [ $SKIP_INSTALL_RUSTUP -eq 0 ]; then
  echo -n "[Installing]... "
  install_rustup & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-install-rustup"
fi

echo "Step 5 - Download Survon Runtime: "
if [ $SKIP_DOWNLOAD_RUNTIME -eq 0 ]; then
  echo -n "[Downloading]... "
  download_runtime & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-download-runtime"
fi

echo "Step 6 - Select Survon AI Model: "
if [ $SKIP_MODEL_SELECTION -eq 0 ]; then
  interactive_model_selection
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-model-selection. Applying default model $MODEL_NAME"
fi

echo "Step 6.5 - Optional Jukebox Audio Download: "
if [ $SKIP_DOWNLOAD_JUKEBOX_AUDIO -eq 0 ]; then
  download_jukebox_audio
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-download-jukebox-audio"
fi

echo "Step 7 - Fetch Pre-built Binary: "
if [ $SKIP_FETCH_BINARY -eq 0 ]; then
  echo -n "[Fetching]... "
  fetch_binary & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-fetch-binary"
fi

echo "Step 8 - Fetch Latest Survon Launcher: "
if [ $SKIP_FETCH_SURVON_SH -eq 0 ]; then
  echo -n "[Fetching]... "
  fetch_survon_sh & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-fetch-survon-sh"
fi

echo "Step 9 - Schedule Launcher: "
if [ $SKIP_SET_CRONTAB -eq 0 ]; then
  echo -n "[Setting Crontab]... "
  set_crontab & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-set-crontab"
fi

echo "Step 10 - Cleanup: "
if [ $SKIP_CLEANUP -eq 0 ]; then
  echo -n "[Cleaning]... "
  cleanup & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-cleanup"
fi

echo "=========================================="
echo "Survon OS installed successfully!"
echo "=========================================="
echo ""
echo "IMPORTANT: You need to REBOOT for BLE changes to take effect"
echo ""
echo "After reboot:"
echo "  - User will be in 'bluetooth' group"
echo "  - BlueZ experimental features enabled"
echo "  - BLE should work with btleplug"
echo ""
echo "If you still see DBus errors after reboot:"
echo "  1. Check BlueZ version: bluetoothctl --version"
echo "  2. Should be 5.50 or higher"
echo "  3. Run: sudo systemctl status bluetooth"
echo ""
read -p "Reboot now? (y/n): " reboot_choice
if [ "$reboot_choice" = "y" ] || [ "$reboot_choice" = "Y" ]; then
  sudo reboot
fi
