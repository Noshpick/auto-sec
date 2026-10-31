# auto-sec

![ShellCheck](https://github.com/Noshpick/auto-sec/actions/workflows/shellcheck.yml/badge.svg)

**[Русский](README.ru.md)**

Interactive bash script for initial setup and hardening of a fresh Ubuntu/Debian server.
Turns a bare VPS into a server with sensible baseline security in a couple of minutes.

## What it does

- Creates a non-privileged user with `sudo` and an SSH key (asks for the name interactively, with confirmation)
- Moves SSH to a custom port (asks, default `2222`), disables root and password login - key only
- Enables the firewall (`ufw`): denies everything inbound except SSH
- Installs and configures `fail2ban`: 5 failed login attempts in 10 minutes = 1 hour ban
- Enables automatic security updates (`unattended-upgrades`)
- Optionally installs Docker

Before touching SSH it backs up the config (`/etc/ssh/sshd_config.bak.*`) and validates
the new config with `sshd -t` **before** restarting the service - you will not lock yourself out.

## Requirements

- Ubuntu or Debian (fresh install)
- SSH access as root (or a user with sudo)
- Your public SSH key (`~/.ssh/id_ed25519.pub` on your machine)

## Install and run

### Quick way

```bash
curl -fsSL https://raw.githubusercontent.com/Noshpick/auto-sec/main/auto-sec.sh | sudo bash
```

Russian version:

```bash
curl -fsSL https://raw.githubusercontent.com/Noshpick/auto-sec/main/auto-sec-ru.sh | sudo bash
```

### Install as a system command

```bash
sudo bash install.sh
# then run from anywhere:
sudo auto-sec
```

## After it finishes

The script prints a verification command at the end:

```bash
ssh -p <port> <user>@<server-ip>
```

**Do not close your current session** until you have logged in with a new one and verified everything works.

## How to roll back

```bash
# Restore the old SSH config
sudo cp /etc/ssh/sshd_config.bak.YYYYMMDDHHMMSS /etc/ssh/sshd_config
sudo rm /etc/ssh/sshd_config.d/99-auto-sec.conf
sudo systemctl restart ssh

# Disable the firewall
sudo ufw disable
```

## Project security

The script is checked with `shellcheck` on every commit. Found a vulnerability or a bug - please open an issue.

## License

MIT - see [LICENSE](LICENSE).
