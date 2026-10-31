#!/usr/bin/env bash
# =============================================================================
# auto-sec - первичная настройка и защита Ubuntu/Debian сервера
# Репозиторий: https://github.com/Noshpick/auto-sec
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
        read -r -p "$question [y/N]: " answer
        case "$answer" in
            y|Y|yes|YES) return 0 ;;
            ""|n|N|no|NO) return 1 ;;
            *) echo "Ответь y (да) или n (нет), Enter = нет." ;;
        esac
    done
}

ask_username() {
    while true; do
        read -r -p "Введи имя нового пользователя: " NEW_USER

        if [[ -z "$NEW_USER" ]]; then
            echo "Имя не может быть пустым. Попробуй ещё раз."
            continue
        fi

        if [[ ! "$NEW_USER" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
            echo "Имя должно начинаться с маленькой латинской буквы и"
            echo "содержать только маленькие буквы, цифры, дефис и подчёркивание."
            continue
        fi

        local confirm
        read -r -p "Повтори имя для подтверждения: " confirm

        if [[ "$NEW_USER" == "$confirm" ]]; then
            break
        else
            echo "Имена не совпадают! Попробуй ещё раз."
        fi
    done

    log "Имя подтверждено: $NEW_USER"
}

ask_ssh_port() {
    while true; do
        read -r -p "Введи SSH-порт [по умолчанию $DEFAULT_SSH_PORT]: " SSH_PORT

        if [[ -z "$SSH_PORT" ]]; then
            SSH_PORT="$DEFAULT_SSH_PORT"
            break
        fi

        if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]]; then
            echo "Порт должен быть числом. Попробуй ещё раз."
            continue
        fi

        if (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
            echo "Порт должен быть от 1 до 65535. Попробуй ещё раз."
            continue
        fi

        if (( SSH_PORT < 1024 )); then
            warn "Порт $SSH_PORT из системного диапазона (1-1023). Это может конфликтовать"
            warn "с другими сервисами (например, 80 - веб-сервер, 443 - HTTPS)."
            if ask_yes_no "Ты уверен, что хочешь порт $SSH_PORT?"; then
                break
            else
                continue
            fi
        fi

        break
    done

    log "SSH-порт: $SSH_PORT"
}

ask_ssh_key() {
    if [[ -f /root/.ssh/authorized_keys ]]; then
        if ask_yes_no "У root уже есть SSH-ключ. Использовать его для $NEW_USER?"; then
            SSH_PUBKEY=$(head -n 1 /root/.ssh/authorized_keys)
            log "Будет использован ключ root"
            return
        fi
    fi

    echo "Вставь свой ПУБЛИЧНЫЙ ключ (начинается с ssh-ed25519 или ssh-rsa)."
    echo "Он лежит на твоём компьютере в ~/.ssh/id_ed25519.pub"
    while true; do
        read -r -p "Публичный ключ: " SSH_PUBKEY

        if [[ -z "$SSH_PUBKEY" ]]; then
            echo "Ключ не может быть пустым."
            continue
        fi

        if [[ "$SSH_PUBKEY" =~ ^ssh- ]]; then
            break
        else
            echo "Это не похоже на публичный ключ (должен начинаться с ssh-...)."
        fi
    done

    log "Ключ принят"
}

ask_web_ports() {
    if ask_yes_no "Планируешь поднимать веб-сервер? (открыть порты 80 и 443)"; then
        OPEN_WEB_PORTS="yes"
        log "Порты 80 (HTTP) и 443 (HTTPS) будут открыты"
    else
        log "Веб-порты открывать не будем (только SSH)"
    fi
}

ask_maxretry() {
    echo "Fail2ban банит IP-адрес после нескольких неудачных попыток входа."
    echo "Рекомендуем $DEFAULT_MAXRETRY попыток: этого хватит, чтобы случайная опечатка"
    echo "не забанила тебя самого, но ботов с перебором паролей остановит."
    while true; do
        read -r -p "Сколько попыток до бана? [по умолчанию $DEFAULT_MAXRETRY]: " F2B_MAXRETRY

        if [[ -z "$F2B_MAXRETRY" ]]; then
            F2B_MAXRETRY="$DEFAULT_MAXRETRY"
            break
        fi

        if [[ ! "$F2B_MAXRETRY" =~ ^[0-9]+$ ]]; then
            echo "Нужно число. Попробуй ещё раз."
            continue
        fi

        if (( F2B_MAXRETRY < 1 || F2B_MAXRETRY > 100 )); then
            echo "Введи число от 1 до 100. Попробуй ещё раз."
            continue
        fi

        break
    done

    log "Fail2ban: бан после $F2B_MAXRETRY неудачных попыток"
}

update_system() {
    log "Обновляю систему (это может занять пару минут)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y curl wget git htop vim ufw fail2ban unattended-upgrades

    timedatectl set-timezone "$TIMEZONE" || warn "Не смог выставить таймзону $TIMEZONE"
    log "Система обновлена"
}

create_user() {
    if id "$NEW_USER" &>/dev/null; then
        warn "Пользователь $NEW_USER уже существует, пропускаю создание"
    else
        adduser --disabled-password --gecos "" "$NEW_USER"
        usermod -aG sudo "$NEW_USER"
        log "Пользователь $NEW_USER создан и добавлен в группу sudo"
    fi

    local user_home
    user_home=$(eval echo "~$NEW_USER")

    mkdir -p "$user_home/.ssh"
    echo "$SSH_PUBKEY" > "$user_home/.ssh/authorized_keys"
    chmod 700 "$user_home/.ssh"
    chmod 600 "$user_home/.ssh/authorized_keys"
    chown -R "$NEW_USER:$NEW_USER" "$user_home/.ssh"

    log "SSH-ключ установлен для $NEW_USER"
}

setup_ssh() {
    local dropin="/etc/ssh/sshd_config.d/99-auto-sec.conf"

    cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"

    cat > "$dropin" <<EOF
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

    sshd -t || die "Ошибка в конфиге sshd! Сервис не перезапущен, доступ не потерян."

    systemctl restart ssh
    log "SSH настроен: порт $SSH_PORT, вход только по ключу, root запрещён"
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
        log "Firewall включён: открыты порты $SSH_PORT (SSH), 80 (HTTP), 443 (HTTPS)"
    else
        log "Firewall включён: открыт только порт $SSH_PORT (SSH)"
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
    log "Fail2ban настроен: $F2B_MAXRETRY неудачных попыток за 10 минут = бан на час"
}

setup_auto_updates() {
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    systemctl enable unattended-upgrades
    systemctl restart unattended-upgrades
    log "Автообновления безопасности включены"
}

install_docker() {
    if command -v docker >/dev/null; then
        warn "Docker уже установлен, пропускаю"
        return
    fi
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker "$NEW_USER"
    systemctl enable docker
    log "Docker установлен, $NEW_USER добавлен в группу docker"
}

if [[ $EUID -ne 0 ]]; then
    die "Запусти меня через sudo:  sudo bash auto-sec.sh"
fi

echo "============================================================"
echo "              auto-sec - настройка и защита сервера"
echo "============================================================"
warn "Не закрывай эту сессию, пока не проверишь новый SSH-доступ!"
echo

ask_username
ask_ssh_port
ask_ssh_key
ask_web_ports
ask_maxretry

if ask_yes_no "Установить Docker?"; then
    INSTALL_DOCKER="yes"
fi

echo
log "Начинаю настройку. Пользователь: $NEW_USER, SSH-порт: $SSH_PORT"
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
log "Готово! Теперь проверь вход, НЕ ЗАКРЫВАЯ эту сессию:"
echo
echo "    ssh -p $SSH_PORT $NEW_USER@$SERVER_IP"
echo
echo "  Если вошёл - всё работает, можно закрывать эту сессию."
echo "  Если нет - старый конфиг лежит рядом: /etc/ssh/sshd_config.bak.*"
echo "============================================================"
