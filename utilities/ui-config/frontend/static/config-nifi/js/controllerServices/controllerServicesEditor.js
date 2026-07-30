import { API_BASE } from '../config/constants.js';
import { getEl, escapeHtml } from '../core/domUtils.js';
import { showAlert, showToast } from '../core/notifications.js';
import { state } from '../core/state.js';
import { showInlineParamDetail, hideInlineParamDetail } from '../paramContexts/paramContextsView.js';
import { loadControllerServices } from './controllerServicesList.js';
import { listParamContexts } from '../paramContexts/paramContextsList.js';

export async function viewControllerService(id) {
  console.log(`[CS VIEW] Loading read-only view for service ${id}`);
  try {
    const res = await fetch(`${API_BASE}/controller-services/${id}`);

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
    if (!data.success || !data.data) throw new Error(data.error || 'Failed to load service details');

    const svc = data.data;
    const comp = svc.component || svc;
    const descriptors = comp.descriptors || {};
    const properties = comp.properties || {};
    const propNames = Object.keys(descriptors).length ? Object.keys(descriptors) : Object.keys(properties);

    let html = `<div class="scroll-box"><table class="data-table" style="table-layout:fixed;width:100%;border-collapse:collapse;"><thead><tr style="font-size:11px;text-transform:uppercase;letter-spacing:.05em;"><th style="width:35%;padding:4px 6px;">Property Name</th><th style="width:65%;padding:4px 6px;">Value</th></tr></thead><tbody>`;

    if (propNames.length === 0) {
      html += `<tr><td colspan="2" style="padding:12px;text-align:center;color:var(--text-secondary,#aaa);font-size:12px;">No properties defined</td></tr>`;
    } else {
      propNames.forEach((name) => {
        const desc = descriptors[name] || { sensitive: false };
        const isSensitive = !!desc.sensitive;
        const rawValue = properties[name];
        const displayValue = isSensitive ? (rawValue ? '••••••••' : '') : (rawValue ?? '');

        html += `<tr style="vertical-align:middle;">
            <td style="padding:3px 4px;"><input type="text" value="${escapeHtml(name)}" readonly style="width:100%;font-size:12px;padding:3px 5px;box-sizing:border-box;border:1px solid var(--border-color,#444);border-radius:3px;background:var(--bg-secondary,#2a2a2a);color:var(--text-primary,#e0e0e0);cursor:default;"></td>
            <td style="padding:3px 4px;"><input type="text" value="${escapeHtml(String(displayValue))}" readonly style="width:100%;font-size:12px;padding:3px 5px;box-sizing:border-box;border:1px solid var(--border-color,#444);border-radius:3px;background:var(--bg-secondary,#2a2a2a);color:var(--text-primary,#e0e0e0);cursor:default;"></td>
        </tr>`;
      });
    }
    html += `</tbody></table></div>`;

    html += `<div style="margin-top:10px;display:flex;gap:16px;font-size:12px;color:var(--text-secondary,#aaa);">
        <span><strong>State:</strong> ${escapeHtml(comp.state || 'UNKNOWN')}</span>
        <span><strong>Validation:</strong> ${escapeHtml(comp.validationStatus || 'UNKNOWN')}</span>
    </div>`;

    html += `<div style="display:flex;gap:8px;margin-top:14px;padding-top:10px;border-top:1px solid var(--border-color,#444);">
        <button class="btn btn-secondary" onclick="hideInlineParamDetail()" style="flex:1;font-size:13px;padding:10px 18px;">Close</button>
    </div>`;

    showInlineParamDetail(`View: ${escapeHtml(comp.name || 'Unnamed')}`, html);
  } catch (e) {
    console.error(`[CS VIEW] Error viewing ${id}:`, e);
    showAlert('Failed to load controller service details: ' + e.message, 'error');
  }
}

export async function editControllerService(id) {
  console.log(`[CS EDIT] Loading inline editor for service ${id}`);
  try {
    const res = await fetch(`${API_BASE}/controller-services/${id}`);

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
    if (!data.success || !data.data) throw new Error(data.error || 'Failed to load service details');

    const svc = data.data;
    const comp = svc.component || svc;

    state.currentEditCSId = id;
    state.currentEditCSRevision = svc.revision?.version || comp.revision?.version;
    state.currentEditCSProperties = { ...(comp.properties || {}) };

    const contentHtml = renderEditCSPropertiesTable(comp);
    showInlineParamDetail(`Edit Controller Service: ${escapeHtml(comp.name || 'Unnamed')}`, contentHtml);
    setTimeout(attachCSEditListeners, 20);
  } catch (e) {
    console.error('[CS EDIT] Error loading details:', e);
    showAlert('Failed to load controller service details: ' + e.message, 'error');
  }
}

export function renderEditCSPropertiesTable(comp) {
  const descriptors = comp.descriptors || {};
  let html = `<div class="scroll-box"><table class="data-table" id="inlineEditCSTable" style="table-layout:fixed;width:100%;border-collapse:collapse;"><thead><tr style="font-size:11px;text-transform:uppercase;letter-spacing:.05em;"><th style="width:32%;padding:4px 6px;">Property Name</th><th style="width:68%;padding:4px 6px;">Value</th></tr></thead><tbody>`;

  const propNames = Object.keys(descriptors).length ? Object.keys(descriptors) : Object.keys(state.currentEditCSProperties);

  propNames.forEach((name, idx) => {
    const desc = descriptors[name] || { sensitive: false, description: '' };
    const value = state.currentEditCSProperties[name] !== undefined ? state.currentEditCSProperties[name] : '';
    const isSensitive = !!desc.sensitive;

    html += `<tr id="cs-prop-row-${idx}" style="vertical-align:middle;">`;
    html += `<td style="padding:3px 4px;"><input type="text" value="${escapeHtml(name)}" readonly style="width:100%;font-size:12px;padding:3px 5px;box-sizing:border-box;border:1px solid var(--border-color,#444);border-radius:3px;background:var(--bg-secondary,#2a2a2a);color:var(--text-primary,#e0e0e0);cursor:default;">${desc.description ? `<div style="font-size:10px;color:#94a3b8;margin-top:2px;">${escapeHtml(desc.description.substring(0, 80))}${desc.description.length > 80 ? '...' : ''}</div>` : ''}</td>`;
    html += `<td style="padding:3px 4px;">
        <input type="${isSensitive ? 'password' : 'text'}"
                class="cs-prop-value-inline"
                data-prop="${escapeHtml(name)}"
                value="${escapeHtml(value)}"
                style="width:100%; font-size:13px; padding:8px 12px; box-sizing:border-box;
                    border:2px solid #475569; border-radius:6px; background:#1e2937;
                    color:#e0e0e0; transition:all 0.2s; min-height:38px;">
    </td>`;
    html += `</tr>`;
  });

  html += `</tbody></table></div>`;

  const jsonStr = JSON.stringify(state.currentEditCSProperties, null, 2);
  html += `
    <details style="margin-top:10px;">
      <summary style="font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.05em;color:var(--text-secondary,#aaa);cursor:pointer;user-select:none;list-style:none;display:flex;align-items:center;gap:8px;">
        JSON Bulk Editor <span style="font-size:10px;opacity:.6;font-weight:400;">(collapsed by default)</span>
      </summary>
      <div style="margin-top:6px;">
        <textarea id="csInlineJsonEditor" style="width:100%;font-family:monospace;font-size:12px;padding:8px;box-sizing:border-box;border:1px solid var(--border-color,#444);border-radius:3px;resize:vertical;min-height:220px;max-height:480px;line-height:1.5;background:var(--bg-secondary,#2a2a2a);color:var(--text-primary,#e0e0e0);">${escapeHtml(jsonStr)}</textarea>
        <div style="display:flex;gap:6px;margin-top:8px;">
          <button class="btn btn-secondary btn-sm" id="cs-format-json-btn">Format JSON</button>
          <button class="btn btn-secondary btn-sm" id="cs-validate-json-btn">Validate JSON</button>
          <button class="btn btn-primary btn-sm" id="cs-sync-json-btn">↑ Sync from JSON</button>
        </div>
      </div>
    </details>`;

  html += `<div style="display:flex;gap:8px;margin-top:14px;padding-top:10px;border-top:1px solid var(--border-color,#444);">
    <button class="btn btn-info btn-sm" id="validate-cs-btn" style="font-size:13px;"><i class="fas fa-check-circle"></i> Validate Properties</button>
    <button class="btn btn-primary btn-sm" id="save-cs-changes-btn" style="flex:1;font-size:13px;">💾 Save Changes</button>
    <button class="btn btn-secondary btn-sm" id="cancel-cs-btn" style="font-size:13px;padding:0 18px;">Cancel</button>
    </div>`;

  return html;
}

export function attachCSEditListeners() {
  if (state.editCSAbortController) state.editCSAbortController.abort();
  state.editCSAbortController = new AbortController();
  const signal = state.editCSAbortController.signal;
  const container = getEl('paramContextDetailContainer');

  container.addEventListener('input', (e) => {
    const propName = e.target.dataset.prop;
    if (!propName || !e.target.classList.contains('cs-prop-value-inline')) return;
    state.currentEditCSProperties[propName] = e.target.value;
  }, { signal });

  container.addEventListener('click', (e) => {
    const target = e.target;
    if (target.classList.contains('remove-cs-prop-btn')) {
      const propName = target.dataset.prop;
      if (propName) { delete state.currentEditCSProperties[propName]; refreshCSEditForm(); }
    } else if (target.id === 'save-cs-changes-btn') saveInlineControllerService();
    else if (target.id === 'validate-cs-btn') validateControllerServiceProperties();
    else if (target.id === 'cancel-cs-btn') hideInlineParamDetail(null); // no refresh on cancel
    else if (target.id === 'cs-format-json-btn') formatCSInlineJSON();
    else if (target.id === 'cs-validate-json-btn') validateCSInlineJSON();
    else if (target.id === 'cs-sync-json-btn') syncCSFromInlineJSON();
  }, { signal });

  console.log('[CS EDIT] Inline listeners attached');
}

export function refreshCSEditForm() {
  const contentHtml = renderEditCSPropertiesTable({});
  const contentDiv = getEl('paramDetailContent');
  if (contentDiv) contentDiv.innerHTML = contentHtml;
  setTimeout(attachCSEditListeners, 10);
}

export async function saveInlineControllerService() {
  if (!state.currentEditCSId) return;
  console.log(`[CS EDIT] Saving properties for ${state.currentEditCSId}`);

  try {
    const payload = { revision: { version: state.currentEditCSRevision }, component: { id: state.currentEditCSId, properties: state.currentEditCSProperties } };

    const res = await fetch(`${API_BASE}/controller-services/${state.currentEditCSId}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    if (data.success) {
      const status = data.validationStatus || 'UNKNOWN';
      if (status === 'VALID') {
        showToast('✅ Controller service properties saved successfully', 'var(--success)');
      } else {
        showToast('✅ Properties saved (service is now INVALID)', 'var(--warning)');
        if (status === 'INVALID') {
          showAlert('⚠️ Service saved but marked INVALID because it references a disabled Controller Service.\n\nEnable the referenced service to make it VALID.', 'warning');
        }
      }
      hideInlineParamDetail(listParamContexts);
      loadControllerServices();
      state.currentEditCSId = null;
    } else {
      throw new Error(data.error || data.message || 'Save failed');
    }
  } catch (e) {
    console.error('[CS EDIT] Save failed:', e);
    showAlert('❌ Save failed: ' + e.message, 'error');
  }
}

export async function validateControllerServiceProperties() {
  if (!state.currentEditCSId) return;
  showToast('Validating properties...', 'var(--info)');

  try {
    const payload = { revision: { version: state.currentEditCSRevision }, component: { id: state.currentEditCSId, properties: state.currentEditCSProperties } };

    const res = await fetch(`${API_BASE}/controller-services/${state.currentEditCSId}/validate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    console.log('[CS VALIDATE] Full response from backend:', data);

    if (data.success === true) {
      if (data.valid === true || data.validationStatus === 'VALID') { showAlert('✅ Properties are valid!', 'success'); return; }

      let errorMsg = data.validationErrors?.length
        ? data.validationErrors.join('\n')
        : (data.message && data.message !== 'Validation completed' ? data.message : 'Properties have validation issues');

      if (errorMsg.includes('disabled') || errorMsg.includes('Controller Service that is currently disabled')) {
        errorMsg = '⚠️ This service references another Controller Service that is currently DISABLED.\n\n' +
          'Solution: Enable the referenced service first, then try Validate again.';
      }
      showAlert(`❌ ${errorMsg}`, 'error');
    } else {
      showAlert(`❌ ${data.error || data.message || 'Validation request failed'}`, 'error');
    }
  } catch (e) {
    console.error('[CS VALIDATE] Error:', e);
    showAlert('Validation request failed: ' + e.message, 'error');
  }
}

export function formatCSInlineJSON() {
  const ta = getEl('csInlineJsonEditor');
  try { ta.value = JSON.stringify(JSON.parse(ta.value), null, 2); } catch { showAlert('Invalid JSON', 'error'); }
}

export function validateCSInlineJSON() {
  const ta = getEl('csInlineJsonEditor');
  try { JSON.parse(ta.value); showAlert('JSON is valid', 'success'); } catch (e) { showAlert('Invalid JSON: ' + e.message, 'error'); }
}

export function syncCSFromInlineJSON() {
  const ta = getEl('csInlineJsonEditor');
  try { state.currentEditCSProperties = JSON.parse(ta.value); refreshCSEditForm(); } catch { showAlert('Invalid JSON', 'error'); }
}
