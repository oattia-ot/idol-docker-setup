import { getEl, getValue } from '../core/domUtils.js';
import { state } from '../core/state.js';
import { listParamContexts } from '../paramContexts/paramContextsList.js';
import { loadControllerServices } from '../controllerServices/controllerServicesList.js';
import { listRegistries } from '../flows/registries.js';
import { loadGitHubBuckets } from '../flows/githubFlows.js';

const SECTION_TITLES = {
  config: 'Configuration',
  registries: 'Registries',
  'param-contexts': 'Parameter Contexts',
  'controller-services': 'Controller Services',
  'repository-flow-files': 'Repository Flows',
};

const SECTION_ICONS = {
  config: 'fa-sliders-h',
  registries: 'fa-server',
  'param-contexts': 'fa-list-ul',
  'controller-services': 'fa-cogs',
};

export function showSection(id) {
  console.log(`[UI] Switching to section: ${id}`);
  document.querySelectorAll('.section').forEach((s) => s.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach((n) => n.classList.remove('active'));

  const sec = getEl(id);
  if (sec) sec.classList.add('active');
  const nav = document.querySelector(`.nav-item[data-section="${id}"]`);
  if (nav) nav.classList.add('active');

  const titleEl = getEl('topbarTitle');
  if (titleEl) titleEl.textContent = SECTION_TITLES[id] || id;

  const iconEl = getEl('topbarIcon');
  if (iconEl) iconEl.innerHTML = `<i class="fas ${SECTION_ICONS[id] || 'fa-code-branch'}"></i>`;

  // === Controller Services (existing pattern) ===
  if (id === 'controller-services' && !state.controllerServicesLoaded) {
    loadControllerServices();
    state.controllerServicesLoaded = true;
  }

  // === Parameter Contexts - Load only once (like Controller Services) ===
  if (id === 'param-contexts' && !state.paramContextsLoaded) {
    listParamContexts();
    state.paramContextsLoaded = true;
  }

  if (id === 'registries') listRegistries();
}

export function toggleImportSource() {
  const src = getValue('flowImportSource');
  console.log(`[UI] Toggle import source to ${src}`);

  const host = getEl('hostConfig');
  const repo = getEl('repositoryConfig');

  if (host) host.classList.toggle('hidden', src !== 'host');
  if (repo) repo.classList.toggle('hidden', src !== 'repository');

  if (src === 'repository') setTimeout(loadGitHubBuckets, 80);
}

/**
 * Same rules as config-idol updateHomeBtnHref():
 * - Prefer live DOM (#hostIp, #extraIpSans, #ipToggleSwitch) when present
 * - Else read idol_* values from localStorage (set by the IDOL wizard)
 * - Extra IP SANs still default (== Host IP or empty) → stay on localhost
 * - Only a customized Extra IP SANs value moves Back to Home to that IP
 */
export function updateHomeBtnHref() {
  const homeBtn = document.getElementById('homeBtn');
  if (!homeBtn) return;

  const hostIp =
    (document.getElementById('hostIp')?.value || '').trim() ||
    (localStorage.getItem('idol_hostIp') || '').trim();

  const extraIpSansVal =
    (document.getElementById('extraIpSans')?.value || '').trim() ||
    (localStorage.getItem('idol_extraIpSans') || '').trim();

  const extraIps = (extraIpSansVal || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

  const isDefault = !extraIpSansVal || extraIpSansVal === hostIp;

  // On IDOL the toggle defaults to checked; on NiFi the element is missing → treat as on
  const ipToggle = document.getElementById('ipToggleSwitch');
  const useIp = ipToggle ? ipToggle.checked : true;

  if (useIp && !isDefault && extraIps.length > 0) {
    homeBtn.href = `http://${extraIps[0]}:5000`;
  } else {
    homeBtn.href = 'http://localhost:5000';
  }
}
