#!/bin/bash
set -euo pipefail

PROJECT="monitor-ui"
echo "🚀 Creating $PROJECT project structure..."

# Clean previous if exists (optional safety)
if [ -d "$PROJECT" ]; then
  echo "Removing existing $PROJECT directory..."
  rm -rf "$PROJECT"
fi

# Create directory structure
mkdir -p "$PROJECT/static/css/features/monitor"
mkdir -p "$PROJECT/static/js/core/ui/toast"
mkdir -p "$PROJECT/static/js/core/ui/modal"
mkdir -p "$PROJECT/static/js/features/monitor/state"
mkdir -p "$PROJECT/static/js/features/monitor/components"

echo "📁 Directories created."

# ============================================
# requirements.txt
# ============================================
cat > "$PROJECT/requirements.txt" << 'EOF'
flask>=3.0.0
EOF

# ============================================
# server.py - Flask backend
# ============================================
cat > "$PROJECT/server.py" << 'PYEOF'
#!/usr/bin/env python3
"""Flask backend for monitor-ui
   - Serves static files (HTML/CSS/JS)
   - Provides /api/status endpoint with mock service data
"""

from flask import Flask, jsonify, send_from_directory
from datetime import datetime, timezone

app = Flask(__name__, static_folder='static', static_url_path='')

# Mock service data (in real app this would come from DB, k8s, etc.)
SERVICES = [
    {
        "id": "svc-api",
        "name": "API Gateway",
        "status": "healthy",
        "uptime": "99.95%",
        "last_check": "2026-06-29T17:12:00Z",
        "version": "v2.4.1",
        "instances": 4
    },
    {
        "id": "svc-db",
        "name": "PostgreSQL Primary",
        "status": "degraded",
        "uptime": "97.80%",
        "last_check": "2026-06-29T17:10:30Z",
        "version": "15.7",
        "instances": 1
    },
    {
        "id": "svc-auth",
        "name": "Auth Service",
        "status": "healthy",
        "uptime": "99.99%",
        "last_check": "2026-06-29T17:13:15Z",
        "version": "v1.8.2",
        "instances": 3
    },
    {
        "id": "svc-cache",
        "name": "Redis Cluster",
        "status": "healthy",
        "uptime": "99.70%",
        "last_check": "2026-06-29T17:11:45Z",
        "version": "7.2.4",
        "instances": 6
    }
]

@app.route('/api/status')
def api_status():
    return jsonify({
        "ok": True,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "services": SERVICES,
        "summary": {
            "total": len(SERVICES),
            "healthy": sum(1 for s in SERVICES if s["status"] == "healthy"),
            "degraded": sum(1 for s in SERVICES if s["status"] == "degraded")
        }
    })

@app.route('/')
def index():
    return send_from_directory('static', 'config-monitor.html')

# Catch-all for static assets (css, js, etc.)
@app.route('/<path:path>')
def static_files(path):
    return send_from_directory('static', path)

if __name__ == '__main__':
    print("Starting Config Monitor UI on http://localhost:5000")
    app.run(host='0.0.0.0', port=5000, debug=True)
PYEOF

echo "✅ server.py created"

# ============================================
# static/config-monitor.html
# ============================================
cat > "$PROJECT/static/config-monitor.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Config Monitor • Live</title>
  <link rel="stylesheet" href="/css/features/monitor/monitor.css">
</head>
<body>
  <div class="app-container">
    <!-- Header -->
    <header class="app-header">
      <div class="header-left">
        <h1>⚙️ Config Monitor</h1>
        <span class="subtitle">Real-time service health</span>
      </div>
      <div class="header-right">
        <button id="btn-refresh" class="btn btn-primary">⟳ Refresh Now</button>
        <div class="last-updated">
          Last updated: <span id="last-updated">—</span>
        </div>
      </div>
    </header>

    <!-- Filters -->
    <div class="filters" id="filters">
      <button class="filter-btn active" data-filter="all">All</button>
      <button class="filter-btn" data-filter="healthy">✅ Healthy</button>
      <button class="filter-btn" data-filter="degraded">⚠️ Degraded</button>
    </div>

    <!-- Main Content -->
    <div class="main-content">
      <!-- Grid -->
      <section class="grid-section">
        <h2>Services</h2>
        <div id="monitor-grid" class="monitor-grid"></div>
      </section>

      <!-- Detail Panel -->
      <aside class="detail-panel">
        <h2>Service Details</h2>
        <div id="detail-panel">
          <p class="empty-state">Select a service from the grid to see details.</p>
        </div>
      </aside>
    </div>
  </div>

  <!-- Toast container (created by JS) -->
  <div id="toast-container"></div>

  <!-- Scripts -->
  <script type="module" src="/js/features/monitor/monitor.page.js"></script>
</body>
</html>
HTMLEOF

echo "✅ config-monitor.html created"

# ============================================
# CSS
# ============================================
cat > "$PROJECT/static/css/features/monitor/monitor.css" << 'CSSEOF'
:root {
  --primary: #2563eb;
  --success: #16a34a;
  --warning: #ca8a04;
  --danger: #dc2626;
  --bg: #0f172a;
  --card-bg: #1e293b;
  --text: #e2e8f0;
  --border: #334155;
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.5;
}

.app-container {
  max-width: 1400px;
  margin: 0 auto;
  padding: 2rem;
}

.app-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1.5rem;
  padding-bottom: 1rem;
  border-bottom: 1px solid var(--border);
}

.header-left h1 {
  margin: 0;
  font-size: 2rem;
}

.subtitle {
  color: #94a3b8;
  font-size: 0.95rem;
}

.header-right {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.last-updated {
  font-size: 0.875rem;
  color: #64748b;
}

.btn {
  padding: 0.5rem 1rem;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  font-weight: 600;
  transition: all 0.2s ease;
}

.btn-primary {
  background: var(--primary);
  color: white;
}

.btn-primary:hover {
  background: #1d4ed8;
}

.filters {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 1.5rem;
}

.filter-btn {
  padding: 0.5rem 1.25rem;
  background: var(--card-bg);
  border: 1px solid var(--border);
  color: var(--text);
  border-radius: 9999px;
  cursor: pointer;
  font-size: 0.9rem;
  transition: all 0.2s;
}

.filter-btn:hover {
  border-color: var(--primary);
}

.filter-btn.active {
  background: var(--primary);
  border-color: var(--primary);
  color: white;
}

.main-content {
  display: grid;
  grid-template-columns: 1fr 380px;
  gap: 2rem;
}

.monitor-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
  gap: 1rem;
}

.service-card {
  background: var(--card-bg);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 1.25rem;
  transition: transform 0.2s, box-shadow 0.2s;
  cursor: pointer;
}

.service-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 10px 15px -3px rgb(0 0 0 / 0.1);
}

.service-card.status-healthy {
  border-left: 5px solid var(--success);
}

.service-card.status-degraded {
  border-left: 5px solid var(--warning);
}

.service-card h3 {
  margin: 0 0 0.5rem;
  font-size: 1.1rem;
}

.status-badge {
  display: inline-block;
  padding: 0.15rem 0.6rem;
  border-radius: 9999px;
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.status-healthy .status-badge {
  background: #052e16;
  color: var(--success);
}

.status-degraded .status-badge {
  background: #451a03;
  color: var(--warning);
}

.service-meta {
  margin-top: 0.75rem;
  font-size: 0.875rem;
  color: #94a3b8;
}

.detail-panel {
  background: var(--card-bg);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 1.5rem;
  position: sticky;
  top: 2rem;
  align-self: start;
}

.detail-panel h2 {
  margin-top: 0;
  font-size: 1.25rem;
}

.empty-state {
  color: #64748b;
  font-style: italic;
}

.detail-grid {
  display: grid;
  gap: 0.75rem;
  margin-top: 1rem;
}

.detail-row {
  display: flex;
  justify-content: space-between;
  padding: 0.5rem 0;
  border-bottom: 1px solid var(--border);
}

.detail-row:last-child {
  border-bottom: none;
}

.detail-label {
  color: #94a3b8;
  font-size: 0.875rem;
}

.detail-value {
  font-weight: 600;
}

/* Toast */
#toast-container {
  position: fixed;
  bottom: 24px;
  right: 24px;
  z-index: 9999;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.toast {
  padding: 12px 20px;
  border-radius: 8px;
  color: white;
  font-weight: 500;
  box-shadow: 0 10px 15px -3px rgb(0 0 0 / 0.2);
  animation: slideIn 0.2s ease forwards;
  max-width: 320px;
}

.toast-success { background: #166534; }
.toast-error   { background: #991b1b; }
.toast-info    { background: #1e40af; }

@keyframes slideIn {
  from { transform: translateX(100%); opacity: 0; }
  to   { transform: translateX(0); opacity: 1; }
}
CSSEOF

echo "✅ monitor.css created"

# ============================================
# JS: core/ui/dom-utils.js
# ============================================
cat > "$PROJECT/static/js/core/ui/dom-utils.js" << 'JSEOF'
/**
 * DOM utility helpers
 * Used across the monitor UI for safe element selection and event delegation.
 */

/**
 * Get a single element (querySelector wrapper)
 * @param {string|Element} selector - CSS selector or element
 * @param {ParentNode} [parent=document]
 * @returns {Element|null}
 */
export function getEl(selector, parent = document) {
  if (!selector) return null;
  if (typeof selector === 'string') {
    return parent.querySelector(selector);
  }
  return selector; // already an element
}

/**
 * Event delegation helper
 * @param {Element} parent
 * @param {string} eventType - e.g. 'click'
 * @param {string} selector - target selector
 * @param {(event: Event, target: Element) => void} handler
 */
export function delegate(parent, eventType, selector, handler) {
  if (!parent) return;

  parent.addEventListener(eventType, (event) => {
    const target = event.target.closest(selector);
    if (target && parent.contains(target)) {
      handler(event, target);
    }
  });
}
JSEOF

echo "✅ dom-utils.js created"

# ============================================
# JS: core/ui/toast/toast.js
# ============================================
cat > "$PROJECT/static/js/core/ui/toast/toast.js" << 'JSEOF'
/**
 * Simple toast notification system
 */

let container = null;

function ensureContainer() {
  if (container) return container;
  container = document.getElementById('toast-container');
  if (!container) {
    container = document.createElement('div');
    container.id = 'toast-container';
    document.body.appendChild(container);
  }
  return container;
}

/**
 * Show a toast message
 * @param {string} message
 * @param {'success'|'error'|'info'} [type='info']
 * @param {number} [duration=3200]
 */
export function showToast(message, type = 'info', duration = 3200) {
  const c = ensureContainer();
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;

  c.appendChild(toast);

  // Auto dismiss
  setTimeout(() => {
    toast.style.transition = 'all 0.2s ease';
    toast.style.opacity = '0';
    setTimeout(() => toast.remove(), 200);
  }, duration);

  // Click to dismiss
  toast.addEventListener('click', () => toast.remove());
}
JSEOF

echo "✅ toast.js created"

# ============================================
# JS: core/ui/modal/modal.js
# ============================================
cat > "$PROJECT/static/js/core/ui/modal/modal.js" << 'JSEOF'
/**
 * Simple modal dialog
 */

let currentModal = null;

export function showModal(title, bodyHtml, options = {}) {
  closeModal(); // only one at a time

  const overlay = document.createElement('div');
  overlay.style.cssText = `
    position: fixed; inset: 0; background: rgba(15, 23, 42, 0.75);
    display: flex; align-items: center; justify-content: center; z-index: 99999;
  `;

  const modal = document.createElement('div');
  modal.style.cssText = `
    background: #1e293b; border: 1px solid #334155; border-radius: 12px;
    width: min(92%, 520px); box-shadow: 0 25px 50px -12px rgb(0 0 0 / 0.4);
    overflow: hidden;
  `;

  modal.innerHTML = `
    <div style="padding: 1rem 1.5rem; border-bottom: 1px solid #334155; display:flex; justify-content:space-between; align-items:center;">
      <h3 style="margin:0; font-size:1.1rem;">${title}</h3>
      <button class="modal-close" style="background:none;border:none;color:#94a3b8;font-size:1.5rem;cursor:pointer;line-height:1;">×</button>
    </div>
    <div style="padding: 1.5rem;">
      ${bodyHtml}
    </div>
    <div style="padding: 1rem 1.5rem; background:#0f172a; display:flex; justify-content:flex-end; gap:0.5rem;">
      <button class="btn-cancel" style="padding:0.5rem 1rem; border-radius:6px; border:1px solid #334155; background:transparent; color:#e2e8f0; cursor:pointer;">Close</button>
    </div>
  `;

  overlay.appendChild(modal);
  document.body.appendChild(overlay);
  currentModal = overlay;

  // Close handlers
  const closeBtn = modal.querySelector('.modal-close');
  const cancelBtn = modal.querySelector('.btn-cancel');

  const closeHandler = () => closeModal();
  closeBtn.addEventListener('click', closeHandler);
  cancelBtn.addEventListener('click', closeHandler);
  overlay.addEventListener('click', (e) => {
    if (e.target === overlay) closeModal();
  });

  // Optional onClose callback
  if (typeof options.onClose === 'function') {
    overlay._onClose = options.onClose;
  }
}

export function closeModal() {
  if (currentModal) {
    if (currentModal._onClose) currentModal._onClose();
    currentModal.remove();
    currentModal = null;
  }
}
JSEOF

echo "✅ modal.js created"

# ============================================
# JS: features/monitor/state/monitor-state.js
# ============================================
cat > "$PROJECT/static/js/features/monitor/state/monitor-state.js" << 'JSEOF'
/**
 * Simple reactive state store for the monitor
 */

let state = {
  services: [],
  filter: 'all',        // 'all' | 'healthy' | 'degraded'
  selectedId: null,
  lastUpdated: null
};

const listeners = new Set();

function notify() {
  const snapshot = getState();
  listeners.forEach(fn => {
    try { fn(snapshot); } catch (e) { console.error(e); }
  });
}

export function getState() {
  return {
    services: [...state.services],
    filter: state.filter,
    selectedId: state.selectedId,
    lastUpdated: state.lastUpdated
  };
}

export function setServices(services) {
  state.services = Array.isArray(services) ? services : [];
  state.lastUpdated = new Date().toISOString();
  notify();
}

export function setFilter(filter) {
  if (['all', 'healthy', 'degraded'].includes(filter)) {
    state.filter = filter;
    notify();
  }
}

export function setSelected(id) {
  state.selectedId = id || null;
  notify();
}

export function subscribe(listener) {
  listeners.add(listener);
  // Immediately call with current state
  listener(getState());
  return () => listeners.delete(listener);
}

export function getFilteredServices() {
  const { services, filter } = state;
  if (filter === 'all') return services;
  return services.filter(s => s.status === filter);
}

export function getSelectedService() {
  if (!state.selectedId) return null;
  return state.services.find(s => s.id === state.selectedId) || null;
}
JSEOF

echo "✅ monitor-state.js created"

# ============================================
# JS: features/monitor/components/monitor-grid.js
# ============================================
cat > "$PROJECT/static/js/features/monitor/components/monitor-grid.js" << 'JSEOF'
/**
 * Render functions for the monitor grid and detail panel
 */

import { showModal } from '../../../core/ui/modal/modal.js';

/**
 * Render the grid of service cards
 */
export function renderGrid(services, container, onCardClick) {
  if (!container) return;
  container.innerHTML = '';

  if (!services.length) {
    container.innerHTML = `<div class="empty-state" style="padding:2rem; text-align:center;">No services match current filter.</div>`;
    return;
  }

  const grid = document.createElement('div');
  grid.className = 'monitor-grid';

  services.forEach(service => {
    const card = document.createElement('div');
    card.className = `service-card status-${service.status}`;
    card.innerHTML = `
      <div style="display:flex; justify-content:space-between; align-items:start;">
        <h3 style="margin:0;">${service.name}</h3>
        <span class="status-badge">${service.status}</span>
      </div>
      <div class="service-meta">
        <div>Uptime: <strong>${service.uptime}</strong></div>
        <div>Instances: ${service.instances || 1}</div>
        <div style="margin-top:0.25rem; font-size:0.75rem; opacity:0.7;">
          Last check: ${new Date(service.last_check).toLocaleTimeString()}
        </div>
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
  const html = `
    <div style="display:grid; gap:0.75rem;">
      <div><strong>Version:</strong> ${service.version || '—'}</div>
      <div><strong>Status:</strong> <span style="color:${service.status === 'healthy' ? '#16a34a' : '#ca8a04'}">${service.status}</span></div>
      <div><strong>Uptime:</strong> ${service.uptime}</div>
      <div><strong>Instances:</strong> ${service.instances || 1}</div>
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
      <div style="display:flex; align-items:center; gap:0.75rem;">
        <h3 style="margin:0; flex:1;">${service.name}</h3>
        <span class="status-badge" style="background:${service.status === 'healthy' ? '#052e16' : '#451a03'}; color:${statusColor};">
          ${service.status}
        </span>
      </div>
    </div>

    <div class="detail-grid">
      <div class="detail-row">
        <span class="detail-label">Version</span>
        <span class="detail-value">${service.version || '—'}</span>
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
JSEOF

echo "✅ monitor-grid.js created"

# ============================================
# JS: features/monitor/monitor.page.js  (Composition root)
# ============================================
cat > "$PROJECT/static/js/features/monitor/monitor.page.js" << 'JSEOF'
/**
 * Monitor Page — Composition root
 * Wires everything together: state, polling, rendering, UI events
 */

import { getEl, delegate } from '../../../core/ui/dom-utils.js';
import { showToast } from '../../../core/ui/toast/toast.js';
import {
  getState,
  setServices,
  setFilter,
  setSelected,
  subscribe,
  getFilteredServices,
  getSelectedService
} from './state/monitor-state.js';
import { renderGrid, renderDetailPanel } from './components/monitor-grid.js';

// DOM refs
let gridContainer;
let detailContainer;
let lastUpdatedEl;
let refreshBtn;
let filterContainer;
let pollTimer = null;

const POLL_INTERVAL = 8000; // 8 seconds

async function fetchStatus() {
  try {
    const res = await fetch('/api/status');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);

    const data = await res.json();

    if (data.ok && Array.isArray(data.services)) {
      setServices(data.services);
      updateLastUpdated(data.timestamp || new Date().toISOString());
      showToast('Status refreshed', 'success', 1800);
    } else {
      throw new Error('Invalid response format');
    }
  } catch (err) {
    console.error('Failed to fetch status:', err);
    showToast('Failed to fetch service status', 'error');
  }
}

function updateLastUpdated(isoString) {
  if (!lastUpdatedEl) return;
  try {
    const date = new Date(isoString);
    lastUpdatedEl.textContent = date.toLocaleTimeString([], {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    });
  } catch {
    lastUpdatedEl.textContent = 'just now';
  }
}

function updateUI(state) {
  // Render filtered grid
  const filtered = getFilteredServices();
  renderGrid(filtered, gridContainer, (serviceId) => {
    setSelected(serviceId);
  });

  // Render detail panel
  const selected = getSelectedService();
  renderDetailPanel(selected, detailContainer);

  // Highlight active filter button
  if (filterContainer) {
    filterContainer.querySelectorAll('.filter-btn').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.filter === state.filter);
    });
  }
}

function setupFilters() {
  if (!filterContainer) return;

  delegate(filterContainer, 'click', '.filter-btn', (event, btn) => {
    const newFilter = btn.dataset.filter;
    if (newFilter) {
      setFilter(newFilter);
    }
  });
}

function setupRefreshButton() {
  if (!refreshBtn) return;

  refreshBtn.addEventListener('click', async () => {
    refreshBtn.disabled = true;
    refreshBtn.textContent = '⟳ Refreshing...';
    await fetchStatus();
    refreshBtn.disabled = false;
    refreshBtn.textContent = '⟳ Refresh Now';
  });
}

function startPolling() {
  if (pollTimer) clearInterval(pollTimer);

  // Initial fetch
  fetchStatus();

  // Then poll
  pollTimer = setInterval(fetchStatus, POLL_INTERVAL);
}

function init() {
  // Grab DOM elements
  gridContainer   = getEl('#monitor-grid');
  detailContainer = getEl('#detail-panel');
  lastUpdatedEl   = getEl('#last-updated');
  refreshBtn      = getEl('#btn-refresh');
  filterContainer = getEl('#filters');

  if (!gridContainer || !detailContainer) {
    console.error('Required containers #monitor-grid or #detail-panel not found in DOM');
    return;
  }

  // Subscribe to state changes
  subscribe(updateUI);

  // Wire UI controls
  setupFilters();
  setupRefreshButton();

  // Keyboard support (press R to refresh)
  document.addEventListener('keydown', (e) => {
    if (e.key.toLowerCase() === 'r' && document.activeElement.tagName === 'BODY') {
      e.preventDefault();
      fetchStatus();
    }
  });

  // Boot polling + initial render
  startPolling();

  // Show welcome toast once
  setTimeout(() => {
    showToast('Monitor UI ready — polling every 8s', 'info', 2200);
  }, 1200);

  console.log('%c[monitor] Config Monitor page initialized', 'color:#64748b');
}

// Auto-start when module loads
init();
JSEOF

echo "✅ monitor.page.js created"

# ============================================
# Final message
# ============================================
echo ""
echo "✅✅✅  monitor-ui project created successfully!"
echo ""
echo "Next steps:"
echo "  cd $PROJECT"
echo "  python3 -m venv .venv && source .venv/bin/activate"
echo "  pip install -r requirements.txt"
echo "  python server.py"
echo ""
echo "Then open http://localhost:5000 in your browser."
echo "The UI will poll /api/status every 8 seconds and show live service health."
echo ""
