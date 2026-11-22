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

**Nothing X Panel** — A fully customized, modern game server management platform and installer.  
Features an Obsidian Electric Purple theme (`#C268F2`), complete de-branding, NAT VPS/IPv6 Cloudflare Tunnel support, and advanced domain management.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Made with Bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](https://www.gnu.org/software/bash/)
[![Theme](https://img.shields.io/badge/Theme-Obsidian%20Purple%20%23C268F2-C268F2.svg)](https://github.com/nothingxdev-top/nothing-x-panel)
[![Panel](https://img.shields.io/badge/Panel-Nothing%20X-8A2BE2.svg)](https://github.com/nothingxdev-top/nothing-x-panel)

</div>

---

## ⚡ Quick Start / Install Commands

### 1. Interactive Installer & Manager Menu (Recommended)
Run this command on your **Ubuntu or Debian Linux server** as root:

```bash
curl -fsSL https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/install.sh | sudo bash
```

Or using `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/install.sh | sudo bash
```

### 2. Apply / Update Theme & UI Fixes Directly
To instantly apply the Obsidian Purple theme, fix button colors, and update UI fixes:

```bash
curl -fsSL https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/scripts/brand-panel.sh | sudo bash
```

> **Requirements:** Ubuntu 22.04 / 24.04 / 26.04 or Debian 12 / 13 with root access.

---

## 📋 Installer Menu Overview

When you launch the installer, you are greeted with a sleek, boxed terminal menu:

```
  ╔══════════════════════════════════════════════════════════════════╗
  ║  Nothing Panel Installer — What would you like to do?            ║
  ╠══════════════════════════════════════════════════════════════════╣
  ║  [ 0] Install Panel + Wings                                      ║
  ║  [ 1] Install Panel on NAT VPS / IPv6 (via Cloudflare Tunnel)    ║
  ║  [ 2] Install the Panel only                                     ║
  ║  [ 3] Install Wings only                                         ║
  ║  [ 4] Update Panel                                               ║
  ║  [ 5] Domain Manager                                             ║
  ╟──────────────────────────────────────────────────────────────────╢
  ║  ──────── Maintenance ────────                                   ║
  ╟──────────────────────────────────────────────────────────────────╢
  ║  [ 7] Uninstall Panel or Wings                                   ║
  ╚══════════════════════════════════════════════════════════════════╝
```

### Options Breakdown:
* **`[ 0] Install Panel + Wings`**: All-in-one setup for dedicated VPS with public IPv4. Automatically configures MySQL, Nginx, Let's Encrypt SSL, Wings daemon, and automatically provisions a local node with 10 port allocations (`25565-25574`).
* **`[ 1] Install Panel on NAT VPS / IPv6 (via Cloudflare Tunnel)`**: Zero-port-forward setup. Exposes your panel through a free, automated Cloudflare Tunnel. Ideal for NAT VPS, CGNAT, dynamic IP, or IPv6-only servers.
* **`[ 2] Install the Panel only`**: Installs only the Web Panel interface (`/var/www/nothing`). Wings can be installed separately on other nodes.
* **`[ 3] Install Wings only`**: Installs only the Wings daemon (`/usr/local/bin/wings`) and Docker runtime for node servers.
* **`[ 4] Update Panel`**: Seamlessly updates an existing Nothing Panel installation to the latest version while preserving your databases, servers, and configuration.
* **`[ 5] Domain Manager`**: Opens the `np-domain` interactive manager to map domains to game server ports with automatic Let's Encrypt SSL certificates.
* **`[ 7] Uninstall Panel or Wings`**: Safe, interactive uninstaller to cleanly remove the Panel, Wings, or both.

---

## ✨ Features & Enhancements

| Feature | Description |
|---|---|
| 🎨 **Obsidian Purple Theme** | Custom Obsidian Purple (`#C268F2`) glass UI with neon accents, custom scrollbars, and glowing action buttons |
| 🌐 **Dedicated Domains Tab** | Built-in `/server/{id}/domains` route in server subnav: connect custom domains via Nginx + Auto-SSL or Cloudflare Tunnel |
| 💻 **Real Public VPS IP** | Always displays actual VPS Public IP:Port (`213.136.89.90:PORT`) across Console address cards, stat blocks, and server rows |
| 🎯 **Minimal & Clean UI** | Completely borderless 3-dots action buttons (`...`), subtle row dividers, zero unnecessary outline boxes |
| 🎛️ **Custom Select Menus** | Styled dark-mode select dropdowns with purple active checks; no default OS blue selection highlights |
| 📝 **Readable Context Menus** | Clean dropdown menus with crisp white text (`#ffffff`), electric purple icons (`#C268F2`), and purple gradient hover states |
| 🖥️ **Full-Width Startup Layout** | Stacked Startup Command (100% width terminal code box with green syntax formatting) above Docker Image selector |
| 🚫 **100% Custom Branded** | Complete custom obsidian purple branding — all system paths migrated to `/var/www/nothing` and `/etc/nothing/config.yml` |
| ☁️ **NAT VPS & IPv6 Ready** | Built-in Cloudflare Tunnel integration for NAT VPS and IPv6-only servers |
| 🌐 **Domain Manager (`np-domain`)** | Assign custom domains to game server ports with automatic Let's Encrypt SSL certificates |
| 📝 **Markdown (.md) Live Editor** | Dual-pane Markdown editor with GitHub-style live preview and syntax highlighting in the file manager |
| ⭕ **Circular Branding** | Sleek circular logo styling across login, navbar, and admin interface |
| 🧹 **Zero-Footer Clean Layout** | Distraction-free interface with footers and redundant copyright links cleanly removed |
| 🔒 **Auto SSL & Firewall** | Automated Let's Encrypt SSL configuration and UFW / firewall-cmd rule setup |
| 🔄 **One-Click Updates** | Built-in panel updater to pull the latest changes without downtime |

---

## 🖥️ Supported Operating Systems

| OS | Supported Versions | Architecture |
|---|---|---|
| **Ubuntu** | 22.04 LTS (Jammy), 24.04 LTS (Noble), 26.04 | `amd64` (x86_64), `arm64` (aarch64) |
| **Debian** | 12 (Bookworm), 13 (Trixie) | `amd64` (x86_64), `arm64` (aarch64) |

---

## 🌐 Domain → Port Mapping (`np-domain`)

Easily map friendly subdomains directly to specific game server ports with automatic Let's Encrypt SSL certificates:

```
Player connects to: game.yourdomain.com (port 80/443)
        ↓
Nginx Reverse Proxy
        ↓
Game Server Port (e.g., 25565)
        ↓
Automatic Let's Encrypt SSL ✔
```

### CLI Commands:

```bash
# Open interactive menu
np-domain

# Add a domain mapping (HTTP)
np-domain add game.yourdomain.com 25565

# Add a domain mapping with automated SSL
np-domain add game.yourdomain.com 25565 --ssl

# Add with SSL specifying your email address
np-domain add game.yourdomain.com 25565 --ssl --email you@example.com

# List all active domain mappings
np-domain list

# Remove a domain mapping
np-domain remove 25565

# Obtain SSL certificate for an existing mapped domain
np-domain ssl game.yourdomain.com
```

---

## 🔧 System Paths & Configuration

| Component | Path |
|---|---|
| **Web Panel Root** | `/var/www/nothing/` |
| **Wings Configuration** | `/etc/nothing/config.yml` |
| **Wings Service** | `systemctl status wings` |
| **Panel Queue Worker** | `systemctl status nothingq` |
| **Domain Mappings** | `/etc/nginx/sites-available/np-port-<PORT>.conf` |
| **Installer Log** | `/var/log/nothing-panel-installer.log` |
| **Domain Manager CLI** | `/usr/local/bin/np-domain` |

---

## 🔐 Post-Installation Quick Start

1. **Access your panel** at `https://your-panel-domain.com` (or your Cloudflare Tunnel URL if using Option 1).
2. **Log in** using the administrative credentials created during setup.
3. If you installed **Option 0 (Panel + Wings)**:
   - Your local Node and port allocations are already configured!
   - You can create your first game server immediately from **Admin → Servers**.
4. If you installed **Option 2 (Panel only)** and **Option 3 (Wings only)** on separate servers:
   - Go to **Admin → Locations** and create a location.
   - Go to **Admin → Nodes** and click **Create New**.
   - Copy the configuration token from the node's **Configuration** tab.
   - On the Wings server, save it to `/etc/nothing/config.yml` and run `systemctl restart wings`.
   - Add port allocations under the node's **Allocation** tab.
5. **(Optional)** Map custom domains to your allocations directly in the web panel under **Domains** tab or using `np-domain add <domain> <port> --ssl`.

---

## 📄 License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

---

<div align="center">

Made with 💜 by **Nothing X Dev**

</div>
