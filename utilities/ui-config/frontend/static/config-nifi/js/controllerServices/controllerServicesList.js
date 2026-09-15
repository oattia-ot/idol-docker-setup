import { API_BASE } from '../config/constants.js';
import { LOAD_THROTTLE_MS } from '../config/constants.js';
import { getEl, escapeHtml } from '../core/domUtils.js';
import { state } from '../core/state.js';

/** Re-render the State badge cell and action buttons cell for a single service row. */
export function updateServiceRowStatus(id) {
  const row = document.querySelector(`tr[data-service-id="${id}"]`);
  if (!row) return;

  const svc = state.allControllerServices.find((s) => s.id === id);
  if (!svc) return;

  // The State badge used to only update on a full table reload, so it kept
  // showing the pre-action value right after pressing Enable/Disable.
  const stateCell = row.cells[3];
  if (stateCell) {
    stateCell.innerHTML = `<span class="badge ${svc.state === 'ENABLED' ? 'bg-success' : 'bg-secondary'}">${svc.state || 'UNKNOWN'}</span>`;
  }

  const actionHTML = buildActionHtml(svc);
  const actionCell = row.cells[5];
  if (actionCell) {
    actionCell.innerHTML = `<div class="btn-group" style="gap:6px;">${actionHTML}</div>`;
  }
}

function buildActionHtml(svc) {
  const op = state.serviceOperationStatus[svc.id] || {};

  if (op.state === 'enabling') return `<span class="text-info"><i class="fas fa-spinner fa-spin"></i> Enabling...</span>`;
  if (op.state === 'disabling') return `<span class="text-warning"><i class="fas fa-spinner fa-spin"></i> Disabling...</span>`;
  if (op.state === 'success') return `<span class="text-success"><i class="fas fa-check"></i> ${op.message || 'Done'}</span>`;
  if (op.state === 'error') return `<span class="text-danger"><i class="fas fa-times"></i> Failed</span>`;

  let btns = '';

  // STRICT per user request:
  // - DISABLED state → ONLY Edit button shown (View is hidden)
  // - ENABLED state  → ONLY View button shown (Edit is hidden)
  if (svc.state === 'DISABLED') {
    btns += `<button class="btn btn-primary btn-sm" onclick="editControllerService('${svc.id}')"><i class="fas fa-edit"></i> Edit</button>`;
    btns += `<button class="btn btn-success btn-sm" onclick="enableControllerService('${svc.id}')"><i class="fas fa-play"></i> Enable</button>`;
  } else {
    btns += `<button class="btn btn-info btn-sm" onclick="viewControllerService('${svc.id}')"><i class="fas fa-eye"></i> View</button>`;
    btns += `<button class="btn btn-warning btn-sm" onclick="disableControllerService('${svc.id}')"><i class="fas fa-pause"></i> Disable</button>`;
  }

  btns += `<button class="btn btn-danger btn-sm" onclick="deleteControllerService('${svc.id}')"><i class="fas fa-trash"></i> Delete</button>`;
  return btns;
}

/** @param {boolean} [force] */
export async function loadControllerServices(force = false) {
  const now = Date.now();

  if (state.isReloading && !force) { console.log('[CS] Already loading, skipping...'); return; }
  if (!force && (now - state.lastLoadTime < LOAD_THROTTLE_MS)) { console.log('[CS] Throttled, skipping...'); return; }

  state.isReloading = true;
  state.lastLoadTime = now;

  const tbody = getEl('controllerServicesTableBody');
  const noMsg = getEl('noControllerServicesMessage');
  const countSpan = getEl('controllerServiceCount');
  const table = getEl('controllerServicesTable');

  if (tbody) {
    tbody.innerHTML = `<tr><td colspan="6" style="text-align:center;padding:40px;">
            <i class="fas fa-spinner fa-spin fa-2x"></i><br><br>
            <strong>Loading Controller Services...</strong>
        </td></tr>`;
  }
  if (noMsg) noMsg.style.display = 'none';

  try {
    const res = await fetch(`${API_BASE}/controller-services/list`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);

    const data = await res.json();
    if (!data.success) throw new Error(data.error || 'Failed to load');

    state.allControllerServices = data.data || [];

    if (state.allControllerServices.length === 0) {
      if (table) table.style.display = 'none';
      if (noMsg) noMsg.style.display = 'block';
      if (countSpan) countSpan.textContent = '0 services';
      return;
    }

    if (table) table.style.display = 'table';
    if (noMsg) noMsg.style.display = 'none';
    if (countSpan) countSpan.textContent = `${state.allControllerServices.length} service${state.allControllerServices.length !== 1 ? 's' : ''}`;

    tbody.innerHTML = '';

    state.allControllerServices.forEach((svc) => {
      const row = tbody.insertRow();
      row.setAttribute('data-service-id', svc.id);
      const actionHTML = buildActionHtml(svc);

      row.innerHTML = `
                <td><strong>${escapeHtml(svc.name)}</strong><br><small class="text-muted">${escapeHtml(svc.id)}</small></td>
                <td><small>${escapeHtml(svc.type)}</small></td>
                <td>${escapeHtml(svc.process_group_path || '—')}</td>
                <td><span class="badge ${svc.state === 'ENABLED' ? 'bg-success' : 'bg-secondary'}">${svc.state || 'UNKNOWN'}</span></td>
                <td><span class="badge ${svc.validation_status === 'INVALID' ? 'bg-danger' : 'bg-success'}">${svc.validation_status || 'OK'}</span></td>
                <td style="text-align:center">
                    <div class="btn-group" style="gap:6px;">${actionHTML}</div>
                </td>
            `;
    });
  } catch (e) {
    console.error('[CS] Load failed:', e);
    if (tbody) {
      tbody.innerHTML = `<tr><td colspan="6" class="alert alert-error" style="text-align:center;padding:30px;">
                ${escapeHtml(e.message)}<br>
                <button onclick="loadControllerServices(true)" class="btn btn-primary btn-sm mt-2"><i class="fas fa-sync-alt"></i> Retry</button>
            </td></tr>`;
    }
  } finally {
    state.isReloading = false;
  }
}

export function debouncedLoadServices() {
  clearTimeout(state.controllerDebounce);
  state.controllerDebounce = setTimeout(() => {
    if (!state.isReloading) loadControllerServices();
  }, 800);
}

export function clearControllerServiceFilters() {
  console.log('[CS] Clearing filters');
  ['filterState', 'filterName', 'filterType', 'filterLocation'].forEach((id) => {
    const el = getEl(id);
    if (el) el.value = '';
  });
  loadControllerServices(true);
}

export async function exportControllerServices() {
  console.log('[CS] Exporting controller services...');
  const { showToast, showAlert } = await import('../core/notifications.js');
  try {
    const response = await fetch(`${API_BASE}/controller-services/export`);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    const contentDisposition = response.headers.get('Content-Disposition');
    let filename = `controller_services_export_${new Date().toISOString().slice(0, 19).replace(/:/g, '-')}.json`;
    if (contentDisposition) {
      const match = contentDisposition.match(/filename="?(.+)"?/);
      if (match) filename = match[1];
    }
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    showToast('✅ Controller services exported', 'var(--success)');
  } catch (err) {
    console.error('[CS] Export error:', err);
    showAlert(`Export failed: ${err.message}`, 'error');
  }
}
