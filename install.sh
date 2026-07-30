#!/bin/bash
# Employer Panel - Bale Bot + Web Dashboard Installer v5
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
    fi
    return 1
}

write_config() {
    local port="$1"
    python3 - "$BOT_TOKEN" "$ADMIN_ID" "$SECRET_PATH" "$port" << 'PYEOF'
import sys
B=sys.argv[1]; A=sys.argv[2]; S=sys.argv[3]; P=sys.argv[4]
P1="تو یه دستیار هوشمندی. لیست SOPهای تعریف شده:\n{sops}\n\n"
P2="پیام کاربر:\n{message}\n\n"
P3="کدام SOP مناسب این سواله؟ فقط اسم دقیق SOP رو بنویس. "
P4="اگر هیچکدوم مناسب نبود، بنویس: none"
AI=(P1+P2+P3+P4)
cfg=f"""# -*- coding: utf-8 -*-
BOT_TOKEN = "{B}"
ADMIN_ID = {A}
BASE_URL = f"https://tapi.bale.ai/bot{{BOT_TOKEN}}"
DATA_DIR = "data"
DATABASE_PATH = f"{{DATA_DIR}}/database.db"
WEB_HOST = "0.0.0.0"
WEB_PORT = {P}
SECRET_PATH = "{S}"
SYNC_BASE_URL = ""
SYNC_API_KEY = ""
AI_BASE_URL = ""
AI_API_KEY = ""
AI_MODEL = "gpt-4o-mini"
VOICE_DIR = f"{{DATA_DIR}}/voices"
AI_PROMPT = {repr(AI)}
"""
with open('/opt/employer-panel/config.py','w',encoding='utf-8') as f:
    f.write(cfg)
PYEOF
}

prompt_config() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Bot Configuration              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Get BOT_TOKEN from ${YELLOW}@BotFather${NC} in Bale."
    echo ""
    while true; do
        read -rp $'\033[33mBOT_TOKEN: \033[0m' BOT_TOKEN
        BOT_TOKEN=$(echo "$BOT_TOKEN" | tr -d ' ')
        [ -z "$BOT_TOKEN" ] && { err "Token cannot be empty"; continue; }
        echo -e "${CYAN}Verifying...${NC}"
        verify_bot "$BOT_TOKEN" && break || err "Invalid token."
    done
    while true; do
        read -rp $'\033[33mADMIN_ID (numeric): \033[0m' ADMIN_ID
        ADMIN_ID=$(echo "$ADMIN_ID" | tr -d ' ')
        [ -z "$ADMIN_ID" ] || ! [[ "$ADMIN_ID" =~ ^[0-9]+$ ]] && { err "Must be a number"; continue; }
        ok "Admin ID: $ADMIN_ID"
        break
    done
    SECRET=$(python3 -c "import secrets; print(secrets.token_hex(6))" 2>/dev/null || echo "admin123")
    SECRET_PATH="/${SECRET}"
    ok "Config ready"
}

create_karpanel_cmd() {
    cat > "$KARPANEL_CMD" <<'KARPANEL_SCRIPT'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
DIR="/opt/employer-panel"; SERVICE="employer-panel"
ok(){ echo -e "${GREEN}[OK]${NC} $1"; }
show_menu(){
 clear
 echo -e "${CYAN}╔══════════════════════════╗${NC}"
 echo -e "${CYAN}║   Employer Panel Manager  ║${NC}"
 echo -e "${CYAN}╚══════════════════════════╝${NC}"
 echo -e "${GREEN}1)${NC} Show URL  ${GREEN}2)${NC} Restart  ${GREEN}3)${NC} Update"
 echo -e "${GREEN}4)${NC} Logs      ${GREEN}5)${NC} Uninstall ${GREEN}0)${NC} Exit"
 read -rp "Choice: " ch
 case "$ch" in
  1)[ -f "$DIR/url.txt" ]&&echo "$(cat $DIR/url.txt)";read -rp "Enter...";show_menu;;
  2)systemctl restart "$SERVICE"&&ok "Restarted";sleep 1;show_menu;;
  3)cd "$DIR"&&git stash&&git pull origin main&&pip3 install -r requirements.txt --break-system-packages 2>/dev/null;sed -i 's/"__BASE_PATH__"/__BASE_PATH__/g' web_server.py 2>/dev/null;systemctl restart "$SERVICE"&&ok "Updated";sleep 1;show_menu;;
  4)journalctl -u "$SERVICE" -n 40 --no-pager;read -rp "Enter...";show_menu;;
  5)systemctl stop "$SERVICE";systemctl disable "$SERVICE";rm -f /etc/systemd/system/$SERVICE.service;rm -f /etc/nginx/sites-enabled/employer-panel /etc/nginx/sites-available/employer-panel;systemctl reload nginx 2>/dev/null;rm -rf "$DIR";rm -f "$0";echo "Uninstalled";exit 0;;
  0)exit 0;;
  *)show_menu;;
 esac
}
show_menu
KARPANEL_SCRIPT
    chmod +x "$KARPANEL_CMD"
    ok "Type 'karpanel' for management menu"
}

main_install() {
    echo -e "${CYAN}╔══════════════════════════╗${NC}"
    echo -e "${CYAN}║ Employer Panel Installer v5 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════╝${NC}"
    [[ $EUID -ne 0 ]] && { err "Run as root"; exit 1; }

    echo -e "${BLUE}────────────────────────────────────${NC}"
    echo -e "${BLUE} Installation method:${NC}"
    echo -e "  ${GREEN}1)${NC} Direct IP  — http://IP/secret (port 80)"
    echo -e "  ${GREEN}2)${NC} Subdomain  — https://domain/secret (SSL+Nginx)"
    echo -e "${BLUE}────────────────────────────────────${NC}"
    read -rp $'\033[33mChoice (1 or 2): \033[0m' INSTALL_METHOD
    [[ "$INSTALL_METHOD" != "1" && "$INSTALL_METHOD" != "2" ]] && { err "Invalid"; exit 1; }

    SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 https://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')

    if [[ "$INSTALL_METHOD" == "2" ]]; then
        read -rp $'\033[33mSubdomain (e.g. bot.example.com): \033[0m' DOMAIN
        [ -z "$DOMAIN" ] && { err "Domain required"; exit 1; }
        echo -e "${CYAN}Server IP: ${GREEN}$SERVER_IP${NC}"
        echo -e "${YELLOW}⚠️  Set A record: ${DOMAIN} → ${SERVER_IP}${NC}"
        read -rp "Press Enter..."
    fi

    info "Installing packages..."
    apt update -y -qq && apt install -y python3 python3-pip python3-venv curl wget git nginx socat dnsutils 2>/dev/null || true

    info "Cloning project..."
    rm -rf "$INSTALL_DIR" 2>/dev/null || true
    git clone --depth 1 "$GIT_REPO" "$INSTALL_DIR" || { err "Clone failed"; exit 1; }
    ok "Cloned"

    mkdir -p "$INSTALL_DIR/data/voices"

    info "Applying __BASE_PATH__ fix..."
    cd "$INSTALL_DIR"
    sed -i 's/"__BASE_PATH__"/__BASE_PATH__/g' web_server.py 2>/dev/null && ok "Fix applied" || warn "Already fixed"

    prompt_config

    info "Installing Python deps..."
    pip3 install -r requirements.txt --break-system-packages 2>/dev/null || pip3 install -r requirements.txt 2>/dev/null || true

    info "Init database..."
    python3 -c "import database; database.init_db(); print('OK')" 2>/dev/null || warn "DB skipped"

    if [[ "$INSTALL_METHOD" == "1" ]]; then
        install_direct_ip
    else
        install_subdomain
    fi

    create_karpanel_cmd

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════╗${NC}"
    echo -e "${GREEN}║    Installation Complete!         ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════╝${NC}"
    echo -e "  ${CYAN}Panel:${NC} ${GREEN}$(cat $INSTALL_DIR/url.txt 2>/dev/null)${NC}"
    echo -e "  ${CYAN}Menu:${NC}  Type ${YELLOW}karpanel${NC}"
    echo ""
}

install_direct_ip() {
    # Write config with port 80
    write_config "80"

    FINAL_URL="http://${SERVER_IP}${SECRET_PATH}"
    echo "$FINAL_URL" > "$INSTALL_DIR/url.txt"

    # Kill anything on port 80
    fuser -k 80/tcp 2>/dev/null || true
    sleep 1

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
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl restart $SERVICE_NAME
    ufw allow 80/tcp 2>/dev/null || true
    sleep 3
    systemctl is-active --quiet $SERVICE_NAME && ok "Running on port 80" || warn "Check: journalctl -u $SERVICE_NAME -n 20"
}

install_subdomain() {
    # Write config with port 5000 (internal)
    write_config "5000"

    FINAL_URL="https://${DOMAIN}${SECRET_PATH}"
    echo "$FINAL_URL" > "$INSTALL_DIR/url.txt"

    info "Checking DNS..."
    DOMAIN_IP=$(dig +short "$DOMAIN" 2>/dev/null | tail -1)
    [ -z "$DOMAIN_IP" ] && warn "Cannot resolve $DOMAIN"
    [[ -n "$DOMAIN_IP" && "$DOMAIN_IP" != "$SERVER_IP" ]] && warn "$DOMAIN → $DOMAIN_IP (not $SERVER_IP)"

    systemctl stop nginx 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true; sleep 1
    ufw allow 80/tcp 2>/dev/null || true
    ufw allow 443/tcp 2>/dev/null || true

    info "Getting SSL..."
    command -v acme.sh &>/dev/null || curl -s https://get.acme.sh | sh -s email=admin@${DOMAIN} 2>/dev/null
    source ~/.bashrc 2>/dev/null || true
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade 2>/dev/null || true
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt 2>/dev/null || true

    if ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --httpport 80 --force 2>/dev/null; then
        ok "SSL obtained"
    else
        warn "Retrying..."
        sleep 2; fuser -k 80/tcp 2>/dev/null || true; sleep 1
        ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --httpport 80 --force 2>/dev/null || {
            warn "SSL failed — falling back to Direct IP"
            install_direct_ip; return
        }
    fi

    mkdir -p /etc/ssl/employer-panel
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --key-file /etc/ssl/employer-panel/key.pem \
        --fullchain-file /etc/ssl/employer-panel/fullchain.pem \
        --reloadcmd "systemctl restart nginx"
    chmod 600 /etc/ssl/employer-panel/key.pem
    chmod 644 /etc/ssl/employer-panel/fullchain.pem
    ok "SSL installed"

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
    location / { return 404; }
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
    nginx -t && systemctl restart nginx && ok "Nginx OK" || warn "Nginx issue"

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
    sleep 3
    systemctl is-active --quiet $SERVICE_NAME && ok "Running" || warn "Check: journalctl -u $SERVICE_NAME -n 20"
}

main_install
