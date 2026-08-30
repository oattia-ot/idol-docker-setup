/**
 * Monitor Page — Composition root
 * Wires everything together: state, polling, rendering, UI events
 */

import { getEl, delegate } from '../../core/ui/dom-utils.js';
import { showToast } from '../../core/ui/toast/toast.js';
import {
  getState,
  setServices,
  setFilter,
  setSelected,
  setActiveTab,
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
let tabsContainer;
let pollTimer = null;

const POLL_INTERVAL = 8000; // 8 seconds

function showLoadingSpinner() {
  if (!gridContainer) return;
  gridContainer.innerHTML = `
    <div style="padding:3rem 2rem; text-align:center; background:#1e293b; border:1px solid #334155; border-radius:12px;">
      <div class="loading-spinner" style="width:52px; height:52px; border-width:5px; margin:0 auto 1.25rem; border-color:#334155; border-top-color:#2563eb;"></div>
      <div style="font-size:1.15rem; font-weight:600; color:#e2e8f0; margin-bottom:0.5rem;">Fetching live service status...</div>
      <div style="font-size:0.95rem; color:#64748b; max-width:420px; margin:0 auto;">
        Collecting Docker container health &amp; metrics.<br>
        First load can take 5–15 seconds depending on number of IDOL services.
      </div>
    </div>
  `;
}

async function fetchStatus() {
  showLoadingSpinner();
  const startTime = performance.now();
  try {
    const res = await fetch('/api/status');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);

    const data = await res.json();
    const duration = Math.round(performance.now() - startTime);

    if (data.ok && Array.isArray(data.services)) {
      setServices(data.services);
      updateLastUpdated(data.timestamp || new Date().toISOString());

      const source = data.source || 'unknown';
      const healthy = data.summary?.healthy ?? 0;
      const degraded = data.summary?.degraded ?? 0;

      console.log(
        `%c[ServiceHealth] ✅ Fetched ${data.services.length} services in ${duration}ms | Healthy: ${healthy} | Degraded: ${degraded} | Source: ${source}`,
        'color:#22c55e'
      );

      if (data.services.length > 0) {
        console.groupCollapsed('%c[ServiceHealth] Service list (click to expand)', 'color:#64748b');
        data.services.forEach(s => {
          console.log(`  • ${s.name} (${s.status}) — CPU: ${s.cpu ?? '—'}% | MEM: ${s.memory ?? '—'}% | Port: ${s.port ?? '—'}`);
        });
        console.groupEnd();
      }

      showToast('Status refreshed', 'success', 1800);
    } else {
      throw new Error('Invalid response format');
    }
  } catch (err) {
    console.error('%c[ServiceHealth] ❌ Failed to fetch status:', 'color:#ef4444', err);
    showToast('Failed to fetch service status', 'error');

    // Hide summary stats when backend is not responding
    const summaryContainer = document.getElementById('summary-stats');
    if (summaryContainer) summaryContainer.style.display = 'none';

    // Show visible error in grid if still empty
    if (gridContainer && (!gridContainer.querySelector('.service-card') && !gridContainer.querySelector('.error-state'))) {
      gridContainer.innerHTML = `
        <div class="error-state" style="padding:2.5rem; text-align:center; background:#3f1f1f; border:1px solid #7f1d1d; border-radius:12px; color:#fca5a5;">
          <div style="font-size:1.05rem; margin-bottom:0.5rem;">⚠️ Unable to load service status</div>
          <div style="font-size:0.9rem; opacity:0.85; margin-bottom:1rem;">${err.message || 'Network or server error'}</div>
          <button onclick="location.reload()" style="padding:0.5rem 1.25rem; background:#7f1d1d; color:white; border:none; border-radius:6px; cursor:pointer; font-weight:600;">
            Retry
          </button>
        </div>
      `;
    }
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

  // Highlight active tab + update counts
  if (tabsContainer) {
    tabsContainer.querySelectorAll('.tab-btn').forEach(btn => {
      const isActive = btn.dataset.tab === state.activeTab;
      btn.classList.toggle('active', isActive);
    });

    // Update tab counts from summary if available
    const totalEl = document.getElementById('stat-total');
    // We use the full services list from state for counts
    const allServices = state.services || [];
    const demoCount = allServices.filter(s => s.group === 'idol-demo').length;
    const monCount = allServices.filter(s => s.group === 'monitoring').length;

    const demoCountEl = document.getElementById('tab-count-demo');
    const monCountEl = document.getElementById('tab-count-monitoring');
    if (demoCountEl) demoCountEl.textContent = demoCount;
    if (monCountEl) monCountEl.textContent = monCount;
  }

  // Update professional summary stats
  updateSummaryStats(state.services);
}

function updateSummaryStats(services) {
  const container = document.getElementById('summary-stats');
  const totalEl = document.getElementById('stat-total');
  const healthyEl = document.getElementById('stat-healthy');
  const degradedEl = document.getElementById('stat-degraded');

  if (!totalEl || !healthyEl || !degradedEl) return;

  const total = services.length;
  const healthy = services.filter(s => s.status === 'healthy').length;
  const degraded = services.filter(s => s.status === 'degraded').length;

  // Hide summary stats bar entirely when Live Monitor has no data (or backend not running)
  if (container) {
    container.style.display = (total === 0) ? 'none' : 'flex';
  }

  if (total > 0) {
    totalEl.textContent = total;
    healthyEl.textContent = healthy;
    degradedEl.textContent = degraded;
  } else {
    totalEl.textContent = '—';
    healthyEl.textContent = '—';
    degradedEl.textContent = '—';
  }
}

function setupFilters() {
  if (!filterContainer) return;

  delegate(filterContainer, 'click', '.filter-btn', (event, btn) => {
    const newFilter = btn.dataset.filter;
    if (newFilter) {
      console.log(`%c[ServiceHealth] 🔍 Filter changed → ${newFilter.toUpperCase()}`, 'color:#3b82f6');
      setFilter(newFilter);
    }
  });
}

function setupTabs() {
  if (!tabsContainer) return;

  delegate(tabsContainer, 'click', '.tab-btn', (event, btn) => {
    const newTab = btn.dataset.tab;
    if (newTab) {
      console.log(`%c[ServiceHealth] 📑 Tab switched → ${newTab.toUpperCase()}`, 'color:#8b5cf6');
      setActiveTab(newTab);
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
  console.log('%c[ServiceHealth] 🚀 Initializing Service Health Dashboard...', 'color:#64748b; font-weight:600');
  console.log('%c[ServiceHealth] Polling interval: ' + POLL_INTERVAL + 'ms', 'color:#64748b');

  // Grab DOM elements
  gridContainer   = getEl('#monitor-grid');
  detailContainer = getEl('#detail-panel');
  lastUpdatedEl   = getEl('#last-updated');
  refreshBtn      = getEl('#btn-refresh');
  filterContainer = getEl('#filters');
  tabsContainer   = getEl('#tabs');

  if (!gridContainer || !detailContainer) {
    console.error('%c[ServiceHealth] ❌ Required containers #monitor-grid or #detail-panel not found in DOM', 'color:#ef4444');
    return;
  }

  // Show initial professional loading state with process circle animation
  if (gridContainer) {
    showLoadingSpinner();
  }

  // Subscribe to state changes
  subscribe(updateUI);

  // Wire UI controls
  setupFilters();
  setupTabs();
  setupRefreshButton();

  // Set initial active tab visually (default is 'idol-demo')
  if (tabsContainer) {
    tabsContainer.querySelectorAll('.tab-btn').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.tab === 'idol-demo');
    });
  }

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
    showToast('Service Health Dashboard ready — polling every 8s', 'info', 2200);
  }, 1200);

  console.log('%c[ServiceHealth] ✅ Dashboard initialized successfully. Press F12 to see detailed logs.', 'color:#22c55e; font-weight:600');
}

// Auto-start when module loads
init();
