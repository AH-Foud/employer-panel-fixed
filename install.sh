#!/bin/bash
# Employer Panel - Bale Bot + Web Dashboard Installer v3.0
# Run: bash <(curl -s https://raw.githubusercontent.com/AH-Foud/employer-panel-fixed/main/install.sh)

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

INSTALL_DIR="/opt/employer-panel"
SERVICE_NAME="employer-panel"
KARPANEL_CMD="/usr/local/bin/karpanel"
GIT_REPO="https://github.com/AH-Foud/employer-panel.git"
GIT_BRANCH="main"

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }

verify_bot() {
    local token="$1"
    local result
    result=$(curl -s "https://tapi.bale.ai/bot${token}/getMe" 2>/dev/null)
    local ok=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ok',''))" 2>/dev/null)
    if [ "$ok" = "True" ]; then
        local name=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'].get('first_name',''))" 2>/dev/null)
        local uname=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'].get('username',''))" 2>/dev/null)
        ok "Bot verified: $name (@$uname)"
        echo "$uname" > /tmp/bot_username.txt
        return 0
    else
        return 1
    fi
}

prompt_config() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Bot Configuration              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "You need a Bale bot token and your admin ID."
    echo -e "Get token from ${YELLOW}@BotFather${NC} in Bale."
    echo ""

    while true; do
        read -rp $'\033[33mBOT_TOKEN (from BotFather): \033[0m' BOT_TOKEN
        BOT_TOKEN=$(echo "$BOT_TOKEN" | tr -d ' ')
        if [ -z "$BOT_TOKEN" ]; then
            err "Token cannot be empty"
            continue
        fi
        echo -e "${CYAN}Verifying token...${NC}"
        if verify_bot "$BOT_TOKEN"; then
            break
        else
            err "Invalid token. Check and try again."
            echo ""
        fi
    done

    while true; do
        read -rp $'\033[33mADMIN_ID (your numeric user ID): \033[0m' ADMIN_ID
        ADMIN_ID=$(echo "$ADMIN_ID" | tr -d ' ')
        if [ -z "$ADMIN_ID" ] || ! [[ "$ADMIN_ID" =~ ^[0-9]+$ ]]; then
            err "Admin ID must be a number"
            continue
        fi
        ok "Admin ID: $ADMIN_ID"
        break
    done

    echo ""
    SECRET=$(python3 -c "import secrets; print(secrets.token_hex(4))" 2>/dev/null || echo "admin")
    SECRET_PATH="/${SECRET}"

    python3 -c "
cfg = f'''# -*- coding: utf-8 -*-
BOT_TOKEN = \"${BOT_TOKEN}\"
ADMIN_ID = ${ADMIN_ID}
BASE_URL = f\"https://tapi.bale.ai/bot{{BOT_TOKEN}}\"
DATA_DIR = \"data\"
DATABASE_PATH = f\"{{DATA_DIR}}/database.db\"
WEB_HOST = \"0.0.0.0\"
WEB_PORT = 5000
SECRET_PATH = \"${SECRET_PATH}\"
SYNC_BASE_URL = \"\"
SYNC_API_KEY = \"\"
AI_BASE_URL = \"\"
AI_API_KEY = \"\"
AI_MODEL = \"gpt-4o-mini\"
VOICE_DIR = f\"{{DATA_DIR}}/voices\"
AI_PROMPT = (
    \"تو یه دستیار هوشمندی. لیست SOPهای تعریف شده:\\n{{sops}}\\n\\n\"
    \"پیام کاربر:\\n{{message}}\\n\\n\"
    \"کدام SOP最适合 این سواله؟ فقط اسم دقیق SOP رو بنویس. \"
    \"اگر هیچکدوم مناسب نبود، بنویس: none\"
)
'''
with open('${INSTALL_DIR}/config.py', 'w', encoding='utf-8') as f:
    f.write(cfg)
"
    ok "Config written with SECRET_PATH=${SECRET_PATH}"
}

main_install() {
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Employer Panel - Installer v3    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"

    if [[ $EUID -ne 0 ]]; then
        err "Please run as root: sudo bash install.sh"
        exit 1
    fi

    info "Installing required packages..."
    apt update -y -qq && apt install -y python3 python3-pip python3-venv curl wget git nginx socat 2>/dev/null || true

    info "Cloning project from GitHub..."
    rm -rf "$INSTALL_DIR" 2>/dev/null || true
    git clone --depth 1 "$GIT_REPO" "$INSTALL_DIR" 2>/dev/null || {
        err "Failed to clone repo. Check internet connection."
        exit 1
    }
    ok "Project cloned to $INSTALL_DIR"

    mkdir -p "$INSTALL_DIR/data" "$INSTALL_DIR/data/voices"

    info "Applying __BASE_PATH__ bug fix..."
    cd "$INSTALL_DIR"
    python3 -c "
content = open('web_server.py').read()
content = content.replace('.replace(\"__BASE_PATH__\", json.dumps(config.SECRET_PATH))', '.replace('\''__BASE_PATH__'\'', json.dumps(config.SECRET_PATH))')
open('web_server.py','w').write(content)
print('Fix applied')
" 2>/dev/null || sed -i 's/"__BASE_PATH__"/__BASE_PATH__/g' web_server.py 2>/dev/null || true
    ok "Bug fix applied"

    prompt_config

    info "Installing Python dependencies..."
    pip3 install -r requirements.txt --break-system-packages 2>/dev/null || pip3 install -r requirements.txt 2>/dev/null || true

    info "Initializing database..."
    cd "$INSTALL_DIR"
    python3 -c "import database; database.init_db(); print('Database OK')" 2>/dev/null || true

    PYTHON_BIN=$(which python3)
    info "Creating systemd service..."
    cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=Employer Panel - Bale Bot + Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$PYTHON_BIN $INSTALL_DIR/run.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl restart $SERVICE_NAME
    sleep 2

    if systemctl is-active --quiet $SERVICE_NAME; then
        ok "Service is running!"
    else
        warn "Checking logs..."
        journalctl -u $SERVICE_NAME -n 10 --no-pager
    fi

    IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 https://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        Installation Complete!                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}Panel URL:${NC} ${GREEN}http://${IP}:5000${SECRET_PATH}${NC}"
    echo ""
    
    BotUsername=$(cat /tmp/bot_username.txt 2>/dev/null || echo "your_bot")
    echo -e "  ${CYAN}Bot:${NC} @${BotUsername}"
    echo ""

    echo "http://${IP}:5000${SECRET_PATH}" > "$INSTALL_DIR/url.txt"
}

main_install
