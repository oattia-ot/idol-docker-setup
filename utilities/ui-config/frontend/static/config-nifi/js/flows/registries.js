import { API_BASE } from '../config/constants.js';
import { getEl, getValue, showLoading, escapeHtml } from '../core/domUtils.js';
import { triggerFileUpload } from '../upload/fileUpload.js';
import { importFlowFromRepository } from './githubFlows.js';

export async function listRegistries() {
  console.log('[REG] Listing GitHub Registries...');
  const container = getEl('registriesList') || getEl('registriesContainer');
  if (!container) return;
  showLoading('registriesList');
  try {
    const githubOwner = getValue('githubOwner');
    const githubRepo = getValue('githubRepoName');
    const configured = githubOwner && githubRepo;
    let html = `<div class="list-item"><div class="list-item-info"><div class="list-item-title"><i class="fab fa-github"></i> GitHub Flow Registry</div><div class="list-item-subtitle">${configured ? `${githubOwner}/${githubRepo}` : 'Configure GitHub credentials to enable registry'}</div></div><div class="action-buttons">`;
    html += configured
      ? `<button class="btn btn-primary" onclick="listBuckets()"><i class="fas fa-folder-open"></i> View Buckets &amp; Flows</button>`
      : `<button class="btn btn-secondary" onclick="showSection('config')">⚙️ Configure GitHub</button>`;
    html += `</div></div>`;
    container.innerHTML = html;
    console.log('[REG] GitHub Registry displayed');
  } catch (e) {
    console.error('[REG] Failed to list registries:', e);
    container.innerHTML = `<div class="alert alert-error">Error loading registries: ${e.message}</div>`;
  }
}

export async function listBuckets() {
  console.log('[REG] Listing buckets (GitHub repository paths)');
  const container = getEl('bucketsList');
  if (!container) return;
  showLoading('bucketsList');

  const repoPath = getValue('githubFlowDir') || 'nifi-flows';
  const owner = getValue('githubOwner');
  const repo = getValue('githubRepoName');
  const branch = getValue('githubBranch') || 'main';

  try {
    const params = new URLSearchParams({ path: repoPath, owner, repo, branch });
    const res = await fetch(`${API_BASE}/github/list-flows?${params}`);
    const data = await res.json();

    container.innerHTML = `
            <div class="table-meta">
                <span class="table-meta-title">GitHub Registry – Buckets</span>
            </div>
            <div class="list-item">
                <strong>Default Bucket:</strong> <code>${escapeHtml(repoPath)}</code>
                ${data.count !== undefined ? `<span class="badge">${data.count} flows</span>` : ''}
            </div>
            <button class="btn btn-success mt-3"
                onclick="listFlows('${escapeHtml(repoPath)}')">
                <i class="fas fa-list"></i> Browse Flows in Bucket
            </button>`;
  } catch (e) {
    console.error('[REG] Error listing buckets:', e);
    container.innerHTML = `<div class="alert alert-error">Failed to load buckets: ${e.message}</div>`;
  }
}

export async function listFlows(bucketPath = '') {
  const path = bucketPath || getValue('githubFlowDir') || 'nifi-flows';
  const owner = getValue('githubOwner');
  const repo = getValue('githubRepoName');
  const branch = getValue('githubBranch') || 'main';
  const token = getValue('githubToken');

  console.log(`[REG] Listing flows: ${owner}/${repo}/${path}@${branch}`);

  const container = getEl('flowsList');
  if (!container) { console.warn('[REG] flowsList container not found'); return; }

  if (!token) {
    container.innerHTML = `<div class="alert alert-error">
            <strong>GitHub Token Missing</strong><br>
            Please go to Configuration and enter your Personal Access Token.
        </div>`;
    return;
  }

  showLoading('flowsList');

  const params = new URLSearchParams({ path, owner, repo, branch, token });

  try {
    const res = await fetch(`${API_BASE}/github/list-flows?${params}`);
    const data = await res.json();
    console.log('[REG] ← Response:', data);

    if (!res.ok || !data.success) throw new Error(data.error || `HTTP ${res.status}`);

    const files = data.files || [];

    if (files.length === 0) {
      let html = `<div class="empty-state">
                <i class="fas fa-folder-open" style="font-size:42px;color:#64748b;margin-bottom:16px;"></i>
                <h4>No flows found</h4>`;
      html += data.warning
        ? `<p style="color:#f59e0b;font-weight:500;">⚠️ ${escapeHtml(data.warning)}</p>`
        : `<p>Path: <code>${escapeHtml(path)}</code> on branch <strong>${escapeHtml(branch)}</strong></p>`;
      html += `<p style="margin-top:16px;font-size:0.9rem;color:#94a3b8;">
                <strong>Next step:</strong> Create the folder <code>${escapeHtml(path)}</code> in your GitHub repo<br>
                or upload some NiFi flow files first.
            </p></div>`;
      container.innerHTML = html;
      return;
    }

    let html = `<div class="table-meta">
            <span class="table-meta-title">Flows in GitHub Registry</span>
            <span class="table-meta-count">${files.length} flows</span>
        </div>
        <table class="data-table">
            <thead><tr>
                <th>Flow Name</th><th>Path</th>
                <th style="width:140px">Actions</th>
            </tr></thead><tbody>`;

    files.forEach((f) => {
      html += `<tr>
                <td><strong>${escapeHtml(f.name)}</strong></td>
                <td><small class="text-muted">${escapeHtml(f.path || f.download_url)}</small></td>
                <td style="text-align:center">
                    <button class="btn btn-sm btn-primary"
                        onclick="importFlowFromRepository('${escapeHtml(f.path || f.download_url)}')">
                        <i class="fas fa-download"></i> Import
                    </button>
                </td>
            </tr>`;
    });
    html += '</tbody></table>';
    container.innerHTML = html;
  } catch (e) {
    console.error('[REG] ❌ Error listing flows:', e);
    container.innerHTML = `<div class="alert alert-error">Failed to load flows: ${e.message}</div>`;
  }
}

export async function uploadToRepository() {
  console.log('[REG] Uploading flow to GitHub Registry...');
  const { showToast } = await import('../core/notifications.js');
  showToast('GitHub Registry upload triggered – use the drag & drop zone or host folder for best results', 'var(--info)');
  triggerFileUpload();
}
