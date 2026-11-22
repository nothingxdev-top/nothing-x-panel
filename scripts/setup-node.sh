#!/bin/bash

######################################################################################
#  Nothing X Panel — Automatic Wings Daemon & Node Setup Script                     #
#  Installs Wings, connects to Nothing Panel, and sets up default allocations       #
######################################################################################

set -e -o pipefail

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Must run as root"
  exit 1
fi

# Detect Panel Directory
PANEL_DIR=""
if [ -d "/var/www/nothing" ]; then
  PANEL_DIR="/var/www/nothing"
elif [ -d "/var/www/pterodactyl" ]; then
  PANEL_DIR="/var/www/pterodactyl"
else
  echo "ERROR: Neither /var/www/nothing nor /var/www/pterodactyl was found."
  exit 1
fi

echo "=========================================================="
echo " Setting up Wings Daemon & Node on Nothing Panel...      "
echo " Panel Directory: $PANEL_DIR"
echo "=========================================================="

# 1. Install Docker if not present
if ! command -v docker >/dev/null 2>&1; then
  echo "* Installing Docker engine..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
else
  echo "✔ Docker is already installed"
fi
systemctl start docker || true

# 2. Download Wings Binary
mkdir -p /etc/nothing /var/log/nothing /var/run/wings /home/daemon-files
ln -sfn /etc/nothing /etc/pterodactyl
ln -sfn /var/log/nothing /var/log/pterodactyl
if [ ! -f "/usr/local/bin/wings" ]; then
  echo "* Downloading Wings binary..."
  ARCH="amd64"
  [ "$(uname -m)" == "aarch64" ] && ARCH="arm64"
  curl -fsSL -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH}"
  chmod +x /usr/local/bin/wings
  echo "✔ Wings downloaded"
else
  echo "✔ Wings binary already present"
fi

# 3. Install Wings systemd service
cat << 'EOF' > /etc/systemd/system/wings.service
[Unit]
Description=Nothing Panel Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/nothing
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings --config /etc/nothing/config.yml
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# 4. Open Firewall Ports
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  echo "* Allowing firewall ports (8080, 2022, 25565-25575)..."
  ufw allow 8080/tcp >/dev/null 2>&1 || true
  ufw allow 2022/tcp >/dev/null 2>&1 || true
  ufw allow 25565:25575/tcp >/dev/null 2>&1 || true
  ufw allow 25565:25575/udp >/dev/null 2>&1 || true
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
  echo "* Allowing firewalld ports (8080, 2022, 25565-25575)..."
  firewall-cmd --permanent --add-port=8080/tcp >/dev/null 2>&1 || true
  firewall-cmd --permanent --add-port=2022/tcp >/dev/null 2>&1 || true
  firewall-cmd --permanent --add-port=25565-25575/tcp >/dev/null 2>&1 || true
  firewall-cmd --permanent --add-port=25565-25575/udp >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
fi

# 5. Bootstrap Laravel to Create Location, Node, Config & Allocations
TMP_PHP=$(mktemp /tmp/np-node-setup.XXXXXX.php)
cat << 'PHPEOF' > "$TMP_PHP"
<?php
$panelDir = is_dir('/var/www/nothing') ? '/var/www/nothing' : '/var/www/pterodactyl';
require $panelDir . '/vendor/autoload.php';
$app = require $panelDir . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Pterodactyl\Models\Location;
use Pterodactyl\Models\Node;
use Pterodactyl\Models\Allocation;
use Pterodactyl\Services\Nodes\NodeCreationService;

// 1. Create Location
$location = Location::firstOrCreate(
    ['short' => 'local'],
    ['long' => 'Default Location']
);
echo "✔ Location ready: [ID {$location->id}] {$location->long}\n";

// 2. Resolve FQDN
$appUrl = config('app.url');
$fqdn = parse_url($appUrl, PHP_URL_HOST);
if (empty($fqdn) || $fqdn === 'localhost') {
    $serverIp = trim(shell_exec("curl -fsSL ifconfig.me 2>/dev/null || curl -fsSL api.ipify.org 2>/dev/null") ?: '127.0.0.1');
    $fqdn = $serverIp;
}

// 3. Create or Update Node
$node = Node::where('fqdn', $fqdn)->orWhere('name', 'Nothing Node')->first();
if (!$node) {
    // RAM: 85% of system memory
    $totalMem = (int) shell_exec("free -m | awk '/^Mem:/{print int($2 * 0.85)}'");
    if ($totalMem < 1024) $totalMem = 2048;

    // Disk: 85% of root partition
    $totalDisk = (int) shell_exec("df -m / | awk 'NR==2{print int($2 * 0.85)}'");
    if ($totalDisk < 10000) $totalDisk = 50000;

    $scheme = (strpos($appUrl, 'https://') === 0) ? 'https' : 'http';

    $node = app(NodeCreationService::class)->handle([
        'name' => 'Nothing Node',
        'location_id' => $location->id,
        'fqdn' => $fqdn,
        'scheme' => $scheme,
        'memory' => $totalMem,
        'memory_overallocate' => 0,
        'disk' => $totalDisk,
        'disk_overallocate' => 0,
        'upload_size' => 100,
        'daemonListen' => 8080,
        'daemonSFTP' => 2022,
        'behind_proxy' => false,
        'public' => true,
    ]);
    echo "✔ Node created: [ID {$node->id}] {$node->name} ({$node->fqdn})\n";
} else {
    echo "✔ Existing Node found: [ID {$node->id}] {$node->name} ({$node->fqdn})\n";
}

// 4. Write /etc/nothing/config.yml
@mkdir('/etc/nothing', 0755, true);
file_put_contents('/etc/nothing/config.yml', $node->getYamlConfiguration());
@symlink('/etc/nothing/config.yml', '/etc/pterodactyl/config.yml');
echo "✔ Generated /etc/nothing/config.yml\n";

// 5. Create Default Allocations (Ports 25565 - 25575)
$createdAllocations = 0;
$alloc_ip = !empty($ip) ? $ip : (!empty($fqdn) ? $fqdn : '0.0.0.0');
for ($port = 25565; $port <= 25575; $port++) {
    $alloc = Allocation::firstOrCreate([
        'node_id' => $node->id,
        'ip' => '0.0.0.0',
        'port' => $port,
    ], [
        'ip_alias' => $alloc_ip,
    ]);
    if ($alloc->wasRecentlyCreated) {
        $createdAllocations++;
    }
}
$totalAllocations = Allocation::where('node_id', $node->id)->count();
echo "✔ Allocations ready: {$totalAllocations} ports configured (25565-25575)\n";
PHPEOF

php "$TMP_PHP"
rm -f "$TMP_PHP"

# 6. Start Wings Service
echo "* Starting Wings daemon service..."
systemctl enable wings
systemctl restart wings
sleep 2

if systemctl is-active --quiet wings; then
  echo "✔ Wings is ACTIVE and connected to Nothing Panel!"
else
  echo "⚠ Wings service started but status is $(systemctl is-active wings). Check journalctl -u wings"
fi

echo "=========================================================="
echo " Wings & Node setup completed successfully!              "
echo "=========================================================="
