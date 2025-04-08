#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="$HOME/t3rn-v2"
SERVICE_FILE="/etc/systemd/system/t3rn-executor-v2.service"
ENV_FILE="/etc/t3rn-executor-v2.env"
KEYS_FILE="$HOME/.t3rn_keys"

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

is_port_in_use() { ss -tuln | grep -q ":$1"; }

# Function to install
install_executor() {
    log "INFO" "1. Updating system"
    sudo apt update && sudo apt upgrade -y

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # Prompt for gas price
    read -p "Enter EXECUTOR_MAX_L3_GAS_PRICE (default 5000): " MAX_GAS_PRICE
    MAX_GAS_PRICE=${MAX_GAS_PRICE:-5000}

    # Handle Private Key and API Key storage
    if [ -f "$KEYS_FILE" ]; then
        echo "Saved keys found:"
        echo -e "1) Use saved keys\n2) Enter new keys"
        read -p "Choose option [1/2]: " key_choice
    else
        key_choice=2
    fi

    if [ "$key_choice" == "2" ]; then
        read -p "Enter PRIVATE_KEY_LOCAL: " PRIVATE_KEY_LOCAL
        [[ -z "$PRIVATE_KEY_LOCAL" ]] && { log "ERROR" "PRIVATE_KEY_LOCAL cannot be empty!"; exit 1; }

        read -p "Enter APIKEY_ALCHEMY: " APIKEY_ALCHEMY
        [[ -z "$APIKEY_ALCHEMY" ]] && { log "ERROR" "APIKEY_ALCHEMY cannot be empty!"; exit 1; }

        echo "PRIVATE_KEY_LOCAL=$PRIVATE_KEY_LOCAL" > "$KEYS_FILE"
        echo "APIKEY_ALCHEMY=$APIKEY_ALCHEMY" >> "$KEYS_FILE"
    else
        source "$KEYS_FILE"
    fi

    # Fetch latest release
    TAG=$(curl -s https://api.github.com/repos/t3rn/executor-release/releases/latest | awk -F '"' '/tag_name/ {print $4}')
    if [ -f "$INSTALL_DIR/executor-linux-$TAG.tar.gz" ]; then
        log "INFO" "Latest version $TAG already downloaded."
    else
        wget -q "https://github.com/t3rn/executor-release/releases/download/$TAG/executor-linux-$TAG.tar.gz"
    fi

    tar -xzf executor-linux-*.tar.gz
    cd executor/executor/bin || exit 1

    # Prepare ENV file
    APIKEY_ALCHEMY=$(grep "APIKEY_ALCHEMY" "$KEYS_FILE" | cut -d '=' -f2)
    cat <<EOF | sudo tee "$ENV_FILE" >/dev/null
RPC_ENDPOINTS='{
  "l2rn": ["http://b2n.rpc.caldera.xyz/http"],
  "arbt": ["https://arbitrum-sepolia.drpc.org", "https://arb-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
  "bast": ["https://base-sepolia-rpc.publicnode.com", "https://base-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
  "blst": ["https://sepolia.blast.io", "https://blast-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
  "opst": ["https://sepolia.optimism.io", "https://opt-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
  "mont": ["https://testnet-rpc.monad.xyz", "https://monad-testnet.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
  "unit": ["https://unichain-sepolia.drpc.org", "https://unichain-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"]
}'
EOF

    # Choose free port
    PORT=9090
    while is_port_in_use $PORT; do PORT=$((PORT + 1)); done
    log "INFO" "Using port $PORT"

    sudo chown -R "$USER:$USER" "$INSTALL_DIR"
    sudo chmod 600 "$ENV_FILE"

    # Create systemd service
    PRIVATE_KEY_LOCAL=$(grep "PRIVATE_KEY_LOCAL" "$KEYS_FILE" | cut -d '=' -f2)
    cat <<EOF | sudo tee "$SERVICE_FILE" >/dev/null
[Unit]
Description=T3rn Executor v2 Service
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
Environment=EXECUTOR_MAX_L3_GAS_PRICE=$MAX_GAS_PRICE
Environment=EXECUTOR_MIN_TX_ETH=2
Environment=EXECUTOR_MAX_TX_GAS=2000000
Environment=PRIVATE_KEY_LOCAL=$PRIVATE_KEY_LOCAL
Environment=ENABLED_NETWORKS=arbitrum-sepolia,base-sepolia,blast-sepolia,optimism-sepolia,l2rn,unichain-sepolia,mont
Environment=NETWORKS_DISABLED=blast-sepolia
Environment=EXECUTOR_PROCESS_PENDING_ORDERS_FROM_API=true
EnvironmentFile=$ENV_FILE

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now t3rn-executor-v2.service

    log "SUCCESS" "✅ Executor v2 successfully installed and running on port $PORT!"
    exec sudo journalctl -u t3rn-executor-v2.service -f --no-hostname -o cat
}

# Function to remove
remove_executor() {
    log "INFO" "Stopping and removing service"
    sudo systemctl stop t3rn-executor-v2.service || true
    sudo systemctl disable t3rn-executor-v2.service || true
    sudo rm -f /etc/systemd/system/t3rn-executor-v2.service
    sudo rm -rf "$INSTALL_DIR"
    sudo rm -f "$ENV_FILE"
    sudo rm -f "$KEYS_FILE"
    sudo systemctl daemon-reload
    log "SUCCESS" "🗑️ Executor v2 has been removed successfully!"
}

# Menu
clear
echo -e "${CYAN}T3rn Executor v2 Auto Installer${NC}"
echo "1) Install"
echo "2) Remove"
read -p "Choose an option [1/2]: " CHOICE

if [ "$CHOICE" == "1" ]; then
    install_executor
elif [ "$CHOICE" == "2" ]; then
    remove_executor
else
    echo -e "${RED}Invalid option. Exiting.${NC}"
    exit 1
fi
