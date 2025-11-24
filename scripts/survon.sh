#!/bin/bash

# Menu loop
while true; do
  echo "Survon OS Menu"
  echo "1. Re-install Latest Survon OS"
  echo "2. Manage configs/env vars"
  echo "3. Update Survon Runtime"
  echo "4. Launch Survon Runtime"
  echo "5. Wasteland Module Manager"
  echo "6. Exit"
  read -p "Select: " choice

  case $choice in
    1) # Run the installer
       echo "Running installer..."
       bash /home/survon/install.sh
       echo "Installer complete. Reboot recommended."
       ;;
    2) # Manage configs (show/edit env vars dynamically from .bashrc)
       echo "Current env vars:"
       if [ -f /home/survon/.bashrc ]; then
         # Extract and display all export lines dynamically
         sed -n 's/export \(.*\)=\(.*\)/\1: \2/p' /home/survon/.bashrc | while read -r key value; do
           echo "$key: $value"
         done
       else
         echo "No .bashrc found. Env vars will be created."
       fi
       read -p "Set ENV_VAR (e.g., LLM_MODEL_NAME): " var_name
       if [ -n "$var_name" ]; then
         read -p "Value: " var_value
         sed -i "/export $var_name=/d" /home/survon/.bashrc  # Remove old if exists
         echo "export $var_name=\"$var_value\"" >> /home/survon/.bashrc  # Persist new
         source /home/survon/.bashrc
         echo "Config set. Accessible in Rust via std::env::var."
       else
         echo "No ENV_VAR specified. Skipping."
       fi
       ;;
    3) # Update runtime-base-rust binary from GitHub releases
       echo "Downloading latest pre-built binary from GitHub..."
       curl -L https://github.com/survon/runtime-base-rust/releases/latest/download/runtime-base-rust \
         -o /tmp/runtime-base-rust
       if [ $? -eq 0 ]; then
         echo "Download success. Replacing binary..."
         sudo mv /tmp/runtime-base-rust /usr/local/bin/runtime-base-rust
         sudo chmod +x /usr/local/bin/runtime-base-rust
         echo "Binary updated successfully."
       else
         echo "Download failed. Check internet connection and GitHub releases."
       fi
       ;;
    4) # Launch Rust TUI
       # Change to home directory where models are expected
       cd /home/survon
       /usr/local/bin/runtime-base-rust
       ;;
    5) # Module Manager
       bash /home/survon/module_manager.sh
       ;;
    6) exit 0 ;;
    *) echo "Invalid." ;;
  esac
done
