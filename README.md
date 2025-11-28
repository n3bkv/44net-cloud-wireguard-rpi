# 44Net Cloud WireGuard Setup for Raspberry Pi

A simple, one-command installer for setting up **WireGuard** on a Raspberry Pi, designed for **44Net Cloud** and other ham radio / private VPN environments — built by [n3bkv](https://github.com/n3bkv).

This script automates your full WireGuard setup **and optionally hardens your Pi**:

✅ Installs WireGuard and dependencies  
✅ Generates public/private keys  
✅ Prompts you to paste your WireGuard config template  
✅ Injects your generated private key automatically  
✅ Displays and confirms the final config  
✅ Installs it in `/etc/wireguard`  
✅ Starts the WireGuard interface  
✅ Optionally enables auto-start on boot  
🛡️ **Optional hardening:** guided setup for UFW firewall (SSH + optional web ports 80/443 + WG listen port) and **Fail2Ban**

---

## Quick Start

```bash
curl -O https://raw.githubusercontent.com/n3bkv/44net-cloud-wireguard-rpi/main/setup-wireguard.sh
chmod +x setup-wireguard.sh
sudo ./setup-wireguard.sh
```

> **Tip:** Run as `root` or let the script elevate via `sudo`.

---

## Example Config Template

When prompted, paste your config (and end input with `EOF`):

```
[Interface]
PrivateKey = REPLACE_ME
Address = 44.xx.xx.xx/24, fe80:0000:0000:0000:f9dc:93ae:XXXX:XXXX/64
DNS = 1.1.1.1,1.0.0.1

[Peer]
PublicKey = Provided
Endpoint = xxx.xxx.xxx.xxx:xxxxx
PersistentKeepalive = 20
AllowedIPs = 0.0.0.0/0, ::/0
```

The script replaces `REPLACE_ME` with your generated private key automatically.

---

##  What the Script Does

1. Updates apt and installs:
   - `wireguard`, `wireguard-tools`, and `resolvconf`/`openresolv`
2. Generates keypair and stores them in `/etc/wireguard/privatekey` and `/etc/wireguard/publickey`
3. Prompts for your WireGuard config and injects your private key
4. Shows the final `.conf` for approval
5. Installs it as `/etc/wireguard/<iface>.conf`
6. Brings the interface up via `wg-quick`
7. Optionally enables systemd auto-start on boot:
   ```bash
   systemctl enable wg-quick@wg0.service
   ```

---

## ️ Optional Hardening Steps (interactive)

During the run, you’ll be asked if you want to:

### 1) Install & Enable UFW Firewall
- Sets **deny incoming / allow outgoing** by default
- Always opens **SSH (22/tcp)** so you don’t lock yourself out
- Offers to open **80/tcp** and **443/tcp** (recommended if you run a web server)
- If your WireGuard config defines a `ListenPort`, the script will allow that **UDP** port too
- Enables the firewall and prints `ufw status verbose`

### 2) Install & Enable Fail2Ban
- Installs `fail2ban` and creates a minimal `/etc/fail2ban/jail.local` enabling the **sshd** jail
- Uses safe defaults (`bantime 1h`, `findtime 10m`, `maxretry 5`)
- Starts and enables the service

---

## 🔧 Useful Commands

| Action | Command |
|--------|----------|
| Show current status | `wg show wg0` |
| Bring interface up/down | `wg-quick up wg0` / `wg-quick down wg0` |
| Enable on boot | `sudo systemctl enable wg-quick@wg0` |
| Disable on boot | `sudo systemctl disable wg-quick@wg0` |
| UFW status | `sudo ufw status verbose` |
| Fail2Ban status | `sudo systemctl status fail2ban` |

---

##  Notes

- Compatible with Raspberry Pi OS (Bookworm/Bullseye)  
- Works well for **44Net Cloud** deployments and static IP VPNs  
- Supports both IPv4 and IPv6 addressing  
- Automatically backs up existing keys/configs before overwriting  
- Detects and installs `resolvconf` or `openresolv` for DNS handling  
- UFW rules only open ports you explicitly approve; SSH (22) is always allowed to prevent lockout

---

##  License

MIT License © 2025 [n3bkv](https://github.com/n3bkv)

---

##  Contributions

Pull requests are welcome!  

---

## Support This Project

If you find this useful, star ⭐ the repo! It helps others discover it.

---

**73, N3BKV**  
Dave  
https://hamradiohacks.blogspot.com
https://hamradiohacks.n3bkv.com  
