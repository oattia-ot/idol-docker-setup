import { API_BASE } from '../config/constants.js';
import { escapeHtml } from '../core/domUtils.js';
import { showAlert } from '../core/notifications.js';
import { copyToClipboard } from '../core/clipboard.js';

function getEl(id) { return document.getElementById(id); }

export function hideInlineParamDetail(refreshFn = null) {
  console.log('[PARAM_CTX] Hiding inline detail view');
  getEl('paramContextDetailContainer').style.display = 'none';
  // Refresh disabled from this function
}

export function showInlineParamDetail(title, contentHtml) {
  console.log(`[PARAM_CTX] Showing inline detail: ${title}`);
  const cont = getEl('paramContextDetailContainer');
  getEl('paramDetailTitle').textContent = title;
  getEl('paramDetailContent').innerHTML = contentHtml;
  cont.style.display = 'flex';
}

/**
 * @param {string} id
 * @param {(id: string) => void} showUpdateParamContext
 * @param {() => void} hideDetail
 */
export async function viewParamContext(id, showUpdateParamContext, hideDetail) {
  console.log(`[PARAM_CTX] Viewing context ${id}`);
  try {
    const res = await fetch(`${API_BASE}/parameter-contexts/${id}`);
    const data = await res.json();
    if (!data.success) throw new Error('Fetch failed');

    const ctx = data.data;
    const comp = ctx.component || {};
    const params = (comp.parameters || []).map((p) => ({ ...(p.parameter || p) }));

    let html = `<div class="scroll-box"><table class="data-table" style="table-layout:fixed;width:100%;border-collapse:collapse;"><thead><tr style="font-size:11px;text-transform:uppercase;letter-spacing:.05em;"><th style="width:28%;padding:4px 6px;">Name</th><th style="width:40%;padding:4px 6px;">Value</th><th style="width:14%;padding:4px 6px;text-align:center;">Sensitive</th></tr></thead><tbody>`;

    if (params.length === 0) {
      html += `<tr><td colspan="3" style="padding:12px;text-align:center;color:var(--text-secondary,#aaa);font-size:12px;">No parameters defined</td></tr>`;
    } else {
      params.forEach((p) => {
        html += `<tr style="vertical-align:middle;">
            <td style="padding:3px 4px;"><input type="text" value="${escapeHtml(p.name)}" readonly style="width:100%;font-size:12px;padding:3px 5px;box-sizing:border-box;border:1px solid var(--border-color,#444);border-radius:3px;background:var(--bg-secondary,#2a2a2a);color:var(--text-primary,#e0e0e0);cursor:default;"></td>
            <td style="padding:3px 4px;"><input type="text" value="${escapeHtml(p.value || '')}" readonly style="width:100%;font-size:12px;padding:3px 5px;box-sizing:border-box;border:1px solid var(--border-color,#444);border-radius:3px;background:var(--bg-secondary,#2a2a2a);color:var(--text-primary,#e0e0e0);cursor:default;"></td>
            <td style="padding:3px 4px;text-align:center;"><input type="checkbox" ${p.sensitive ? 'checked' : ''} disabled style="width:14px;height:14px;accent-color:var(--accent,#4a9eff);"></td>
        </tr>`;
      });
    }
    html += `</tbody></table></div>`;

    const prettyJson = JSON.stringify(
      params.map((p) => ({ name: p.name, value: p.value || '', sensitive: !!p.sensitive, description: p.description || '' })),
      null, 2
    );

    html += `
        <details style="margin-top:12px;">
          <summary style="font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.05em;color:var(--text-secondary,#aaa);cursor:pointer;user-select:none;list-style:none;display:flex;align-items:center;justify-content:space-between;gap:8px;">
            <span>JSON (Read-only) <span style="font-size:10px;opacity:.6;font-weight:400;">(collapsed by default)</span></span>
            <button class="btn btn-sm btn-secondary" id="copyReadonlyJsonBtn" style="font-size:11px;padding:2px 8px;flex-shrink:0;" onclick="event.stopImmediatePropagation();">
              <i class="fas fa-copy"></i> Copy
            </button>
          </summary>
          <div style="margin-top:6px;">
            <textarea readonly style="width:100%;font-family:monospace;font-size:12px;padding:8px;box-sizing:border-box;border:1px solid var(--border-color,#444);border-radius:3px;resize:vertical;min-height:220px;max-height:480px;line-height:1.5;background:var(--bg-secondary,#2a2a2a);color:var(--text-primary,#e0e0e0);cursor:default;">${escapeHtml(prettyJson)}</textarea>
          </div>
        </details>`;

    html += `<div style="display:flex;gap:8px;margin-top:14px;padding-top:10px;border-top:1px solid var(--border-color,#444);">
        <button class="btn btn-warning" onclick="showUpdateParamContext('${escapeHtml(id)}')" style="flex:1;font-size:13px;"><i class="fas fa-edit"></i> Edit</button>
        <button class="btn btn-secondary" onclick="hideInlineParamDetail()" style="font-size:13px;padding:0 18px;">Close</button>
    </div>`;

    showInlineParamDetail(`View: ${escapeHtml(comp.name || 'Unnamed')}`, html);

    setTimeout(() => {
      getEl('copyReadonlyJsonBtn')?.addEventListener('click', () => {
        copyToClipboard(prettyJson, '✅ View JSON copied to clipboard!');
      });
    }, 150);
  } catch (e) {
    console.error(`[PARAM_CTX] Error viewing ${id}:`, e);
    showAlert('Error viewing: ' + e.message, 'error');
  }
}
