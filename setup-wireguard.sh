#!/usr/bin/env bash
set -euo pipefail

# === WireGuard + Optional Hardening Auto-Setup for Raspberry Pi ===
# - Installs WireGuard and DNS helper
# - Generates and shows keys
# - Prompts for a config, injects the generated PrivateKey
# - Shows final config for approval, installs to /etc/wireguard/<iface>.conf
# - Starts the interface
# - Optional: enable autostart on boot
# - Optional: install & configure UFW firewall (SSH + optional web + WG listen port)
# - Optional: install & enable fail2ban (basic sshd jail)
#
# Usage:
#   bash setup-wireguard.sh
#
# Notes:
# - Designed for Raspberry Pi OS (Debian-based).
# - Requires sudo/root. Prompts for elevation if needed.
# - If your config defines ListenPort in [Interface], this script will open it in UFW (if enabled).
#
# 73, N3BKV

# --- Helpers ---
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Elevating with sudo..."
    exec sudo -E bash "$0" "$@"
  fi
}

ask_yes_no() {
  local prompt="$1" default="${2:-Y}" reply
  local hint="[Y/n]"
  [[ "$default" =~ ^[Nn]$ ]] && hint="[y/N]"
  read -rp "$prompt $hint " reply || true
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy]$ ]]
}

msg() { echo -e "\n==== $* ====\n"; }

# --- Start ---
require_root "$@"

trap 'echo; echo "Exiting."; rm -f /tmp/wg_input.$$ /tmp/wg_final.$$ 2>/dev/null || true' EXIT

msg "1) Updating apt and installing WireGuard packages"
apt-get update -y
PACKAGES=(wireguard wireguard-tools)
# install resolvconf/openresolv so wg-quick can handle DNS
if ! dpkg -s resolvconf >/dev/null 2>&1 && ! dpkg -s openresolv >/dev/null 2>&1; then
  if apt-cache show resolvconf >/dev/null 2>&1; then
    PACKAGES+=("resolvconf")
  elif apt-cache show openresolv >/dev/null 2>&1; then
    PACKAGES+=("openresolv")
  fi
fi
DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}"
modprobe wireguard 2>/dev/null || true

msg "2) Generating WireGuard keypair"
install -d -m 0700 /etc/wireguard
if [[ -f /etc/wireguard/privatekey || -f /etc/wireguard/publickey ]]; then
  echo "Existing keys detected in /etc/wireguard. Backing up."
  ts="$(date +%Y%m%d-%H%M%S)"
  cp -a /etc/wireguard/privatekey "/etc/wireguard/privatekey.bak.$ts" 2>/dev/null || true
  cp -a /etc/wireguard/publickey  "/etc/wireguard/publickey.bak.$ts" 2>/dev/null || true
fi
umask 077
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey

PRIVKEY="$(cat /etc/wireguard/privatekey)"
PUBKEY="$(cat /etc/wireguard/publickey)"

echo "Your new WireGuard keys (save these securely):"
echo "  Private key: $PRIVKEY"
echo "  Public  key: $PUBKEY"
echo
echo ">> Copy the PUBLIC key and paste it into the PUBLIC key prompt on your 44net Cloud tunnel prompt."
read -rp "Press Enter to continue..."

msg "3) Choose interface name"
read -rp "Enter interface name to create (default: wg0): " IFACE
IFACE="${IFACE:-wg0}"
CFG_TARGET="/etc/wireguard/${IFACE}.conf"

if [[ -f "$CFG_TARGET" ]]; then
  echo "An existing config $CFG_TARGET was found."
  if ask_yes_no "Backup and overwrite it?" "Y"; then
    cp -a "$CFG_TARGET" "${CFG_TARGET}.bak.$(date +%Y%m%d-%H%M%S)"
  else
    echo "Aborting to avoid overwriting."
    exit 1
  fi
fi

msg "4) Paste your WireGuard config below"
cat <<'INSTR'
Paste your config (including [Interface] and [Peer] sections).
When finished, type a single line with:  EOF then hit return
Example:
[Interface]
PrivateKey = REPLACE_ME
Address = 44.xx.xx.xx/24, fe80:0000:0000:0000:f9dc:93ae:XXXX:XXXX/64
DNS = 1.1.1.1,1.0.0.1

[Peer]
PublicKey = Provided
Endpoint = xxx.xxx.xxx.xxx:xxxxx
PersistentKeepalive = 20
AllowedIPs = 0.0.0.0/0, ::/0
INSTR
echo

: > /tmp/wg_input.$$
while IFS= read -r line; do
  [[ "$line" == "EOF" ]] && break
  printf "%s\n" "$line" >> /tmp/wg_input.$$
done

if ! grep -q '^\s*\[Interface\]\s*$' /tmp/wg_input.$$; then
  echo "Error: No [Interface] section detected. Aborting."
  exit 1
fi

# Inject PrivateKey into config
cp /tmp/wg_input.$$ /tmp/wg_final.$$

if grep -q 'REPLACE_ME' /tmp/wg_final.$$; then
  sed -i -E "s|REPLACE_ME|$PRIVKEY|g" /tmp/wg_final.$$
elif grep -Eq '^[[:space:]]*PrivateKey[[:space:]]*=' /tmp/wg_final.$$; then
  sed -i -E "s|^[[:space:]]*PrivateKey[[:space:]]*=.*$|PrivateKey = $PRIVKEY|" /tmp/wg_final.$$
else
  awk -v pk="$PRIVKEY" '
    BEGIN{done=0}
    /^\s*\[Interface\]\s*$/ && !done { print; print "PrivateKey = " pk; done=1; next }
    { print }
  ' /tmp/wg_final.$$ > /tmp/wg_final.$$.new && mv /tmp/wg_final.$$.new /tmp/wg_final.$$
fi

# Normalize endings & whitespace
sed -i 's/\r$//' /tmp/wg_final.$$
sed -i -E 's/[[:space:]]+$//' /tmp/wg_final.$$

msg "5) Final config preview (${IFACE}.conf)"
echo "------------------------------------------------------------"
cat /tmp/wg_final.$$
echo "------------------------------------------------------------"

if ! ask_yes_no "Accept and install to $CFG_TARGET?" "Y"; then
  echo "Aborted by user."
  exit 1
fi

install -m 600 /tmp/wg_final.$$ "$CFG_TARGET"

# Detect ListenPort from config (if present)
LISTEN_PORT="$(awk -F'=' '/^\s*ListenPort\s*=/ {gsub(/ /,"",$2); print $2}' "$CFG_TARGET" | tr -d '[:space:]' || true)"
[[ -n "${LISTEN_PORT:-}" ]] && echo "Detected WireGuard ListenPort: $LISTEN_PORT/udp"

msg "6) Bringing interface up: wg-quick up ${IFACE}"
wg-quick down "$IFACE" >/dev/null 2>&1 || true
if wg-quick up "$IFACE"; then
  echo
  echo "Interface ${IFACE} is up. Current status:"
  wg show "$IFACE" || true
else
  echo "Failed to bring ${IFACE} up. Showing journal hints (last 50 lines):"
  journalctl -u "wg-quick@${IFACE}.service" --no-pager -n 50 || true
  exit 1
fi

echo
if ask_yes_no "Enable auto-start at boot for ${IFACE}?" "Y"; then
  systemctl enable "wg-quick@${IFACE}.service"
  systemctl daemon-reload || true
  echo "Enabled: wg-quick@${IFACE}.service"
else
  echo "Skipping enable at boot."
fi

# === Optional Hardening: UFW Firewall ===
if ask_yes_no "Install and enable UFW firewall (recommended)?" "Y"; then
  msg "Installing and configuring UFW"
  apt-get install -y ufw

  # Default policy: deny incoming, allow outgoing
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  # Always allow SSH to avoid lockout
  ufw allow 22/tcp

  # Offer to open web ports
  if ask_yes_no "Open web server ports 80 and 443 (recommended if you host a web server)?" "Y"; then
    ufw allow 80/tcp
    ufw allow 443/tcp
  fi

  # If WG ListenPort present, allow it
  if [[ -n "${LISTEN_PORT:-}" ]]; then
    ufw allow "${LISTEN_PORT}/udp"
  fi

  # Enable UFW
  echo "Enabling UFW..."
  ufw --force enable
  ufw status verbose
else
  echo "Skipping firewall installation."
fi

# === Optional Hardening: Fail2Ban ===
if ask_yes_no "Install and enable fail2ban for basic SSH protection?" "Y"; then
  msg "Installing fail2ban"
  apt-get install -y fail2ban

  # Minimal sane defaults for sshd jail
  JAIL_LOCAL="/etc/fail2ban/jail.local"
  if [[ ! -f "$JAIL_LOCAL" ]]; then
    cat > "$JAIL_LOCAL" <<'JAIL'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend = systemd

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
JAIL
  fi

  systemctl enable fail2ban
  systemctl restart fail2ban
  systemctl --no-pager -l status fail2ban || true
else
  echo "Skipping fail2ban installation."
fi

msg "All done!"
echo "Config file: $CFG_TARGET"
echo "Private key stored at: /etc/wireguard/privatekey (600)"
echo "Public  key stored at: /etc/wireguard/publickey (644)"
echo
echo "Tips:"
echo "  - View status:      wg show $IFACE"
echo "  - Bring down/up:    wg-quick down $IFACE && wg-quick up $IFACE"
echo "  - Start at boot:    systemctl enable wg-quick@$IFACE.service"
echo "  - UFW status:       ufw status verbose"
echo "  - Fail2Ban status:  systemctl status fail2ban"
