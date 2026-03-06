#!/bin/bash

# Menu loop
while true; do
  echo "Survon OS Menu"
  echo "1. Re-install Latest Survon OS"
  echo "2. Manage configs/env vars"
  echo "3. Update Survon Runtime"
  echo "4. Launch Survon Runtime"
  echo "5. Wasteland Module Manager"
  echo "--- Council Seat ---"
  echo "6. Install Council Seat"
  echo "7. Configure Council Strategy"
  echo "8. Launch Council Seat"
  echo "9. Exit"
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
    6) # Install Council Seat
       echo "Installing Survon Council Seat..."
       echo ""
       echo "Available strategies:"
       echo "  1. librarian    - Search static knowledge (default)"
       echo "  2. medicine    - Medical expertise"
       echo "  3. mechanical  - Mechanical engineering"
       echo "  4. botany      - Agriculture & plants"
       echo "  5. veterinary  - Animal health"
       echo "  6. building    - Construction"
       echo "  7. survival    - Survival skills"
       read -p "Select strategy (1-7, default 1): " strategy_choice
       
       case $strategy_choice in
         2) STRATEGY="medicine" ;;
         3) STRATEGY="mechanical" ;;
         4) STRATEGY="botany" ;;
         5) STRATEGY="veterinary" ;;
         6) STRATEGY="building" ;;
         7) STRATEGY="survival" ;;
         *) STRATEGY="librarian" ;;
       esac
       
       echo "Installing with strategy: $STRATEGY"
       curl -sSL https://raw.githubusercontent.com/survon/survon-council-seat/master/scripts/install.sh | bash -s -- --strategy "$STRATEGY"
       echo "Council Seat installed!"
       ;;
    7) # Configure Council Strategy
       echo "Current council strategy configuration:"
       grep -E "COUNCIL_STRATEGY|DATABASE_PATH|LOG_LEVEL" /home/survon/.bashrc 2>/dev/null || echo "No configuration found"
       echo ""
       echo "Available strategies:"
       echo "  librarian, medicine, mechanical, botany, veterinary, building, survival"
       read -p "Enter new strategy name: " new_strategy
       if [ -n "$new_strategy" ]; then
         sed -i "/export COUNCIL_STRATEGY=/d" /home/survon/.bashrc
         echo "export COUNCIL_STRATEGY=$new_strategy" >> /home/survon/.bashrc
         source /home/survon/.bashrc
         echo "Strategy updated to: $new_strategy"
       fi
       ;;
    8) # Launch Council Seat
       cd /home/survon
       if [ -f /usr/local/bin/survon-council-seat ]; then
         /usr/local/bin/survon-council-seat
       else
         echo "Council Seat not installed. Select option 6 to install."
       fi
       ;;
    9) exit 0 ;;
    *) echo "Invalid." ;;
  esac
done
