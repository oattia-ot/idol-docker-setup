import { API_BASE } from '../config/constants.js';
import { escapeHtml } from '../core/domUtils.js';
import { state } from '../core/state.js';

export function debouncedFilterParamContexts() {
  clearTimeout(state.paramFilterTimeout);
  state.paramFilterTimeout = setTimeout(() => {
    state.paramContextFilter = document.getElementById('paramFilterName')?.value.toLowerCase() || '';
    renderParamContextsTable(state.allParamContexts);
  }, 300);
}

/** @param {Array<Object>} contexts */
export function renderParamContextsTable(contexts) {
  const tbody = document.getElementById('paramContextsTableBody');
  const noMsg = document.getElementById('noParamContextsMessage');
  const countSpan = document.getElementById('paramContextCount');

  if (!Array.isArray(contexts)) contexts = [];

  let filtered = contexts;
  if (state.paramContextFilter) {
    filtered = contexts.filter((ctx) => {
      const name = (ctx.component?.name || ctx.name || '').toLowerCase();
      return name.includes(state.paramContextFilter.toLowerCase());
    });
  }

  if (!filtered.length) {
    tbody.innerHTML = '';
    if (noMsg) noMsg.style.display = 'block';
    if (countSpan) countSpan.textContent = '0 contexts';
    return;
  }

  if (noMsg) noMsg.style.display = 'none';
  if (countSpan) countSpan.textContent = `${filtered.length} context${filtered.length !== 1 ? 's' : ''}`;

  let html = '';
  filtered.forEach((ctx) => {
    const component = ctx.component || ctx;
    const ctxId = ctx.id || component.id || 'unknown';
    const name = escapeHtml(component.name || 'Unnamed Context');
    const description = escapeHtml(component.description || '');
    const paramCount = Array.isArray(component.parameters) ? component.parameters.length : 0;

    html += `
            <tr>
                <td><strong>${name}</strong>
                    ${description ? `<br><small class="text-muted">${description}</small>` : ''}
                </td>
                <td><small class="text-muted">${ctxId}</small></td>
                <td>
                    <span class="badge ${paramCount > 0 ? 'badge-success' : 'badge-secondary'}">
                        ${paramCount} parameter${paramCount !== 1 ? 's' : ''}
                    </span>
                </td>
                <td style="text-align:center">
                    <div class="btn-group" style="gap:6px;">
                        <button class="btn btn-warning btn-sm" onclick="showUpdateParamContext('${ctxId}')" style="min-width:70px;">
                            <i class="fas fa-edit"></i> Edit
                        </button>
                        <button class="btn btn-danger btn-sm" onclick="deleteParamContext('${ctxId}')" style="min-width:70px;">
                            <i class="fas fa-trash"></i> Delete
                        </button>
                    </div>
                </td>
            </tr>`;
  });

  tbody.innerHTML = html;
}

export async function listParamContexts() {
  const tbody = document.getElementById('paramContextsTableBody');
  const noMsg = document.getElementById('noParamContextsMessage');

  if (tbody) {
    tbody.innerHTML = `<tr><td colspan="5" style="text-align:center;padding:40px;">
        <i class="fas fa-spinner fa-spin"></i> Loading Parameter Contexts...</td></tr>`;
  }
  if (noMsg) noMsg.style.display = 'none';

  try {
    const res = await fetch(`${API_BASE}/parameter-contexts`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);

    const data = await res.json();
    if (!data.success) throw new Error(data.error || 'Failed to load');

    const contexts = data.data?.parameterContexts || [];
    console.log(`[PARAM_CTX] Loaded ${contexts.length} contexts from overview`);

    const fullContexts = [];
    for (const ctx of contexts) {
      try {
        const fullRes = await fetch(`${API_BASE}/parameter-contexts/${ctx.id || ctx.component?.id}`);
        const fullData = await fullRes.json();
        fullContexts.push(fullData.success ? fullData.data : ctx);
      } catch {
        fullContexts.push(ctx);
      }
    }

    state.allParamContexts = fullContexts;
    renderParamContextsTable(fullContexts);
  } catch (err) {
    console.error('[PARAM_CTX] Load failed:', err);
    if (tbody) {
      tbody.innerHTML = `<tr><td colspan="5" class="alert alert-error">
                <i class="fas fa-exclamation-triangle"></i> ${err.message}<br>
                <button class="btn btn-sm btn-primary mt-2" onclick="listParamContexts()">Retry</button>
            </td></tr>`;
    }
  }
}

export async function deleteParamContext(id) {
  console.log(`[PARAM_CTX] Delete requested for context: ${id}`);
  if (document.getElementById(`delete-confirm-pc-${id}`)) return;

  const triggerBtn = document.querySelector(`[onclick*="deleteParamContext('${id}')"]`);

  const banner = document.createElement('div');
  banner.id = `delete-confirm-pc-${id}`;
  banner.style.cssText = `
    display: flex; align-items: center; gap: 12px; margin: 8px 0; padding: 12px 16px;
    border-radius: 8px; background: #1e2937; border: 2px solid #ef4444; font-size: 13px;
    color: #f1f5f9; animation: fadeIn 0.2s ease;`;
  banner.innerHTML = `
    <span style="flex:1;">
        ⚠️ <strong>Permanently delete this Parameter Context?</strong><br>
        <small style="color:#94a3b8;">This action cannot be undone. All referencing Process Groups will lose these parameters.</small>
    </span>
    <button id="confirm-yes-pc-${id}" class="btn btn-danger btn-sm" style="padding:6px 16px; white-space:nowrap;">Yes, Delete</button>
    <button id="confirm-no-pc-${id}" class="btn btn-secondary btn-sm" style="padding:6px 14px;">Cancel</button>`;

  const row = triggerBtn ? triggerBtn.closest('tr') : null;
  if (row) {
    row.insertAdjacentElement('afterend', banner);
    triggerBtn.disabled = true;
  } else {
    document.getElementById('paramContextsTableBody')?.appendChild(banner);
  }

  const cleanup = () => {
    banner.remove();
    if (triggerBtn) triggerBtn.disabled = false;
  };

  document.getElementById(`confirm-yes-pc-${id}`).addEventListener('click', async () => {
    cleanup();
    await executeDeleteParamContext(id);
  });
  document.getElementById(`confirm-no-pc-${id}`).addEventListener('click', cleanup);
}

async function executeDeleteParamContext(id) {
  console.log(`[PARAM_CTX] Executing permanent delete for ${id}`);
  const { showToast } = await import('../core/notifications.js');
  const { showAlert } = await import('../core/notifications.js');
  try {
    showToast('Fetching current revision...', 'var(--info)');
    const getRes = await fetch(`${API_BASE}/parameter-contexts/${id}`);
    const getData = await getRes.json();
    if (!getData.success) throw new Error('Could not fetch context for deletion');

    const version = getData.data.revision?.version;
    if (version === undefined) throw new Error('No revision version found');

    const delRes = await fetch(`${API_BASE}/parameter-contexts/${id}?version=${version}`, { method: 'DELETE' });
    const delData = await delRes.json();

    if (delData.success) {
      showToast('✅ Parameter Context permanently deleted', 'var(--success)');
      listParamContexts();
    } else {
      throw new Error(delData.error || 'Delete failed');
    }
  } catch (e) {
    console.error('[PARAM_CTX] Delete failed:', e);
    showAlert('Delete failed: ' + e.message, 'error');
    listParamContexts();
  }
}

// ============================================================
// BULK DELETE ALL PARAMETER CONTEXTS
// ============================================================
export async function clearAllParameterContexts() {
  console.log('[PARAM_CTX] clearAllParameterContexts() called');

  const { showToast, showAlert } = await import('../core/notifications.js');
  const { confirmDialog, showProgress } = await import('../core/dialogs.js');

  // Single inline confirmation (a second native window.confirm() used to live
  // in the button's onclick attribute in the HTML — removed since it
  // duplicated this one and broke the "all dialogs are inline" UX).
  const ok = await confirmDialog(
    '⚠️ FINAL WARNING: This will PERMANENTLY DELETE ALL Parameter Contexts in NiFi.\n\nThis action cannot be undone. Many contexts are usually referenced by Process Groups and may fail to delete.\n\nContinue?',
    { title: 'Delete All Parameter Contexts', confirmText: 'Delete All', danger: true }
  );
  if (!ok) return;

  const progress = showProgress('Deleting all Parameter Contexts...');

  try {
    const res = await fetch(`${API_BASE}/parameter-contexts/clear-all-parameter-contexts`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    });

    const data = await res.json();

    if (!res.ok || data.success === false) {
      throw new Error(data.error || data.message || 'Bulk delete request failed');
    }

    const deleted = data.deleted_count ?? 0;
    const failed  = data.failed_count ?? 0;

    progress.update(`Deleted ${deleted} context(s), ${failed} failed`);
    progress.close();

    if (failed > 0) {
      showAlert(
        `Deleted ${deleted} context(s). ${failed} failed (usually because they are still referenced by Process Groups).`,
        'warning'
      );
    } else if (deleted > 0) {
      showToast(`✅ Successfully deleted ${deleted} Parameter Context(s)`, 'var(--success)');
    } else {
      showToast('No Parameter Contexts found to delete.', 'var(--info)');
    }

    // Refresh the table
    listParamContexts();

  } catch (e) {
    console.error('[PARAM_CTX] clearAllParameterContexts failed:', e);
    progress.close();
    showAlert('Failed to delete all Parameter Contexts: ' + e.message, 'error');
    listParamContexts(); // refresh anyway
  }
}