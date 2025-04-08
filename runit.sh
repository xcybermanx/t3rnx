#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Display banner
curl -s https://file.winsnip.xyz/file/uploads/Logo-winsip.sh | bash
echo "Starting Auto Install T3rn Executor v2"
sleep 2

# Function for logging
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

# Function to install T3rn Executor v2
install_executor() {
    log "INFO" "1. Updating system packages"
    sudo apt update && sudo apt install -y jq

    read -p "Enter PRIVATE_KEY_LOCAL: " PRIVATE_KEY_LOCAL
    [[ -z "$PRIVATE_KEY_LOCAL" ]] && { log "ERROR" "PRIVATE_KEY_LOCAL cannot be empty!"; exit 1; }

    read -p "Enter APIKEY_ALCHEMY: " APIKEY_ALCHEMY
    [[ -z "$APIKEY_ALCHEMY" ]] && { log "ERROR" "APIKEY_ALCHEMY cannot be empty!"; exit 1; }

    INSTALL_DIR="$HOME/t3rn-v2"
    SERVICE_FILE="/etc/systemd/system/t3rn-executor-v2.service"
    ENV_FILE="/etc/t3rn-executor-v2.env"

    mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR"

    # Get latest version
    TAG=$(curl -s https://api.github.com/repos/t3rn/executor-release/releases/latest | jq -r '.tag_name')
    [[ -z "$TAG" || "$TAG" == "null" ]] && { log "ERROR" "Failed to get latest version from GitHub!"; exit 1; }

    log "INFO" "Using version: $TAG"

    # Download and extract
    EXECUTOR_URL="https://github.com/t3rn/executor-release/releases/download/$TAG/executor-linux-$TAG.tar.gz"
    log "INFO" "Downloading $EXECUTOR_URL"
    wget -q --show-progress "$EXECUTOR_URL" -O "executor-linux.tar.gz"
    tar -xzf executor-linux.tar.gz || { log "ERROR" "Failed to extract file!"; exit 1; }
    cd executor/executor/bin || { log "ERROR" "Executor directory not found!"; exit 1; }

    # Create environment file
    cat <<EOF | sudo tee "$ENV_FILE" >/dev/null
RPC_ENDPOINTS='{
  "l2rn": ["http://b2n.rpc.caldera.xyz/http"],
  "arbt": ["https://arbitrum-sepolia.drpc.org", "https://arb-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
  "bast": ["https://base-sepolia-rpc.publicnode.com", "https://base-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
  "opst": ["https://sepolia.optimism.io", "https://opt-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
  "mont": ["https://testnet-rpc.monad.xyz", "https://monad-testnet.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
  "unit": ["https://unichain-sepolia.drpc.org", "https://unichain-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"]
}'
EOF

    # Find available port
    is_port_in_use() { netstat -tuln | grep -q ":$1"; }
    PORT=9090
    while is_port_in_use $PORT; do
        PORT=$((PORT + 1))
    done
    log "INFO" "Using port $PORT"

    # Set permissions
    sudo chown -R "$USER:$USER" "$INSTALL_DIR"
    sudo chmod 600 "$ENV_FILE"

    # Create service file
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
Environment=EXECUTOR_MAX_L3_GAS_PRICE=500
Environment=EXECUTOR_MIN_TX_ETH=2
Environment=EXECUTOR_MAX_TX_GAS=2000000
Environment=PRIVATE_KEY_LOCAL=$PRIVATE_KEY_LOCAL
Environment=NETWORKS_DISABLED=blast-sepolia
Environment=ENABLED_NETWORKS=arbitrum-sepolia,base-sepolia,optimism-sepolia,l2rn,blst
EnvironmentFile=$ENV_FILE
Environment=EXECUTOR_PROCESS_PENDING_ORDERS_FROM_API=true

[Install]
WantedBy=multi-user.target
EOF

    # Start service
    sudo systemctl daemon-reload
    sudo systemctl enable --now t3rn-executor-v2.service

    log "SUCCESS" "✅ T3rn Executor v2 successfully installed and running!"
    log "INFO" "To view logs: sudo journalctl -u t3rn-executor-v2.service -f --no-hostname -o cat"
}

# Function to remove T3rn Executor v2
remove_executor() {
    log "INFO" "Removing T3rn Executor v2..."
    
    # Stop and disable service
    sudo systemctl stop t3rn-executor-v2.service 2>/dev/null || true
    sudo systemctl disable t3rn-executor-v2.service 2>/dev/null || true
    
    # Remove files
    sudo rm -f /etc/systemd/system/t3rn-executor-v2.service
    sudo rm -f /etc/t3rn-executor-v2.env
    rm -rf "$HOME/t3rn-v2"
    
    # Reload systemd
    sudo systemctl daemon-reload
    sudo systemctl reset-failed
    
    log "SUCCESS" "✅ T3rn Executor v2 successfully removed!"
}

# Main menu
PS3="Please select an option: "
options=("Install T3rn Executor v2" "Remove T3rn Executor v2" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "Install T3rn Executor v2")
            install_executor
            break
            ;;
        "Remove T3rn Executor v2")
            remove_executor
            break
            ;;
        "Quit")
            log "INFO" "Exiting..."
            exit 0
            ;;
        *) 
            log "ERROR" "Invalid option $REPLY"
            ;;
    esac
done
