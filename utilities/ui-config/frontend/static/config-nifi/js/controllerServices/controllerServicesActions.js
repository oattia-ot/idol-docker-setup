import { API_BASE } from '../config/constants.js';
import { showAlert, showToast } from '../core/notifications.js';
import { confirmDialog, showProgress } from '../core/dialogs.js';
import { state } from '../core/state.js';
import { updateServiceRowStatus, loadControllerServices } from './controllerServicesList.js';

export async function getControllerService(id) {
  const res = await fetch(`${API_BASE}/controller-services/${id}`);
  const data = await res.json();
  if (!data.success || !data.data) throw new Error(data.error || 'Failed to fetch service');
  return data.data;
}

function pollUntilState(id, targetState, onDone) {
  return new Promise((resolve) => {
    let count = 0;
    const timer = setInterval(async () => {
      count++;
      try {
        const check = await (await fetch(`${API_BASE}/controller-services/${id}`)).json();
        const current = check.data?.component?.state || check.data?.state || 'UNKNOWN';

        // Keep the cached service object in sync. Without this, buildActionHtml()
        // and the State badge kept reading the pre-action value from
        // state.allControllerServices and never reflected the real outcome of
        // pressing Enable/Disable until the whole table was reloaded.
        const svc = state.allControllerServices.find((s) => s.id === id);
        if (svc) svc.state = current;

        if (current === targetState || count >= 10) {
          clearInterval(timer);
          onDone();
          resolve();
        }
      } catch (e) {
        console.error('Poll error:', e);
      }
    }, 1000);
  });
}

export async function enableControllerService(id) {
  state.serviceOperationStatus[id] = { state: 'enabling' };
  updateServiceRowStatus(id);

  try {
    const svc = await getControllerService(id);
    const version = svc.revision?.version || svc.component?.revision?.version || 0;

    await fetch(`${API_BASE}/controller-services/${id}/enable?version=${version}`, { method: 'POST' });

    await pollUntilState(id, 'ENABLED', () => {
      state.serviceOperationStatus[id] = { state: 'success', message: 'Enabled' };
      updateServiceRowStatus(id);
      setTimeout(() => { delete state.serviceOperationStatus[id]; updateServiceRowStatus(id); }, 3000);
    });
  } catch (e) {
    console.error(`[ENABLE] Failed ${id}:`, e);
    state.serviceOperationStatus[id] = { state: 'error' };
    updateServiceRowStatus(id);
    setTimeout(() => { delete state.serviceOperationStatus[id]; updateServiceRowStatus(id); }, 4000);
  }
}

export async function disableControllerService(id) {
  state.serviceOperationStatus[id] = { state: 'disabling' };
  updateServiceRowStatus(id);

  try {
    const svc = await getControllerService(id);
    const version = svc.revision?.version || svc.component?.revision?.version || 0;

    await fetch(`${API_BASE}/controller-services/${id}/disable?version=${version}`, { method: 'POST' });

    await pollUntilState(id, 'DISABLED', () => {
      state.serviceOperationStatus[id] = { state: 'success', message: 'Disabled' };
      updateServiceRowStatus(id);
      setTimeout(() => { delete state.serviceOperationStatus[id]; updateServiceRowStatus(id); }, 3000);
    });
  } catch (e) {
    console.error(`[DISABLE] Failed ${id}:`, e);
    state.serviceOperationStatus[id] = { state: 'error' };
    updateServiceRowStatus(id);
    setTimeout(() => { delete state.serviceOperationStatus[id]; updateServiceRowStatus(id); }, 4000);
  }
}

export async function bulkEnableServices() {
  if (!state.allControllerServices.length) { showAlert('No services available', 'warning'); return; }

  const toEnable = state.allControllerServices.filter((svc) => {
    const s = (svc.state || '').toUpperCase();
    return s !== 'ENABLED' && s !== 'ENABLING';
  });

  if (toEnable.length === 0) { showAlert('All services are already enabled or currently being enabled', 'info'); return; }

  const ok = await confirmDialog(`Enable ${toEnable.length} service(s)?`, { confirmText: 'Enable', title: 'Bulk Enable Services' });
  if (!ok) return;

  const progress = showProgress(`Enabling ${toEnable.length} services...`);

  let success = 0, failed = 0;
  for (const svc of toEnable) {
    try {
      await enableControllerService(svc.id);
      success++;
      progress.update(`Enabled: ${svc.name || svc.id}`);
    } catch (e) {
      failed++;
      progress.update(`Failed: ${svc.name || svc.id}`);
      console.error(`Failed to enable ${svc.name || svc.id}`, e);
    }
    await new Promise((r) => setTimeout(r, 700));
  }

  progress.close();
  showToast(`Bulk enable completed: ${success} succeeded, ${failed} failed`, failed ? 'var(--warning)' : 'var(--success)');
}

export async function bulkDisableServices() {
  if (!state.allControllerServices.length) { showAlert('No services to disable', 'warning'); return; }

  const toDisable = state.allControllerServices.filter((svc) => {
    const s = (svc.state || '').toUpperCase();
    return s !== 'DISABLED' && s !== 'DISABLING';
  });

  if (toDisable.length === 0) { showAlert('All services are already disabled or currently being disabled', 'info'); return; }

  const ok = await confirmDialog(`Disable ${toDisable.length} service(s)?`, { confirmText: 'Disable', title: 'Bulk Disable Services', danger: true });
  if (!ok) return;

  const progress = showProgress(`Disabling ${toDisable.length} services...`);

  let success = 0, failed = 0;
  for (const svc of toDisable) {
    try {
      await disableControllerService(svc.id);
      success++;
      progress.update(`Disabled: ${svc.name || svc.id}`);
    } catch {
      failed++;
      progress.update(`Failed: ${svc.name || svc.id}`);
    }
    await new Promise((r) => setTimeout(r, 700));
  }

  progress.close();
  showToast(`Bulk disable completed: ${success} succeeded, ${failed} failed`, failed ? 'var(--warning)' : 'var(--success)');
}

/** Used internally by host-flow "reset & import" — disables all without confirm dialog. */
export async function bulkDisableServicesInternal() {
  if (!state.allControllerServices.length) return;

  const toDisable = state.allControllerServices.filter((svc) => !['DISABLED', 'DISABLING'].includes(svc.state || ''));
  if (toDisable.length === 0) return;

  let success = 0, failed = 0;
  for (const svc of toDisable) {
    try { await disableControllerService(svc.id); success++; } catch { failed++; }
    await new Promise((r) => setTimeout(r, 700));
  }

  console.log(`[RESET] Bulk disabled ${success} services (${failed} failed)`);
}

export async function deleteControllerService(id) {
  console.log(`[CS] Requesting inline delete confirmation for ${id}`);
  const triggerBtn = document.querySelector(`button[onclick*="deleteControllerService('${id}')"]`);
  if (!triggerBtn) { await executeDeleteControllerService(id); return; }
  if (document.getElementById(`delete-confirm-cs-${id}`)) return;

  const banner = document.createElement('div');
  banner.id = `delete-confirm-cs-${id}`;
  banner.style.cssText = `display:flex; align-items:center; gap:12px; flex-wrap:wrap; margin:8px 0; padding:12px 16px; border-radius:8px; background:#1e2937; border:2px solid #e05252; font-size:13px; color:#f1f5f9;`;
  banner.innerHTML = `<span style="flex:1; min-width:240px;">⚠️ <strong>Delete this Controller Service?</strong><br><span style="font-size:12px; color:#94a3b8;">It will be disabled first, then deleted after a short delay.</span></span><button id="confirm-yes-cs-${id}" class="btn btn-danger btn-sm" style="padding:6px 16px;">Yes, delete</button><button id="confirm-no-cs-${id}" class="btn btn-secondary btn-sm" style="padding:6px 14px;">Cancel</button>`;

  const row = triggerBtn.closest('tr');
  if (row) row.insertAdjacentElement('afterend', banner);
  triggerBtn.disabled = true;

  const cleanup = () => { banner.remove(); triggerBtn.disabled = false; };

  document.getElementById(`confirm-yes-cs-${id}`).addEventListener('click', async () => { cleanup(); await executeDeleteControllerService(id); });
  document.getElementById(`confirm-no-cs-${id}`).addEventListener('click', cleanup);
}

async function executeDeleteControllerService(id) {
  console.log(`[CS SAFE DELETE] Starting for ${id}`);
  try {
    showToast('Disabling service before deletion...', 'var(--info)');
    await disableControllerService(id);
    const delay = 3000;
    showToast(`Waiting ${delay / 1000} seconds before deleting...`, 'var(--info)');
    await new Promise((r) => setTimeout(r, delay));

    const svcRes = await fetch(`${API_BASE}/controller-services/${id}`);
    const svcData = await svcRes.json();
    const version = svcData.data?.revision?.version;
    if (!version) throw new Error('Could not get revision version');

    const res = await fetch(`${API_BASE}/controller-services/${id}?version=${version}`, { method: 'DELETE' });
    const data = await res.json();

    if (data.success) {
      showToast('✅ Controller service deleted successfully', 'var(--success)');
      loadControllerServices();
    } else {
      throw new Error(data.error || data.message || 'Delete failed');
    }
  } catch (err) {
    console.error('[CS SAFE DELETE] Error:', err);
    showAlert(`Delete failed: ${err.message}`, 'error');
    loadControllerServices();
  }
}
