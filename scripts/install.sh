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
  echo "Checking for installer updates..."

  # Download latest installer to temp file
  if curl -s -L "$INSTALLER_URL" -o /tmp/install_latest.sh 2>/dev/null; then
    # Calculate hashes
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
    echo "Could not check for updates (offline mode). Continuing..."
  fi
}

# Parse flags (skip per step)
SKIP_APT_UPDATE=0
SKIP_INSTALL_DEPS=0
SKIP_INSTALL_RUSTUP=0
SKIP_DOWNLOAD_RUNTIME=0
SKIP_MODEL_SELECTION=0
SKIP_FETCH_BINARY=0  # New step for binary download
SKIP_FETCH_SURVON_SH=0
SKIP_SET_CRONTAB=0
SKIP_CLEANUP=0
SKIP_UPDATE_CHECK=0

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
      bluez \
      libbluetooth-dev \
      libdbus-1-dev \
      libasound2-dev \
      pkg-config > /dev/null 2>&1
}

# Step 3: Install Rustup (optional, skipped if binary used)
install_rustup() {
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y > /dev/null 2>&1
  source $HOME/.cargo/env
}

# Step 4: Download runtime-base-rust (for source, if needed)
download_runtime() {
  curl -L https://github.com/survon/runtime-base-rust/archive/master.tar.gz -o runtime-base-rust.tar.gz
  tar -xzf runtime-base-rust.tar.gz -C $HOME
  rm -rf $HOME/runtime-base-rust  # Clean old if exists
  mv $HOME/runtime-base-rust-master $HOME/runtime-base-rust
  rm runtime-base-rust.tar.gz

  # Copy the wasteland modules to the home directory where the binary expects them
  if [ -d "$HOME/runtime-base-rust/wasteland" ]; then
    cp -r $HOME/runtime-base-rust/wasteland $HOME/
    echo "Copied default modules to $HOME/wasteland/modules/"
  fi
}

# Step 5: Model selection/download/set env
interactive_model_selection() {
  # Create models directory in home - where the app will likely look for them
  MODEL_DIR="$HOME/bundled/models"
  mkdir -p "$MODEL_DIR"
  cd "$MODEL_DIR"

  echo "Select model:"
  echo "1. phi3-mini.gguf (Q3_K_S quantized, ~1.3GB)"
  echo "2. Custom"
  read -p "Choice: " model_choice < /dev/tty

  if [ "$model_choice" == "1" ]; then
    echo "Downloading Phi-3 model to $MODEL_DIR (this may take a while)..."
    curl -L -o "$MODEL_NAME" "$DEFAULT_MODEL_URL"
    if [ $? -ne 0 ]; then
      echo "Failed to download model. Check disk space and internet connection."
      exit 1
    fi
  elif [ "$model_choice" == "2" ]; then
    read -p "Enter URL to your model: " custom_url < /dev/tty
    MODEL_NAME=$(basename "$custom_url")
    echo "Downloading custom model to $MODEL_DIR..."
    curl -L -o "$MODEL_NAME" "$custom_url"
    if [ $? -ne 0 ]; then
      echo "Failed to download model."
      exit 1
    fi
  else
    echo "Invalid choice. Exiting."
    exit 1
  fi

  # Set environment variables for model location
  sed -i "/export LLM_MODEL_NAME=/d" $HOME/.bashrc 2>/dev/null || true
  sed -i "/export LLM_MODEL_PATH=/d" $HOME/.bashrc 2>/dev/null || true
  echo "export LLM_MODEL_NAME=\"$MODEL_NAME\"" >> $HOME/.bashrc
  echo "export LLM_MODEL_PATH=\"$MODEL_DIR/$MODEL_NAME\"" >> $HOME/.bashrc
  source $HOME/.bashrc

  echo "Model downloaded successfully to: $MODEL_DIR/$MODEL_NAME"
}

# Step 6: Fetch pre-built binary from GitHub releases
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

# Step 7: Fetch survon.sh and create module manager
fetch_survon_sh() {
  curl -O https://raw.githubusercontent.com/survon/survon-os/master/scripts/survon.sh
  mv survon.sh $HOME/survon.sh
  chmod +x $HOME/survon.sh

  # Create module_manager.sh
  cat > $HOME/module_manager.sh << 'EOF'
#!/bin/bash
MODULES_DIR="/home/survon/wasteland/modules"
mkdir -p "$MODULES_DIR"

show_installed_modules() {
    echo "=== Installed Modules ==="
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
    echo "       Survon Module Manager"
    echo "========================================"
    echo "1. Show installed modules"
    echo "2. Back to main menu"
    echo ""
    read -p "Select option: " choice

    case $choice in
        1) show_installed_modules; read -p "Press Enter to continue..." ;;
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

# Check for updates first (unless explicitly skipped)
if [ -z "$SKIP_UPDATE_CHECK" ]; then
  check_installer_updates "$@"
fi

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

echo "Step 3 - Update Rust: "
if [ $SKIP_INSTALL_RUSTUP -eq 0 ]; then
  echo -n "[Installing]... "
  install_rustup & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-install-rustup"
fi

echo "Step 4 - Download Survon Runtime: "
if [ $SKIP_DOWNLOAD_RUNTIME -eq 0 ]; then
  echo -n "[Downloading]... "
  download_runtime & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-download-runtime"
fi

# TODO skipping model selection doesnt make sense unless we choose one for the user here
echo "Step 5 - Select Survon AI Model: "
if [ $SKIP_MODEL_SELECTION -eq 0 ]; then
  interactive_model_selection
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-model-selection. Applying default model $MODEL_NAME"
fi

echo "Step 6 - Fetch Pre-built Binary: "
if [ $SKIP_FETCH_BINARY -eq 0 ]; then
  echo -n "[Fetching]... "
  fetch_binary & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-fetch-binary"
fi

echo "Step 7 - Fetch Latest Survon Launcher: "
if [ $SKIP_FETCH_SURVON_SH -eq 0 ]; then
  echo -n "[Fetching]... "
  fetch_survon_sh & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-fetch-survon-sh"
fi

echo "Step 8 - Schedule Launcher: "
if [ $SKIP_SET_CRONTAB -eq 0 ]; then
  echo -n "[Setting Crontab]... "
  set_crontab & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-set-crontab"
fi

echo "Step 9 - Cleanup: "
if [ $SKIP_CLEANUP -eq 0 ]; then
  echo -n "[Cleaning]... "
  cleanup & spinner $!
  echo "Done."
else
  echo "$STR_SKIP_RE_FLAG --skip-cleanup"
fi

echo "Survon OS installed. LLM_MODEL_NAME set to $MODEL_NAME. Reboot to start menu."
