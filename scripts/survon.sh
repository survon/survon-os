#!/bin/bash

RUNTIME_BINARY="survon-runtime-base"
COUNCIL_BINARY="survon-runtime-council-seat"
RUNTIME_URL="https://github.com/survon/survon-runtime-base/releases/latest/download/$RUNTIME_BINARY"
COUNCIL_URL="https://github.com/survon/survon-runtime-council-seat/releases/latest/download/$COUNCIL_BINARY"

# Menu loop
while true; do
  echo "Survon OS Menu"
  echo "1. Re-install Latest Survon OS"
  echo "2. Manage configs/env vars"
  echo ""
  echo "--- Survon Runtime Base ---"
  echo "3. Install/Update Survon Runtime Base"
  echo "4. Launch Survon Runtime Base"
  echo ""
  echo "--- Council Seat ---"
  echo "5. Install Council Seat"
  echo "6. Update Council Seat"
  echo "7. Configure Council Strategy"
  echo "8. Launch Council Seat"
  echo ""
  echo "--- Other ---"
  echo "9. Wasteland Module Manager"
  echo "10. Exit"
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
    3) # Install/Update Runtime Base
       echo "Downloading latest $RUNTIME_BINARY..."
       curl -L "$RUNTIME_URL" -o /tmp/$RUNTIME_BINARY
       if [ $? -eq 0 ]; then
         echo "Download success. Installing..."
         sudo mv /tmp/$RUNTIME_BINARY /usr/local/bin/$RUNTIME_BINARY
         sudo chmod +x /usr/local/bin/$RUNTIME_BINARY
         echo "$RUNTIME_BINARY installed successfully."
         
         # Set env vars if not already set
         if ! grep -q "export RUNTIME_NAME=" ~/.bashrc 2>/dev/null; then
           echo "export RUNTIME_NAME=base" >> ~/.bashrc
         fi
       else
         echo "Download failed. Check internet connection and GitHub releases."
       fi
       ;;
    4) # Launch Runtime Base
       cd /home/survon
       if [ -f /usr/local/bin/$RUNTIME_BINARY ]; then
         /usr/local/bin/$RUNTIME_BINARY
       else
         echo "Runtime not installed. Select option 3 to install."
       fi
       ;;
    5) # Install Council Seat
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
       curl -sSL https://raw.githubusercontent.com/survon/survon-runtime-council-seat/master/scripts/install.sh | bash -s -- --strategy "$STRATEGY"
       echo "Council Seat installed!"
       ;;
    6) # Update Council Seat
       echo "Downloading latest $COUNCIL_BINARY..."
       curl -L "$COUNCIL_URL" -o /tmp/$COUNCIL_BINARY
       if [ $? -eq 0 ]; then
         echo "Download success. Installing..."
         sudo mv /tmp/$COUNCIL_BINARY /usr/local/bin/$COUNCIL_BINARY
         sudo chmod +x /usr/local/bin/$COUNCIL_BINARY
         echo "$COUNCIL_BINARY updated successfully."
       else
         echo "Download failed. Check internet connection and GitHub releases."
       fi
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
       if [ -f /usr/local/bin/$COUNCIL_BINARY ]; then
         /usr/local/bin/$COUNCIL_BINARY
       else
         echo "Council Seat not installed. Select option 5 to install."
       fi
       ;;
    9) # Module Manager
       bash /home/survon/module_manager.sh
       ;;
    10) exit 0 ;;
    *) echo "Invalid." ;;
  esac
done
