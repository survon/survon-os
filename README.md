# survon-os

Survon OS is a minimal, bash-driven bootable system for Raspberry Pi, acting as a Unix-like interface for managing 
and launching the [runtime-base-rust](https://github.com/survon/runtime-base-rust) application. 
The installer pulls dependencies, compiles llama-cli, downloads models (e.g., phi3-mini.gguf), and sets env vars like LLM_MODEL_NAME (accessible in Rust via std::env::var, similar to process.env in Node).

## Requirements
- Raspberry Pi 3B v1.2 (armhf architecture).
- MicroSD card (16GB+).
- Ethernet for initial setup (no WiFi on base model).
- Computer for flashing (Mac/Windows/Ubuntu).

## Installation
### Step 1: Flash SD Card
Use Raspberry Pi Imager to install Raspberry Pi OS Lite (32-bit) for headless setup.

1. Download and install Raspberry Pi Imager from https://www.raspberrypi.com/software/.
2. Insert SD card into your computer.
3. Run Imager.
4. Click "Choose OS" > "Raspberry Pi OS (other)" > "Raspberry Pi OS Lite (32-bit)".
5. Click "Choose Storage" and select SD card.
6. Click gear icon (Advanced): Enable SSH (password authentication), set hostname (e.g., survon), username (e.g., survon), password.
7. Click "Write".

Insert SD into Pi, power on. Wait 1-2 min for boot.

### Step 2: Install Survon OS
Via SSH (from computer: `ssh survon@survon.local` or IP) or direct (keyboard/HDMI on Pi).

Run:
```bash
curl -sSL https://raw.githubusercontent.com/survon/survon-os/master/scripts/install.sh | bash -s -- --cleanup
```
- Select model (1: phi3-mini.gguf; 2: custom URL).
- Sets LLM_MODEL_NAME (e.g., "phi3-mini.gguf").
- Reboot: `sudo reboot` for menu.

## Usage
- Menu auto-starts: Manage env vars (e.g., LLM_MODEL_NAME, DEBUG), update binary from releases, launch TUI (`/usr/local/bin/runtime-base-rust`).
- In Rust: Use `std::env::var("LLM_MODEL_NAME").unwrap_or("phi3-mini.gguf".to_string())` for model path (assumption disclosed: Based on prior chat; verify in main.rs).
- Test LLM: `./bundled/llama-cli --model bundled/models/${LLM_MODEL_NAME:-phi3-mini.gguf} ...` (from README.md).

## Advanced Configuration

### Debug Logging
The runtime supports debug logging via the DEBUG environment variable. To enable:

**Via survon.sh menu:**
1. Select option 2 (Manage configs/env vars)
2. Set ENV_VAR: `DEBUG`
3. Value: `true`
4. Launch runtime (option 4)

**Or modify survon.sh directly:**
Edit option 4 in `/home/survon/survon.sh`:
```bash
4) cd /home/survon
   DEBUG=true /usr/local/bin/runtime-base-rust
   ;;
```

Debug logs are written to `./logs/debug.log` (cleared on each startup).

## License
MIT License. See [LICENSE](./LICENSE).
