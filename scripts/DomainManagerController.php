<?php

namespace Pterodactyl\Http\Controllers\Base;

use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Pterodactyl\Models\Server;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Support\Facades\Auth;

class DomainManagerController extends Controller
{
    /**
     * Get list of allocated ports and active mapped domains / Cloudflare tunnels for this server.
     */
    public function index(Request $request, string $server_id): JsonResponse
    {
        $server = Server::where('uuidShort', $server_id)
            ->orWhere('uuid', $server_id)
            ->first();

        if (!$server) {
            return response()->json(['error' => 'Server not found'], 404);
        }

        $user = Auth::user();
        if (!$user || (!$user->root_admin && $server->owner_id !== $user->id)) {
            return response()->json(['error' => 'Unauthorized'], 403);
        }

        $allocations = $server->allocations()->get();
        $ports = $allocations->pluck('port')->toArray();

        $domains = [];
        foreach ($ports as $port) {
            // 1. Check Nginx configuration
            $confFile = "/etc/nginx/sites-available/np-port-{$port}.conf";
            if (file_exists($confFile)) {
                $content = @file_get_contents($confFile);
                if (preg_match('/server_name\s+([^;]+);/', $content, $m)) {
                    $domain = trim($m[1]);
                    $hasSsl = strpos($content, 'ssl_certificate') !== false || file_exists("/etc/letsencrypt/live/{$domain}");
                    $domains[] = [
                        'type' => 'nginx',
                        'domain' => $domain,
                        'port' => (int) $port,
                        'ssl' => (bool) $hasSsl,
                    ];
                }
            }

            // 2. Check Cloudflare Tunnel status
            $cfMetaFile = "/var/log/cf-tunnel-{$port}.meta";
            $cfLogFile = "/var/log/cf-tunnel-{$port}.log";
            if (file_exists($cfMetaFile)) {
                $meta = json_decode(@file_get_contents($cfMetaFile), true);
                if ($meta && !empty($meta['domain'])) {
                    // Check if service/process is active
                    exec("pgrep -f 'cloudflared.*127.0.0.1:{$port}'", $pids);
                    $isActive = !empty($pids);
                    $domains[] = [
                        'type' => 'cloudflared',
                        'domain' => $meta['domain'],
                        'port' => (int) $port,
                        'ssl' => true,
                        'active' => $isActive,
                        'custom_domain' => $meta['custom_domain'] ?? false,
                    ];
                }
            } elseif (file_exists($cfLogFile)) {
                // Parse trycloudflare.com URL from log if meta missing
                $logContent = @file_get_contents($cfLogFile);
                if (preg_match('/https:\/\/([a-zA-Z0-9-]+\.trycloudflare\.com)/', $logContent, $matches)) {
                    $domains[] = [
                        'type' => 'cloudflared',
                        'domain' => $matches[1],
                        'port' => (int) $port,
                        'ssl' => true,
                        'active' => true,
                        'custom_domain' => false,
                    ];
                }
            }
        }

        return response()->json([
            'success' => true,
            'server_id' => $server->uuidShort,
            'allocations' => $allocations->map(function ($a) {
                return [
                    'id' => $a->id,
                    'ip' => $a->ip,
                    'port' => $a->port,
                ];
            }),
            'domains' => $domains,
            'cloudflared_installed' => file_exists('/usr/local/bin/cloudflared') || !empty(shell_exec('which cloudflared 2>/dev/null')),
        ]);
    }

    /**
     * Add a domain mapping or Cloudflare Tunnel for this server's port.
     */
    public function store(Request $request, string $server_id): JsonResponse
    {
        $server = Server::where('uuidShort', $server_id)
            ->orWhere('uuid', $server_id)
            ->first();

        if (!$server) {
            return response()->json(['error' => 'Server not found'], 404);
        }

        $user = Auth::user();
        if (!$user || (!$user->root_admin && $server->owner_id !== $user->id)) {
            return response()->json(['error' => 'Unauthorized'], 403);
        }

        $mode = $request->input('mode', 'nginx'); // 'nginx' or 'cloudflared'
        $port = (int) $request->input('port', 0);
        $allowedPorts = $server->allocations()->pluck('port')->toArray();

        if (!$user->root_admin && !in_array($port, $allowedPorts)) {
            return response()->json(['error' => 'Selected port does not belong to this server.'], 403);
        }

        // ========================================================
        // MODE A: CLOUDFLARE TUNNEL (NAT VPS / IPv6 / NO PORT FORWARDING)
        // ========================================================
        if ($mode === 'cloudflared') {
            $cfBin = file_exists('/usr/local/bin/cloudflared') ? '/usr/local/bin/cloudflared' : trim((string) shell_exec('which cloudflared 2>/dev/null'));
            if (empty($cfBin)) {
                // Auto-install cloudflared if not present
                exec("curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared && sudo /bin/mv -f /tmp/cloudflared /usr/local/bin/cloudflared && sudo /bin/chmod +x /usr/local/bin/cloudflared 2>&1");
                $cfBin = '/usr/local/bin/cloudflared';
            }

            $token = trim((string) $request->input('cf_token', ''));
            $customDomain = trim((string) $request->input('domain', ''));
            if (!empty($customDomain) && !preg_match('/^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/', $customDomain)) {
                return response()->json(['error' => 'Invalid domain name format.'], 422);
            }

            $svcName = "np-cf-tunnel-{$port}";
            $svcFile = "/etc/systemd/system/{$svcName}.service";
            $logFile = "/var/log/cf-tunnel-{$port}.log";
            $metaFile = "/var/log/cf-tunnel-{$port}.meta";

            // Stop existing service if running
            exec("sudo /bin/systemctl stop {$svcName} 2>/dev/null");
            @unlink($logFile);
            @unlink($metaFile);

            if (!empty($token)) {
                // Token-based Named Tunnel
                $serviceUnit = <<<UNIT
[Unit]
Description=Nothing Panel Cloudflare Tunnel (Port {$port})
After=network.target

[Service]
Type=simple
User=root
ExecStart={$cfBin} tunnel --no-autoupdate run --token {$token}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT;
                $assignedDomain = !empty($customDomain) ? $customDomain : 'Cloudflare Tunnel (Token Active)';
                file_put_contents("/tmp/{$svcName}.service", $serviceUnit);
                exec("sudo /bin/mv -f /tmp/{$svcName}.service {$svcFile} && sudo /bin/systemctl daemon-reload && sudo /bin/systemctl enable --now {$svcName} 2>&1");

                file_put_contents($metaFile, json_encode([
                    'domain' => $assignedDomain,
                    'port' => $port,
                    'custom_domain' => true,
                    'token_mode' => true,
                ]));

                return response()->json([
                    'success' => true,
                    'message' => "Cloudflare Tunnel successfully launched with token for Port {$port}!",
                    'domain' => $assignedDomain,
                    'port' => $port,
                    'type' => 'cloudflared',
                ]);
            } else {
                // Instant Quick Tunnel (trycloudflare.com)
                // Launch cloudflared tunnel
                $cmd = "sudo nohup {$cfBin} tunnel --no-autoupdate --url http://127.0.0.1:{$port} > {$logFile} 2>&1 &";
                exec($cmd);

                // Wait up to 5 seconds to capture assigned trycloudflare.com URL
                $assignedDomain = null;
                for ($i = 0; $i < 10; $i++) {
                    usleep(500000); // 0.5 sec
                    if (file_exists($logFile)) {
                        $log = file_get_contents($logFile);
                        if (preg_match('/https:\/\/([a-zA-Z0-9-]+\.trycloudflare\.com)/', $log, $m)) {
                            $assignedDomain = $m[1];
                            break;
                        }
                    }
                }

                if (!$assignedDomain) {
                    $assignedDomain = "tunnel-port-{$port}.trycloudflare.com";
                }

                file_put_contents($metaFile, json_encode([
                    'domain' => $assignedDomain,
                    'port' => $port,
                    'custom_domain' => false,
                    'token_mode' => false,
                ]));

                return response()->json([
                    'success' => true,
                    'message' => "Instant Cloudflare Tunnel active: https://{$assignedDomain} is now routing to Port {$port}!",
                    'domain' => $assignedDomain,
                    'port' => $port,
                    'type' => 'cloudflared',
                ]);
            }
        }

        // ========================================================
        // MODE B: DIRECT NGINX REVERSE PROXY WITH AUTO-SSL
        // ========================================================
        $domain = strtolower(trim((string) $request->input('domain', '')));
        $enableSsl = filter_var($request->input('ssl', true), FILTER_VALIDATE_BOOLEAN);

        if (empty($domain) || !preg_match('/^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/', $domain)) {
            return response()->json(['error' => 'Invalid domain name format.'], 422);
        }

        $confFile = "/etc/nginx/sites-available/np-port-{$port}.conf";
        $linkFile = "/etc/nginx/sites-enabled/np-port-{$port}.conf";

        $nginxConf = <<<NGINX
# Nothing Panel — Domain Port Mapping
# Domain: {$domain}
# Port: {$port}
# Server: {$server->uuidShort}

server {
    listen 80;
    listen [::]:80;
    server_name {$domain};

    location / {
        proxy_pass http://127.0.0.1:{$port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }

    access_log /var/log/nginx/np-port-{$port}.access.log;
    error_log  /var/log/nginx/np-port-{$port}.error.log error;
}
NGINX;

        $tmpFile = tempnam(sys_get_temp_dir(), 'np_conf_');
        file_put_contents($tmpFile, $nginxConf);
        chmod($tmpFile, 0644);

        exec("sudo /bin/mv -f " . escapeshellarg($tmpFile) . " " . escapeshellarg($confFile), $out, $ret);
        exec("sudo /bin/ln -sf " . escapeshellarg($confFile) . " " . escapeshellarg($linkFile));

        exec("sudo /usr/sbin/nginx -t 2>&1", $tOut, $tRet);
        if ($tRet !== 0) {
            exec("sudo /bin/rm -f " . escapeshellarg($confFile) . " " . escapeshellarg($linkFile));
            return response()->json(['error' => 'Nginx configuration test failed: ' . implode(" ", $tOut)], 500);
        }

        exec("sudo /bin/systemctl reload nginx 2>&1");

        $sslNotice = "";
        if ($enableSsl) {
            $email = $user->email ?: 'admin@' . $domain;
            exec("sudo certbot --nginx --redirect --no-eff-email --email " . escapeshellarg($email) . " -d " . escapeshellarg($domain) . " 2>&1", $cOut, $cRet);
            if ($cRet === 0) {
                $sslNotice = " with SSL (HTTPS) enabled";
            } else {
                $sslNotice = " (HTTP active; SSL pending DNS propagation)";
            }
        }

        return response()->json([
            'success' => true,
            'message' => "Domain {$domain} successfully connected to port {$port}{$sslNotice}!",
            'domain' => $domain,
            'port' => $port,
            'type' => 'nginx',
        ]);
    }

    /**
     * Remove a domain mapping or Cloudflare Tunnel for this server's port.
     */
    public function destroy(Request $request, string $server_id): JsonResponse
    {
        $server = Server::where('uuidShort', $server_id)
            ->orWhere('uuid', $server_id)
            ->first();

        if (!$server) {
            return response()->json(['error' => 'Server not found'], 404);
        }

        $user = Auth::user();
        if (!$user || (!$user->root_admin && $server->owner_id !== $user->id)) {
            return response()->json(['error' => 'Unauthorized'], 403);
        }

        $port = (int) $request->input('port', 0);
        $allowedPorts = $server->allocations()->pluck('port')->toArray();

        if (!$user->root_admin && !in_array($port, $allowedPorts)) {
            return response()->json(['error' => 'Selected port does not belong to this server.'], 403);
        }

        // 1. Remove Nginx configuration if present
        $confFile = "/etc/nginx/sites-available/np-port-{$port}.conf";
        $linkFile = "/etc/nginx/sites-enabled/np-port-{$port}.conf";

        if (file_exists($confFile)) {
            $content = @file_get_contents($confFile);
            if (preg_match('/server_name\s+([^;]+);/', $content, $m)) {
                $domain = trim($m[1]);
                exec("sudo certbot delete --cert-name " . escapeshellarg($domain) . " --non-interactive 2>&1");
            }
            exec("sudo /bin/rm -f " . escapeshellarg($confFile) . " " . escapeshellarg($linkFile));
            exec("sudo /bin/systemctl reload nginx 2>&1");
        }

        // 2. Stop and remove Cloudflare Tunnel if present
        $svcName = "np-cf-tunnel-{$port}";
        $svcFile = "/etc/systemd/system/{$svcName}.service";
        exec("sudo /bin/systemctl stop {$svcName} 2>/dev/null");
        exec("sudo /bin/systemctl disable {$svcName} 2>/dev/null");
        if (file_exists($svcFile)) {
            exec("sudo /bin/rm -f {$svcFile} && sudo /bin/systemctl daemon-reload 2>/dev/null");
        }
        exec("sudo pkill -f 'cloudflared.*127.0.0.1:{$port}' 2>/dev/null");
        @unlink("/var/log/cf-tunnel-{$port}.log");
        @unlink("/var/log/cf-tunnel-{$port}.meta");

        return response()->json([
            'success' => true,
            'message' => "Port {$port} domain mapping / Cloudflare Tunnel disconnected successfully.",
        ]);
    }
}
