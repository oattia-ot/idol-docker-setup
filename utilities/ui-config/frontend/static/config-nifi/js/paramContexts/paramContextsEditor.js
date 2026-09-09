import { API_BASE } from '../config/constants.js';
import { getEl, escapeHtml } from '../core/domUtils.js';
import { showAlert, showToast } from '../core/notifications.js';
import { state } from '../core/state.js';
import { showInlineParamDetail, hideInlineParamDetail } from './paramContextsView.js';
import { listParamContexts } from './paramContextsList.js';

export function refreshParamEditForm() {
  const contentHtml = renderEditParamTable();
  const contentDiv = getEl('paramDetailContent');
  if (contentDiv) {
    contentDiv.innerHTML = contentHtml;
    setTimeout(attachEditFormListeners, 10);
  }
}

export function renderEditParamTable() {
  let html = `<div class="scroll-box"><table class="data-table" id="inlineEditParamTable" style="table-layout:fixed;width:100%;border-collapse:collapse;"><thead><tr style="font-size:11px;text-transform:uppercase;letter-spacing:.05em;"><th style="width:35%;padding:4px 6px;">Name</th><th style="width:65%;padding:4px 6px;">Value</th></tr></thead><tbody>`;

  state.currentEditParameters.forEach((param, idx) => {
    html += `<tr id="param-row-${idx}" style="vertical-align:middle;">
        <td style="padding:3px 4px;">
        <input type="text" value="${escapeHtml(param.name)}" readonly
                style="width:100%;font-size:12px;padding:3px 5px;box-sizing:border-box;border:1px solid var(--border-color,#444);border-radius:3px;background:var(--bg-secondary,#2a2a2a);color:var(--text-primary,#e0e0e0);cursor:default;">
        </td>
        <td style="padding:3px 4px;">
        <input type="text" class="param-value-inline" data-idx="${idx}" value="${escapeHtml(param.value || '')}"
                style="width:100%;font-size:12px;padding:3px 5px;box-sizing:border-box;border:1px solid var(--border-color,#444);border-radius:3px;background:var(--bg-secondary,#2a2a2a);color:var(--text-primary,#e0e0e0);">
        </td>
    </tr>`;
  });

  html += `</tbody></table></div>`;
  html += `
    <div style="margin-top:12px;display:flex;gap:8px;flex-wrap:wrap;">
        <button class="btn btn-success btn-sm" id="add-param-btn" style="font-size:12px;padding:4px 12px;">＋ Add Parameter</button>
        <button class="btn btn-secondary btn-sm" id="format-json-btn" style="font-size:12px;padding:4px 12px;">Format JSON</button>
        <button class="btn btn-secondary btn-sm" id="validate-json-btn" style="font-size:12px;padding:4px 12px;">Validate JSON</button>
    </div>`;

  const jsonStr = JSON.stringify(
    state.currentEditParameters.map((p) => ({ name: p.name, value: p.value, sensitive: p.sensitive, description: p.description || '' })),
    null, 2
  );

  html += `
    <details style="margin-top:16px;">
      <summary style="font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.05em;color:var(--text-secondary,#aaa);cursor:pointer;user-select:none;list-style:none;display:flex;align-items:center;justify-content:space-between;gap:8px;">
        <span>JSON Bulk Editor <span style="font-size:10px;opacity:.6;font-weight:400;">(collapsed by default — use for bulk edit)</span></span>
        <button class="btn btn-sm btn-secondary" id="copyBulkJsonBtn" style="font-size:11px;padding:2px 8px;flex-shrink:0;" onclick="event.stopImmediatePropagation();">
            <i class="fas fa-copy"></i> Copy
        </button>
      </summary>
      <div style="margin-top:6px;">
        <textarea id="inlineJsonEditor" style="width:100%;font-family:monospace;font-size:12px;padding:8px;box-sizing:border-box;border:1px solid var(--border-color,#444);border-radius:3px;resize:vertical;min-height:200px;max-height:450px;line-height:1.5;background:var(--bg-secondary,#2a2a2a);color:var(--text-primary,#e0e0e0);">${escapeHtml(jsonStr)}</textarea>
        <button class="btn btn-primary btn-sm" id="sync-json-btn" style="margin-top:6px;">↑ Sync from JSON</button>
      </div>
    </details>`;

  html += `
    <div style="margin-top:20px;padding-top:12px;border-top:2px solid var(--border-color,#475569);display:flex;gap:10px;">
        <button class="btn btn-success" id="save-changes-btn" style="flex:1;font-size:15px;padding:10px 16px;font-weight:600;">💾 Save Changes</button>
        <button class="btn btn-secondary" id="cancel-btn" style="padding:10px 20px;font-size:14px;">Cancel</button>
    </div>`;

  return html;
}

export function attachEditFormListeners() {
  if (state.editFormAbortController) state.editFormAbortController.abort();
  state.editFormAbortController = new AbortController();
  const signal = state.editFormAbortController.signal;
  const container = getEl('paramContextDetailContainer');

  container.addEventListener('input', (e) => {
    if (!e.target.dataset.idx) return;
    const idx = parseInt(e.target.dataset.idx, 10);
    if (Number.isNaN(idx) || !state.currentEditParameters[idx]) return;
    const param = state.currentEditParameters[idx];
    if (e.target.classList.contains('param-value-inline')) param.value = e.target.value;
  }, { signal });

  container.addEventListener('click', (e) => {
    const target = e.target;
    if (target.id === 'add-param-btn') addInlineParameter();
    else if (target.id === 'format-json-btn') formatInlineJSON();
    else if (target.id === 'validate-json-btn') validateInlineJSON();
    else if (target.id === 'sync-json-btn') syncFromInlineJSON();
    else if (target.id === 'save-changes-btn') saveInlineParameterContext();
    else if (target.id === 'cancel-btn') hideInlineParamDetail(null); // no refresh on cancel
    else if (target.id === 'copyBulkJsonBtn') {
      import('../core/clipboard.js').then(({ copyToClipboard }) =>
        copyToClipboard(getEl('inlineJsonEditor')?.value || '', 'Bulk Editor JSON copied!'));
    }
  }, { signal });

  console.log('[PARAM_CTX] Edit form listeners attached');
}

export async function showUpdateParamContext(id) {
  console.log(`[PARAM_CTX] Loading edit form for ${id}`);
  try {
    const res = await fetch(`${API_BASE}/parameter-contexts/${id}`);

    // Aligned with controller service update logic: check res.ok and extract
    // the real error body/text instead of throwing a generic message.
    if (!res.ok) {
      let errorText = `HTTP ${res.status}`;
      try {
        const errorData = await res.json();
        errorText = errorData.error || errorData.message || errorText;
      } catch {
        const text = await res.text();
        errorText += ` - ${text.substring(0, 200)}`;
      }
      throw new Error(errorText);
    }

    const data = await res.json();
    if (!data.success || !data.data) throw new Error(data.error || 'Failed to load parameter context details');

    const ctx = data.data;
    const comp = ctx.component || {};

    state.currentEditParameters = (comp.parameters || []).map((p) => {
      const param = p.parameter || p;
      return { name: param.name || '', value: param.value || '', sensitive: !!param.sensitive, description: param.description || '' };
    });
    state.currentEditContextId = id;
    state.currentEditRevision = ctx.revision.version;

    const contentHtml = renderEditParamTable();
    showInlineParamDetail(`Edit: ${comp.name}`, contentHtml);
    setTimeout(attachEditFormListeners, 10);
  } catch (e) {
    console.error(`[PARAM_CTX] Error loading edit form for ${id}:`, e);
    showAlert('Error loading edit form: ' + e.message, 'error');
  }
}

export function addInlineParameter() {
  console.log('[PARAM_CTX] Add new parameter');
  let baseName = `newParam${state.newParamCounter}`;
  while (state.currentEditParameters.some((p) => p.name === baseName)) {
    state.newParamCounter++;
    baseName = `newParam${state.newParamCounter}`;
  }
  state.newParamCounter++;
  state.currentEditParameters.push({ name: baseName, value: '', sensitive: false, description: '' });
  refreshParamEditForm();
}

export function removeInlineParameter(idx) {
  console.log(`[PARAM_CTX] Remove parameter at index ${idx}`);
  state.currentEditParameters.splice(idx, 1);
  refreshParamEditForm();
}

export async function saveInlineParameterContext() {
  if (!state.currentEditContextId) {
    showAlert('No context ID found', 'error');
    return;
  }

  console.log(`[PARAM_CTX] Saving edited context ${state.currentEditContextId}`);
  try {
    const normalizedParams = state.currentEditParameters
      .map((p) => {
        if (!p || typeof p !== 'object') return null;
        return { name: String(p.name || '').trim(), value: String(p.value || ''), sensitive: Boolean(p.sensitive), description: String(p.description || '') };
      })
      .filter((p) => p && p.name);

    console.log(`[SAVE] Sending ${normalizedParams.length} parameters`);

    const payload = {
      revision: { version: state.currentEditRevision },
      component: {
        id: state.currentEditContextId,
        parameters: normalizedParams
      }
    };

    const res = await fetch(`${API_BASE}/parameter-contexts/${state.currentEditContextId}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (!res.ok) {
      let errorText = `HTTP ${res.status}`;
      try {
        const errorData = await res.json();
        errorText = errorData.error || errorData.message || errorText;
      } catch {
        const text = await res.text();
        errorText += ` - ${text.substring(0, 200)}`;
      }
      throw new Error(errorText);
    }

    const data = await res.json();

    if (data.success) {
      // Aligned with controller service update logic: the backend now returns
      // the refreshed entity as data.data (no validationStatus equivalent exists
      // for parameter contexts in the NiFi 2.x API, so none is surfaced here).
      console.log('[PARAM_CTX] Updated context:', data.data);
      showToast('✅ Parameter context updated successfully', 'var(--success)');
      hideInlineParamDetail(null); // explicitly no auto-refresh; only Refresh button updates the list
      state.newParamCounter = 1;
      state.currentEditContextId = null;
      state.currentEditRevision = null;
      state.currentEditParameters = [];
    } else {
      throw new Error(data.error || data.message || 'Update failed');
    }
  } catch (e) {
    console.error('[PARAM_CTX] Update failed:', e);
    showAlert('Update failed: ' + (e.message || 'Unknown error'), 'error');
  }
}

export function syncFromInlineJSON() {
  const ta = getEl('inlineJsonEditor');
  try {
    const parsed = JSON.parse(ta.value);
    state.currentEditParameters = parsed.map((p) => ({ name: p.name, value: p.value || '', sensitive: !!p.sensitive, description: p.description || '' }));
    refreshParamEditForm();
  } catch {
    showAlert('Invalid JSON', 'error');
  }
}

export function formatInlineJSON() {
  const ta = getEl('inlineJsonEditor');
  try { ta.value = JSON.stringify(JSON.parse(ta.value), null, 2); } catch { showAlert('Invalid JSON', 'error'); }
}

export function validateInlineJSON() {
  const ta = getEl('inlineJsonEditor');
  try { JSON.parse(ta.value); showAlert('JSON is valid', 'success'); } catch (e) { showAlert('Invalid JSON: ' + e.message, 'error'); }
}