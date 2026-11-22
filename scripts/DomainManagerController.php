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
            // 1. Check Nginx configuration (scoped first, then legacy fallback)
            $confFile = "/etc/nginx/sites-available/np-srv-{$server->uuidShort}-port-{$port}.conf";
            if (!file_exists($confFile)) {
                $confFile = "/etc/nginx/sites-available/np-port-{$port}.conf";
            }

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

            // 2. Check Cloudflare Tunnel status (scoped meta first, then legacy)
            $cfMetaFile = "/etc/nothing/tunnels/cf-srv-{$server->uuidShort}-port-{$port}.meta";
            if (!file_exists($cfMetaFile)) {
                $cfMetaFile = "/var/log/cf-tunnel-{$port}.meta";
            }

            if (file_exists($cfMetaFile)) {
                $meta = json_decode(@file_get_contents($cfMetaFile), true);
                if ($meta && !empty($meta['domain'])) {
                    $statusOut = [];
                    exec("sudo /usr/local/sbin/np-domain-helper status-cf " . escapeshellarg($server->uuidShort) . " " . escapeshellarg($port) . " 2>/dev/null", $statusOut);
                    $isActive = trim($statusOut[0] ?? '') === 'active';
                    $domains[] = [
                        'type' => 'cloudflared',
                        'domain' => $meta['domain'],
                        'port' => (int) $port,
                        'ssl' => true,
                        'active' => $isActive,
                        'custom_domain' => $meta['custom_domain'] ?? false,
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

        if ($port < 1024 || $port > 65535) {
            return response()->json(['error' => 'Invalid port number (must be between 1024 and 65535).'], 422);
        }

        // ========================================================
        // MODE A: CLOUDFLARE TUNNEL (NAT VPS / IPv6 / NO PORT FORWARDING)
        // ========================================================
        if ($mode === 'cloudflared') {
            $token = trim((string) $request->input('cf_token', ''));
            $customDomain = trim((string) $request->input('domain', ''));

            if (!empty($token) && !preg_match('/^[A-Za-z0-9=_-]{20,2048}$/', $token)) {
                return response()->json(['error' => 'Invalid Cloudflare Tunnel token format.'], 422);
            }

            if (!empty($customDomain) && !preg_match('/^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/', $customDomain)) {
                return response()->json(['error' => 'Invalid custom domain name format.'], 422);
            }

            $cmd = "sudo /usr/local/sbin/np-domain-helper add-cf " .
                escapeshellarg($server->uuidShort) . " " .
                escapeshellarg((string) $port) . " " .
                escapeshellarg($token) . " " .
                escapeshellarg($customDomain) . " 2>&1";

            $output = [];
            $exitCode = 0;
            exec($cmd, $output, $exitCode);

            if ($exitCode !== 0) {
                return response()->json([
                    'error' => 'Cloudflare tunnel creation failed: ' . implode(' ', $output)
                ], 500);
            }

            // Read domain from metadata file
            $metaFile = "/etc/nothing/tunnels/cf-srv-{$server->uuidShort}-port-{$port}.meta";
            $assignedDomain = $customDomain ?: "tunnel-port-{$port}.trycloudflare.com";
            if (file_exists($metaFile)) {
                $meta = json_decode(@file_get_contents($metaFile), true);
                if (!empty($meta['domain'])) {
                    $assignedDomain = $meta['domain'];
                }
            }

            return response()->json([
                'success' => true,
                'message' => implode(' ', $output),
                'domain' => $assignedDomain,
                'port' => $port,
                'type' => 'cloudflared',
            ]);
        }

        // ========================================================
        // MODE B: DIRECT NGINX REVERSE PROXY WITH AUTO-SSL
        // ========================================================
        $domain = strtolower(trim((string) $request->input('domain', '')));
        $enableSsl = filter_var($request->input('ssl', true), FILTER_VALIDATE_BOOLEAN);

        if (empty($domain) || !preg_match('/^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/', $domain)) {
            return response()->json(['error' => 'Invalid domain name format.'], 422);
        }

        $cmd = "sudo /usr/local/sbin/np-domain-helper add-nginx " .
            escapeshellarg($server->uuidShort) . " " .
            escapeshellarg($domain) . " " .
            escapeshellarg((string) $port) . " " .
            ($enableSsl ? "1" : "0") . " 2>&1";

        $output = [];
        $exitCode = 0;
        exec($cmd, $output, $exitCode);

        if ($exitCode !== 0) {
            return response()->json([
                'error' => implode(' ', $output) ?: 'Nginx configuration failed.'
            ], 500);
        }

        return response()->json([
            'success' => true,
            'message' => implode(' ', $output),
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

        // Clean up both Nginx and Cloudflare for this port
        exec("sudo /usr/local/sbin/np-domain-helper delete-nginx " .
            escapeshellarg($server->uuidShort) . " " .
            escapeshellarg((string) $port) . " 2>&1");

        exec("sudo /usr/local/sbin/np-domain-helper delete-cf " .
            escapeshellarg($server->uuidShort) . " " .
            escapeshellarg((string) $port) . " 2>&1");

        return response()->json([
            'success' => true,
            'message' => "Port {$port} domain mapping / Cloudflare Tunnel disconnected successfully.",
        ]);
    }
}
