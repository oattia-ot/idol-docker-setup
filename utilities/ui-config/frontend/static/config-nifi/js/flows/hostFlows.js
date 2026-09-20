import { API_BASE } from '../config/constants.js';
import { getEl, getValue, escapeHtml } from '../core/domUtils.js';
import { showToast, showAlert } from '../core/notifications.js';
import { confirmDialog, showProgress } from '../core/dialogs.js';
import { state } from '../core/state.js';
import { getFlowCategory, getFolderBadge, getRelativeSegments } from '../styles/colorManager.js';
import { isValidNifi2Flow } from './flowValidation.js';
import { bulkDisableServicesInternal } from '../controllerServices/controllerServicesActions.js';
import { loadControllerServices } from '../controllerServices/controllerServicesList.js';

export async function clearRootFlows() {
  console.log('[RESET] Attempting to clear ALL flows in root Process Group...');
  try {
    const res = await fetch(`${API_BASE}/flows/clear-root`, { method: 'POST', headers: { 'Content-Type': 'application/json' } });

    let data;
    try { data = await res.json(); } catch { const text = await res.text(); throw new Error(`Server returned ${res.status}: ${text.substring(0, 100)}`); }

    if (res.ok && data.success) {
      console.log('✅ Root canvas cleared successfully');
      showToast('✅ All existing flows cleared!', 'var(--success)');
      return true;
    }
    throw new Error(data.error || data.message || `HTTP ${res.status}`);
  } catch (e) {
    console.error('❌ Clear root flows failed:', e);
    showAlert(`Failed to clear flows: ${e.message}`, 'error');
    return false;
  }
}

export async function importFlowFromHost(filePath, skipRefresh = false, importMode = 'new_child_group') {
  console.log(`[FLOWS] Importing from host: ${filePath} (mode: ${importMode})`);
  showToast('Importing flow from host…', 'var(--info)');

  try {
    const res = await fetch(`${API_BASE}/flows/import-from-host`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path: filePath, importMode }),
    });

    let data;
    try { data = await res.json(); } catch { throw new Error(`Server returned ${res.status} (not JSON)`); }

    if (res.ok && data.success) {
      console.log(`✅ SUCCESS - Flow imported: ${filePath}`);
      state.importResults.set(filePath, { status: 'success', message: data.message || 'Imported successfully' });
      showToast(`✅ Flow "${filePath}" imported successfully!`, 'var(--success)');
      
      if (!skipRefresh) setTimeout(loadHostFolderFlows, 1200);

      // Refresh Parameter Contexts list after import
      if (typeof listParamContexts === 'function') {
        setTimeout(listParamContexts, 1500);
      }
    } else {
      throw new Error(data.error || data.message || 'Import failed');
    }
  } catch (e) {
    console.error(`❌ FAILED - Import failed for ${filePath}:`, e);
    state.importResults.set(filePath, { status: 'failed', message: e.message });
    showAlert(`Import failed: ${e.message}`, 'error');
  }
}

export async function importSelectedHostFlows() {
  if (state.selectedHostFlows.size === 0) { showAlert('No flows selected to import.', 'warning'); return; }

  const paths = Array.from(state.selectedHostFlows);
  const chkClear = document.getElementById('chkClearBeforeImport');
  const shouldClear = chkClear && chkClear.checked;

  if (!shouldClear) {
    const progress = showProgress(`Importing ${paths.length} flow(s)...`);
    for (const path of paths) {
      progress.update(`Importing: ${path}`);
      await importFlowFromHost(path, true);
    }
    progress.close();
    loadHostFolderFlows();

    // === NEW: Refresh Parameter Contexts after batch import ===
    if (typeof listParamContexts === 'function') {
      setTimeout(listParamContexts, 1500);
    }
    return;
  }

  const ok = await confirmDialog(
    `⚠️ This will permanently:\n\n1. Disable ALL Controller Services\n2. DELETE ALL existing flows in NiFi\n3. Import ${paths.length} selected flows\n\nContinue?`,
    { title: 'Reset & Import Flows', confirmText: 'Reset & Import', danger: true }
  );
  if (!ok) return;

  const progress = showProgress('Starting Reset + Import...');

  try {
    progress.update('Disabling all Controller Services...');
    await bulkDisableServicesInternal();
    await new Promise((r) => setTimeout(r, 1500));

    progress.update('Clearing all existing flows...');
    const cleared = await clearRootFlows();
    if (!cleared) throw new Error('Clear operation failed or cancelled');

    await new Promise((r) => setTimeout(r, 2000));

    progress.update(`Importing ${paths.length} flows...`);
    let imported = 0;
    for (const path of paths) {
      try {
        await importFlowFromHost(path, true, 'new_child_group');
        imported++;
        progress.update(`Imported: ${path}`);
      } catch (err) {
        console.error(`Failed to import ${path}`, err);
        progress.update(`Failed: ${path}`);
      }
      await new Promise((r) => setTimeout(r, 800));
    }

    progress.close();
    showToast(`✅ Reset completed! ${imported} flows imported.`, 'var(--success)');
  } catch (err) {
    console.error('Reset flow failed:', err);
    progress.close();
    showAlert('Reset failed: ' + err.message, 'error');
  } finally {
    state.selectedHostFlows.clear();
    state.importResults.clear();
    state.paramContextsLoaded = false;   // Force reload next time section is opened
    
    setTimeout(() => {
      loadHostFolderFlows();
      loadControllerServices(true);

      // === NEW: Refresh Parameter Contexts after Reset + Import ===
      if (typeof listParamContexts === 'function') {
        listParamContexts();
      }
    }, 2000);
  }
}

export function toggleHostFlowSelection(btn) {
  const path = btn.getAttribute('data-path');
  const tr = btn.closest('tr');
  const cat = getFlowCategory(path, state.currentHostScanRoot);
  const isUserFlow = cat.badgeClass === 'user-badge';

  if (state.selectedHostFlows.has(path)) {
    state.selectedHostFlows.delete(path);
    tr.classList.remove('selected-row', 'selected-row-user', 'selected-row-folder');
    btn.classList.remove('btn-success', 'btn-user-flow', 'btn-feature', 'btn-tutorial', 'btn-folder', 'btn-root');
    btn.classList.add(cat.btnClass);
    btn.innerHTML = `<span class="${cat.badgeClass}">${escapeHtml(cat.label)}</span><i class="fas fa-check-circle"></i> Select`;
  } else {
    state.selectedHostFlows.add(path);
    if (isUserFlow) tr.classList.add('selected-row-user');
    else if (cat.badgeClass === 'folder-badge') tr.classList.add('selected-row-folder');
    else tr.classList.add('selected-row');

    btn.classList.remove('btn-user-flow', 'btn-feature', 'btn-tutorial', 'btn-folder', 'btn-root');
    btn.classList.add('btn-success');
    btn.innerHTML = `<span class="${cat.badgeClass}">${escapeHtml(cat.label)}</span><i class="fas fa-check"></i> Selected`;
  }

  updateImportSelectedButton();
}

export function updateImportSelectedButton() {
  const btn = document.getElementById('btnImportSelected');
  if (!btn) return;

  const count = state.selectedHostFlows.size;
  const chkClear = document.getElementById('chkClearBeforeImport');
  const shouldClear = chkClear && chkClear.checked;

  btn.disabled = count === 0;

  if (shouldClear) {
    btn.innerHTML = count > 0
      ? `<i class="fas fa-trash-alt"></i> Reset NiFi Flows & Import Selected (${count})`
      : `<i class="fas fa-trash-alt"></i> Reset NiFi Flows & Import Selected`;
  } else {
    btn.innerHTML = count > 0 ? `<i class="fas fa-download"></i> Import Selected (${count})` : `<i class="fas fa-download"></i> Import Selected`;
  }
}

export function resetAllSelections() {
  state.selectedHostFlows.clear();
  state.importResults.clear();
  loadHostFolderFlows();
}

/** Build a { folders: {name: node}, files: [...] } tree from a flat flow list. */
function buildFlowTree(flows, root) {
  const tree = { folders: {}, files: [] };
  flows.forEach((f) => {
    const segments = getRelativeSegments(f.path, root);
    const folderSegments = segments.slice(0, -1);
    let node = tree;
    for (const seg of folderSegments) {
      if (!node.folders[seg]) node.folders[seg] = { folders: {}, files: [] };
      node = node.folders[seg];
    }
    node.files.push(f);
  });
  return tree;
}

function countTreeFlows(node) {
  let count = node.files.length;
  for (const key in node.folders) count += countTreeFlows(node.folders[key]);
  return count;
}

/** Render one flow file as a table row (selection button + status icon). */
function renderFlowRow(f) {
  const isSelected = state.selectedHostFlows.has(f.path);
  const cat = getFlowCategory(f.path, state.currentHostScanRoot);

  let rowClass = '';
  if (isSelected) {
    const cls = cat.badgeClass === 'user-badge' ? 'selected-row-user'
      : cat.badgeClass === 'folder-badge' ? 'selected-row-folder'
      : 'selected-row';
    rowClass = `class="${cls}"`;
  }

  let statusIcon = '';
  const result = state.importResults.get(f.path);
  if (result) {
    statusIcon = result.status === 'success'
      ? `<i class="fas fa-check-circle text-success" title="Imported successfully" style="margin-right:8px;"></i>`
      : result.status === 'failed'
      ? `<i class="fas fa-times-circle text-danger" title="Import failed" style="margin-right:8px;"></i>`
      : '';
  }

  // The badge (colored span) is kept as its own element with its own
  // color rule (see colorManager.js / injectStyles.js), so it never
  // inherits the wrapping button's text color.
  const badgeHTML = `<span class="${cat.badgeClass}">${escapeHtml(cat.label)}</span>`;
  const btnHTML = isSelected
    ? `<button class="btn btn-sm btn-success" data-path="${escapeHtml(f.path)}" onclick="toggleHostFlowSelection(this)">${badgeHTML}<i class="fas fa-check"></i> Selected</button>`
    : `<button class="btn btn-sm ${cat.btnClass}" data-path="${escapeHtml(f.path)}" onclick="toggleHostFlowSelection(this)">${badgeHTML}<i class="fas fa-check-circle"></i> Select</button>`;

  return `<tr ${rowClass}>
        <td><strong>${escapeHtml(f.name)}</strong><br><small class="text-muted">${escapeHtml(f.path)}</small></td>
        <td style="text-align:center">${statusIcon}${btnHTML}</td>
        </tr>`;
}

/** Recursively render a tree node: subfolders first, then files. */
function renderFlowTreeNode(node) {
  let html = '';

  const folderNames = Object.keys(node.folders).sort((a, b) => a.localeCompare(b));
  folderNames.forEach((name) => {
    const sub = node.folders[name];
    const count = countTreeFlows(sub);
    const badge = getFolderBadge(name);
    html += `
        <details class="folder-tree-node">
        <summary class="folder-summary">
            <i class="fas fa-folder"></i>
            <span class="folder-name">${escapeHtml(name)}</span>
            <span class="${badge.badgeClass}">${escapeHtml(badge.label)}</span>
            <span class="folder-count">${count} flow${count === 1 ? '' : 's'}</span>
        </summary>
        <div class="folder-tree-children">
            ${renderFlowTreeNode(sub)}
        </div>
        </details>`;
  });

  if (node.files.length > 0) {
    const files = node.files.slice().sort((a, b) => a.name.localeCompare(b.name));
    html += `<table class="data-table"><thead><tr><th>File Name</th><th style="text-align:center">Actions</th></tr></thead><tbody>`;
    files.forEach((f) => { html += renderFlowRow(f); });
    html += `</tbody></table>`;
  }

  return html;
}

export async function loadHostFolderFlows() {
  const folderPath = getValue('hostFolderPath').trim() || '/nifi-flows';
  state.currentHostScanRoot = folderPath;
  console.log(`[HOST FLOWS] Scanning: ${folderPath}`);

  const container = getEl('importFilesList');
  const status = getEl('importFilesStatus');

  container.innerHTML = `<div style="padding:40px;text-align:center"><i class="fas fa-spinner fa-spin fa-2x"></i><br><br>Validating NiFi 2 flows...</div>`;
  if (status) { status.textContent = `Scanning: ${folderPath}`; status.className = 'info-message show info'; }

  try {
    const res = await fetch(`${API_BASE}/flows/host/list?path=${encodeURIComponent(folderPath)}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    if (data.success && data.files?.length > 0) {
      const validFlows = [];
      for (const f of data.files) {
        if (await isValidNifi2Flow(f.path)) validFlows.push(f);
      }

      if (validFlows.length > 0) {
        const tree = buildFlowTree(validFlows, folderPath);

        let html = `<div class="table-meta"><span class="table-meta-title">Valid NiFi 2 Flows (Host)</span><span class="table-meta-count">${validFlows.length} valid</span></div>`;
        html += `<div class="folder-tree-root">${renderFlowTreeNode(tree)}</div>`;

        const selectedCount = state.selectedHostFlows.size;
        html += `
            <div style="margin-top: 25px; padding: 20px; background:#f8f9fa; border-radius:8px; border:1px solid #ddd;">
            <label style="display:flex; align-items:center; gap:10px; cursor:pointer; font-weight:500; margin-bottom:15px; color:#000000 !important;">
                <input type="checkbox" id="chkClearBeforeImport" style="width:18px;height:18px;">
                <span>Clear <strong>all existing NiFi flows</strong> before importing
                <span style="color:#d32f2f;font-size:0.9em">(destructive!)</span>
                </span>
            </label>
            <div style="text-align:right; display:flex; gap:12px; justify-content:flex-end;">
                <button onclick="resetAllSelections()" class="btn btn-outline-secondary" style="padding:12px 24px;">
                <i class="fas fa-undo"></i> Reset Selection
                </button>
                <button id="btnImportSelected" onclick="importSelectedHostFlows()" class="btn btn-success" style="padding:12px 32px; font-size:1.1em;" ${selectedCount === 0 ? 'disabled' : ''}>
                <i class="fas fa-download"></i> Import Selected (${selectedCount})
                </button>
            </div>
            </div>`;

        container.innerHTML = html;

        const chk = document.getElementById('chkClearBeforeImport');
        if (chk) chk.addEventListener('change', updateImportSelectedButton);
        updateImportSelectedButton();

        if (status) { status.className = 'info-message show success'; status.innerHTML = `✅ ${validFlows.length} valid NiFi 2 flows`; }
      } else {
        container.innerHTML = `<div class="empty-state"><i class="fas fa-folder-open"></i><h4>No valid NiFi 2 flows found</h4><p>No real NiFi 2 flows in this folder</p></div>`;
        if (status) status.textContent = 'No valid flows';
      }
    } else {
      container.innerHTML = `<div class="empty-state"><i class="fas fa-folder-open"></i><h4>No files found</h4><p>No flow files in the folder</p></div>`;
      if (status) status.textContent = 'No files';
    }
  } catch (e) {
    console.error(e);
    container.innerHTML = `<div class="alert alert-danger">Scan failed.<br>${escapeHtml(e.message)}</div>`;
    if (status) status.textContent = 'Error';
  }
}
