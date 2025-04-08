#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

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

# Check if the script is running for the first time or being used for removal
if [ ! -f "$HOME/t3rn-v2/installed" ]; then
    # Ask the user whether they want to install or remove the service
    echo -e "${CYAN}Do you want to install or remove the T3rn Executor v2? (install/remove):${NC}"
    read -p "Choice: " CHOICE

    if [[ "$CHOICE" == "install" ]]; then
        log "INFO" "Installing T3rn Executor v2..."
        # Update system packages
        sudo apt update && sudo apt upgrade -y

        # Ask for PRIVATE_KEY_LOCAL and APIKEY_ALCHEMY
        read -p "Enter PRIVATE_KEY_LOCAL: " PRIVATE_KEY_LOCAL
        [[ -z "$PRIVATE_KEY_LOCAL" ]] && { log "ERROR" "PRIVATE_KEY_LOCAL cannot be empty!"; exit 1; }

        read -p "Enter APIKEY_ALCHEMY: " APIKEY_ALCHEMY
        [[ -z "$APIKEY_ALCHEMY" ]] && { log "ERROR" "APIKEY_ALCHEMY cannot be empty!"; exit 1; }

        # Ask if the user wants to store these keys securely
        read -p "Do you want to store these keys securely? (y/n): " STORE_KEYS

        SECRETS_FILE="$HOME/.t3rn-secrets"
        if [[ "$STORE_KEYS" == "y" ]]; then
            # Store the private key and API key securely
            echo "PRIVATE_KEY_LOCAL=$PRIVATE_KEY_LOCAL" > "$SECRETS_FILE"
            echo "APIKEY_ALCHEMY=$APIKEY_ALCHEMY" >> "$SECRETS_FILE"
            chmod 600 "$SECRETS_FILE"
            log "INFO" "Stored keys securely in $SECRETS_FILE"
        fi

        INSTALL_DIR="$HOME/t3rn-v2"
        SERVICE_FILE="/etc/systemd/system/t3rn-executor-v2.service"
        ENV_FILE="/etc/t3rn-executor-v2.env"

        mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR"

        TAG=$(curl -s https://api.github.com/repos/t3rn/executor-release/releases/latest | awk -F '"' '/tag_name/ {print $4}')
        wget -q "https://github.com/t3rn/executor-release/releases/download/$TAG/executor-linux-$TAG.tar.gz"

        tar -xzf executor-linux-*.tar.gz
        cd executor/executor/bin || exit 1

        # Save RPC endpoints to the env file
        cat <<EOF | sudo tee "$ENV_FILE" >/dev/null
RPC_ENDPOINTS='{
  "l2rn": ["http://b2n.rpc.caldera.xyz/http"],
  "arbt": ["https://arbitrum-sepolia.drpc.org", "https://arb-sepolia.g.alchemy.com/v2/\$APIKEY_ALCHEMY"],
  "bast": ["https://base-sepolia-rpc.publicnode.com", "https://base-sepolia.g.alchemy.com/v2/\$APIKEY_ALCHEMY"],
  "blst": ["https://sepolia.blast.io", "https://blast-sepolia.g.alchemy.com/v2/\$APIKEY_ALCHEMY"],
  "opst": ["https://sepolia.optimism.io", "https://opt-sepolia.g.alchemy.com/v2/\$APIKEY_ALCHEMY"],
  "mont": ["https://testnet-rpc.monad.xyz", "https://monad-testnet.g.alchemy.com/v2/\$APIKEY_ALCHEMY"],
  "unit": ["https://unichain-sepolia.drpc.org", "https://unichain-sepolia.g.alchemy.com/v2/\$APIKEY_ALCHEMY"]
}'
EOF

        is_port_in_use() { netstat -tuln | grep -q ":$1"; }

        PORT=9090
        while is_port_in_use $PORT; do
            PORT=$((PORT + 1))
        done

        log "INFO" "Using port $PORT"

        sudo chown -R "$USER:$USER" "$INSTALL_DIR"
        sudo chmod 600 "$ENV_FILE"

        # Create systemd service file
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
Environment=PRIVATE_KEY_LOCAL=${PRIVATE_KEY_LOCAL}
Environment=APIKEY_ALCHEMY=${APIKEY_ALCHEMY}
Environment=NETWORKS_DISABLED='blast-sepolia'
Environment=ENABLED_NETWORKS=arbitrum-sepolia,base-sepolia,optimism-sepolia,l2rn,unichain-sepolia,mont
Environment=EXECUTOR_PROCESS_PENDING_ORDERS_FROM_API=true
EnvironmentFile=$ENV_FILE
EnvironmentFile=$SECRETS_FILE

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable --now t3rn-executor-v2.service

        # Mark installation as completed
        touch "$HOME/t3rn-v2/installed"

        log "SUCCESS" "✅ Executor v2 successfully installed and running on port $PORT!"
        exec sudo journalctl -u t3rn-executor-v2.service -f --no-hostname -o cat

    elif [[ "$CHOICE" == "remove" ]]; then
        log "INFO" "Removing T3rn Executor v2..."

        sudo systemctl stop t3rn-executor-v2.service
        sudo systemctl disable t3rn-executor-v2.service
        sudo rm -f /etc/systemd/system/t3rn-executor-v2.service
        sudo rm -rf /home/$USER/t3rn-v2
        sudo systemctl daemon-reload

        # Optionally remove the secrets file
        if [ -f "$SECRETS_FILE" ]; then
            rm -f "$SECRETS_FILE"
        fi

        log "SUCCESS" "✅ T3rn Executor v2 successfully removed!"
        exit 0
    else
        log "ERROR" "Invalid choice! Please run the script again and choose 'install' or 'remove'."
        exit 1
    fi
else
    log "ERROR" "The script has already been installed or is being re-run. Please remove manually if necessary."
    exit 1
fi
