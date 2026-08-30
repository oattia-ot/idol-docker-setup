import { API_BASE } from '../config/constants.js';
import { getEl, getValue, setValue } from '../core/domUtils.js';
import { showToast } from '../core/notifications.js';
import { confirmDialog } from '../core/dialogs.js';

/** Persist current form configuration to backend + localStorage. */
export async function saveConfig() {
  console.log('[CONFIG] Saving configuration to backend...');
  try {
    const data = {
      nifi_api_url: getValue('nifiApiUrl'),
      nifi_username: getValue('nifiUsername'),
      nifi_password: getValue('nifiPassword'),
      github_api_url: getValue('githubApiUrl'),
      github_owner: getValue('githubOwner'),
      github_repo_name: getValue('githubRepoName'),
      github_token: getValue('githubToken'),
      github_branch: getValue('githubBranch'),
      github_flow_dir: getValue('githubFlowDir'),
    };
    console.debug('[CONFIG] Payload (passwords/tokens hidden):', {
      ...data,
      nifi_password: data.nifi_password ? '***' : '',
      github_token: data.github_token ? '***' : '',
    });
    const res = await fetch(`${API_BASE}/config`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    const json = await res.json();
    if (json.success) {
      localStorage.setItem('nifiConfig', JSON.stringify({ config: data }));
      console.log('[CONFIG] Saved successfully to backend and localStorage');
    } else {
      console.warn('[CONFIG] Backend returned not successful:', json);
    }
  } catch (e) {
    console.error('[CONFIG] Save config failed:', e);
    showToast('Save config failed', 'var(--danger)');
  }
}

/** Load configuration from localStorage, falling back to backend. */
export async function loadConfig() {
  console.log('[CONFIG] Loading configuration...');
  const saved = localStorage.getItem('nifiConfig');
  if (saved) {
    try {
      const cfg = JSON.parse(saved);
      if (cfg.config) {
        populateAllFormFields(cfg);
        console.log('[CONFIG] Loaded from localStorage');
        return;
      }
    } catch (e) {
      console.warn('[CONFIG] Failed to parse localStorage config', e);
    }
  }
  try {
    const res = await fetch(`${API_BASE}/config`);
    if (!res.ok) {
      console.warn(`[CONFIG] Backend config fetch returned ${res.status}`);
      return;
    }
    const srv = await res.json();
    console.log('[CONFIG] Loaded from backend');
    populateAllFormFields({
      config: {
        nifiApiUrl: srv.nifi_api_url,
        nifiUsername: srv.nifi_username,
        nifiPassword: '',
        githubApiUrl: srv.github_api_url || 'https://api.github.com',
        githubOwner: srv.github_owner,
        githubRepoName: srv.github_repo_name,
        githubToken: '',
        githubBranch: srv.github_branch || 'main',
        githubFlowDir: srv.github_flow_dir || 'nifi-flows',
      },
    });
  } catch (e) {
    console.error('[CONFIG] Failed to load from backend', e);
  }
}

/** @param {{config: Record<string, string>}} cfg */
export function populateAllFormFields(cfg) {
  console.log('[CONFIG] Populating form fields');
  if (!cfg.config) return;
  setValue('nifiApiUrl', cfg.config.nifiApiUrl);
  setValue('nifiUsername', cfg.config.nifiUsername);
  setValue('nifiPassword', cfg.config.nifiPassword);
  setValue('githubApiUrl', cfg.config.githubApiUrl);
  setValue('githubOwner', cfg.config.githubOwner);
  setValue('githubRepoName', cfg.config.githubRepoName);
  setValue('githubToken', cfg.config.githubToken);
  setValue('githubBranch', cfg.config.githubBranch);
  setValue('githubFlowDir', cfg.config.githubFlowDir);
}

export async function testNiFiConnection() {
  console.log('[TEST] Testing NiFi connection...');
  const info = getEl('nifi-info');
  info.textContent = 'Testing...';
  info.className = 'info-message show info';
  try {
    await saveConfig();
    const res = await fetch(`${API_BASE}/test-connection`);
    const data = await res.json();
    if (data.success) {
      console.log('[TEST] NiFi connection OK, version:', data.version);
      info.innerHTML = `✅ Success!<br>Version: ${data.version || 'Unknown'}`;
      info.className = 'info-message show success';
      showToast('NiFi OK', 'var(--success)');
    } else {
      throw new Error(data.error || 'Failed');
    }
  } catch (e) {
    console.error('[TEST] NiFi connection failed:', e);
    info.innerHTML = `❌ ${e.message}`;
    info.className = 'info-message show error';
    showToast('Failed', 'var(--danger)');
  }
}

export async function testGitHubConnection() {
  console.log('[TEST] Testing GitHub connection...');
  const info = getEl('github-api-info') || getEl('github-info');
  info.textContent = 'Testing...';
  info.className = 'info-message show info';

  try {
    const body = {
      github_api_url: getValue('githubApiUrl'),
      github_owner: getValue('githubOwner'),
      github_repo_name: getValue('githubRepoName'),
      github_token: getValue('githubToken'),
      github_branch: getValue('githubBranch'),
      github_flow_dir: getValue('githubFlowDir'),
    };
    const res = await fetch(`${API_BASE}/test-github`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const data = await res.json();

    if (data.success) {
      console.log('[TEST] GitHub connection OK');
      info.innerHTML = `✅ Connected to ${body.github_owner}/${body.github_repo_name}`;
      info.className = 'info-message show success';
      showToast('GitHub connected', 'var(--success)');
      document.querySelectorAll('[data-requires-github]').forEach((btn) => {
        btn.disabled = false;
        btn.title = '';
      });
    } else {
      throw new Error(data.error || 'Connection failed');
    }
  } catch (e) {
    console.error('[TEST] GitHub connection failed:', e);
    info.innerHTML = `❌ ${e.message}`;
    info.className = 'info-message show error';
    showToast('GitHub connection failed', 'var(--danger)');
    document.querySelectorAll('[data-requires-github]').forEach((btn) => {
      btn.disabled = true;
      btn.title = 'Test GitHub connection first';
    });
  }
}

export function exportConfigToFile() {
  console.log('[CONFIG] Exporting configuration to file');
  const cfg = {
    config: {
      nifiApiUrl: getValue('nifiApiUrl'),
      nifiUsername: getValue('nifiUsername'),
      nifiPassword: getValue('nifiPassword'),
      githubApiUrl: getValue('githubApiUrl'),
      githubOwner: getValue('githubOwner'),
      githubRepoName: getValue('githubRepoName'),
      githubToken: getValue('githubToken'),
      githubBranch: getValue('githubBranch'),
      githubFlowDir: getValue('githubFlowDir'),
    },
  };
  const dataStr = JSON.stringify(cfg, null, 2);
  const blob = new Blob([dataStr], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `nifi-config-${new Date().toISOString().split('T')[0]}.json`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
  showToast('Exported', 'var(--success)');
}

export function importConfigFromFile() {
  console.log('[CONFIG] Importing configuration from file');
  const inp = document.createElement('input');
  inp.type = 'file';
  inp.accept = '.json';
  inp.onchange = (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (ev) => {
      try {
        const cfg = JSON.parse(ev.target.result);
        if (cfg.config) {
          populateAllFormFields(cfg);
          localStorage.setItem('nifiConfig', JSON.stringify(cfg));
          showToast('Imported', 'var(--success)');
          console.log('[CONFIG] Import successful');
        } else {
          import('../core/notifications.js').then(({ showAlert }) => showAlert('Invalid config', 'error'));
        }
      } catch (err) {
        console.error('[CONFIG] Import parse error:', err);
        import('../core/notifications.js').then(({ showAlert }) => showAlert('JSON error', 'error'));
      }
    };
    reader.readAsText(file);
  };
  inp.click();
}

export async function resetConfig() {
  console.log('[CONFIG] Resetting configuration');
  const ok = await confirmDialog('Reset all config?', { title: 'Reset Configuration', confirmText: 'Reset', danger: true });
  if (!ok) return;
  localStorage.removeItem('nifiConfig');
  setValue('nifiApiUrl', '');
  setValue('nifiUsername', '');
  setValue('nifiPassword', '');
  setValue('githubApiUrl', 'https://api.github.com');
  setValue('githubOwner', '');
  setValue('githubRepoName', '');
  setValue('githubToken', '');
  setValue('githubBranch', 'main');
  setValue('githubFlowDir', 'nifi-flows');
  showToast('Reset to defaults', 'var(--info)');
}
