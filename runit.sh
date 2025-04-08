#!/bin/bash
set -e

# ---- Color & Logging Setup ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
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

# ---- Initial Greeting ----
echo -e "${CYAN}🚀 Starting Auto Install T3rn Executor v2...${NC}"
sleep 1

# ---- Update ----
log "INFO" "1. Updating system packages..."
sudo apt update && sudo apt upgrade -y

# ---- User Input Section ----
read -rp "🔐 Enter PRIVATE_KEY_LOCAL: " PRIVATE_KEY_LOCAL
[[ -z "$PRIVATE_KEY_LOCAL" ]] && { log "ERROR" "PRIVATE_KEY_LOCAL cannot be empty!"; exit 1; }

read -rp "🔑 Enter APIKEY_ALCHEMY: " APIKEY_ALCHEMY
[[ -z "$APIKEY_ALCHEMY" ]] && { log "ERROR" "APIKEY_ALCHEMY cannot be empty!"; exit 1; }

read -rp "💾 Do you want to store your PRIVATE_KEY and APIKEY in the environment file? (y/N): " STORE_KEYS
STORE_KEYS=${STORE_KEYS,,} # to lowercase

# ---- Paths and Setup ----
INSTALL_DIR="$HOME/t3rn-v2"
EXECUTOR_BIN="$INSTALL_DIR/executor/executor/bin/executor"
VERSION_FILE="$INSTALL_DIR/.executor_version"
SERVICE_FILE="/etc/systemd/system/t3rn-executor-v2.service"
ENV_FILE="/etc/t3rn-executor-v2.env"

mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR"

# ---- Fetch Latest Version Tag ----
log "INFO" "2. Checking for latest executor version..."
LATEST_TAG=$(curl -s https://api.github.com/repos/t3rn/executor-release/releases/latest | awk -F '"' '/tag_name/ {print $4}')

if [[ -f "$VERSION_FILE" && "$(cat "$VERSION_FILE")" == "$LATEST_TAG" && -f "$EXECUTOR_BIN" ]]; then
    log "INFO" "Executor v$LATEST_TAG already downloaded. Skipping download."
else
    log "INFO" "Downloading Executor v$LATEST_TAG..."
    wget -q "https://github.com/t3rn/executor-release/releases/download/$LATEST_TAG/executor-linux-$LATEST_TAG.tar.gz"
    tar -xzf executor-linux-*.tar.gz
    echo "$LATEST_TAG" > "$VERSION_FILE"
fi

cd "$INSTALL_DIR/executor/executor/bin" || { log "ERROR" "Executor binary folder not found!"; exit 1; }

# ---- Create ENV File ----
log "INFO" "3. Creating environment configuration..."

RPC_JSON=$(cat <<EOF
{
  "l2rn": ["https://t3rn-b2n.blockpi.network/v1/rpc/public", "https://b2n.rpc.caldera.xyz/http"],
  "arbt": ["https://arbitrum-sepolia.drpc.org", "https://arb-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
  "bast": ["https://base-sepolia-rpc.publicnode.com", "https://base-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
  "opst": ["https://sepolia.optimism.io", "https://opt-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
  "unit": ["https://unichain-sepolia.drpc.org", "https://unichain-sepolia.g.alchemy.com/v2/$APIKEY_ALCHEMY"],
  "mont": ["https://testnet-rpc.monad.xyz", "https://monad-testnet.g.alchemy.com/v2/$APIKEY_ALCHEMY"]
}
EOF
)

echo "RPC_ENDPOINTS=$RPC_JSON" | sudo tee "$ENV_FILE" >/dev/null

if [[ "$STORE_KEYS" == "y" || "$STORE_KEYS" == "yes" ]]; then
    echo "PRIVATE_KEY_LOCAL=$PRIVATE_KEY_LOCAL" | sudo tee -a "$ENV_FILE" >/dev/null
    echo "APIKEY_ALCHEMY=$APIKEY_ALCHEMY" | sudo tee -a "$ENV_FILE" >/dev/null
fi

sudo chmod 600 "$ENV_FILE"
sudo chown "$USER:$USER" "$ENV_FILE"

# ---- Dynamic Port Assignment ----
is_port_in_use() { netstat -tuln | grep -q ":$1"; }

PORT=9090
while is_port_in_use $PORT; do
    ((PORT++))
done
log "INFO" "Using available port $PORT"

# ---- Create Systemd Service ----
log "INFO" "4. Creating systemd service file..."

sudo tee "$SERVICE_FILE" >/dev/null <<EOF
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
Environment=ENABLED_NETWORKS=arbitrum-sepolia,base-sepolia,optimism-sepolia,l2rn,unichain-sepolia,mont
Environment=EXECUTOR_PROCESS_PENDING_ORDERS_FROM_API=true
EnvironmentFile=$ENV_FILE
EOF

# ---- Enable and Start Service ----
log "INFO" "5. Starting Executor service..."
sudo systemctl daemon-reload
sudo systemctl enable --now t3rn-executor-v2.service

log "SUCCESS" "✅ Executor v$LATEST_TAG installed and running on port $PORT!"
echo -e "${CYAN}To view logs, run:${NC} ${YELLOW}sudo journalctl -u t3rn-executor-v2.service -f${NC}"
