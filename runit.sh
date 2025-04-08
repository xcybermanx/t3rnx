#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="$HOME/t3rn-v2"
SERVICE_FILE="/etc/systemd/system/t3rn-executor-v2.service"
CONFIG_FILE="$HOME/.t3rn_config.json"

log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local border="-----------------------------------------------------"
    echo -e "${border}"
    case $level in
        "INFO") echo -e "${CYAN}[INFO] ${timestamp} - ${message}${NC}" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS] ${timestamp} - ${message}${NC}" ;;
        "ERROR") echo -e "${RED}[ERROR] ${timestamp} - ${message}${NC}" ;;
        *) echo -e "${YELLOW}[UNKNOWN] ${timestamp} - ${message}${NC}" ;;
    esac
    echo -e "${border}\n"
}

echo -e "${CYAN}Starting Auto Install T3rn Executor v2${NC}"
sleep 2

log "INFO" "1. Update system"
sudo apt update && sudo apt upgrade -y

# Handle credentials
if [[ -f "$CONFIG_FILE" ]]; then
    log "INFO" "Credentials file detected."
    read -p "Do you want to reuse the saved PRIVATE_KEY_LOCAL and APIKEY_ALCHEMY? (y/n): " reuse_keys

    if [[ "$reuse_keys" == "y" || "$reuse_keys" == "Y" ]]; then
        PRIVATE_KEY_LOCAL=$(jq -r '.PRIVATE_KEY_LOCAL' "$CONFIG_FILE")
        APIKEY_ALCHEMY=$(jq -r '.APIKEY_ALCHEMY' "$CONFIG_FILE")
        if [[ -z "$PRIVATE_KEY_LOCAL" || -z "$APIKEY_ALCHEMY" ]]; then
            log "ERROR" "Saved values are incomplete. You must enter new ones."
            exit 1
        fi
        log "SUCCESS" "Using saved credentials."
    else
        read -p "Enter PRIVATE_KEY_LOCAL: " PRIVATE_KEY_LOCAL
        [[ -z "$PRIVATE_KEY_LOCAL" ]] && { log "ERROR" "PRIVATE_KEY_LOCAL cannot be empty!"; exit 1; }

        read -p "Enter APIKEY_ALCHEMY: " APIKEY_ALCHEMY
        [[ -z "$APIKEY_ALCHEMY" ]] && { log "ERROR" "APIKEY_ALCHEMY cannot be empty!"; exit 1; }

        # Save credentials in the config file
        echo "{\"PRIVATE_KEY_LOCAL\":\"$PRIVATE_KEY_LOCAL\", \"APIKEY_ALCHEMY\":\"$APIKEY_ALCHEMY\"}" > "$CONFIG_FILE"
        log "SUCCESS" "Credentials saved to $CONFIG_FILE"
    fi
else
    read -p "Enter PRIVATE_KEY_LOCAL: " PRIVATE_KEY_LOCAL
    [[ -z "$PRIVATE_KEY_LOCAL" ]] && { log "ERROR" "PRIVATE_KEY_LOCAL cannot be empty!"; exit 1; }

    read -p "Enter APIKEY_ALCHEMY: " APIKEY_ALCHEMY
    [[ -z "$APIKEY_ALCHEMY" ]] && { log "ERROR" "APIKEY_ALCHEMY cannot be empty!"; exit 1; }

    # Save credentials in the config file
    echo "{\"PRIVATE_KEY_LOCAL\":\"$PRIVATE_KEY_LOCAL\", \"APIKEY_ALCHEMY\":\"$APIKEY_ALCHEMY\"}" > "$CONFIG_FILE"
    log "SUCCESS" "Credentials saved to $CONFIG_FILE"
fi

mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR"

# Get latest version tag
log "INFO" "Checking latest version from GitHub"
TAG=$(curl -s https://api.github.com/repos/t3rn/executor-release/releases/latest | awk -F '\"' '/tag_name/ {print $4}')

if [[ -f "$INSTALL_DIR/.version" ]]; then
    OLD_TAG=$(<"$INSTALL_DIR/.version")
    if [[ "$OLD_TAG" == "$TAG" ]]; then
        log "SUCCESS" "Latest version ($TAG) already installed. Skipping download."
    else
        log "INFO" "New version found: $TAG (old: $OLD_TAG). Downloading..."
        DOWNLOAD=1
    fi
else
    DOWNLOAD=1
fi

if [[ "$DOWNLOAD" == "1" ]]; then
    wget -q "https://github.com/t3rn/executor-release/releases/download/$TAG/executor-linux-$TAG.tar.gz"
    tar -xzf executor-linux-*.tar.gz
    echo "$TAG" > "$INSTALL_DIR/.version"
fi

cd executor/executor/bin || exit 1

# Write systemd service
is_port_in_use() { netstat -tuln | grep -q ":$1"; }
PORT=9090
while is_port_in_use $PORT; do PORT=$((PORT + 1)); done
log "INFO" "Using port $PORT"

cat <<EOF | sudo tee "$SERVICE_FILE" >/dev/null
[Unit]
Description=t3rn Executor v2 Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$INSTALL_DIR/executor/executor/bin
ExecStart=$INSTALL_DIR/executor/executor/bin/executor --port $PORT
Restart=always
RestartSec=10
Environment=ENVIRONMENT=testnet
Environment=LOG_LEVEL=debug
Environment=LOG_PRETTY=false
Environment=EXECUTOR_PROCESS_BIDS_ENABLED=true
Environment=EXECUTOR_PROCESS_ORDERS_ENABLED=true
Environment=EXECUTOR_PROCESS_CLAIMS_ENABLED=true
Environment=EXECUTOR_MAX_L3_GAS_PRICE=5000
Environment=EXECUTOR_MIN_TX_ETH=2
Environment=EXECUTOR_MAX_TX_GAS=2000000
Environment=PRIVATE_KEY_LOCAL=$PRIVATE_KEY_LOCAL
Environment=APIKEY_ALCHEMY=$APIKEY_ALCHEMY
Environment=ENABLED_NETWORKS=arbitrum-sepolia,base-sepolia,optimism-sepolia,l2rn,unichain-sepolia,mont
Environment=EXECUTOR_PROCESS_PENDING_ORDERS_FROM_API=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now t3rn-executor-v2.service

log "SUCCESS" "✅ Executor v2 successfully installed and running on port $PORT!"
exec sudo journalctl -u t3rn-executor-v2.service -f --no-hostname -o cat
