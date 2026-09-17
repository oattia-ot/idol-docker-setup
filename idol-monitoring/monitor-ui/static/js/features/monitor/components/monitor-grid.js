/**
 * Render functions for the monitor grid and detail panel
 */

import { showModal } from '../../../core/ui/modal/modal.js';

function metricClass(value) {
  if (value >= 80) return 'metric-high';
  if (value >= 50) return 'metric-mid';
  return 'metric-low';
}

function metricBar(label, value) {
  const v = Number.isFinite(value) ? value : 0;
  const cls = metricClass(v);
  return `
    <div class="metric-row">
      <span class="metric-label">${label}</span>
      <div class="metric-bar-track">
        <div class="metric-bar-fill ${cls}" style="width:${Math.min(v, 100)}%"></div>
      </div>
      <span class="metric-value">${v}%</span>
    </div>
  `;
}

/**
 * Render the grid of service cards
 */
export function renderGrid(services, container, onCardClick) {
  if (!container) return;
  container.innerHTML = '';

  if (!services.length) {
    container.innerHTML = `
      <div class="empty-state" style="padding:2.5rem 2rem; text-align:center; background:#1e293b; border:1px solid #334155; border-radius:12px;">
        <div style="font-size:1rem; color:#94a3b8;">No services match the current filter.</div>
        <div style="font-size:0.85rem; margin-top:0.5rem; color:#64748b;">Try selecting "All" or check backend connection.</div>
      </div>
    `;
    return;
  }

  const grid = document.createElement('div');
  grid.className = 'monitor-grid';

  services.forEach(service => {
    const card = document.createElement('div');
    card.className = `service-card status-${service.status}`;
    const portBadge = service.port 
      ? `<span style="background:#0f172a; border:1px solid #334155; border-radius:6px; padding:0.1rem 0.5rem; font-size:0.75rem; font-family:monospace; color:#94a3b8;">:${service.port}</span>` 
      : '';

    const descLine = service.description 
      ? `<div style="font-size:0.8rem; color:#64748b; margin-top:0.25rem;">${service.description}</div>` 
      : '';

    const dockerStatusLine = service.docker_status && service.status !== 'healthy'
      ? `<div style="font-size:0.75rem; color:#f87171; margin-top:0.2rem;">Docker: ${service.docker_status}</div>` 
      : '';

    card.innerHTML = `
      <div style="display:flex; justify-content:space-between; align-items:start; gap:0.5rem;">
        <div style="flex:1; min-width:0;">
          <div style="display:flex; align-items:center; gap:0.5rem; flex-wrap:wrap;">
            <h3 style="margin:0; font-size:1.05rem;">${service.name}</h3>
            ${portBadge}
          </div>
          ${descLine}
        </div>
        <span class="status-badge">${service.status}</span>
      </div>

      <div class="service-meta">
        <div>Uptime: <strong>${service.uptime}</strong></div>
        <div>Instances: ${service.instances || 1} &nbsp;•&nbsp; Response: ${service.response_ms ?? '—'}ms</div>
        ${dockerStatusLine}
        <div style="margin-top:0.25rem; font-size:0.75rem; opacity:0.7;">
          Last check: ${new Date(service.last_check).toLocaleTimeString()}
        </div>
      </div>

      ${metricBar('CPU', service.cpu)}
      ${metricBar('MEM', service.memory)}

      <div class="card-footer">
        <span class="region-tag">${service.region || 'local'}</span>
        <span class="endpoint-text" title="${service.endpoint || ''}">${service.endpoint || ''}</span>
      </div>

      <div style="margin-top:1rem; display:flex; gap:0.5rem;">
        <button class="btn-details" style="flex:1; padding:0.4rem; font-size:0.85rem; border-radius:6px; border:1px solid #334155; background:#0f172a; color:#e2e8f0; cursor:pointer;">
          View Details
        </button>
      </div>
    `;

    // Click on card selects it
    card.addEventListener('click', (e) => {
      // Ignore if clicking the button
      if (!e.target.classList.contains('btn-details')) {
        onCardClick?.(service.id);
      }
    });

    // Details button
    const btn = card.querySelector('.btn-details');
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      onCardClick?.(service.id);
      // Also show a quick modal with more info
      showQuickInfoModal(service);
    });

    grid.appendChild(card);
  });

  container.appendChild(grid);
}

function showQuickInfoModal(service) {
  const portInfo = service.port ? `<div><strong>Port:</strong> ${service.port}</div>` : '';
  const descInfo = service.description ? `<div><strong>Description:</strong> ${service.description}</div>` : '';
  const urlInfo = service.url ? `<div><strong>URL:</strong> <a href="${service.url}" target="_blank" style="color:#60a5fa;">${service.url}</a></div>` : '';
  const credInfo = service.credentials ? `<div><strong>Login:</strong> <span style="font-family:monospace;">${service.credentials}</span></div>` : '';

  const html = `
    <div style="display:grid; gap:0.75rem;">
      ${descInfo}
      ${portInfo}
      ${urlInfo}
      ${credInfo}
      <div><strong>Version:</strong> ${service.version || '—'}</div>
      <div><strong>Status:</strong> <span style="color:${service.status === 'healthy' ? '#16a34a' : '#ca8a04'}">${service.status}</span></div>
      <div><strong>Docker Status:</strong> ${service.docker_status || '—'}</div>
      <div><strong>Uptime:</strong> ${service.uptime}</div>
      <div><strong>Instances:</strong> ${service.instances || 1}</div>
      <div><strong>CPU:</strong> ${service.cpu ?? '—'}%</div>
      <div><strong>Memory:</strong> ${service.memory ?? '—'}%</div>
      <div><strong>Response Time:</strong> ${service.response_ms ?? '—'}ms</div>
      <div><strong>Region:</strong> ${service.region || '—'}</div>
      <div><strong>Endpoint:</strong> ${service.endpoint || '—'}</div>
      <div><strong>Last Check:</strong> ${new Date(service.last_check).toLocaleString()}</div>
    </div>
  `;
  showModal(`Service: ${service.name}`, html);
}

/**
 * Render the detail side panel
 */
export function renderDetailPanel(service, container) {
  if (!container) return;

  if (!service) {
    container.innerHTML = `
      <p class="empty-state">Select a service card to view detailed information here.</p>
    `;
    return;
  }

  const statusColor = service.status === 'healthy' ? '#16a34a' : '#ca8a04';

  container.innerHTML = `
    <div style="margin-bottom:1rem;">
      <div style="display:flex; align-items:center; gap:0.75rem; flex-wrap:wrap;">
        <h3 style="margin:0; flex:1;">${service.name}</h3>
        <span class="status-badge" style="background:${service.status === 'healthy' ? '#052e16' : '#451a03'}; color:${statusColor};">
          ${service.status}
        </span>
      </div>

      ${service.url ? `
        <div style="margin-top:0.6rem;">
          <a href="${service.url}" target="_blank" 
             style="display:inline-flex; align-items:center; gap:0.4rem; background:#1e40af; color:white; padding:0.35rem 0.85rem; border-radius:6px; text-decoration:none; font-size:0.9rem; font-weight:600;">
            🔗 Open ${service.name} →
          </a>
        </div>` : ''}

      ${service.credentials ? `
        <div style="margin-top:0.5rem; font-size:0.85rem; background:#0f172a; padding:0.5rem 0.75rem; border-radius:6px; border:1px solid #334155;">
          <strong>Login:</strong> <span style="font-family:monospace;">${service.credentials}</span>
        </div>` : ''}
    </div>

    <div class="detail-grid">
      ${service.description ? `
      <div class="detail-row">
        <span class="detail-label">Description</span>
        <span class="detail-value">${service.description}</span>
      </div>` : ''}
      ${service.port ? `
      <div class="detail-row">
        <span class="detail-label">Port</span>
        <span class="detail-value" style="font-family:monospace;">${service.port}</span>
      </div>` : ''}
      <div class="detail-row">
        <span class="detail-label">Version</span>
        <span class="detail-value">${service.version || '—'}</span>
      </div>
      <div class="detail-row">
        <span class="detail-label">Docker Status</span>
        <span class="detail-value">${service.docker_status || '—'}</span>
      </div>
      <div class="detail-row">
        <span class="detail-label">Uptime</span>
        <span class="detail-value">${service.uptime}</span>
      </div>
      <div class="detail-row">
        <span class="detail-label">Instances</span>
        <span class="detail-value">${service.instances || 1}</span>
      </div>
      <div class="detail-row">
        <span class="detail-label">CPU</span>
        <span class="detail-value">${service.cpu ?? '—'}%</span>
      </div>
      <div class="detail-row">
        <span class="detail-label">Memory</span>
        <span class="detail-value">${service.memory ?? '—'}%</span>
      </div>
      <div class="detail-row">
        <span class="detail-label">Response Time</span>
        <span class="detail-value">${service.response_ms ?? '—'}ms</span>
      </div>
      <div class="detail-row">
        <span class="detail-label">Region</span>
        <span class="detail-value">${service.region || '—'}</span>
      </div>
      <div class="detail-row">
        <span class="detail-label">Endpoint</span>
        <span class="detail-value" style="font-family:monospace; font-size:0.8rem;">${service.endpoint || '—'}</span>
      </div>
      <div class="detail-row">
        <span class="detail-label">Last Check</span>
        <span class="detail-value">${new Date(service.last_check).toLocaleString()}</span>
      </div>
      <div class="detail-row">
        <span class="detail-label">Service ID</span>
        <span class="detail-value" style="font-family:monospace; font-size:0.8rem;">${service.id}</span>
      </div>
    </div>

    <div style="margin-top:1.5rem; display:flex; gap:0.5rem;">
      <button id="btn-restart" class="btn" style="flex:1; background:#334155; color:white; padding:0.6rem; border-radius:6px; border:none; cursor:pointer;">
        Restart Service
      </button>
      <button id="btn-logs" class="btn" style="flex:1; background:#1e40af; color:white; padding:0.6rem; border-radius:6px; border:none; cursor:pointer;">
        View Logs
      </button>
    </div>
  `;

  // Wire action buttons (demo only)
  const restartBtn = container.querySelector('#btn-restart');
  const logsBtn = container.querySelector('#btn-logs');

  if (restartBtn) {
    restartBtn.addEventListener('click', () => {
      alert(`[Demo] Restart requested for ${service.name}\n\n(In real system this would call an API)`);
    });
  }

  if (logsBtn) {
    logsBtn.addEventListener('click', () => {
      const logHtml = `
        <pre style="background:#0f172a; padding:1rem; border-radius:8px; font-size:0.8rem; max-height:260px; overflow:auto; margin:0;">
[2026-06-29 17:12:44] INFO  Service started successfully
[2026-06-29 17:08:12] INFO  Health check passed (latency 12ms)
[2026-06-29 17:05:01] WARN  High memory usage detected (87%)
[2026-06-29 16:59:33] INFO  Configuration reloaded
        </pre>
      `;
      showModal(`Logs — ${service.name}`, logHtml);
    });
  }
}
