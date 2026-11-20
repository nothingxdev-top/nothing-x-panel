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
     * Get list of allocated ports and active mapped domains for this server.
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
            $confFile = "/etc/nginx/sites-available/np-port-{$port}.conf";
            if (file_exists($confFile)) {
                $content = @file_get_contents($confFile);
                if (preg_match('/server_name\s+([^;]+);/', $content, $m)) {
                    $domain = trim($m[1]);
                    $hasSsl = strpos($content, 'ssl_certificate') !== false || file_exists("/etc/letsencrypt/live/{$domain}");
                    $domains[] = [
                        'domain' => $domain,
                        'port' => (int) $port,
                        'ssl' => (bool) $hasSsl,
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
        ]);
    }

    /**
     * Add a domain mapping for this server's port.
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

        $domain = strtolower(trim((string) $request->input('domain', '')));
        $port = (int) $request->input('port', 0);
        $enableSsl = filter_var($request->input('ssl', true), FILTER_VALIDATE_BOOLEAN);

        if (empty($domain) || !preg_match('/^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/', $domain)) {
            return response()->json(['error' => 'Invalid domain name format.'], 422);
        }

        $allowedPorts = $server->allocations()->pluck('port')->toArray();
        if (!$user->root_admin && !in_array($port, $allowedPorts)) {
            return response()->json(['error' => 'Selected port does not belong to this server.'], 403);
        }

        $confFile = "/etc/nginx/sites-available/np-port-{$port}.conf";
        $linkFile = "/etc/nginx/sites-enabled/np-port-{$port}.conf";

        // Generate Nginx reverse-proxy configuration
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

        // Move into place via sudo
        exec("sudo /bin/mv -f " . escapeshellarg($tmpFile) . " " . escapeshellarg($confFile), $out, $ret);
        exec("sudo /bin/ln -sf " . escapeshellarg($confFile) . " " . escapeshellarg($linkFile));

        // Test and reload Nginx
        exec("sudo /usr/sbin/nginx -t 2>&1", $tOut, $tRet);
        if ($tRet !== 0) {
            exec("sudo /bin/rm -f " . escapeshellarg($confFile) . " " . escapeshellarg($linkFile));
            return response()->json(['error' => 'Nginx configuration test failed: ' . implode(" ", $tOut)], 500);
        }

        exec("sudo /bin/systemctl reload nginx 2>&1");

        // Attempt SSL if requested
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
        ]);
    }

    /**
     * Remove a domain mapping for this server's port.
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

        return response()->json([
            'success' => true,
            'message' => "Domain mapping for port {$port} removed successfully.",
        ]);
    }
}
