#!/usr/bin/env bash
# =============================================================================
# install.sh - устанавливает auto-sec как системную команду /usr/local/bin/auto-sec
# Запускать из папки проекта:  sudo bash install.sh
# =============================================================================

set -euo pipefail

INSTALL_PATH="/usr/local/bin/auto-sec"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "Ошибка: запусти через sudo:  sudo bash install.sh" >&2
    exit 1
fi

install -m 755 "$SCRIPT_DIR/auto-sec.sh" "$INSTALL_PATH"

echo "[OK] Установлено: $INSTALL_PATH"
echo "     Теперь можно запускать командой:  sudo auto-sec"
