const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.TEST_PORT || 3100;

// Read brand-panel.sh to extract the latest injected CSS and JS
let customCss = '';
let customJs = '';
try {
  const brandPanelPath = path.resolve(__dirname, '../../../scripts/brand-panel.sh');
  const content = fs.readFileSync(brandPanelPath, 'utf-8');

  const cssMatch = content.match(/custom_css = """([\s\S]*?)"""/);
  if (cssMatch) {
    customCss = cssMatch[1];
  }
} catch (e) {
  console.warn('Could not extract CSS/JS dynamically from brand-panel.sh:', e.message);
}

function renderHtml(title, bodyContent, currentRoute) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="csrf-token" content="mock-csrf-token-12345">
  <title>${title} | Nothing Panel</title>
  ${customCss}
  <style>
    /* Baseline Tailwind-like styling for mock Pterodactyl container */
    * { box-sizing: border-box; }
    .w-full { width: 100%; }
    .max-w-screen-xl { max-width: 1280px; margin: 0 auto; }
    .flex { display: flex; }
    .items-center { align-items: center; }
    .space-x-4 > * + * { margin-left: 1rem; }
    .px-4 { padding-left: 1rem; padding-right: 1rem; }
    .py-3 { padding-top: 0.75rem; padding-bottom: 0.75rem; }
    .mb-6 { margin-bottom: 1.5rem; }
    .text-sm { font-size: 0.875rem; }
    .font-semibold { font-weight: 600; }
    .bg-neutral-900 { background-color: #120e24; }
    .border-b { border-bottom: 1px solid rgba(255,255,255,0.1); }
    .overflow-x-auto { overflow-x: auto; }
  </style>
</head>
<body data-np-route="${currentRoute}">
  <div id="app">
    <!-- SubNavigation Mock -->
    <div class="bg-neutral-900 border-b flex overflow-x-auto px-4 SubNavigation">
      <nav class="flex space-x-4">
        <a href="/server/test-srv-123/console" class="px-3 py-3 text-sm font-semibold ${currentRoute === 'console' ? 'active border-cyan-500' : ''}">Console</a>
        <a href="/server/test-srv-123/files" class="px-3 py-3 text-sm font-semibold ${currentRoute === 'files' ? 'active border-cyan-500' : ''}">Files</a>
        <a href="/server/test-srv-123/databases" class="px-3 py-3 text-sm font-semibold ${currentRoute === 'databases' ? 'active border-cyan-500' : ''}">Databases</a>
        <a href="/server/test-srv-123/schedules" class="px-3 py-3 text-sm font-semibold ${currentRoute === 'schedules' ? 'active border-cyan-500' : ''}">Schedules</a>
        <a href="/server/test-srv-123/users" class="px-3 py-3 text-sm font-semibold ${currentRoute === 'users' ? 'active border-cyan-500' : ''}">Users</a>
        <a href="/server/test-srv-123/backups" class="px-3 py-3 text-sm font-semibold ${currentRoute === 'backups' ? 'active border-cyan-500' : ''}">Backups</a>
        <a href="/server/test-srv-123/network" class="px-3 py-3 text-sm font-semibold ${currentRoute === 'network' ? 'active border-cyan-500' : ''}">Network</a>
        <a href="/server/test-srv-123/startup" class="px-3 py-3 text-sm font-semibold ${currentRoute === 'startup' ? 'active border-cyan-500' : ''}">Startup</a>
        <a href="/server/test-srv-123/settings" class="px-3 py-3 text-sm font-semibold ${currentRoute === 'settings' ? 'active border-cyan-500' : ''}">Settings</a>
        <a href="/server/test-srv-123/domains" class="px-3 py-3 text-sm font-semibold ${currentRoute === 'domains' ? 'active border-cyan-500' : ''}">Domains</a>
        <a href="/server/test-srv-123/activity" class="px-3 py-3 text-sm font-semibold ${currentRoute === 'activity' ? 'active border-cyan-500' : ''}">Activity</a>
      </nav>
    </div>

    <!-- Main Content Outlet -->
    <div class="max-w-screen-xl px-4 py-6" id="main-content">
      ${bodyContent}
    </div>
  </div>
</body>
</html>`;
}

const server = http.createServer((req, res) => {
  const url = req.url || '/';

  if (url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK');
    return;
  }

  // GET /api/server/:id/domains
  if (url.startsWith('/api/server/') && url.endsWith('/domains')) {
    if (url.includes('error-srv')) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Internal Database Connection Error' }));
      return;
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      success: true,
      server_id: 'test-srv-123',
      allocations: [
        { id: 1, ip: '213.136.89.90', port: 25565, is_default: true },
        { id: 2, ip: '213.136.89.90', port: 25566, is_default: false },
      ],
      domains: [
        { type: 'nginx', domain: 'play.example.com', port: 25565, ssl: true },
        { type: 'cloudflared', domain: 'lobby.example.org', port: 25566, ssl: true, active: true },
      ],
      cloudflared_installed: true,
    }));
    return;
  }

  // POST /api/server/:id/domains
  if (url.startsWith('/api/server/') && url.endsWith('/domains') && req.method === 'POST') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      success: true,
      message: 'Domain successfully connected!',
      domain: 'play.example.com',
      port: 25565,
    }));
    return;
  }

  // Route: /server/:id/startup
  if (url.includes('/startup')) {
    const startupInvocation = 'if [[ -d .git ]] && [[ 0 == "1" ]]; then git pull; fi; if [[ ! -z ${NODE_PACKAGES} ]]; then /usr/local/bin/npm install ${NODE_PACKAGES}; fi; if [[ ! -z ${UNNODE_PACKAGES} ]]; then /usr/local/bin/npm uninstall ${UNNODE_PACKAGES}; fi; if [ -f /home/container/package.json ]; then /usr/local/bin/npm install; fi; if [[ "${MAIN_FILE}" == "*.js" ]]; then /usr/local/bin/node "/home/container/${MAIN_FILE}" ${NODE_ARGS}; else /usr/local/bin/ts-node --esm "/home/container/${MAIN_FILE}" ${NODE_ARGS}; fi';

    const startupHtml = `
      <div class="StartupContainer">
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div class="md:col-span-2" id="startup-command-card">
            <div class="TitledGreyBox">
              <div><p class="font-header">Startup Command</p></div>
              <div>
                <p class="font-mono bg-neutral-900 rounded p-3 text-sm">${startupInvocation}</p>
              </div>
            </div>
          </div>
          <div class="md:col-span-2" id="docker-image-card">
            <div class="TitledGreyBox">
              <div><p class="font-header">Docker Image</p></div>
              <div>
                <select name="docker_image" class="w-full">
                  <option value="nodejs_25">Nodejs 25</option>
                  <option value="nodejs_24">Nodejs 24</option>
                </select>
                <p class="text-neutral-300 text-sm mt-2">This is an advanced feature allowing you to select a Docker image to use when running this server instance.</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    `;
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(renderHtml('Startup Settings', startupHtml, 'startup'));
    return;
  }

  // Route: /server/:id/domains
  if (url.includes('/domains')) {
    const isErrorServer = url.includes('error-srv');
    const domainsHtml = `
      <div id="np-domains-view-mount" style="width: 100%; min-height: 400px; padding: 24px 0; box-sizing: border-box;"></div>
    `;
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(renderHtml('Domain Manager', domainsHtml, 'domains'));
    return;
  }

  // Default Console page
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(renderHtml('Console', '<div class="ServerConsoleContainer"><p>Console Ready</p></div>', 'console'));
});

if (require.main === module) {
  server.listen(PORT, '127.0.0.1', () => {
    console.log(`Mock Pterodactyl UI server listening on http://127.0.0.1:${PORT}`);
  });
}

module.exports = { server, PORT };
