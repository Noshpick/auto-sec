#!/usr/bin/env bash
# =============================================================================
# auto-sec - initial setup and hardening of an Ubuntu/Debian server
# Repository: https://github.com/Noshpick/auto-sec
# =============================================================================

set -euo pipefail

DEFAULT_SSH_PORT="2222"
SSH_PORT=""
NEW_USER=""
SSH_PUBKEY=""
TIMEZONE="Europe/Moscow"
INSTALL_DOCKER="no"
OPEN_WEB_PORTS="no"
DEFAULT_MAXRETRY="5"
F2B_MAXRETRY=""

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[X] $*${NC}" >&2; exit 1; }

ask_yes_no() {
    local question="$1"
    local answer
    while true; do
        read -r -p "$question [y/N]: " answer < /dev/tty
        case "$answer" in
            y|Y|yes|YES) return 0 ;;
            ""|n|N|no|NO) return 1 ;;
            *) echo "Answer y (yes) or n (no), Enter = no." ;;
        esac
    done
}

ask_username() {
    while true; do
        read -r -p "Enter a name for the new user: " NEW_USER < /dev/tty

        if [[ -z "$NEW_USER" ]]; then
            echo "The name cannot be empty. Try again."
            continue
        fi

        if [[ ! "$NEW_USER" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
            echo "The name must start with a lowercase Latin letter and"
            echo "contain only lowercase letters, digits, hyphens and underscores."
            continue
        fi

        local confirm
        read -r -p "Repeat the name to confirm: " confirm < /dev/tty

        if [[ "$NEW_USER" == "$confirm" ]]; then
            break
        else
            echo "Names do not match! Try again."
        fi
    done

    log "Username confirmed: $NEW_USER"
}

ask_ssh_port() {
    while true; do
        read -r -p "Enter the SSH port [default $DEFAULT_SSH_PORT]: " SSH_PORT < /dev/tty

        if [[ -z "$SSH_PORT" ]]; then
            SSH_PORT="$DEFAULT_SSH_PORT"
            break
        fi

        if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]]; then
            echo "The port must be a number. Try again."
            continue
        fi

        if (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
            echo "The port must be between 1 and 65535. Try again."
            continue
        fi

        if (( SSH_PORT < 1024 )); then
            warn "Port $SSH_PORT is in the system range (1-1023). It may conflict"
            warn "with other services (e.g. 80 - web server, 443 - HTTPS)."
            if ask_yes_no "Are you sure you want port $SSH_PORT?"; then
                break
            else
                continue
            fi
        fi

        break
    done

    log "SSH port: $SSH_PORT"
}

ask_ssh_key() {
    if [[ -f /root/.ssh/authorized_keys ]]; then
        if ask_yes_no "Root already has an SSH key. Use it for $NEW_USER?"; then
            SSH_PUBKEY=$(head -n 1 /root/.ssh/authorized_keys)
            log "Root's key will be used"
            return
        fi
    fi

    echo "Paste your PUBLIC key (starts with ssh-ed25519 or ssh-rsa)."
    echo "It lives on your computer in ~/.ssh/id_ed25519.pub"
    while true; do
        read -r -p "Public key: " SSH_PUBKEY < /dev/tty

        if [[ -z "$SSH_PUBKEY" ]]; then
            echo "The key cannot be empty."
            continue
        fi

        if [[ "$SSH_PUBKEY" =~ ^ssh- ]]; then
            break
        else
            echo "This does not look like a public key (it should start with ssh-...)."
        fi
    done

    log "Key accepted"
}

ask_web_ports() {
    if ask_yes_no "Planning to run a web server? (open ports 80 and 443)"; then
        OPEN_WEB_PORTS="yes"
        log "Ports 80 (HTTP) and 443 (HTTPS) will be opened"
    else
        log "Web ports will stay closed (SSH only)"
    fi
}

ask_maxretry() {
    echo "Fail2ban bans an IP address after several failed login attempts."
    echo "We recommend $DEFAULT_MAXRETRY attempts: enough that a random typo"
    echo "won't ban you, but brute-force bots get stopped."
    while true; do
        read -r -p "How many attempts before a ban? [default $DEFAULT_MAXRETRY]: " F2B_MAXRETRY < /dev/tty

        if [[ -z "$F2B_MAXRETRY" ]]; then
            F2B_MAXRETRY="$DEFAULT_MAXRETRY"
            break
        fi

        if [[ ! "$F2B_MAXRETRY" =~ ^[0-9]+$ ]]; then
            echo "A number is required. Try again."
            continue
        fi

        if (( F2B_MAXRETRY < 1 || F2B_MAXRETRY > 100 )); then
            echo "Enter a number from 1 to 100. Try again."
            continue
        fi

        break
    done

    log "Fail2ban: ban after $F2B_MAXRETRY failed attempts"
}

update_system() {
    log "Updating the system (this may take a couple of minutes)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y curl wget git htop vim ufw fail2ban unattended-upgrades

    timedatectl set-timezone "$TIMEZONE" || warn "Could not set timezone $TIMEZONE"
    log "System updated"
}

create_user() {
    if id "$NEW_USER" &>/dev/null; then
        warn "User $NEW_USER already exists, skipping creation"
    else
        adduser --disabled-password --gecos "" "$NEW_USER"
        usermod -aG sudo "$NEW_USER"
        log "User $NEW_USER created and added to the sudo group"
    fi

    local user_home
    user_home=$(eval echo "~$NEW_USER")

    mkdir -p "$user_home/.ssh"
    echo "$SSH_PUBKEY" > "$user_home/.ssh/authorized_keys"
    chmod 700 "$user_home/.ssh"
    chmod 600 "$user_home/.ssh/authorized_keys"
    chown -R "$NEW_USER:$NEW_USER" "$user_home/.ssh"

    log "SSH key installed for $NEW_USER"
}

setup_ssh() {
    local dropin="/etc/ssh/sshd_config.d/99-auto-sec.conf"

    cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"

    cat > "$dropin" <<EOF
# --- settings from auto-sec ---
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowUsers $NEW_USER
EOF

    sshd -t || die "Error in the sshd config! Service not restarted, access not lost."

    systemctl restart ssh
    log "SSH configured: port $SSH_PORT, key-only login, root login disabled"
}

setup_firewall() {
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "$SSH_PORT"/tcp comment 'SSH'

    if [[ "$OPEN_WEB_PORTS" == "yes" ]]; then
        ufw allow 80/tcp  comment 'HTTP'
        ufw allow 443/tcp comment 'HTTPS'
    fi

    ufw --force enable

    if [[ "$OPEN_WEB_PORTS" == "yes" ]]; then
        log "Firewall enabled: ports $SSH_PORT (SSH), 80 (HTTP), 443 (HTTPS) open"
    else
        log "Firewall enabled: only port $SSH_PORT (SSH) open"
    fi
}

setup_fail2ban() {
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = $F2B_MAXRETRY
backend  = systemd

[sshd]
enabled = true
port    = $SSH_PORT
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban
    log "Fail2ban configured: $F2B_MAXRETRY failed attempts in 10 minutes = 1 hour ban"
}

setup_auto_updates() {
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    systemctl enable unattended-upgrades
    systemctl restart unattended-upgrades
    log "Automatic security updates enabled"
}

install_docker() {
    if command -v docker >/dev/null; then
        warn "Docker is already installed, skipping"
        return
    fi
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker "$NEW_USER"
    systemctl enable docker
    log "Docker installed, $NEW_USER added to the docker group"
}

if [[ $EUID -ne 0 ]]; then
    die "Run me with sudo:  sudo bash auto-sec.sh"
fi

echo "============================================================"
echo "          auto-sec - server setup and hardening"
echo "============================================================"
warn "Do not close this session until you verify the new SSH access!"
echo

ask_username
ask_ssh_port
ask_ssh_key
ask_web_ports
ask_maxretry

if ask_yes_no "Install Docker?"; then
    INSTALL_DOCKER="yes"
fi

echo
log "Starting setup. User: $NEW_USER, SSH port: $SSH_PORT"
echo

update_system
create_user
setup_ssh
setup_firewall
setup_fail2ban
setup_auto_updates

if [[ "$INSTALL_DOCKER" == "yes" ]]; then
    install_docker
fi

SERVER_IP=$(hostname -I | awk '{print $1}')
echo
echo "============================================================"
log "Done! Now verify the login WITHOUT closing this session:"
echo
echo "    ssh -p $SSH_PORT $NEW_USER@$SERVER_IP"
echo
echo "  If you got in - everything works, you can close this session."
echo "  If not - the old config is nearby: /etc/ssh/sshd_config.bak.*"
echo "============================================================"
