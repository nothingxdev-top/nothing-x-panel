const { JSDOM, VirtualConsole } = require('jsdom');
const fs = require('fs');
const path = require('path');
const assert = require('assert');

async function runTest() {
  const scriptContent = fs.readFileSync(path.resolve(__dirname, '../../assets/np-theme.js'), 'utf-8');

  const consoleErrors = [];
  const virtualConsole = new VirtualConsole();
  virtualConsole.on('error', (err) => {
    consoleErrors.push(err);
  });

  const dom = new JSDOM(
    `<!DOCTYPE html>
    <html>
      <head>
        <meta name="csrf-token" content="mock-token-xyz">
      </head>
      <body>
        <div id="app">
          <div class="SubNavigation">
            <nav>
              <a href="/server/abc12345/console">Console</a>
              <a href="/server/abc12345/domains" class="active">Domains</a>
            </nav>
          </div>
          <div id="main-content">
            <div id="np-domains-view-mount"></div>
          </div>
        </div>
      </body>
    </html>`,
    {
      url: 'https://panel.example.com/server/abc12345/domains',
      runScripts: 'dangerously',
      virtualConsole,
    }
  );

  const { window } = dom;

  // Mock fetch for /api/server/abc12345/domains
  window.fetch = async (url) => {
    if (url.includes('/api/server/abc12345/domains')) {
      return {
        ok: true,
        status: 200,
        json: async () => ({
          success: true,
          server_id: 'abc12345',
          allocations: [
            { id: 1, port: 25565, is_default: true },
            { id: 2, port: 25566, is_default: false },
          ],
          domains: [
            { type: 'nginx', domain: 'sub.example.com', port: 25565, ssl: true },
            { type: 'cloudflared', domain: 'tunnel-demo.trycloudflare.com', port: 25566, ssl: true, active: true },
          ],
          cloudflared_installed: true,
        }),
      };
    }
    return { ok: false, status: 404, json: async () => ({ error: 'Not found' }) };
  };

  // Execute the theme script in the jsdom window
  const scriptEl = window.document.createElement('script');
  scriptEl.textContent = scriptContent;
  window.document.head.appendChild(scriptEl);

  // Wait for async execution and fetch resolution
  await new Promise((r) => setTimeout(r, 300));

  // 1. Assert #np-domain-manager-card renders
  const card = window.document.getElementById('np-domain-manager-card');
  assert.ok(card, '#np-domain-manager-card should be rendered in the DOM');

  // 2. Assert the port select has options
  const portSelect = window.document.getElementById('np-port-select');
  assert.ok(portSelect, '#np-port-select should exist');
  assert.ok(portSelect.options.length >= 2, 'portSelect should have options');
  assert.strictEqual(portSelect.options[0].value, '25565');

  // 3. Assert the list shows mapped domains and tunnels
  const domainList = window.document.getElementById('np-domains-list');
  assert.ok(domainList, '#np-domains-list should exist');
  assert.ok(domainList.textContent.includes('sub.example.com'), 'Mapped domain sub.example.com must be in list');
  assert.ok(domainList.textContent.includes('tunnel-demo.trycloudflare.com'), 'Cloudflare tunnel must be in list');
  assert.ok(domainList.textContent.includes('TUNNEL ACTIVE'), 'Active badge must be rendered for tunnel');

  // 4. Assert Cloudflare Tunnel tab UI requirements
  // A) Domain Name input must NOT exist in the Cloudflare tab
  const cfDomainInput = window.document.getElementById('np-cf-domain-input');
  assert.strictEqual(cfDomainInput, null, '#np-cf-domain-input should be removed');

  // B) Tunnel Token input exists, is type=password, has show/hide toggle
  const cfTokenInput = window.document.getElementById('np-cf-token-input');
  assert.ok(cfTokenInput, '#np-cf-token-input should exist');
  assert.strictEqual(cfTokenInput.type, 'password', '#np-cf-token-input should have type="password"');

  const cfTokenToggle = window.document.getElementById('np-cf-token-toggle');
  assert.ok(cfTokenToggle, '#np-cf-token-toggle show/hide button should exist');

  // C) Launch button should initially be disabled until token is entered
  const launchBtn = window.document.getElementById('np-btn-launch-cf');
  assert.ok(launchBtn, '#np-btn-launch-cf should exist');
  assert.strictEqual(launchBtn.disabled, true, 'Launch button must be disabled when token is empty');

  // D) Helper text must exist under the controls
  const helperText = window.document.getElementById('np-cf-helper-text');
  assert.ok(helperText, '#np-cf-helper-text should exist');
  assert.ok(helperText.textContent.includes('http://localhost:'), 'Helper text must contain http://localhost:<port>');

  // 5. Assert zero console errors
  assert.strictEqual(consoleErrors.length, 0, `Expected 0 console errors, got: ${JSON.stringify(consoleErrors)}`);

  console.log('✔ jsdom domains.test.js passed with 0 console errors!');
  process.exit(0);
}

runTest().catch((err) => {
  console.error('✖ Test failed:', err);
  process.exit(1);
});
