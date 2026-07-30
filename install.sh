#!/bin/bash
# Employer Panel - Bale Bot + Web Dashboard Installer v4
# Full version: subdomain+SSL, direct IP, bug fixes
# Run: bash <(curl -s https://raw.githubusercontent.com/AH-Foud/employer-panel-fixed/main/install.sh)

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

INSTALL_DIR="/opt/employer-panel"
SERVICE_NAME="employer-panel"
KARPANEL_CMD="/usr/local/bin/karpanel"
GIT_REPO="https://github.com/AH-Foud/employer-panel.git"

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

    SECRET=$(python3 -c "import secrets; print(secrets.token_hex(4))" 2>/dev/null || echo "admin")
    SECRET_PATH="/${SECRET}"

    python3 << 'PYEOF'
import os
cfg = f'''# -*- coding: utf-8 -*-
BOT_TOKEN = "{os.environ['BOT_TOKEN']}"
ADMIN_ID = {os.environ['ADMIN_ID']}
BASE_URL = f"https://tapi.bale.ai/bot{{BOT_TOKEN}}"
DATA_DIR = "data"
DATABASE_PATH = f"{{DATA_DIR}}/database.db"
WEB_HOST = "0.0.0.0"
WEB_PORT = 5000
SECRET_PATH = "{os.environ['SECRET_PATH']}"
SYNC_BASE_URL = ""
SYNC_API_KEY = ""
AI_BASE_URL = ""
AI_API_KEY = ""
AI_MODEL = "gpt-4o-mini"
VOICE_DIR = f"{{DATA_DIR}}/voices"
AI_PROMPT = (
    "\\u062a\\u0648 \\u06cc\\u0647 \\u062f\\u0633\\u062a\\u06cc\\u0627\\u0631 \\u0647\\u0648\\u0634\\u0645\\u0646\\u062f\\u06cc. \\u0644\\u06cc\\u0633\\u062a SOP\\u0647\\u0627\\u06cc \\u062a\\u0639\\u0631\\u06cc\\u0641 \\u0634\\u062f\\u0647:\\\\n{{sops}}\\\\n\\\\n"
    "\\u067e\\u06cc\\u0627\\u0645 \\u06a9\\u0627\\u0631\\u0628\\u0631:\\\\n{{message}}\\\\n\\\\n"
    "\\u06a9\\u062f\\u0627\\u0645 SOP \\u0645\\u0646\\u0627\\u0633\\u0628 \\u0627\\u06cc\\u0646 \\u0633\\u0648\\u0627\\u0644\\u0647\\u061f \\u0641\\u0642\\u0637 \\u0627\\u0633\\u0645 \\u062f\\u0642\\u06cc\\u0642 SOP \\u0631\\u0648 \\u0628\\u0646\\u0648\\u06cc\\u0633. "
    "\\u0627\\u06af\\u0631 \\u0647\\u06cc\\u0686\\u06a9\\u062f\\u0648\\u0645 \\u0645\\u0646\\u0627\\u0633\\u0628 \\u0646\\u0628\\u0648\\u062f\\u060c \\u0628\\u0646\\u0648\\u06cc\\u0633: none"
)
'''
with open('/opt/employer-panel/config.py', 'w', encoding='utf-8') as f:
    f.write(cfg)
PYEOF
    ok "Config written with SECRET_PATH=${SECRET_PATH}"
}

create_karpanel_cmd() {
    cat > "$KARPANEL_CMD" <<'KARPANEL_SCRIPT'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
DIR="/opt/employer-panel"
SERVICE="employer-panel"

ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }

show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        Employer Panel Manager        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Show panel URL"
    echo -e "  ${GREEN}2)${NC} Restart panel"
    echo -e "  ${GREEN}3)${NC} Update from GitHub"
    echo -e "  ${GREEN}4)${NC} View logs"
    echo -e "  ${GREEN}5)${NC} Uninstall"
    echo -e "  ${GREEN}0)${NC} Exit"
    echo ""
    read -rp "Choice: " ch
    case "$ch" in
        1) show_url ;;
        2) systemctl restart "$SERVICE" && ok "Restarted"; sleep 2; show_menu ;;
        3) cd "$DIR" && git stash && git pull origin main && pip3 install -r requirements.txt --break-system-packages 2>/dev/null; sed -i 's/"__BASE_PATH__"/__BASE_PATH__/g' web_server.py 2>/dev/null; systemctl restart "$SERVICE" && ok "Updated"; sleep 2; show_menu ;;
        4) journalctl -u "$SERVICE" -n 50 --no-pager; read -rp "Press Enter..."; show_menu ;;
        5) systemctl stop "$SERVICE"; systemctl disable "$SERVICE"; rm -f /etc/systemd/system/$SERVICE.service; rm -f /etc/nginx/sites-enabled/employer-panel /etc/nginx/sites-available/employer-panel; systemctl reload nginx 2>/dev/null; rm -rf "$DIR"; rm -f "$0"; ok "Uninstalled"; exit 0 ;;
        0) exit 0 ;;
        *) err "Invalid"; sleep 1; show_menu ;;
    esac
}

show_url() {
    if [ -f "$DIR/url.txt" ]; then echo -e "${GREEN}$(cat $DIR/url.txt)${NC}"; fi
    read -rp "Press Enter..."; show_menu
}
show_menu
KARPANEL_SCRIPT
    chmod +x "$KARPANEL_CMD"
    ok "Type 'karpanel' for the management menu"
}

main_install() {
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Employer Panel - Installer v4       ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"

    if [[ $EUID -ne 0 ]]; then
        err "Please run as root: sudo bash install.sh"
        exit 1
    fi

    echo ""
    echo -e "${BLUE}────────────────────────────────────────${NC}"
    echo -e "${BLUE}  Installation method:${NC}"
    echo -e "  ${GREEN}1)${NC} Direct IP  — http://YOUR_IP:5000/secret"
    echo -e "  ${GREEN}2)${NC} Subdomain   — https://your.domain.com/secret  (SSL + Nginx)"
    echo -e "${BLUE}────────────────────────────────────────${NC}"
    read -rp $'\033[33mChoice (1 or 2): \033[0m' INSTALL_METHOD

    if [[ "$INSTALL_METHOD" != "1" && "$INSTALL_METHOD" != "2" ]]; then
        err "Invalid choice. Enter 1 or 2."
        exit 1
    fi

    if [[ "$INSTALL_METHOD" == "2" ]]; then
        echo ""
        read -rp $'\033[33mSubdomain (e.g. bot.example.com): \033[0m' DOMAIN
        if [ -z "$DOMAIN" ]; then
            err "Domain cannot be empty"
            exit 1
        fi
        IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 https://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')
        echo -e "${CYAN}Your server IP: ${GREEN}$IP${NC}"
        echo -e "${YELLOW}⚠️  Make sure A record for ${DOMAIN} → ${IP}${NC}"
        read -rp "Press Enter to continue..."
    fi

    info "Installing system packages..."
    apt update -y -qq && apt install -y python3 python3-pip python3-venv curl wget git nginx socat dnsutils 2>/dev/null || true

    info "Cloning project from GitHub..."
    rm -rf "$INSTALL_DIR" 2>/dev/null || true
    git clone --depth 1 "$GIT_REPO" "$INSTALL_DIR" 2>/dev/null || { err "Failed to clone repo."; exit 1; }
    ok "Project cloned"

    mkdir -p "$INSTALL_DIR/data" "$INSTALL_DIR/data/voices"

    info "Applying __BASE_PATH__ bug fix..."
    cd "$INSTALL_DIR"
    sed -i 's/"__BASE_PATH__"/__BASE_PATH__/g' web_server.py 2>/dev/null && ok "Fix applied" || warn "Fix already applied"

    prompt_config

    info "Installing Python dependencies..."
    pip3 install -r requirements.txt --break-system-packages 2>/dev/null || pip3 install -r requirements.txt 2>/dev/null || true

    info "Initializing database..."
    python3 -c "import database; database.init_db(); print('DB OK')" 2>/dev/null || warn "DB init skipped"

    if [[ "$INSTALL_METHOD" == "1" ]]; then
        install_direct_ip
    else
        install_subdomain
    fi

    create_karpanel_cmd

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        Installation Complete!                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}Panel:${NC} ${GREEN}$(cat $INSTALL_DIR/url.txt 2>/dev/null)${NC}"
    BotUsername=$(cat /tmp/bot_username.txt 2>/dev/null || echo "your_bot")
    echo -e "  ${CYAN}Bot:${NC}   @${BotUsername}"
    echo -e "  ${CYAN}Menu:${NC}  Type ${YELLOW}karpanel${NC}"
    echo ""
}

install_direct_ip() {
    IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 https://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')
    FINAL_URL="http://${IP}:5000${SECRET_PATH}"
    echo "$FINAL_URL" > "$INSTALL_DIR/url.txt"

    info "Creating systemd service..."
    cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=Employer Panel - Bale Bot + Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$(which python3) $INSTALL_DIR/run.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl restart $SERVICE_NAME
    ufw allow 5000/tcp 2>/dev/null || true

    sleep 2
    if systemctl is-active --quiet $SERVICE_NAME; then
        ok "Panel is running on port 5000"
    else
        warn "Check: journalctl -u $SERVICE_NAME -n 20"
    fi
}

install_subdomain() {
    FINAL_URL="https://${DOMAIN}${SECRET_PATH}"
    echo "$FINAL_URL" > "$INSTALL_DIR/url.txt"

    info "Checking DNS for $DOMAIN ..."
    DOMAIN_IP=$(dig +short "$DOMAIN" 2>/dev/null | tail -1)
    if [[ -z "$DOMAIN_IP" ]]; then
        warn "Could not resolve $DOMAIN. Proceeding anyway..."
    elif [[ "$DOMAIN_IP" != "$IP" ]]; then
        warn "$DOMAIN → $DOMAIN_IP (not $IP). Proceeding anyway..."
    fi

    systemctl stop nginx 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true
    sleep 1

    ufw allow 80/tcp 2>/dev/null || true
    ufw allow 443/tcp 2>/dev/null || true

    info "Getting SSL certificate..."
    if ! command -v acme.sh &>/dev/null; then
        curl -s https://get.acme.sh | sh -s email=admin@${DOMAIN} 2>/dev/null
    fi
    source ~/.bashrc 2>/dev/null || true
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade 2>/dev/null || true
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt 2>/dev/null || true

    if ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --httpport 80 --force 2>/dev/null; then
        ok "SSL certificate obtained"
    else
        warn "First attempt failed, retrying..."
        sleep 2
        fuser -k 80/tcp 2>/dev/null || true
        sleep 1
        ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --httpport 80 --force 2>/dev/null || {
            warn "SSL failed. Falling back to direct IP."
            install_direct_ip
            return
        }
    fi

    mkdir -p /etc/ssl/employer-panel
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --key-file /etc/ssl/employer-panel/key.pem \
        --fullchain-file /etc/ssl/employer-panel/fullchain.pem \
        --reloadcmd "systemctl restart nginx"
    chmod 600 /etc/ssl/employer-panel/key.pem
    chmod 644 /etc/ssl/employer-panel/fullchain.pem

    info "Configuring Nginx..."
    cat > /etc/nginx/sites-available/employer-panel <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/ssl/employer-panel/fullchain.pem;
    ssl_certificate_key /etc/ssl/employer-panel/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/html;
    location / {
        return 404;
    }

    location ${SECRET_PATH}/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Prefix ${SECRET_PATH};
        proxy_read_timeout 120s;
        proxy_buffering off;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/employer-panel /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl restart nginx && ok "Nginx configured" || warn "Nginx issue"

    info "Creating systemd service..."
    cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=Employer Panel - Bale Bot + Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$(which python3) $INSTALL_DIR/run.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl restart $SERVICE_NAME

    (crontab -l 2>/dev/null; echo "0 3 * * * ~/.acme.sh/acme.sh --cron --home ~/.acme.sh >/dev/null 2>&1") | crontab - 2>/dev/null || true

    sleep 2
    if systemctl is-active --quiet $SERVICE_NAME; then
        ok "Panel is running"
    else
        warn "Check: journalctl -u $SERVICE_NAME -n 20"
    fi
}

main_install
