#!/bin/bash

# Assumptions: Run as survon (non-root); Pi OS Lite armhf (RPi 3B v1.2); repos on master (no git; use curl for tarballs/zips).
# Flags: --skip-<step> (e.g., --skip-apt-update to skip that function).
# Steps: Each in named function; controller downloads pre-built binary instead of building.
# Spinner: Simple animation during non-interactive steps. No spinner for interactive steps.

set -e  # Exit on error.

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
  sudo apt install -y curl bc > /dev/null 2>&1  # curl for downloads, bc for boot timer
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
  cd $HOME/runtime-base-rust
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

# Step 7: Fetch survon.sh
fetch_survon_sh() {
  curl -O https://raw.githubusercontent.com/survon/survon-os/master/scripts/survon.sh
  mv survon.sh $HOME/survon.sh
  chmod +x $HOME/survon.sh

  # Create boot selector script
  cat > $HOME/boot_selector.sh << 'EOF'
#!/bin/bash
# boot_selector.sh - DOS-style boot interrupt system for Survon OS

clear
echo "========================================="
echo "         SURVON OS BOOT LOADER          "
echo "========================================="
echo ""
echo "Starting Survon Runtime in 5 seconds..."
echo ""
echo "Press [SPACE] for Survon OS Menu"
echo "Press [M] for Maintenance Mode"
echo ""

COUNTER=50
BOOT_MODE="runtime"

while [ $COUNTER -gt 0 ]; do
    printf "\rBooting in %.1f seconds... " $(echo "scale=1; $COUNTER/10" | bc)

    if read -r -s -n 1 -t 0.1 key; then
        case "$key" in
            " ")
                BOOT_MODE="menu"
                break
                ;;
            "m"|"M")
                BOOT_MODE="maintenance"
                break
                ;;
        esac
    fi

    let COUNTER=COUNTER-1
done

clear

case $BOOT_MODE in
    "runtime")
        echo "Starting Survon Runtime..."
        cd /home/survon
        exec /usr/local/bin/runtime-base-rust
        ;;
    "menu")
        echo "Entering Survon OS Menu..."
        cd /home/survon
        exec /home/survon/survon.sh
        ;;
    "maintenance")
        echo "Maintenance Mode"
        echo "=============="
        echo "Type 'survon.sh' for menu, 'runtime-base-rust' for app"
        echo ""
        ;;
esac
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
