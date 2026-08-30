import { API_BASE } from '../config/constants.js';
import { getEl, getValue, escapeHtml } from '../core/domUtils.js';
import { showToast, showAlert } from '../core/notifications.js';
import { state } from '../core/state.js';

export function debouncedFilterGitHubFlows() {
  clearTimeout(state.githubFilterTimeout);
  state.githubFilterTimeout = setTimeout(() => { loadRepositoryFlows(); }, 280);
}

export async function loadGitHubBuckets() {
  const select = getEl('githubBucketSelect');
  if (!select) return;

  select.innerHTML = '<option value="">Loading buckets from GitHub...</option>';

  const owner = getValue('githubOwner');
  const repo = getValue('githubRepoName');
  const token = getValue('githubToken');
  const branch = getValue('githubBranch') || 'main';

  if (!owner || !repo || !token) {
    select.innerHTML = '<option value="">⚠️ Please configure GitHub and test connection first</option>';
    return;
  }

  const params = new URLSearchParams({ owner, repo, token, branch });

  try {
    const res = await fetch(`${API_BASE}/github/list-buckets?${params}`);
    const data = await res.json();

    if (!data.success) {
      select.innerHTML = `<option value="">❌ ${data.error || 'Failed to load buckets'}</option>`;
      return;
    }

    select.innerHTML = '<option value="">— All Buckets —</option>';

    if (data.buckets && data.buckets.length > 0) {
      data.buckets.forEach((bucket) => {
        const option = document.createElement('option');
        option.value = bucket.path || bucket.name;
        option.textContent = bucket.name;
        select.appendChild(option);
      });
      select.selectedIndex = 1;
      console.log(`[BUCKETS] Loaded ${data.buckets.length} buckets. First bucket selected as default.`);
    } else {
      const fallback = getValue('githubFlowDir') || 'nifi-flows';
      const option = document.createElement('option');
      option.value = fallback;
      option.textContent = `${fallback} (default)`;
      select.appendChild(option);
      select.selectedIndex = 1;
    }

    setTimeout(() => { loadRepositoryFlows(); }, 100);
  } catch (e) {
    console.error('[BUCKETS] Failed to load buckets:', e);
    select.innerHTML = '<option value="">❌ Could not load buckets from GitHub</option>';
  }
}

export async function loadRepositoryFlows() {
  const container = getEl('githubFilesList');
  const statusEl = getEl('githubFilesStatus');
  const countEl = getEl('githubFilesCount');
  const selectedBucket = getEl('githubBucketSelect')?.value || getValue('githubFlowDir') || 'nifi-flows';

  if (!container) return;

  const owner = getValue('githubOwner');
  const repo = getValue('githubRepoName');
  const branch = getValue('githubBranch') || 'main';
  const token = getValue('githubToken');
  const filterText = (getEl('githubFlowFilter')?.value || '').toLowerCase().trim();

  if (!owner || !repo || !token) {
    container.innerHTML = `<div class="alert alert-error">GitHub not configured. Please test connection first.</div>`;
    return;
  }

  const { showLoading } = await import('../core/domUtils.js');
  showLoading('githubFilesList');
  if (statusEl) statusEl.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Loading...';

  const params = new URLSearchParams({ path: selectedBucket, owner, repo, branch, token });

  try {
    const res = await fetch(`${API_BASE}/github/list-flows?${params}`);
    const data = await res.json();

    if (!res.ok || !data.success) throw new Error(data.error || 'Failed to load flows');

    const files = data.files || [];
    const filteredFiles = filterText ? files.filter((f) => f.name.toLowerCase().includes(filterText)) : files;

    if (filteredFiles.length === 0) {
      let msg = data.warning ? `<p style="color:#f59e0b;">${escapeHtml(data.warning)}</p>` : '';
      container.innerHTML = `
                <div class="empty-state">
                    <i class="fas fa-folder-open"></i>
                    <h4>No flows found in bucket "${selectedBucket}"</h4>
                    ${msg}
                </div>`;
      if (countEl) countEl.textContent = '0 files';
      return;
    }

    let html = `
            <div class="table-meta">
                <span class="table-meta-title"><i class="fab fa-github"></i> Flows in <strong>${selectedBucket}</strong></span>
                <span class="table-meta-count">${filteredFiles.length} flows</span>
            </div>
            <table class="data-table">
                <thead><tr><th>Flow Name</th><th style="text-align:center;">Actions</th></tr></thead>
                <tbody>`;

    filteredFiles.forEach((f) => {
      html += `
                <tr>
                    <td><strong>${escapeHtml(f.name)}</strong></td>
                    <td style="text-align:center">
                        <button class="btn btn-sm btn-primary" onclick="importFlowFromRepository('${escapeHtml(f.path || f.download_url)}')">
                            <i class="fas fa-download"></i> Import
                        </button>
                    </td>
                </tr>`;
    });

    html += '</tbody></table>';
    container.innerHTML = html;
    if (countEl) countEl.textContent = `${filteredFiles.length} flows`;
  } catch (e) {
    console.error('[REPO] Error:', e);
    container.innerHTML = `<div class="alert alert-error">Failed to load flows: ${escapeHtml(e.message)}</div>`;
  }
}

export async function importFlowFromRepository(filePath) {
  console.log(`[FLOWS] Importing from GitHub: ${filePath}`);
  showToast('Importing flow from GitHub…', 'var(--info)');
  try {
    const res = await fetch(`${API_BASE}/flows/import-from-github`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path: filePath }),
    });
    let data;
    try { data = await res.json(); } catch { throw new Error(`Server returned ${res.status} (not JSON)`); }
    if (res.ok && data.success) {
      showToast(`✅ Flow "${filePath}" imported successfully!`, 'var(--success)');
      setTimeout(loadRepositoryFlows, 1200);
    } else {
      throw new Error(data.error || data.message || 'Import failed - check Flask console');
    }
  } catch (e) {
    console.error(`[FLOWS] Import failed for ${filePath}:`, e);
    showAlert(`Import failed: ${e.message}`, 'error');
  }
}

export async function displayImportedGithubRegistryFlows() {
  console.log('[REG] Displaying flows imported from GitHub Registry');
  const container = getEl('importedFlowsContainer') || getEl('importFilesList') || getEl('repositoryFlowsList');
  if (!container) return;
  try {
    await loadRepositoryFlows();
    if (container.id === 'importFilesList') {
      const header = document.createElement('div');
      header.className = 'table-meta';
      header.innerHTML = `<span class="table-meta-title"> Flows Imported from GitHub Registry</span>`;
      container.prepend(header);
    }
  } catch (e) {
    console.error('[REG] Could not display imported registry flows:', e);
    container.innerHTML = `<div class="alert alert-warning">Could not load imported registry flows</div>`;
  }
}
