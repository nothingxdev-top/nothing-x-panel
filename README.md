# Nothing X Panel

<div align="center">

```
  ███╗   ██╗ ██████╗ ████████╗██╗  ██╗██╗███╗   ██╗ ██████╗ 
  ████╗  ██║██╔═══██╗╚══██╔══╝██║  ██║██║████╗  ██║██╔════╝ 
  ██╔██╗ ██║██║   ██║   ██║   ███████║██║██╔██╗ ██║██║  ███╗
  ██║╚██╗██║██║   ██║   ██║   ██╔══██║██║██║╚██╗██║██║   ██║
  ██║ ╚████║╚██████╔╝   ██║   ██║  ██║██║██║ ╚████║╚██████╔╝
  ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝
  ██████╗  █████╗ ███╗   ██╗███████╗██╗     
  ██╔══██╗██╔══██╗████╗  ██║██╔════╝██║     
  ██████╔╝███████║██╔██╗ ██║█████╗  ██║     
  ██╔═══╝ ██╔══██║██║╚██╗██║██╔══╝  ██║     
  ██║     ██║  ██║██║ ╚████║███████╗███████╗
  ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝
```

**Nothing X Panel** — A fully custom game server management panel installer.  
Looks and feels 100% like your own custom panel with advanced domain management.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Made with Bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](https://www.gnu.org/software/bash/)
[![Panel](https://img.shields.io/badge/Panel-Nothing%20X-cyan.svg)](https://github.com/nothingxdev-top/nothing-x-panel)

</div>

---

## ⚡ One-Line Install Command

Run this on your **Ubuntu/Debian Linux server** as root:

```bash
curl -fsSL https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/install.sh | sudo bash
```

Or using wget:

```bash
wget -qO- https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/install.sh | sudo bash
```

> **Requirements:** Ubuntu 22.04 / 24.04 or Debian 12 / 13 — Root access required.

> **Note:** `sudo bash <(curl ...)` may not work on some Ubuntu versions due to `/dev/fd` restrictions. Use the pipe method above.

---

## ✨ Features

| Feature | Description |
|---|---|
| 🎨 **Custom Branding** | Fully rebranded — no "Pterodactyl" visible anywhere |
| 📋 **Custom Select Menus** | Beautiful boxed, numbered menus — not plain text |
| 🌐 **Domain Management** | Assign domains to game server ports |
| 🔒 **Auto SSL** | Automatic Let's Encrypt SSL for panel + port domains |
| 🔥 **Firewall Auto-Config** | UFW / firewall-cmd auto setup |
| 📦 **Panel + Wings** | Install panel, game node (Wings), or both |
| ♻️ **Uninstall Support** | Clean uninstall for panel and Wings |
| 🛠️ **np-domain CLI** | Standalone domain → port management tool |

---

## 🗂️ What Gets Installed

```
Nothing X Panel
├── Web Panel (nginx + PHP + MariaDB + Redis)
│   └── Access at https://your-panel-domain.com
├── Wings (Game Server Node)
│   ├── Docker
│   └── Wings daemon (systemd service)
└── np-domain (Domain Manager CLI)
    └── /usr/local/bin/np-domain
```

---

## 🖥️ Supported Operating Systems

| OS | Version | Supported |
|---|---|---|
| Ubuntu | 22.04 | ✅ |
| Ubuntu | 24.04 | ✅ |
| Ubuntu | 26.04 | ✅ |
| Debian | 12 | ✅ |
| Debian | 13 | ✅ |

> Other OS versions are **not supported**.

---

## 🌐 Domain → Port Mapping (New Feature!)

After installing Wings, you can map domains to game server ports — with automatic SSL.

### Using the interactive menu (after install):
The installer will ask you if you want to set up domain mappings after Wings installation.

### Using `np-domain` CLI anytime:

```bash
# Interactive menu
np-domain

# Add a domain mapping (HTTP)
np-domain add game.yourdomain.com 25565

# Add a domain mapping with SSL
np-domain add game.yourdomain.com 25565 --ssl

# Add with SSL + specify email
np-domain add game.yourdomain.com 25565 --ssl --email you@example.com

# List all mappings
np-domain list

# Remove a mapping
np-domain remove 25565

# Get SSL for existing domain
np-domain ssl game.yourdomain.com
```

### How it works:
```
Player connects to: game.yourdomain.com (port 80/443)
        ↓
nginx reverse proxy
        ↓
Your game server on port 25565
        ↓
Automatic Let's Encrypt SSL ✔
```

---

## 📋 Install Options

When you run the installer, you'll see this custom menu:

```
  ┌──────────────────────────────────────────────────────────────┐
  │  Nothing Panel Installer — What would you like to do?        │
  ├──────────────────────────────────────────────────────────────┤
  │  [0] Install the Panel                                       │
  │  [1] Install Wings (Game Server Node)                        │
  │  [2] Install Panel + Wings on the same machine              │
  │  [3] Uninstall Panel or Wings                               │
  │  [4] ──────── Advanced / Canary ────────                    │
  │  [5] Install Panel (canary/dev version)                      │
  │  [6] Install Wings (canary/dev version)                      │
  │  [7] Install Panel + Wings (canary/dev)                     │
  │  [8] Uninstall using canary version                         │
  └──────────────────────────────────────────────────────────────┘
```

---

## 🛠️ Manual np-domain Installation

If you want to install just the domain manager on an existing server:

```bash
curl -fsSL https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/scripts/np-domain.sh -o /usr/local/bin/np-domain
chmod +x /usr/local/bin/np-domain
np-domain
```

---

## 🔧 Configuration

### Panel is installed at:
```
/var/www/nothing/
```

### Wings config:
```
/etc/pterodactyl/config.yml
```

### Domain mappings (nginx):
```
/etc/nginx/sites-available/np-port-<PORT>.conf
```

### Logs:
```
/var/log/nothing-panel-installer.log
/var/log/nginx/np-port-<PORT>.access.log
/var/log/nginx/np-port-<PORT>.error.log
```

---

## 🔐 After Panel Install — Next Steps

1. **Open your panel** at `https://your-panel-domain.com`
2. **Create a Location** (Admin → Locations)
3. **Create a Node** (Admin → Nodes) — set the FQDN to your Wings server IP/domain
4. **Copy the Wings config** from the Node's auto-deploy tab
5. **Paste it on your Wings server** at `/etc/pterodactyl/config.yml`
6. **Start Wings**: `systemctl start wings`
7. **Create an Allocation** in the Node settings (IP + port)
8. **(Optional) Add a domain** to the allocation port: `np-domain add game.yourdomain.com <PORT> --ssl`

---

## 📂 Project Structure

```
nothing-x-panel/
├── install.sh              ← Main installer entry point
├── lib/
│   └── lib.sh              ← Core library (menus, colors, helpers)
├── ui/
│   ├── panel.sh            ← Panel install UI
│   ├── wings.sh            ← Wings install UI
│   └── uninstall.sh        ← Uninstall UI
├── installers/
│   ├── panel.sh            ← Panel installation logic
│   ├── wings.sh            ← Wings installation logic
│   └── uninstall.sh        ← Uninstall logic
├── configs/
│   ├── nginx.conf          ← nginx HTTP config template
│   ├── nginx_ssl.conf      ← nginx HTTPS config template
│   ├── pteroq.service      ← Panel queue service
│   └── wings.service       ← Wings systemd service
└── scripts/
    └── np-domain.sh        ← Standalone domain manager CLI
```

---

## ⚠️ Important Notes

- Run only on **fresh servers** — not on existing installations
- Requires **root access**
- For the SSL / Let's Encrypt to work, your domain **must point to the server's IP** via DNS

---

## 📄 License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

---

<div align="center">

Made with ❤️ by **Nothing X Dev**

</div>
