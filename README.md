# auto-sec

[![ShellCheck](https://github.com/Noshpick/auto-sec/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Noshpick/auto-sec/actions/workflows/shellcheck.yml)

Интерактивный bash-скрипт для первичной настройки и защиты свежего Ubuntu/Debian сервера.
За пару минут превращает «голый» VPS в сервер с разумной базовой безопасностью.

## Что делает

- Создаёт непривилегированного пользователя с `sudo` и SSH-ключом (имя спрашивает интерактивно, с подтверждением)
- Переводит SSH на нестандартный порт (спрашивает, по умолчанию `2222`), запрещает вход под root и по паролю - только по ключу
- Включает firewall (`ufw`): запрещено всё входящее, кроме SSH
- Ставит и настраивает `fail2ban`: 5 неудачных попыток входа за 10 минут - бан на час
- Включает автоматические обновления безопасности (`unattended-upgrades`)
- Опционально устанавливает Docker

Перед изменением SSH делает бэкап конфига (`/etc/ssh/sshd_config.bak.*`) и проверяет
новый конфиг командой `sshd -t` **до** перезапуска сервиса - вы не потеряете доступ к серверу.

## Требования

- Ubuntu или Debian (свежая установка)
- Доступ по SSH под root (или пользователем с sudo)
- Ваш публичный SSH-ключ (`~/.ssh/id_ed25519.pub` на вашем компьютере)

## Установка и запуск

### Быстрый способ

```bash
curl -fsSL https://raw.githubusercontent.com/Noshpick/auto-sec/main/auto-sec.sh | sudo bash
```

### Установка как системная команда

```bash
sudo bash install.sh
# дальше можно запускать откуда угодно:
sudo auto-sec
```

## После запуска

Скрипт в конце напечатает команду для проверки:

```bash
ssh -p <порт> <пользователь>@<ip-сервера>
```

**Не закрывайте текущую сессию**, пока не войдёте в новую и не убедитесь, что всё работает.

## Как откатить изменения

```bash
# Вернуть старый конфиг SSH
sudo cp /etc/ssh/sshd_config.bak.YYYYMMDDHHMMSS /etc/ssh/sshd_config
sudo rm /etc/ssh/sshd_config.d/99-auto-sec.conf
sudo systemctl restart ssh

# Выключить firewall
sudo ufw disable
```

## Безопасность проекта

Скрипт проверен `shellcheck`. Нашли уязвимость или ошибку - откройте issue.

## Лицензия

MIT - см. [LICENSE](LICENSE).
