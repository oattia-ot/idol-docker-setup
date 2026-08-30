/**
 * features/dashboard/dashboard.page.js
 * Composition root for the dashboard page. Wires the pure state
 * (dashboard-state.js) to the pure renderer (service-grid.js) and to
 * DOM events, using event delegation instead of inline onclick handlers.
 * This is the only file in the feature that touches `document`.
 *
 * Replaces: frontend/static/main/js/main.js
 */

import { createDashboardStore } from './state/dashboard-state.js';
import { renderServiceGrid } from './components/service-grid.js';
import { createToaster } from '../../core/ui/toast/toast.js';
import { delegate, getEl } from '../../core/ui/dom-utils.js';
import { isPageAccessible } from '../../core/accessibility-check.js';

// ==================== UI-CONFIG: Monitoring Stack Tools ====================
// This is the single source of truth for Monitoring Stack items in the main dashboard.
// Add new tools here for automatic rendering + accessibility guard.
const MONITORING_TOOLS_CONFIG = [
  {
    id: 'idol-monitoring',
    title: 'Idol Monitoring',
    description: 'Detailed observability dashboard for IDOL services, metrics, logs & container health',
    url: 'monitoring.html',
    icon: 'fas fa-chart-line',
    category: 'monitoring',
    type: 'detailed',
    primaryActionLabel: 'Open Detailed View'
  },
  {
    id: 'live-monitor',
    title: 'Live Monitor (5011)',
    description: 'Real-time service health, CPU/MEM metrics and Docker status from the monitoring stack',
    url: 'http://localhost:5011',
    icon: 'fas fa-tachometer-alt',
    category: 'monitoring',
    type: 'live',
    primaryActionLabel: 'Open Live Dashboard'
  }
];

export function initDashboardPage() {
  const store = createDashboardStore();
  const toast = createToaster('toastWrap');
  const grid = getEl('servicesGrid');

  function render() {
    renderServiceGrid(grid, store.getAll());
    const { running, stopped } = store.counts();
    const runEl = getEl('runCount');
    const stopEl = getEl('stopCount');
    if (runEl) runEl.textContent = running;
    if (stopEl) stopEl.textContent = stopped;
  }

  function svcAction(cmd, id) {
    const result = store.applyServiceCommand(cmd, id);
    if (result.info) {
      toast(`$ ./monitor.sh logs ${id}`, 'info');
      return;
    }
    if (result.changed) {
      render();
      toast(`$ ./monitor.sh ${cmd} ${id}`, cmd === 'stop' ? 'error' : 'success');
    }
  }

  function globalAction(cmd) {
    const result = store.applyGlobalCommand(cmd);
    if (result.info) {
      toast('$ ./monitor.sh status all', 'info');
      return;
    }
    if (result.changed) {
      render();
      toast(`$ ./monitor.sh ${cmd} all`, cmd === 'stop' ? 'error' : 'success');
    }
  }

  function showUrls() {
    const lines = store
      .getAll()
      .map((s) => `${s.name.padEnd(14)} → http://localhost:${s.port}`)
      .join('\n');
    toast('URLs logged to browser console', 'info');
    console.log('=== Monitoring Stack URLs ===\n' + lines);
  }

  // Event delegation replaces every inline onclick="..." in index.html
  delegate(grid, {
    'service-cmd': (el) => svcAction(el.dataset.cmd, el.dataset.id),
  });
  delegate(document.querySelector('.monitor-actions'), {
    'global-cmd': (el) => globalAction(el.dataset.cmd),
    'show-urls': () => showUrls(),
  });

  // Live date in topbar
  const dateEl = getEl('topbarDate');
  if (dateEl) dateEl.textContent = new Date().toISOString().split('T')[0];

  // =====================================================
  // "Open IDOL Setup" / "Open NiFi Config" links
  // Mirrors the Network page's "Back to Home" logic:
  //  - Extra IP SANs at its default (empty, or == Host IP) → localhost
  //  - Extra IP SANs overridden to a different value        → that value
  // Values are read from localStorage, written by the config-idol page
  // under the `idol_hostIp` / `idol_extraIpSans` keys (auto-save or
  // "Save to Browser").
  // =====================================================
  function resolveConfigHost() {
    const hostIp         = (localStorage.getItem('idol_hostIp') || '').trim();
    const extraIpSansVal = (localStorage.getItem('idol_extraIpSans') || '').trim();
    const extraIps       = extraIpSansVal.split(',').map(s => s.trim()).filter(Boolean);
    const isDefault       = !extraIpSansVal || extraIpSansVal === hostIp;

    return (!isDefault && extraIps.length > 0) ? extraIps[0] : 'localhost';
  }

  function updateConfigLinks() {
    const host    = resolveConfigHost();
    const idolBtn = document.querySelector('.btn-idol');
    const nifiBtn = document.querySelector('.btn-nifi');
    if (idolBtn) idolBtn.href = `http://${host}:5000/config-idol`;
    if (nifiBtn) nifiBtn.href = `http://${host}:5000/config-nifi`;
  }

  updateConfigLinks();

  // Keep links in sync if the Network settings are edited in another tab
  window.addEventListener('storage', (e) => {
    if (e.key === 'idol_hostIp' || e.key === 'idol_extraIpSans') updateConfigLinks();
  });

  render();

  // =====================================================
  // LIVE SERVICES STATS + MINI GRID from real monitor backend
  // Uses the proxied endpoint /api/monitor/status (no hard-coded port 5011)
  // =====================================================
  let lastRealServices = [];

  function renderMiniServiceGrid(services) {
    const container = document.getElementById('mini-service-grid');
    const emptyEl   = document.getElementById('mini-grid-empty');
    if (!container) return;

    container.innerHTML = '';

    if (!services || services.length === 0) {
      if (emptyEl) emptyEl.style.display = 'block';
      return;
    }
    if (emptyEl) emptyEl.style.display = 'none';

    // Show up to 9 services in the mini grid (most relevant first)
    const toShow = services.slice(0, 9);

    toShow.forEach(svc => {
      const card = document.createElement('div');
      card.style.cssText = `
        background: #1e293b; border: 1px solid #334155; border-radius: 10px;
        padding: 0.7rem 0.85rem; font-size: 0.82rem; cursor: pointer;
        transition: transform 0.1s ease, box-shadow 0.1s ease;
      `;
      card.onmouseenter = () => card.style.transform = 'translateY(-2px)';
      card.onmouseleave = () => card.style.transform = '';

      const statusColor = svc.status === 'healthy' ? '#16a34a' : '#ca8a04';
      const statusBg    = svc.status === 'healthy' ? '#052e16' : '#451a03';

      const portBadge = svc.port 
        ? `<span style="font-family:monospace; background:#0f172a; padding:1px 6px; border-radius:4px; font-size:0.7rem; color:#94a3b8;">:${svc.port}</span>` 
        : '';

      card.innerHTML = `
        <div style="display:flex; justify-content:space-between; align-items:flex-start; gap:0.4rem;">
          <div style="flex:1; min-width:0;">
            <div style="font-weight:600; color:#e2e8f0; line-height:1.2; margin-bottom:2px;">${svc.name}</div>
            <div style="font-size:0.72rem; color:#64748b; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">
              ${svc.description || svc.endpoint || ''}
            </div>
          </div>
          <span style="background:${statusBg}; color:${statusColor}; padding:1px 7px; border-radius:999px; font-size:0.65rem; font-weight:700; white-space:nowrap; align-self:flex-start;">
            ${svc.status}
          </span>
        </div>
        <div style="margin-top:0.45rem; display:flex; justify-content:space-between; align-items:center; font-size:0.72rem;">
          <div style="color:#94a3b8;">${portBadge}</div>
          <div style="color:#64748b; font-size:0.68rem;">
            ${svc.cpu != null ? `CPU ${svc.cpu}%` : ''} 
            ${svc.memory != null ? `· MEM ${svc.memory}%` : ''}
          </div>
        </div>
      `;

      // Click → open the service URL if available, else just log
      card.onclick = () => {
        if (svc.url) {
          window.open(svc.url, '_blank');
        } else {
          console.log('[Dashboard] Service clicked:', svc);
        }
      };

      container.appendChild(card);
    });
  }

  async function updateLiveStatsAndGrid(refreshBtn = null) {
    const totalEl    = document.getElementById('stat-total');
    const healthyEl  = document.getElementById('stat-healthy');
    const degradedEl = document.getElementById('stat-degraded');
    const runEl      = document.getElementById('runCount');
    const stopEl     = document.getElementById('stopCount');

    if (refreshBtn) {
      refreshBtn.disabled = true;
      refreshBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Refreshing...';
    }

    try {
      const res = await fetch('/api/monitor/status', {
        method: 'GET',
        cache: 'no-cache',
        headers: { 'Pragma': 'no-cache' }
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);

      const data = await res.json();
      const summary = data.summary || {};
      const services = Array.isArray(data.services) ? data.services : [];

      lastRealServices = services;

      // Update stats pills
      if (totalEl)   totalEl.textContent   = summary.total   ?? '—';
      if (healthyEl) healthyEl.textContent = summary.healthy ?? '—';
      if (degradedEl) degradedEl.textContent = summary.degraded ?? '—';

      if (runEl)   runEl.textContent   = summary.healthy ?? 0;
      if (stopEl)  stopEl.textContent  = summary.degraded ?? 0;

      // Render mini service grid with real data
      renderMiniServiceGrid(services);

      // Control "Open Live Monitor" button visibility
      // Show button only if we got a successful response with actual service data
      const hasRealData = data.ok !== false && Array.isArray(services) && services.length > 0;
      updateLiveMonitorButtonVisibility(hasRealData);

      const warnEl = document.getElementById('live-monitor-warning');
      if (warnEl) warnEl.style.display = (data.ok === false) ? 'flex' : 'none';

      console.log('%c[Dashboard] ✅ Live stats + mini grid updated from real monitor backend', 'color:#22c55e');
    } catch (err) {
      console.warn('%c[Dashboard] ⚠️ Could not fetch real monitor data', 'color:#f59e0b', err.message);
      const container = document.getElementById('mini-service-grid');
      if (container) container.innerHTML = `<div style="color:#f59e0b; font-size:0.8rem; padding:0.5rem;">Monitor backend unavailable</div>`;
      
      const warnEl = document.getElementById('live-monitor-warning');
      if (warnEl) warnEl.style.display = 'flex';

      // Hide button and show instructions on error
      updateLiveMonitorButtonVisibility(false);
    } finally {
      if (refreshBtn) {
        refreshBtn.disabled = false;
        refreshBtn.innerHTML = '<i class="fas fa-sync-alt"></i> <span>Refresh Now</span>';
      }
    }
  }

  // Wire the new "Refresh Now" button
  const refreshBtn = document.getElementById('btn-refresh-stats');
  if (refreshBtn) {
    refreshBtn.addEventListener('click', () => updateLiveStatsAndGrid(refreshBtn));
  } else {
    console.warn('%c[Dashboard] ⚠️ #btn-refresh-stats not found in DOM — check index.html markup', 'color:#f59e0b');
  }

  // Initial load + auto-poll every 12 seconds
  updateLiveStatsAndGrid();
  setInterval(() => updateLiveStatsAndGrid(), 12000);

  // =====================================================
  // Render Monitoring Tools from UI-CONFIG + Accessibility Guard
  // =====================================================
  function renderMonitoringTools() {
    const container = document.getElementById('monitoring-tools-grid');
    if (!container) return;

    container.innerHTML = '';

    MONITORING_TOOLS_CONFIG.forEach(tool => {
      const card = document.createElement('div');
      card.style.cssText = 'background:#0f172a; border:1px solid #334155; border-radius:12px; padding:1rem; transition:all .2s ease; cursor:pointer;';
      card.innerHTML = `
        <div style="display:flex; align-items:flex-start; gap:0.75rem;">
          <div style="width:42px; height:42px; background:#1e293b; border-radius:10px; display:flex; align-items:center; justify-content:center; flex-shrink:0;">
            <i class="${tool.icon}" style="font-size:1.35rem; color:#60a5fa;"></i>
          </div>
          <div style="flex:1; min-width:0;">
            <div style="display:flex; align-items:center; gap:0.5rem; margin-bottom:0.25rem;">
              <strong style="font-size:1rem; color:#e2e8f0;">${tool.title}</strong>
              <span id="status-${tool.id}" 
                    style="font-size:0.7rem; padding:1px 7px; border-radius:9999px; background:rgba(16,185,129,.15); color:#10b981; border:1px solid rgba(16,185,129,.3); white-space:nowrap;">
                🟢 checking…
              </span>
            </div>
            <div style="font-size:0.82rem; color:#94a3b8; line-height:1.35; margin-bottom:0.6rem;">
              ${tool.description}
            </div>
            <button class="btn-tool-open" 
                    data-tool-id="${tool.id}"
                    style="font-size:0.8rem; padding:0.35rem 0.9rem; border-radius:6px; border:1px solid #334155; background:#1e40af; color:white; cursor:pointer; display:inline-flex; align-items:center; gap:5px;">
              <i class="fas fa-external-link-alt" style="font-size:0.75rem;"></i> 
              <span>${tool.primaryActionLabel || 'Open'}</span>
            </button>
          </div>
        </div>
      `;

      // Click on whole card also triggers open (except button)
      card.addEventListener('click', (e) => {
        if (!e.target.closest('.btn-tool-open')) {
          openMonitoringTool(tool);
        }
      });

      // Button click
      const btn = card.querySelector('.btn-tool-open');
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        openMonitoringTool(tool);
      });

      container.appendChild(card);

      // Initial status check (non-blocking)
      updateToolStatus(tool.id, tool.url);
    });
  }

  async function updateToolStatus(toolId, url) {
    const statusEl = document.getElementById(`status-${toolId}`);
    if (!statusEl) return;

    statusEl.innerHTML = `<i class="fas fa-spinner fa-spin"></i> checking`;
    statusEl.style.background = 'rgba(59,130,246,.15)';
    statusEl.style.color = '#60a5fa';
    statusEl.style.border = '1px solid rgba(59,130,246,.3)';

    const accessible = await isPageAccessible(url);

    if (accessible) {
      statusEl.innerHTML = `🟢 Available`;
      statusEl.style.background = 'rgba(16,185,129,.15)';
      statusEl.style.color = '#10b981';
      statusEl.style.border = '1px solid rgba(16,185,129,.3)';
    } else {
      statusEl.innerHTML = `🔴 Unavailable`;
      statusEl.style.background = 'rgba(245,158,11,.15)';
      statusEl.style.color = '#f59e0b';
      statusEl.style.border = '1px solid rgba(245,158,11,.3)';
    }
  }

  async function openMonitoringTool(tool) {
    const statusEl = document.getElementById(`status-${tool.id}`);
    
    // Show checking state
    if (statusEl) {
      statusEl.innerHTML = `<i class="fas fa-spinner fa-spin"></i> verifying…`;
    }

    const accessible = await isPageAccessible(tool.url);

    if (!accessible) {
      // Failure path - show clear warning, do NOT navigate
      const msg = `⚠️ ${tool.title} is currently unavailable<br>The page could not be reached. It may be temporarily down or misconfigured. Please try again later or contact support.`;
      
      // Use accessible modal-style warning (consistent with existing patterns)
      const warn = document.createElement('div');
      warn.style.cssText = 'position:fixed;inset:0;background:rgba(15,23,42,.88);display:flex;align-items:center;justify-content:center;z-index:999999;';
      warn.innerHTML = `
        <div style="background:#1e293b; border:1px solid #334155; border-radius:14px; max-width:440px; width:92%; padding:1.75rem; box-shadow:0 25px 50px -12px rgb(0 0 0 / 0.4);">
          <div style="display:flex; align-items:center; gap:0.6rem; margin-bottom:1rem; color:#fbbf24;">
            <i class="fas fa-exclamation-triangle" style="font-size:1.4rem;"></i>
            <strong style="font-size:1.15rem;">Service Unavailable</strong>
          </div>
          <div style="color:#e2e8f0; line-height:1.5; margin-bottom:1.5rem; font-size:0.95rem;">
            ${msg}
          </div>
          <div style="display:flex; gap:0.75rem; justify-content:flex-end;">
            <button class="btn-close-warn" style="padding:0.55rem 1.1rem; border-radius:8px; border:1px solid #334155; background:transparent; color:#e2e8f0; cursor:pointer; font-weight:500;">Close</button>
            <button class="btn-retry-warn" style="padding:0.55rem 1.1rem; border-radius:8px; background:#334155; color:white; border:none; cursor:pointer; font-weight:500;">Retry Check</button>
          </div>
        </div>
      `;
      document.body.appendChild(warn);

      warn.querySelector('.btn-close-warn').onclick = () => warn.remove();
      warn.querySelector('.btn-retry-warn').onclick = async () => {
        warn.remove();
        await openMonitoringTool(tool); // retry
      };
      warn.onclick = (e) => { if (e.target === warn) warn.remove(); };

      if (statusEl) {
        statusEl.innerHTML = `🔴 Unavailable`;
        statusEl.style.background = 'rgba(245,158,11,.15)';
        statusEl.style.color = '#f59e0b';
      }
      return;
    }

    // Success path
    if (statusEl) {
      statusEl.innerHTML = `🟢 Available`;
      statusEl.style.background = 'rgba(16,185,129,.15)';
      statusEl.style.color = '#10b981';
    }

    // Open in new tab (recommended for monitoring tools to keep dashboard open)
    const target = tool.url.startsWith('http') ? tool.url : tool.url;
    window.open(target, '_blank', 'noopener,noreferrer');
  }

  // Render the tools on init
  renderMonitoringTools();

  // Optional: re-check status of tools every 60 seconds
  setInterval(() => {
    MONITORING_TOOLS_CONFIG.forEach(tool => updateToolStatus(tool.id, tool.url));
  }, 60000);

  // =====================================================
  // Reusable function to show/hide "Open Live Monitor" button
  // =====================================================
  function updateLiveMonitorButtonVisibility(isReachable) {
    const btn = document.getElementById('btn-open-live-monitor');
    const instructions = document.getElementById('live-monitor-instructions');
    if (!btn || !instructions) return;

    if (isReachable) {
      btn.style.display = 'inline-flex';
      instructions.style.display = 'none';
    } else {
      btn.style.display = 'none';
      instructions.style.display = 'block';
    }
  }

  // =====================================================
  // "Open Live Monitor" button visibility + safety click handler
  // =====================================================
  const liveMonitorLink = document.getElementById('btn-open-live-monitor');
  const liveMonitorInstructions = document.getElementById('live-monitor-instructions');

  // Safety click handler
  if (liveMonitorLink) {
    liveMonitorLink.addEventListener('click', async (e) => {
      e.preventDefault();
      const targetUrl = liveMonitorLink.href;

      try {
        const res = await fetch('/api/monitor/status', {
          method: 'GET',
          cache: 'no-cache',
          headers: { 'Pragma': 'no-cache' }
        });

        let reachable = res.ok;
        if (res.ok) {
          const data = await res.json().catch(() => ({}));
          if (data.ok === false) reachable = false;
        }

        if (!reachable) throw new Error('Monitor not reachable');

        window.open(targetUrl, '_blank', 'noopener');
      } catch (err) {
        console.warn('%c[Dashboard] Live Monitor click blocked - not reachable', 'color:#f59e0b');
        if (liveMonitorLink) liveMonitorLink.style.display = 'none';
        if (liveMonitorInstructions) liveMonitorInstructions.style.display = 'block';
      }
    });
  }
}

initDashboardPage();
