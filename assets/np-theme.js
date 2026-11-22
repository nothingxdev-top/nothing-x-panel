window.NP_VPS_IP = '" + server_ip + "';
        // Intercept API responses to replace domain alias with VPS IP in React internal store
        (function() {
            const origFetch = window.fetch;
            if (!origFetch) return;
            window.fetch = async function(...args) {
                const response = await origFetch.apply(this, args);
                try {
                    const url = typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url ? args[0].url : '');
                    if (url.includes('/api/client') || url.includes('/api/server')) {
                        const clone = response.clone();
                        const data = await clone.json();
                        const vpsIp = window.NP_VPS_IP || '213.136.89.90';
                        let modified = false;

                        function fixAlloc(obj) {
                            if (!obj || typeof obj !== 'object') return;
                            if (Array.isArray(obj)) {
                                obj.forEach(fixAlloc);
                                return;
                            }
                            if (typeof obj.alias === 'string' && (obj.alias.includes('panel.') || obj.alias.includes('.nx.kg') || obj.alias.includes('.top') || obj.alias.includes('.com') || obj.alias.includes('.net') || obj.alias === '0.0.0.0')) {
                                obj.alias = vpsIp;
                                modified = true;
                            }
                            if (typeof obj.ip_alias === 'string' && (obj.ip_alias.includes('panel.') || obj.ip_alias.includes('.nx.kg') || obj.ip_alias.includes('.top') || obj.ip_alias.includes('.com') || obj.ip_alias.includes('.net') || obj.ip_alias === '0.0.0.0')) {
                                obj.ip_alias = vpsIp;
                                modified = true;
                            }
                            if (typeof obj.ip === 'string' && (obj.ip.includes('panel.') || obj.ip.includes('.nx.kg') || obj.ip.includes('.top') || obj.ip.includes('.com') || obj.ip.includes('.net') || obj.ip === '0.0.0.0' || obj.ip === 'localhost' || obj.ip === '127.0.0.1')) {
                                obj.ip = vpsIp;
                                modified = true;
                            }
                            for (const k in obj) {
                                if (obj[k] && typeof obj[k] === 'object') {
                                    fixAlloc(obj[k]);
                                }
                            }
                        }

                        fixAlloc(data);

                        if (modified) {
                            return new Response(JSON.stringify(data), {
                                status: response.status,
                                statusText: response.statusText,
                                headers: response.headers
                            });
                        }
                    }
                } catch(e) {}
                return response;
            };
        })();
        // Clean daemon console output in real-time over WebSocket
        (function() {
            const OrigWebSocket = window.WebSocket;
            if (!OrigWebSocket) return;
            window.WebSocket = function(url, protocols) {
                const ws = protocols !== undefined ? new OrigWebSocket(url, protocols) : new OrigWebSocket(url);

                function cleanData(data) {
                    if (typeof data === 'string' && (data.includes('pterodactyl') || data.includes('Pterodactyl'))) {
                        return data
                            .replace(/container@pterodactyl~/g, 'container@nothing~')
                            .replace(/container@pterodactyl/g, 'container@nothing')
                            .replace(/\[Pterodactyl Daemon\]:/g, '[Nothing Daemon]:')
                            .replace(/Pterodactyl Daemon/g, 'Nothing Daemon')
                            .replace(/pterodactyl/g, 'nothing')
                            .replace(/Pterodactyl/g, 'Nothing');
                    }
                    return data;
                }

                const origAddEventListener = ws.addEventListener;
                ws.addEventListener = function(type, listener, options) {
                    if (type === 'message') {
                        const wrapped = function(event) {
                            let ev = event;
                            if (typeof event.data === 'string' && (event.data.includes('pterodactyl') || event.data.includes('Pterodactyl'))) {
                                try {
                                    ev = new MessageEvent('message', {
                                        data: cleanData(event.data),
                                        origin: event.origin,
                                        lastEventId: event.lastEventId,
                                        source: event.source,
                                        ports: event.ports
                                    });
                                } catch (err) {
                                    try {
                                        Object.defineProperty(event, 'data', { value: cleanData(event.data) });
                                    } catch (e) {}
                                }
                            }
                            return listener.call(this, ev);
                        };
                        return origAddEventListener.call(this, type, wrapped, options);
                    }
                    return origAddEventListener.call(this, type, listener, options);
                };

                let userOnMessage = null;
                Object.defineProperty(ws, 'onmessage', {
                    get() { return userOnMessage; },
                    set(handler) {
                        userOnMessage = handler;
                        if (!handler) {
                            return;
                        }
                        this._np_wrapped_onmessage = function(event) {
                            let ev = event;
                            if (typeof event.data === 'string' && (event.data.includes('pterodactyl') || event.data.includes('Pterodactyl'))) {
                                try {
                                    ev = new MessageEvent('message', {
                                        data: cleanData(event.data),
                                        origin: event.origin,
                                        lastEventId: event.lastEventId,
                                        source: event.source,
                                        ports: event.ports
                                    });
                                } catch (err) {
                                    try {
                                        Object.defineProperty(event, 'data', { value: cleanData(event.data) });
                                    } catch (e) {}
                                }
                            }
                            return handler.call(this, ev);
                        };
                        origAddEventListener.call(this, 'message', this._np_wrapped_onmessage);
                    }
                });

                return ws;
            };
            window.WebSocket.prototype = OrigWebSocket.prototype;
            window.WebSocket.CONNECTING = OrigWebSocket.CONNECTING;
            window.WebSocket.OPEN = OrigWebSocket.OPEN;
            window.WebSocket.CLOSING = OrigWebSocket.CLOSING;
            window.WebSocket.CLOSED = OrigWebSocket.CLOSED;
        })();

        (function() {
            let activeMode = 'nginx'; // 'nginx' or 'cloudflared'

            let _domainMountObserver = null;
            let _domainMountTimeout = null;

            function injectDomainManager() {
                const path = window.location.pathname || '';
                const match = path.match(/^\/server\/([a-zA-Z0-9]+)\/domains/);
                const existingCard = document.getElementById('np-domain-manager-card');

                if (!match) {
                    if (_domainMountObserver) {
                        _domainMountObserver.disconnect();
                        _domainMountObserver = null;
                    }
                    if (_domainMountTimeout) {
                        clearTimeout(_domainMountTimeout);
                        _domainMountTimeout = null;
                    }
                    if (existingCard) existingCard.remove();
                    const fb = document.getElementById('np-domains-fallback-mount');
                    if (fb) fb.remove();
                    return;
                }

                const serverId = match[1];

                // If card already mounted for this server and is in the DOM, keep it
                if (existingCard && existingCard.getAttribute('data-server-id') === serverId && document.body.contains(existingCard)) {
                    return;
                }

                function tryMount() {
                    let mount = document.getElementById('np-domains-view-mount');
                    if (!mount) {
                        const domainsLink = document.querySelector('a[href*="/domains"]');
                        const subNav = domainsLink ? (domainsLink.closest('div.bg-neutral-900, div[class*="SubNavigation"], div.flex.overflow-x-auto, nav') || (domainsLink.parentElement ? domainsLink.parentElement.parentElement : null)) : null;
                        if (subNav && subNav.parentElement) {
                            let fb = document.getElementById('np-domains-fallback-mount');
                            if (!fb) {
                                fb = document.createElement('div');
                                fb.id = 'np-domains-fallback-mount';
                                fb.style.cssText = 'position: relative !important; width: 100% !important; max-width: 1200px !important; margin: 1.5rem auto 3rem auto !important; padding: 0 1rem !important; box-sizing: border-box !important; display: block !important; clear: both !important; z-index: 100 !important;';
                            }
                            if (fb.parentElement !== subNav.parentElement) {
                                subNav.insertAdjacentElement('afterend', fb);
                            }
                            mount = fb;
                        }
                    }

                    if (!mount) {
                        return false;
                    }

                    if (mount.id === 'np-domains-view-mount') {
                        const fb = document.getElementById('np-domains-fallback-mount');
                        if (fb) fb.remove();
                    }

                    mountDomainCard(mount, serverId);
                    return true;
                }

                if (tryMount()) {
                    if (_domainMountObserver) {
                        _domainMountObserver.disconnect();
                        _domainMountObserver = null;
                    }
                    if (_domainMountTimeout) {
                        clearTimeout(_domainMountTimeout);
                        _domainMountTimeout = null;
                    }
                    return;
                }

                // If not mounted yet, observe DOM for mount point
                if (!_domainMountObserver) {
                    const target = document.getElementById('app') || document.body;
                    _domainMountObserver = new MutationObserver(() => {
                        if (tryMount()) {
                            _domainMountObserver.disconnect();
                            _domainMountObserver = null;
                            if (_domainMountTimeout) {
                                clearTimeout(_domainMountTimeout);
                                _domainMountTimeout = null;
                            }
                        }
                    });
                    _domainMountObserver.observe(target, { childList: true, subtree: true });
                }

                // Timeout fallback after 500ms
                if (!_domainMountTimeout) {
                    _domainMountTimeout = setTimeout(() => {
                        _domainMountTimeout = null;
                        if (_domainMountObserver) {
                            _domainMountObserver.disconnect();
                            _domainMountObserver = null;
                        }
                        const app = document.getElementById('app') || document.body;
                        let fb = document.getElementById('np-domains-fallback-mount');
                        if (!fb) {
                            fb = document.createElement('div');
                            fb.id = 'np-domains-fallback-mount';
                            fb.style.cssText = 'position: relative !important; width: 100% !important; max-width: 1200px !important; margin: 1.5rem auto 3rem auto !important; padding: 0 1rem !important; box-sizing: border-box !important; display: block !important; clear: both !important; z-index: 100 !important;';
                            app.appendChild(fb);
                        }
                        mountDomainCard(fb, serverId);
                    }, 500);
                }
            }

            function mountDomainCard(mount, serverId) {
                // Ensure mount is visible
                mount.style.display = 'block';

                let existing = document.getElementById('np-domain-manager-card');
                if (existing && mount.contains(existing) && existing.getAttribute('data-server-id') === serverId) {
                    return;
                }
                if (existing) {
                    existing.remove();
                }

                const card = document.createElement('div');
                card.id = 'np-domain-manager-card';
                card.setAttribute('data-server-id', serverId);
                card.style.cssText = 'width: 100% !important; background: #110d22 !important; border: 1.5px solid rgba(194, 104, 242, 0.35) !important; border-radius: 14px !important; padding: 1.75rem !important; box-shadow: 0 10px 35px rgba(0, 0, 0, 0.6), 0 0 20px rgba(194, 104, 242, 0.15) !important; box-sizing: border-box !important; display: block !important;';

                // Header
                const header = document.createElement('div');
                header.style.cssText = 'display:flex; justify-content:space-between; align-items:center; border-bottom:1px solid rgba(194,104,242,0.15); padding-bottom:0.85rem; margin-bottom:1.25rem;';
                
                const headerLeft = document.createElement('div');
                headerLeft.style.cssText = 'display:flex; align-items:center; gap:10px;';
                headerLeft.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:middle;"><circle cx="12" cy="12" r="10"></circle><line x1="2" y1="12" x2="22" y2="12"></line><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"></path></svg>';
                
                const title = document.createElement('h3');
                title.style.cssText = 'margin:0; font-size:1.15rem; font-weight:800; color:#ffffff; letter-spacing:0.5px;';
                title.textContent = 'CUSTOM DOMAINS & PORT ROUTING';
                headerLeft.appendChild(title);

                const badge = document.createElement('span');
                badge.style.cssText = 'background:rgba(194,104,242,0.18); color:#C268F2; font-size:0.72rem; font-weight:800; padding:3px 10px; border-radius:20px; border:1px solid rgba(194,104,242,0.35); text-transform:uppercase; letter-spacing:0.5px;';
                badge.textContent = 'INSTANT ROUTER';
                headerLeft.appendChild(badge);
                header.appendChild(headerLeft);
                card.appendChild(header);

                // Mode Tabs
                const tabWrap = document.createElement('div');
                tabWrap.style.cssText = 'display:flex; gap:10px; margin-bottom:1.25rem;';

                const tabNginx = document.createElement('button');
                tabNginx.id = 'np-tab-nginx';
                tabNginx.type = 'button';
                tabNginx.style.cssText = 'padding:8px 18px; border-radius:8px; font-size:0.82rem; font-weight:700; cursor:pointer; background:linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%); color:#fff; border:none; box-shadow:0 2px 10px rgba(194,104,242,0.4); display:inline-flex; align-items:center; gap:7px;';
                tabNginx.textContent = 'CUSTOM DOMAIN (NGINX & SSL)';

                const tabCf = document.createElement('button');
                tabCf.id = 'np-tab-cf';
                tabCf.type = 'button';
                tabCf.style.cssText = 'padding:8px 18px; border-radius:8px; font-size:0.82rem; font-weight:700; cursor:pointer; background:#1b1531; color:#c7b4e2; border:1px solid rgba(194,104,242,0.25); display:inline-flex; align-items:center; gap:7px;';
                tabCf.textContent = 'CLOUDFLARE TUNNEL (NAT VPS / IPV6)';

                tabWrap.appendChild(tabNginx);
                tabWrap.appendChild(tabCf);
                card.appendChild(tabWrap);

                // Form Nginx
                const formNginx = document.createElement('div');
                formNginx.id = 'np-form-nginx';
                formNginx.style.cssText = 'display:flex; flex-wrap:wrap; gap:14px; align-items:flex-end; margin-bottom:1.5rem;';
                formNginx.innerHTML = `
                    <div style="flex:2; min-width:220px;">
                        <label style="display:block; font-size:0.75rem; font-weight:700; color:#d1b8eb; text-transform:uppercase; margin-bottom:6px;">Custom Domain</label>
                        <input type="text" id="np-domain-input" placeholder="e.g. play.yourdomain.com" style="width:100%; height:42px; box-sizing:border-box; background:#0b0818; border:1px solid rgba(194,104,242,0.3); color:#fff; border-radius:8px; padding:0 14px; font-size:0.9rem; outline:none;" />
                    </div>
                    <div style="flex:1; min-width:140px;">
                        <label style="display:block; font-size:0.75rem; font-weight:700; color:#d1b8eb; text-transform:uppercase; margin-bottom:6px;">Target Port</label>
                        <select id="np-port-select" style="width:100%; height:42px; box-sizing:border-box; background:#0b0818; border:1px solid rgba(194,104,242,0.3); color:#fff; border-radius:8px; padding:0 36px 0 14px; font-size:0.9rem; outline:none; cursor:pointer;">
                            <option value="">Loading ports...</option>
                        </select>
                    </div>
                    <div style="display:flex; align-items:center; gap:8px; height:42px; padding:0 4px;">
                        <input type="checkbox" id="np-ssl-toggle" checked style="cursor:pointer; accent-color:#C268F2; width:16px; height:16px; margin:0;" />
                        <label for="np-ssl-toggle" style="font-size:0.82rem; color:#d1b8eb; cursor:pointer; font-weight:600; margin:0; text-transform:none;">Auto-SSL</label>
                    </div>
                    <div>
                        <button id="np-btn-add-domain" type="button" style="height:42px; background:linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%); color:#fff; font-weight:700; font-size:0.85rem; padding:0 24px; border-radius:8px; border:none; cursor:pointer; box-shadow:0 4px 15px rgba(194,104,242,0.4); text-transform:uppercase; letter-spacing:0.5px; display:inline-flex; align-items:center;">+ Connect Domain</button>
                    </div>
                `;
                card.appendChild(formNginx);

                // Form Cloudflare
                const formCf = document.createElement('div');
                formCf.id = 'np-form-cf';
                formCf.style.cssText = 'display:none; flex-wrap:wrap; gap:14px; align-items:flex-end; margin-bottom:1.5rem;';
                formCf.innerHTML = `
                    <div style="flex:2; min-width:200px;">
                        <label style="display:block; font-size:0.75rem; font-weight:700; color:#d1b8eb; text-transform:uppercase; margin-bottom:6px;">Domain Name</label>
                        <input type="text" id="np-cf-domain-input" placeholder="e.g. play.yourdomain.com (optional)" style="width:100%; height:42px; box-sizing:border-box; background:#0b0818; border:1px solid rgba(194,104,242,0.3); color:#fff; border-radius:8px; padding:0 14px; font-size:0.9rem; outline:none;" />
                    </div>
                    <div style="flex:2; min-width:200px;">
                        <label style="display:block; font-size:0.75rem; font-weight:700; color:#d1b8eb; text-transform:uppercase; margin-bottom:6px;">Cloudflare Tunnel Token</label>
                        <input type="text" id="np-cf-token-input" placeholder="Tunnel token (leave empty for Quick Tunnel)" style="width:100%; height:42px; box-sizing:border-box; background:#0b0818; border:1px solid rgba(194,104,242,0.3); color:#fff; border-radius:8px; padding:0 14px; font-size:0.9rem; outline:none;" />
                    </div>
                    <div style="flex:1; min-width:140px;">
                        <label style="display:block; font-size:0.75rem; font-weight:700; color:#d1b8eb; text-transform:uppercase; margin-bottom:6px;">Target Port</label>
                        <select id="np-cf-port-select" style="width:100%; height:42px; box-sizing:border-box; background:#0b0818; border:1px solid rgba(194,104,242,0.3); color:#fff; border-radius:8px; padding:0 36px 0 14px; font-size:0.9rem; outline:none; cursor:pointer;">
                            <option value="">Loading ports...</option>
                        </select>
                    </div>
                    <div>
                        <button id="np-btn-launch-cf" type="button" style="height:42px; background:linear-gradient(135deg, #06b6d4 0%, #3b82f6 100%); color:#fff; font-weight:700; font-size:0.85rem; padding:0 24px; border-radius:8px; border:none; cursor:pointer; box-shadow:0 4px 15px rgba(6,182,212,0.4); text-transform:uppercase; letter-spacing:0.5px; display:inline-flex; align-items:center;">
                            Launch Cloudflare Tunnel
                        </button>
                    </div>
                `;
                card.appendChild(formCf);

                // Message box
                const msgBox = document.createElement('div');
                msgBox.id = 'np-domain-msg';
                msgBox.style.cssText = 'display:none; margin-bottom:1rem; padding:10px 14px; border-radius:8px; font-size:0.85rem; font-weight:600;';
                card.appendChild(msgBox);

                // Active List Section
                const listSection = document.createElement('div');
                const listHeader = document.createElement('h4');
                listHeader.style.cssText = 'margin:0 0 10px 0; font-size:0.8rem; font-weight:700; color:#8e79b0; text-transform:uppercase; letter-spacing:0.8px;';
                listHeader.textContent = 'Active Domains & Tunnels';
                listSection.appendChild(listHeader);

                const listContainer = document.createElement('div');
                listContainer.id = 'np-domains-list';
                listSection.appendChild(listContainer);
                card.appendChild(listSection);

                mount.appendChild(card);

                // Tab Switch Handlers
                tabNginx.onclick = function() {
                    formNginx.style.display = 'flex';
                    formCf.style.display = 'none';
                    tabNginx.style.background = 'linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%)';
                    tabNginx.style.color = '#fff';
                    tabCf.style.background = '#1b1531';
                    tabCf.style.color = '#c7b4e2';
                };
                tabCf.onclick = function() {
                    formNginx.style.display = 'none';
                    formCf.style.display = 'flex';
                    tabCf.style.background = 'linear-gradient(135deg, #06b6d4 0%, #3b82f6 100%)';
                    tabCf.style.color = '#fff';
                    tabNginx.style.background = '#1b1531';
                    tabNginx.style.color = '#c7b4e2';
                };

                const btnAdd = document.getElementById('np-btn-add-domain');
                if (btnAdd) {
                    btnAdd.addEventListener('click', function() {
                        addServerDomain(serverId, 'nginx');
                    });
                }
                const btnLaunchCf = document.getElementById('np-btn-launch-cf');
                if (btnLaunchCf) {
                    btnLaunchCf.addEventListener('click', function() {
                        addServerDomain(serverId, 'cloudflared');
                    });
                }

                loadServerDomains(serverId);
            }

            function getCsrfToken() {
                const el = document.querySelector('meta[name="csrf-token"]');
                return el ? el.getAttribute('content') : '';
            }

            function showMsg(text, isError) {
                const msg = document.getElementById('np-domain-msg');
                if (!msg) return;
                msg.style.display = 'block';
                msg.style.background = isError ? 'rgba(239, 68, 68, 0.2)' : 'rgba(16, 185, 129, 0.2)';
                msg.style.border = isError ? '1px solid #ef4444' : '1px solid #10b981';
                msg.style.color = isError ? '#fca5a5' : '#a7f3d0';
                msg.textContent = text;
                setTimeout(() => { if (msg) msg.style.display = 'none'; }, 7000);
            }

            function loadServerDomains(serverId) {
                const list = document.getElementById('np-domains-list');
                if (list) {
                    list.replaceChildren();
                    const loadingBox = document.createElement('div');
                    loadingBox.style.cssText = 'color:#a794c2; font-size:0.88rem; font-style:italic; padding:16px 0; display:flex; align-items:center; gap:10px;';
                    loadingBox.innerHTML = '<span style="display:inline-block; width:16px; height:16px; border:2px solid rgba(194,104,242,0.3); border-top-color:#C268F2; border-radius:50%; animation:spin 0.8s linear infinite;"></span><span>Loading domains &amp; tunnels...</span>';
                    list.appendChild(loadingBox);
                }

                console.log('[Nothing Panel] Fetching domains for server: ' + serverId);
                fetch('/api/server/' + encodeURIComponent(serverId) + '/domains', {
                    headers: { 'Accept': 'application/json' }
                })
                .then(async response => {
                    console.log('[Nothing Panel] Domains API response status: ' + response.status);
                    if (!response.ok) {
                        let errDetail = 'HTTP ' + response.status;
                        try {
                            const errJson = await response.json();
                            if (errJson && errJson.error) errDetail += ' - ' + errJson.error;
                        } catch (_) {}
                        throw new Error(errDetail);
                    }
                    return response.json();
                })
                .then(data => {
                    if (!data.success) {
                        throw new Error(data.error || 'Request unsuccessful');
                    }

                    const portSelect = document.getElementById('np-port-select');
                    const cfPortSelect = document.getElementById('np-cf-port-select');
                    if (data.allocations && data.allocations.length > 0) {
                        [portSelect, cfPortSelect].forEach(sel => {
                            if (!sel) return;
                            sel.replaceChildren();
                            data.allocations.forEach(a => {
                                const opt = document.createElement('option');
                                opt.value = String(a.port);
                                opt.textContent = 'Port ' + a.port + (a.is_default ? ' (Primary)' : '');
                                sel.appendChild(opt);
                            });
                            sel.selectedIndex = 0;
                            sel.removeAttribute('data-np-select');
                            const prevWrap = sel.nextElementSibling;
                            if (prevWrap && prevWrap.classList.contains('np-custom-select-wrap')) {
                                prevWrap.remove();
                            }
                            sel.dispatchEvent(new Event('change', { bubbles: true }));
                            sel.dispatchEvent(new Event('input', { bubbles: true }));
                        });
                        initCustomSelects();
                    }

                    const list = document.getElementById('np-domains-list');
                    if (!list) return;
                    list.replaceChildren();

                    if (!data.domains || data.domains.length === 0) {
                        const emptyBox = document.createElement('div');
                        emptyBox.style.cssText = 'color:#8e79b0; font-size:0.88rem; font-style:italic; padding:14px 0;';
                        emptyBox.textContent = 'No active domains or tunnels. Use the controls above to connect your server.';
                        list.appendChild(emptyBox);
                        return;
                    }

                    data.domains.forEach(d => {
                        const row = document.createElement('div');
                        row.style.cssText = 'display:flex; justify-content:space-between; align-items:center; border-bottom:1px solid rgba(194,104,242,0.12); padding:10px 0;';

                        const left = document.createElement('div');
                        left.style.cssText = 'display:flex; align-items:center; gap:12px; flex-wrap:wrap;';

                        const link = document.createElement('a');
                        link.href = 'https://' + encodeURIComponent(d.domain);
                        link.target = '_blank';
                        link.rel = 'noopener noreferrer';
                        link.style.cssText = 'font-weight:700; color:#ffffff; text-decoration:none; font-size:0.95rem; display:inline-flex; align-items:center; gap:6px;';
                        link.textContent = String(d.domain);

                        const portBadge = document.createElement('span');
                        portBadge.style.cssText = 'color:#a895c2; font-size:0.82rem;';
                        portBadge.textContent = 'Port ' + String(d.port);

                        const typeBadge = document.createElement('span');
                        typeBadge.style.cssText = 'display:inline-flex; align-items:center; gap:5px; font-size:0.7rem; font-weight:700; padding:2px 8px; border-radius:6px;';
                        if (d.type === 'cloudflared') {
                            typeBadge.style.background = 'rgba(6,182,212,0.18)';
                            typeBadge.style.color = '#06b6d4';
                            typeBadge.textContent = 'CLOUDFLARE TUNNEL';
                        } else {
                            typeBadge.style.background = 'rgba(16,185,129,0.18)';
                            typeBadge.style.color = '#10b981';
                            typeBadge.textContent = 'CONNECTED';
                        }

                        left.appendChild(link);
                        left.appendChild(portBadge);
                        left.appendChild(typeBadge);

                        if (d.ssl) {
                            const sslBadge = document.createElement('span');
                            sslBadge.style.cssText = 'display:inline-flex; align-items:center; gap:5px; background:rgba(194,104,242,0.18); color:#C268F2; font-size:0.7rem; font-weight:700; padding:2px 8px; border-radius:6px;';
                            sslBadge.textContent = 'SSL SECURED';
                            left.appendChild(sslBadge);
                        }

                        const delBtn = document.createElement('button');
                        delBtn.type = 'button';
                        delBtn.style.cssText = 'background:transparent; border:1px solid #ef4444; color:#ef4444; font-size:0.75rem; font-weight:700; padding:4px 10px; border-radius:6px; cursor:pointer; text-transform:uppercase;';
                        delBtn.textContent = 'Disconnect';
                        delBtn.addEventListener('click', () => {
                            window.npRemoveDomain(serverId, d.port);
                        });

                        row.appendChild(left);
                        row.appendChild(delBtn);
                        list.appendChild(row);
                    });
                })
                .catch(e => {
                    console.error('[Nothing Panel] Error loading domains:', e);
                    const list = document.getElementById('np-domains-list');
                    if (list) {
                        list.replaceChildren();
                        const errBox = document.createElement('div');
                        errBox.style.cssText = 'background:rgba(239, 68, 68, 0.15); border:1px solid #ef4444; color:#fca5a5; padding:12px 16px; border-radius:8px; font-size:0.85rem; font-weight:600;';
                        errBox.textContent = 'Unable to load domains (' + e.message + '). Verify backend route and permissions.';
                        list.appendChild(errBox);
                    }
                });
            }

            const RFC1035_DOMAIN_REGEX = /^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/;

            function addServerDomain(serverId, mode) {
                const portSelect = document.getElementById(mode === 'cloudflared' ? 'np-cf-port-select' : 'np-port-select');
                const port = portSelect ? portSelect.value : '';
                
                if (!port) {
                    showMsg('Please select a target port.', true);
                    return;
                }

                let payload = { mode: mode, port: port };

                if (mode === 'nginx') {
                    const input = document.getElementById('np-domain-input');
                    const sslToggle = document.getElementById('np-ssl-toggle');
                    const domain = input ? input.value.trim() : '';
                    if (!domain || !RFC1035_DOMAIN_REGEX.test(domain)) {
                        showMsg('Please enter a valid domain name (e.g. play.yourdomain.com).', true);
                        return;
                    }
                    payload.domain = domain;
                    payload.ssl = sslToggle ? sslToggle.checked : true;

                    const btn = document.getElementById('np-btn-add-domain');
                    if (btn) {
                        btn.disabled = true;
                        btn.textContent = 'Configuring Nginx...';
                    }
                } else {
                    const cfDomainInput = document.getElementById('np-cf-domain-input');
                    const tokenInput = document.getElementById('np-cf-token-input');
                    const cfDomain = cfDomainInput ? cfDomainInput.value.trim() : '';
                    if (cfDomain && !RFC1035_DOMAIN_REGEX.test(cfDomain)) {
                        showMsg('Please enter a valid domain name (e.g. play.yourdomain.com).', true);
                        return;
                    }
                    payload.domain = cfDomain;
                    payload.cf_token = tokenInput ? tokenInput.value.trim() : '';

                    const btn = document.getElementById('np-btn-launch-cf');
                    if (btn) {
                        btn.disabled = true;
                        btn.textContent = 'Starting Tunnel...';
                    }
                }
                
                fetch('/api/server/' + encodeURIComponent(serverId) + '/domains', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Accept': 'application/json',
                        'X-CSRF-TOKEN': getCsrfToken()
                    },
                    body: JSON.stringify(payload)
                })
                .then(r => r.json())
                .then(res => {
                    const btn1 = document.getElementById('np-btn-add-domain');
                    const btn2 = document.getElementById('np-btn-launch-cf');
                    if (btn1) { btn1.disabled = false; btn1.textContent = '+ Connect Domain'; }
                    if (btn2) { btn2.disabled = false; btn2.textContent = 'Launch Cloudflare Tunnel'; }

                    if (res.success) {
                        showMsg(res.message, false);
                        const inp = document.getElementById('np-domain-input');
                        if (inp) inp.value = '';
                        loadServerDomains(serverId);
                    } else {
                        showMsg(res.error || 'Operation failed', true);
                    }
                })
                .catch(err => {
                    const btn1 = document.getElementById('np-btn-add-domain');
                    const btn2 = document.getElementById('np-btn-launch-cf');
                    if (btn1) { btn1.disabled = false; btn1.textContent = '+ Connect Domain'; }
                    if (btn2) { btn2.disabled = false; btn2.textContent = 'Launch Cloudflare Tunnel'; }
                    showMsg('Error: ' + err.message, true);
                });
            }

            window.npRemoveDomain = function(serverId, port) {
                if (!confirm('Are you sure you want to disconnect port ' + port + '?')) return;
                
                fetch('/api/server/' + encodeURIComponent(serverId) + '/domains/delete', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Accept': 'application/json',
                        'X-CSRF-TOKEN': getCsrfToken()
                    },
                    body: JSON.stringify({ port: port })
                })
                .then(r => r.json())
                .then(res => {
                    if (res.success) {
                        showMsg(res.message, false);
                        loadServerDomains(serverId);
                    } else {
                        showMsg(res.error || 'Failed to remove domain/tunnel', true);
                    }
                })
                .catch(err => showMsg('Error: ' + err.message, true));
            };

                        // Real-time DOM text sanitizer (Guarantees zero Pterodactyl visibility anywhere)
            function sanitizePterodactylText(node) {
                if (!node) return;
                if (node.nodeType === 3) { // TEXT_NODE
                    var val = node.nodeValue;
                    if (val && (val.indexOf('pterodactyl') !== -1 || val.indexOf('Pterodactyl') !== -1)) {
                        node.nodeValue = val
                            .replace(/Configure Pterodactyl to your liking\.?/gi, 'Configure Nothing Panel to your liking.')
                            .replace(/Configure advanced settings for Pterodactyl\.?/gi, 'Configure advanced settings for Nothing Panel.')
                            .replace(/Configure how Pterodactyl should handle sending emails\.?/gi, 'Configure how Nothing Panel should handle sending emails.')
                            .replace(/All nodes currently configured on the Pterodactyl Panel\.?/gi, 'All nodes currently configured on Nothing Panel.')
                            .replace(/All servers currently configured on the Pterodactyl Panel\.?/gi, 'All servers currently configured on Nothing Panel.')
                            .replace(/Pterodactyl Software/gi, 'Nothing Panel')
                            .replace(/Pterodactyl Panel/gi, 'Nothing Panel')
                            .replace(/Pterodactyl Wings/gi, 'Nothing Wings')
                            .replace(/container@pterodactyl~/g, 'container@nothing~')
                            .replace(/container@pterodactyl/g, 'container@nothing')
                            .replace(/\[Pterodactyl Daemon\]:/g, '[Nothing Daemon]:')
                            .replace(/Pterodactyl Daemon/g, 'Nothing Daemon')
                            .replace(/https?:\/\/pterodactyl\.io[^\s"']*/gi, '#')
                            .replace(/pterodactyl\.io/gi, 'nothingx.top')
                            .replace(/Pterodactyl/g, 'Nothing Panel')
                            .replace(/pterodactyl/g, 'nothing');
                    }
                } else if (node.nodeType === 1) { // ELEMENT_NODE
                    ['title', 'placeholder', 'alt', 'aria-label'].forEach(function(attr) {
                        var aVal = node.getAttribute && node.getAttribute(attr);
                        if (aVal && (aVal.indexOf('pterodactyl') !== -1 || aVal.indexOf('Pterodactyl') !== -1)) {
                            node.setAttribute(attr, aVal
                                .replace(/Configure Pterodactyl to your liking\.?/gi, 'Configure Nothing Panel to your liking.')
                                .replace(/Pterodactyl Software/gi, 'Nothing Panel')
                                .replace(/Pterodactyl Panel/gi, 'Nothing Panel')
                                .replace(/Pterodactyl/g, 'Nothing Panel')
                                .replace(/pterodactyl/g, 'nothing')
                            );
                        }
                    });
                    var children = node.childNodes;
                    for (var k = 0; k < children.length; k++) {
                        sanitizePterodactylText(children[k]);
                    }
                }
            }

            // ULTRA-SLEEK CUSTOM SELECT CONTROLLER
            function initCustomSelects() {
                // Cleanup orphaned custom select wraps
                document.querySelectorAll('.np-custom-select-wrap').forEach(wrap => {
                    const prev = wrap.previousElementSibling;
                    if (!prev || prev.tagName !== 'SELECT' || !document.body.contains(prev)) {
                        wrap.remove();
                    }
                });

                const selects = Array.from(document.querySelectorAll('select:not([data-np-select="true"])'));
                selects.forEach(select => {
                    if (select.classList.contains('select2-hidden-accessible')) return;

                    select.setAttribute('data-np-select', 'true');

                    // Visually hide native select but keep it accessible for form submissions & state
                    select.style.cssText = 'position: absolute !important; opacity: 0 !important; pointer-events: none !important; width: 0 !important; height: 0 !important; margin: 0 !important; padding: 0 !important; border: none !important; z-index: -1 !important;';

                    // Wrapper container
                    const container = document.createElement('div');
                    container.className = 'np-custom-select-wrap';
                    container.style.cssText = 'position: relative !important; width: 100% !important; min-width: 140px !important; box-sizing: border-box !important; font-family: inherit !important; user-select: none !important;';

                    // Trigger button
                    const trigger = document.createElement('div');
                    trigger.className = 'np-custom-select-trigger';
                    trigger.style.cssText = 'width: 100% !important; min-height: 40px !important; background: #0b0717 !important; border: 1.5px solid rgba(194, 104, 242, 0.45) !important; border-radius: 8px !important; color: #ffffff !important; padding: 8px 38px 8px 14px !important; font-size: 0.92rem !important; font-weight: 500 !important; display: flex !important; align-items: center !important; justify-content: space-between !important; cursor: pointer !important; box-sizing: border-box !important; transition: all 0.2s ease !important;';

                    const labelSpan = document.createElement('span');
                    labelSpan.className = 'np-custom-select-label';
                    labelSpan.style.cssText = 'overflow: hidden !important; text-overflow: ellipsis !important; white-space: nowrap !important; flex: 1 !important; color: #ffffff !important;';

                    const arrowSpan = document.createElement('span');
                    arrowSpan.className = 'np-custom-select-arrow';
                    arrowSpan.style.cssText = 'position: absolute !important; right: 12px !important; top: 50% !important; transform: translateY(-50%) !important; display: flex !important; align-items: center !important; transition: transform 0.2s ease !important; pointer-events: none !important;';
                    arrowSpan.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"></polyline></svg>';

                    trigger.appendChild(labelSpan);
                    trigger.appendChild(arrowSpan);
                    container.appendChild(trigger);

                    // Dropdown menu
                    const menu = document.createElement('div');
                    menu.className = 'np-custom-select-menu';
                    menu.style.cssText = 'display: none !important; position: absolute !important; top: calc(100% + 4px) !important; left: 0 !important; width: 100% !important; max-height: 250px !important; overflow-y: auto !important; background: #120e24 !important; border: 1.5px solid #C268F2 !important; border-radius: 10px !important; box-shadow: 0 16px 45px rgba(0, 0, 0, 0.95), 0 0 25px rgba(194, 104, 242, 0.35) !important; z-index: 9999999 !important; padding: 4px !important; box-sizing: border-box !important; backdrop-filter: blur(12px) !important;';

                    function syncOptions() {
                        menu.innerHTML = '';
                        const opts = Array.from(select.options);
                        if (opts.length > 0 && select.selectedIndex < 0) {
                            select.selectedIndex = 0;
                        }
                        const selOpt = select.options[select.selectedIndex];
                        labelSpan.textContent = selOpt ? selOpt.text : (opts[0] ? opts[0].text : 'Select...');

                        opts.forEach((opt, idx) => {
                            const item = document.createElement('div');
                            const isSelected = idx === select.selectedIndex;
                            item.className = 'np-custom-select-item';
                            item.style.cssText = `padding: 10px 14px !important; margin: 2px 0 !important; border-radius: 6px !important; font-size: 0.9rem !important; cursor: pointer !important; color: ${isSelected ? '#ffffff' : '#dcc7f5'} !important; background: ${isSelected ? 'linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%)' : 'transparent'} !important; font-weight: ${isSelected ? '700' : '500'} !important; display: flex !important; align-items: center !important; justify-content: space-between !important; transition: all 0.15s ease !important;`;

                            item.innerHTML = `<span>${opt.text}</span>` + (isSelected ? '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>' : '');

                            item.onmouseenter = function() {
                                if (idx !== select.selectedIndex) {
                                    item.style.background = 'rgba(194, 104, 242, 0.22)';
                                    item.style.color = '#ffffff';
                                }
                            };
                            item.onmouseleave = function() {
                                if (idx !== select.selectedIndex) {
                                    item.style.background = 'transparent';
                                    item.style.color = '#dcc7f5';
                                }
                            };

                            item.onclick = function(e) {
                                e.stopPropagation();
                                select.selectedIndex = idx;
                                select.value = opt.value;
                                if (window.jQuery) {
                                    window.jQuery(select).val(opt.value).trigger('change');
                                }
                                select.dispatchEvent(new Event('change', { bubbles: true }));
                                select.dispatchEvent(new Event('input', { bubbles: true }));
                                closeSelect();
                                syncOptions();
                            };

                            menu.appendChild(item);
                        });
                    }

                    // Dynamically sync options if select elements or text changes
                    const optObserver = new MutationObserver(() => syncOptions());
                    optObserver.observe(select, { childList: true, subtree: true, characterData: true });

                    function openSelect() {
                        document.querySelectorAll('.np-custom-select-menu').forEach(m => m.style.display = 'none');
                        document.querySelectorAll('.np-custom-select-arrow').forEach(a => a.style.transform = 'translateY(-50%) rotate(0deg)');
                        document.querySelectorAll('.np-custom-select-trigger').forEach(t => {
                            t.style.borderColor = 'rgba(194, 104, 242, 0.45)';
                            t.style.boxShadow = 'none';
                        });

                        syncOptions();
                        menu.style.display = 'block';
                        trigger.style.borderColor = '#C268F2';
                        trigger.style.boxShadow = '0 0 16px rgba(194, 104, 242, 0.45)';
                        arrowSpan.style.transform = 'translateY(-50%) rotate(180deg)';
                    }

                    function closeSelect() {
                        menu.style.display = 'none';
                        trigger.style.borderColor = 'rgba(194, 104, 242, 0.45)';
                        trigger.style.boxShadow = 'none';
                        arrowSpan.style.transform = 'translateY(-50%) rotate(0deg)';
                    }

                    trigger.onclick = function(e) {
                        e.stopPropagation();
                        if (menu.style.display === 'block') {
                            closeSelect();
                        } else {
                            openSelect();
                        }
                    };

                    container.appendChild(menu);
                    select.parentNode.insertBefore(container, select.nextSibling);
                    syncOptions();

                    select.addEventListener('change', syncOptions);
                });
            }

            document.addEventListener('click', function() {
                document.querySelectorAll('.np-custom-select-menu').forEach(m => m.style.display = 'none');
                document.querySelectorAll('.np-custom-select-arrow').forEach(a => a.style.transform = 'translateY(-50%) rotate(0deg)');
                document.querySelectorAll('.np-custom-select-trigger').forEach(t => {
                    t.style.borderColor = 'rgba(194, 104, 242, 0.4)';
                    t.style.boxShadow = 'none';
                });
            });

            // IMAGE PREVIEW MODAL FOR FILE MANAGER (PNG, JPG, GIF, WEBP, SVG)
            function openImageModal(serverId, filePath, fileName) {
                let modal = document.getElementById('np-image-preview-modal');
                if (!modal) {
                    modal = document.createElement('div');
                    modal.id = 'np-image-preview-modal';
                    document.body.appendChild(modal);
                }

                modal.style.cssText = 'position: fixed; inset: 0; z-index: 9999999; background: rgba(5, 3, 12, 0.85); backdrop-filter: blur(12px); display: flex; align-items: center; justify-content: center; padding: 20px; box-sizing: border-box; animation: npFadeIn 0.2s ease-out;';

                modal.innerHTML = `
                    <div style="background: #110d24; border: 1.5px solid rgba(194, 104, 242, 0.45); border-radius: 16px; width: 100%; max-width: 820px; max-height: 90vh; display: flex; flex-direction: column; overflow: hidden; box-shadow: 0 25px 60px rgba(0,0,0,0.9), 0 0 35px rgba(194,104,242,0.25);">
                        <div style="display: flex; align-items: center; justify-content: space-between; padding: 14px 20px; border-bottom: 1px solid rgba(194, 104, 242, 0.18); background: #0c081c;">
                            <div style="display: flex; align-items: center; gap: 10px; overflow: hidden;">
                                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect><circle cx="8.5" cy="8.5" r="1.5"></circle><polyline points="21 15 16 10 5 21"></polyline></svg>
                                <span style="color: #ffffff; font-weight: 700; font-size: 1.05rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${fileName}</span>
                                <span id="np-img-meta" style="font-size: 0.72rem; color: #a794c2; background: rgba(194, 104, 242, 0.15); padding: 3px 8px; border-radius: 6px; border: 1px solid rgba(194, 104, 242, 0.3);">Loading...</span>
                            </div>
                            <button id="np-img-close-btn" style="background: transparent; border: none; color: #a794c2; font-size: 1.6rem; cursor: pointer; padding: 4px 8px; border-radius: 6px; display: flex; align-items: center; justify-content: center; transition: all 0.15s ease;">&times;</button>
                        </div>
                        <div style="flex: 1; min-height: 260px; max-height: calc(90vh - 140px); overflow: auto; display: flex; align-items: center; justify-content: center; padding: 24px; background: repeating-conic-gradient(#0b0717 0% 25%, #130e28 0% 50%) 50% / 20px 20px; position: relative;">
                            <div id="np-img-spinner" style="display: flex; flex-direction: column; align-items: center; gap: 12px; color: #C268F2;">
                                <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="animation: npSpin 1s linear infinite;"><line x1="12" y1="2" x2="12" y2="6"></line><line x1="12" y1="18" x2="12" y2="22"></line><line x1="4.93" y1="4.93" x2="7.76" y2="7.76"></line><line x1="16.24" y1="16.24" x2="19.07" y2="19.07"></line><line x1="2" y1="12" x2="6" y2="12"></line><line x1="18" y1="12" x2="22" y2="12"></line><line x1="4.93" y1="19.07" x2="7.76" y2="16.24"></line><line x1="16.24" y1="7.76" x2="19.07" y2="4.93"></line></svg>
                                <span style="font-size: 0.85rem; font-weight: 600;">Loading image...</span>
                            </div>
                            <img id="np-img-view" style="display: none; max-width: 100%; max-height: calc(90vh - 190px); object-fit: contain; border-radius: 6px; box-shadow: 0 10px 30px rgba(0,0,0,0.8);" alt="${fileName}" />
                        </div>
                        <div style="display: flex; align-items: center; justify-content: space-between; padding: 14px 20px; border-top: 1px solid rgba(194, 104, 242, 0.18); background: #0c081c;">
                            <span id="np-img-dims" style="color: #8b77a6; font-size: 0.82rem;"></span>
                            <div style="display: flex; gap: 10px;">
                                <a id="np-img-download-btn" href="#" download="${fileName}" target="_blank" style="display: inline-flex; align-items: center; gap: 6px; padding: 8px 16px; border-radius: 8px; font-size: 0.85rem; font-weight: 700; background: linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%); color: #ffffff; text-decoration: none; box-shadow: 0 2px 10px rgba(194,104,242,0.4);">
                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg>
                                    Download
                                </a>
                                <button id="np-img-close-action" type="button" style="padding: 8px 16px; border-radius: 8px; font-size: 0.85rem; font-weight: 700; background: #1a1430; color: #dcc7f5; border: 1px solid rgba(194, 104, 242, 0.3); cursor: pointer;">Close</button>
                            </div>
                        </div>
                    </div>
                `;

                function closeModal() {
                    modal.style.display = 'none';
                    const img = document.getElementById('np-img-view');
                    if (img) img.src = '';
                }

                document.getElementById('np-img-close-btn').onclick = closeModal;
                document.getElementById('np-img-close-action').onclick = closeModal;
                modal.onclick = function(e) {
                    if (e.target === modal) closeModal();
                };
                window.addEventListener('keydown', function escHandler(e) {
                    if (e.key === 'Escape') {
                        closeModal();
                        window.removeEventListener('keydown', escHandler);
                    }
                });

                // Request signed download URL from client API
                fetch('/api/client/servers/' + serverId + '/files/download?file=' + encodeURIComponent(filePath), {
                    headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' }
                })
                .then(r => r.json())
                .then(res => {
                    const downloadUrl = res?.attributes?.url;
                    if (!downloadUrl) throw new Error('Could not retrieve image URL from daemon');

                    const imgEl = document.getElementById('np-img-view');
                    const spinner = document.getElementById('np-img-spinner');
                    const metaEl = document.getElementById('np-img-meta');
                    const dimsEl = document.getElementById('np-img-dims');
                    const dlBtn = document.getElementById('np-img-download-btn');

                    dlBtn.href = downloadUrl;

                    imgEl.onload = function() {
                        if (spinner) spinner.style.display = 'none';
                        imgEl.style.display = 'block';
                        if (metaEl) metaEl.textContent = `${imgEl.naturalWidth} × ${imgEl.naturalHeight} px`;
                        if (dimsEl) dimsEl.textContent = `Dimensions: ${imgEl.naturalWidth} × ${imgEl.naturalHeight} pixels`;
                    };
                    imgEl.onerror = function() {
                        if (spinner) spinner.innerHTML = '<span style="color:#ef4444; font-weight:700;">Failed to load image preview</span>';
                    };
                    imgEl.src = downloadUrl;
                })
                .catch(err => {
                    const spinner = document.getElementById('np-img-spinner');
                    if (spinner) spinner.innerHTML = `<span style="color:#ef4444; font-weight:700;">Error: ${err.message}</span>`;
                });
            }

            function initFileManagerImagePreview() {
                const path = window.location.pathname;
                const match = path.match(/^\/server\/([a-zA-Z0-9]+)\/files/);
                if (!match) return;
                const serverId = match[1];

                const imageExts = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.ico', '.bmp'];
                const rows = document.querySelectorAll('div[class*="file_row"], div[class*="style-module_HHpjDvv7"]');

                // Determine current directory from URL hash
                let currentDir = '';
                if (window.location.hash) {
                    try {
                        currentDir = decodeURIComponent(window.location.hash.replace(/^#\/?/, ''));
                    } catch (e) {
                        currentDir = window.location.hash.replace(/^#\/?/, '');
                    }
                }
                currentDir = currentDir.replace(/^\/+|\/+$/g, '');

                rows.forEach(row => {
                    if (row.getAttribute('data-np-img-bound')) return;

                    const detailsEl = row.querySelector('div[class*="details"], a[class*="details"], div[class*="style-module_le7taa7N"], a[class*="style-module_le7taa7N"]');
                    if (!detailsEl) return;

                    const textNodes = Array.from(detailsEl.querySelectorAll('div, span, p')).filter(el => el.children.length === 0);
                    let fileName = '';
                    for (const el of textNodes) {
                        const t = (el.textContent || '').trim();
                        if (imageExts.some(ext => t.toLowerCase().endsWith(ext))) {
                            fileName = t;
                            break;
                        }
                    }

                    if (!fileName) return;

                    row.setAttribute('data-np-img-bound', 'true');
                    detailsEl.style.cursor = 'pointer';
                    detailsEl.title = 'Click to view ' + fileName;

                    // Click handler to open image modal
                    detailsEl.addEventListener('click', function(e) {
                        // Ignore if user clicked on checkbox or context menu trigger
                        if (e.target.closest('label') || e.target.closest('input')) return;
                        e.preventDefault();
                        e.stopPropagation();

                        const fullPath = currentDir ? (currentDir + '/' + fileName) : fileName;
                        openImageModal(serverId, fullPath, fileName);
                    });
                });
            }

            // SPA Navigation Interceptors (React Router history.pushState & history.replaceState)
            const _historyPush = history.pushState;
            history.pushState = function() {
                const res = _historyPush.apply(this, arguments);
                window.dispatchEvent(new Event('np:locationchange'));
                return res;
            };
            const _historyReplace = history.replaceState;
            history.replaceState = function() {
                const res = _historyReplace.apply(this, arguments);
                window.dispatchEvent(new Event('np:locationchange'));
                return res;
            };

            // ============================================================
            // TOGGLE / SWITCH SYNC (Uses CSS classes without overriding styles)
            // ============================================================
            function syncToggles() {
                document.querySelectorAll('div[class*="sc-1nxt82m-0"] > input[type="checkbox"], div[class*="sc-1nxt82m-1"] > input[type="checkbox"], div[class*="Switch"] > input[type="checkbox"], div[class*="Toggle"] > input[type="checkbox"]').forEach(inp => {
                    const label = inp.nextElementSibling;
                    if (!label || label.tagName !== 'LABEL') return;
                    if (inp.checked) {
                        label.classList.add('np-toggle-active');
                    } else {
                        label.classList.remove('np-toggle-active');
                    }
                });
            }

            document.addEventListener('change', function(e) {
                if (e.target && e.target.type === 'checkbox') {
                    const parent = e.target.parentElement;
                    if (parent && (parent.className.includes('sc-1nxt82m') || parent.className.includes('Switch') || parent.className.includes('Toggle'))) {
                        syncToggles();
                    }
                }
            }, true);


            // ============================================================
            // CONSOLE ADDRESS STAT CARD & SERVER ROWS: Always Show Real VPS IP:Port
            // ============================================================
            function enforceVpsIpDisplay() {
                const vpsIp = window.NP_VPS_IP || '213.136.89.90';

                // 1. Dashboard server rows & cards (Replace domain or 0.0.0.0 with real VPS IP)
                document.querySelectorAll('a[href*="/server/"] div[class*="lg:col-span-2"] p, a[href*="/server/"] p, div[class*="ServerRow"] p').forEach(el => {
                    const txt = (el.textContent || '').trim();
                    if (txt.includes(':') && (txt.includes('panel.') || txt.includes('.nx.kg') || txt.includes('.top') || txt.includes('.com') || txt.includes('.net') || txt.includes('0.0.0.0') || txt.includes('localhost') || txt.includes('127.0.0.1'))) {
                        const portM = txt.match(/:(\d+)$/);
                        if (portM) {
                            el.textContent = vpsIp + ':' + portM[1];
                        }
                    }
                });

                // 2. Console Address Stat Card (Real-time DOM replacement)
                updateAddressStatCard();
            }

            function updateAddressStatCard() {
                const vpsIp = window.NP_VPS_IP || '213.136.89.90';

                // Scan all elements labeled "Address"
                document.querySelectorAll('p, span, div').forEach(el => {
                    if (el.children.length === 0 && (el.textContent || '').trim() === 'Address') {
                        const card = el.closest('div[class*="style-module_V4CSEpa4"]') || el.closest('div[class*="StatBlock"]') || el.parentElement?.parentElement || el.parentElement;
                        if (card) {
                            if (!card.hasAttribute('data-np-vps-copy')) {
                                card.setAttribute('data-np-vps-copy', 'true');
                                card.addEventListener('click', () => {
                                    const portM = card.textContent.match(/:(\d+)/);
                                    if (portM) {
                                        navigator.clipboard.writeText(vpsIp + ':' + portM[1]);
                                    }
                                }, true);
                            }
                            card.querySelectorAll('p, div, span').forEach(valEl => {
                                if (valEl !== el && valEl.children.length === 0) {
                                    const txt = (valEl.textContent || '').trim();
                                    if (txt.includes(':') && (txt.includes('panel') || txt.includes('.kg') || txt.includes('.com') || txt.includes('.net') || txt.includes('.top') || txt.includes('0.0.0.0') || txt.includes('localhost') || txt.includes('127.0.0.1'))) {
                                        const portM = txt.match(/:(\d+)$/);
                                        if (portM) {
                                            const target = vpsIp + ':' + portM[1];
                                            if (valEl.textContent !== target) {
                                                valEl.textContent = target;
                                            }
                                        }
                                    }
                                }
                            });
                        }
                    }
                });

                // Universal fallback: Any standalone element showing domain:port
                document.querySelectorAll('p, span, div, code').forEach(el => {
                    if (el.children.length === 0) {
                        const txt = (el.textContent || '').trim();
                        if (txt.includes(':') && (txt.includes('panel.') || txt.includes('.nx.kg') || txt.includes('.top') || txt.includes('0.0.0.0') || txt.includes('localhost') || txt.includes('127.0.0.1'))) {
                            const portM = txt.match(/^(?:https?:\/\/)?(?:[a-zA-Z0-9_.-]+):(\d+)$/);
                            if (portM) {
                                const target = vpsIp + ':' + portM[1];
                                if (el.textContent !== target) {
                                    el.textContent = target;
                                }
                            }
                        }
                    }
                });
            }

            // ============================================================
            // MARKDOWN (.md) EDITOR & GITHUB-STYLE PREVIEW CONTROLLER
            // ============================================================
            function simpleMarkdownToHtml(md) {
                if (!md) return '<p style="color:#7c6999;font-style:italic;">Nothing to preview</p>';
                let html = md;
                html = html.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
                
                // Code blocks
                html = html.replace(/```([a-zA-Z0-9_-]*)\n([\s\S]*?)```/g, function(match, lang, code) {
                    return '<pre style="background:#0d1117;border:1px solid rgba(194,104,242,0.25);border-radius:8px;padding:14px;overflow-x:auto;margin:12px 0;"><code style="color:#e2d4f8;font-family:monospace;font-size:0.88rem;">' + code.trim() + '</code></pre>';
                });

                // Inline code
                html = html.replace(/`([^`]+)`/g, '<code style="background:#1a1330;border:1px solid rgba(194,104,242,0.25);border-radius:4px;padding:2px 6px;color:#C268F2;font-family:monospace;font-size:0.88rem;">$1</code>');

                // Headers
                html = html.replace(/^###### (.*$)/gim, '<h6 style="color:#d8b4fe;font-size:0.95rem;font-weight:700;margin:14px 0 6px 0;">$1</h6>');
                html = html.replace(/^##### (.*$)/gim, '<h5 style="color:#d8b4fe;font-size:1.05rem;font-weight:700;margin:16px 0 8px 0;">$1</h5>');
                html = html.replace(/^#### (.*$)/gim, '<h4 style="color:#d8b4fe;font-size:1.15rem;font-weight:700;margin:18px 0 8px 0;">$1</h4>');
                html = html.replace(/^### (.*$)/gim, '<h3 style="color:#e9d5ff;font-size:1.3rem;font-weight:700;margin:20px 0 10px 0;border-bottom:1px solid rgba(194,104,242,0.15);padding-bottom:6px;">$1</h3>');
                html = html.replace(/^## (.*$)/gim, '<h2 style="color:#f3e8ff;font-size:1.55rem;font-weight:700;margin:24px 0 12px 0;border-bottom:1px solid rgba(194,104,242,0.2);padding-bottom:8px;">$1</h2>');
                html = html.replace(/^# (.*$)/gim, '<h1 style="color:#ffffff;font-size:1.85rem;font-weight:800;margin:28px 0 14px 0;border-bottom:2px solid #C268F2;padding-bottom:10px;">$1</h1>');

                // Blockquotes
                html = html.replace(/^\> (.*$)/gim, '<blockquote style="border-left:3.5px solid #C268F2;background:rgba(194,104,242,0.08);margin:12px 0;padding:8px 16px;color:#c4b5fd;border-radius:0 8px 8px 0;">$1</blockquote>');

                // Bold & Italic
                html = html.replace(/\*\*([^*]+)\*\*/g, '<strong style="color:#ffffff;font-weight:700;">$1</strong>');
                html = html.replace(/\*([^*]+)\*/g, '<em style="color:#e9d5ff;">$1</em>');
                html = html.replace(/__([^_]+)__/g, '<strong style="color:#ffffff;font-weight:700;">$1</strong>');
                html = html.replace(/_([^_]+)_/g, '<em style="color:#e9d5ff;">$1</em>');

                // Horizontal Rule
                html = html.replace(/^---$/gim, '<hr style="border:none;border-top:1px solid rgba(194,104,242,0.25);margin:20px 0;" />');

                // Task lists & Lists
                html = html.replace(/^- \[x\] (.*$)/gim, '<div style="display:flex;align-items:center;gap:8px;margin:4px 0;"><span style="color:#10b981;font-weight:bold;">☑</span> <span style="color:#94a3b8;text-decoration:line-through;">$1</span></div>');
                html = html.replace(/^- \[ \] (.*$)/gim, '<div style="display:flex;align-items:center;gap:8px;margin:4px 0;"><span style="color:#C268F2;">☐</span> <span style="color:#ffffff;">$1</span></div>');
                html = html.replace(/^\- (.*$)/gim, '<li style="color:#e2d4f8;margin:4px 0 4px 20px;">$1</li>');
                html = html.replace(/^\* (.*$)/gim, '<li style="color:#e2d4f8;margin:4px 0 4px 20px;">$1</li>');

                // Links
                html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer" style="color:#C268F2;text-decoration:underline;font-weight:600;">$1</a>');

                // Paragraphs
                html = html.split('\n\n').map(p => {
                    p = p.trim();
                    if (!p) return '';
                    if (p.startsWith('<h') || p.startsWith('<pre') || p.startsWith('<blockquote') || p.startsWith('<div') || p.startsWith('<li') || p.startsWith('<hr')) {
                        return p;
                    }
                    return '<p style="margin:8px 0;line-height:1.6;color:#e2d4f8;">' + p.replace(/\n/g, '<br/>') + '</p>';
                }).join('');

                return html;
            }

            function initMarkdownPreview() {
                const path = window.location.pathname;
                const isEditPage = path.includes('/files/edit');
                if (!isEditPage) {
                    const existingBar = document.getElementById('np-md-toolbar');
                    if (existingBar) existingBar.remove();
                    const existingPrev = document.getElementById('np-md-preview-container');
                    if (existingPrev) existingPrev.remove();
                    return;
                }

                const editorContainer = document.querySelector('.ace_editor') || document.querySelector('div[class*="FileEditContainer"]') || document.querySelector('div[class*="EditorContainer"]');
                if (!editorContainer) return;
                const parent = editorContainer.parentElement;
                if (!parent) return;

                let toolbar = document.getElementById('np-md-toolbar');
                if (!toolbar) {
                    toolbar = document.createElement('div');
                    toolbar.id = 'np-md-toolbar';
                    toolbar.style.cssText = 'display:flex;align-items:center;justify-content:space-between;background:#110d22;border:1px solid rgba(194,104,242,0.25);border-bottom:none;border-radius:10px 10px 0 0;padding:8px 14px;margin-bottom:0;width:100%;box-sizing:border-box;';

                    toolbar.innerHTML = `
                        <div style="display:flex;align-items:center;gap:8px;">
                            <span style="font-weight:700;font-size:0.85rem;color:#C268F2;display:inline-flex;align-items:center;gap:6px;">
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line><polyline points="10 9 9 9 8 9"></polyline></svg>
                                MARKDOWN
                            </span>
                        </div>
                        <div style="display:flex;align-items:center;background:#0b0717;border:1px solid rgba(194,104,242,0.3);border-radius:8px;padding:3px;gap:4px;">
                            <button id="np-md-btn-edit" type="button" style="background:#C268F2;color:#ffffff;border:none;border-radius:6px;padding:5px 12px;font-size:0.82rem;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:5px;transition:all 0.15s ease;">
                                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"></path><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"></path></svg>
                                Edit
                            </button>
                            <button id="np-md-btn-preview" type="button" style="background:transparent;color:#c4b5fd;border:none;border-radius:6px;padding:5px 12px;font-size:0.82rem;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;gap:5px;transition:all 0.15s ease;">
                                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle></svg>
                                Preview
                            </button>
                        </div>
                    `;

                    parent.insertBefore(toolbar, editorContainer);

                    let previewCont = document.getElementById('np-md-preview-container');
                    if (!previewCont) {
                        previewCont = document.createElement('div');
                        previewCont.id = 'np-md-preview-container';
                        previewCont.style.cssText = 'display:none;width:100%;min-height:500px;max-height:75vh;overflow-y:auto;background:#0d1117;border:1px solid rgba(194,104,242,0.25);border-radius:0 0 10px 10px;padding:2rem;box-sizing:border-box;color:#e2d4f8;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;';
                        parent.insertBefore(previewCont, editorContainer.nextSibling);
                    }

                    const btnEdit = document.getElementById('np-md-btn-edit');
                    const btnPreview = document.getElementById('np-md-btn-preview');

                    btnEdit.onclick = function() {
                        btnEdit.style.background = '#C268F2';
                        btnEdit.style.color = '#ffffff';
                        btnPreview.style.background = 'transparent';
                        btnPreview.style.color = '#c4b5fd';
                        editorContainer.style.display = 'block';
                        previewCont.style.display = 'none';
                    };

                    btnPreview.onclick = function() {
                        btnPreview.style.background = '#C268F2';
                        btnPreview.style.color = '#ffffff';
                        btnEdit.style.background = 'transparent';
                        btnEdit.style.color = '#c4b5fd';

                        let text = '';
                        if (window.ace && window.ace.edit) {
                            try {
                                const ed = window.ace.edit(editorContainer);
                                if (ed) text = ed.getValue();
                            } catch(e) {}
                        }
                        if (!text) {
                            const ta = editorContainer.querySelector('textarea');
                            if (ta) text = ta.value;
                        }
                        if (!text) {
                            const lines = Array.from(editorContainer.querySelectorAll('.ace_line'));
                            if (lines.length > 0) text = lines.map(l => l.innerText).join('\n');
                        }

                        previewCont.innerHTML = simpleMarkdownToHtml(text);
                        editorContainer.style.display = 'none';
                        previewCont.style.display = 'block';
                    };
                }
            }

            function updateRouteAttributes() {
                const path = window.location.pathname || '';
                let route = 'other';
                if (path.includes('/startup')) route = 'startup';
                else if (path.includes('/domains')) route = 'domains';
                else if (path.includes('/files')) route = 'files';
                else if (path.includes('/databases')) route = 'databases';
                else if (path.includes('/schedules')) route = 'schedules';
                else if (path.includes('/users')) route = 'users';
                else if (path.includes('/backups')) route = 'backups';
                else if (path.includes('/network')) route = 'network';
                else if (path.includes('/settings')) route = 'settings';
                else if (path.includes('/activity')) route = 'activity';
                else if (path.match(/\/server\/[^/]+$/) || path.includes('/console')) route = 'console';
                if (document.body) {
                    document.body.setAttribute('data-np-route', route);
                }
            }

            function fixContextMenuColors(root) {
                const target = root || document.body;
                target.querySelectorAll('nav.react-contextmenu, .react-contextmenu, div.react-contextmenu, div[role="menu"]:not([role="menubar"]), ul[role="menu"]').forEach(menu => {
                    // Safety: Never style elements inside table or file rows as floating menus
                    if (menu.closest('div[class*="file_row"], div[class*="FileObjectRow"], div[class*="style-module_HHpjDvv7"], tr, td')) {
                        menu.style.setProperty('border', 'none', 'important');
                        menu.style.setProperty('background', 'transparent', 'important');
                        menu.style.setProperty('box-shadow', 'none', 'important');
                        return;
                    }
                    menu.style.setProperty('background', '#120e24', 'important');
                    menu.style.setProperty('background-color', '#120e24', 'important');
                    menu.style.setProperty('border', '1.5px solid #C268F2', 'important');
                    menu.style.setProperty('box-shadow', '0 16px 45px rgba(0, 0, 0, 0.95), 0 0 25px rgba(194, 104, 242, 0.35)', 'important');
                    menu.style.setProperty('min-width', '190px', 'important');
                    menu.style.setProperty('border-radius', '10px', 'important');
                    menu.querySelectorAll('.react-contextmenu-item, [role="menuitem"], button, a, li, span, p, div').forEach(child => {
                        if (child.tagName === 'SVG' || child.tagName === 'path') {
                            child.style.setProperty('color', '#C268F2', 'important');
                            child.style.setProperty('stroke', '#C268F2', 'important');
                            child.style.setProperty('fill', 'currentColor', 'important');
                        } else if (child.children.length === 0 || child.textContent.trim().length > 0) {
                            child.style.setProperty('color', '#ffffff', 'important');
                            child.style.setProperty('opacity', '1', 'important');
                            child.style.setProperty('visibility', 'visible', 'important');
                        }
                    });
                });

                // Strictly ensure 3-dots action buttons and their wrappers in table rows are plain and borderless
                target.querySelectorAll('div[class*="FileObjectRow"] button, div[class*="file_row"] button, div[class*="FileObjectRow"] div[class*="DropdownMenu"], div[class*="FileObjectRow"] div[class*="FileDropdownMenu"], div[class*="file_row"] div[class*="DropdownMenu"], div[class*="style-module_HHpjDvv7"] button, div[class*="style-module_HHpjDvv7"] div[class*="DropdownMenu"], div[class*="DropdownMenu__Menu"], button:has(svg[data-icon="ellipsis-h"]), button:has(svg.fa-ellipsis-h), button:has(svg[class*="ellipsis"])').forEach(btn => {
                    btn.style.setProperty('border', 'none', 'important');
                    btn.style.setProperty('border-width', '0', 'important');
                    btn.style.setProperty('border-color', 'transparent', 'important');
                    btn.style.setProperty('outline', 'none', 'important');
                    btn.style.setProperty('box-shadow', 'none', 'important');
                    btn.style.setProperty('background', 'transparent', 'important');
                    btn.style.setProperty('background-color', 'transparent', 'important');
                    btn.style.setProperty('min-width', '0', 'important');
                    btn.style.setProperty('width', 'auto', 'important');
                    btn.style.setProperty('padding', '4px 6px', 'important');
                });
            }

            updateRouteAttributes();
            function onNavigate() {
                updateRouteAttributes();
                sanitizePterodactylText(document.body);
                updateRouteAttributes();
                fixContextMenuColors(document.body);
                injectDomainManager();
                initCustomSelects();
                initFileManagerImagePreview();
                syncToggles();
                enforceVpsIpDisplay();
                initMarkdownPreview();
            }

            window.addEventListener('popstate', onNavigate);
            window.addEventListener('np:locationchange', onNavigate);

            setInterval(onNavigate, 120);

            const bodyObserver = new MutationObserver((mutations) => {
                mutations.forEach(m => {
                    m.addedNodes.forEach(node => {
                        if (node.nodeType === 1) {
                            fixContextMenuColors(node);
                        }
                    });
                });
                onNavigate();
            });
            bodyObserver.observe(document.body, { childList: true, subtree: true });
        })();
