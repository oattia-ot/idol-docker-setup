import { FIELDS_TO_SAVE } from '../config/constants.js';
import { state } from '../core/state.js';
import { showToast } from '../core/notifications.js';
import { showAlert } from '../core/notifications.js';

let isSaving = false;
let pending = false;

/**
 * Debounced/serialized save of tracked form fields to localStorage.
 * @param {boolean} [force]
 */
export function saveConfigToLocalStorage(force = false) {
  if (isSaving) { pending = true; return; }
  if (!force && !state.autoSaveEnabled) return;
  isSaving = true;
  try {
    const saveData = {};
    FIELDS_TO_SAVE.forEach((id) => {
      const el = document.getElementById(id);
      if (el) saveData[id] = el.type === 'checkbox' ? el.checked : el.value;
    });
    const flowSource = document.getElementById('flowImportSource');
    if (flowSource) saveData.flowImportSource = flowSource.value;
    const autoSaveCb = document.getElementById('autoSaveToggle');
    if (autoSaveCb) saveData.autoSaveEnabled = autoSaveCb.checked;
    localStorage.setItem('nifiPersistedConfig', JSON.stringify(saveData));
    if (force) showToast('Configuration saved to browser storage');
    console.log('[STORAGE] Saved config to localStorage', force ? '(forced)' : '');
  } catch (e) {
    console.error('[STORAGE] Error saving to localStorage:', e);
  } finally {
    isSaving = false;
    if (pending) { pending = false; saveConfigToLocalStorage(force); }
  }
}

function applyPersistedFields(data, { toggleImportSource, loadControllerServices } = {}) {
  FIELDS_TO_SAVE.forEach((id) => {
    if (Object.prototype.hasOwnProperty.call(data, id)) {
      const el = document.getElementById(id);
      if (el) {
        if (el.type === 'checkbox') el.checked = data[id];
        else el.value = data[id];
      }
    }
  });
  const flowSource = document.getElementById('flowImportSource');
  if (flowSource && data.flowImportSource) flowSource.value = data.flowImportSource;
  const autoSaveCb = document.getElementById('autoSaveToggle');
  if (autoSaveCb && Object.prototype.hasOwnProperty.call(data, 'autoSaveEnabled')) {
    autoSaveCb.checked = data[id];
    state.autoSaveEnabled = data.autoSaveEnabled;
  } else if (autoSaveCb) {
    autoSaveCb.checked = true;
    state.autoSaveEnabled = true;
  }
  if (typeof toggleImportSource === 'function') toggleImportSource();
  if (typeof loadControllerServices === 'function') loadControllerServices();
}

/** @param {{toggleImportSource?: Function, loadControllerServices?: Function}} deps */
export function loadConfigFromLocalStorage(deps = {}) {
  console.log('[STORAGE] Loading config from localStorage');
  const saved = localStorage.getItem('nifiPersistedConfig');
  if (!saved) { showToast('No saved configuration found', 'var(--warning)'); return; }
  state.isUpdating = true;
  try {
    applyPersistedFields(JSON.parse(saved), deps);
    showToast('Configuration loaded from browser storage');
    console.log('[STORAGE] Load successful');
  } catch (e) {
    console.error('[STORAGE] Failed to load saved config:', e);
    showAlert('Failed to load saved config: ' + e.message, 'error');
  } finally {
    state.isUpdating = false;
  }
}

/** @param {{toggleImportSource?: Function}} deps */
export function clearLocalStorageConfig(deps = {}) {
  console.log('[STORAGE] Clearing localStorage config');
  state.isUpdating = true;
  try {
    localStorage.removeItem('nifiPersistedConfig');
    FIELDS_TO_SAVE.forEach((id) => {
      const el = document.getElementById(id);
      if (el) {
        if (el.type === 'checkbox') el.checked = false;
        else el.value = '';
      }
    });
    const flowSource = document.getElementById('flowImportSource');
    if (flowSource) flowSource.value = 'repository';
    const autoSaveCb = document.getElementById('autoSaveToggle');
    if (autoSaveCb) { autoSaveCb.checked = true; state.autoSaveEnabled = true; }
    if (typeof deps.toggleImportSource === 'function') deps.toggleImportSource();
    showToast('Cleared saved configuration from browser storage');
  } finally {
    state.isUpdating = false;
  }
}

export function toggleAutoSave() {
  const cb = document.getElementById('autoSaveToggle');
  state.autoSaveEnabled = cb ? cb.checked : true;
  console.log(`[STORAGE] Auto-save ${state.autoSaveEnabled ? 'enabled' : 'disabled'}`);
  showToast(`Auto-save ${state.autoSaveEnabled ? 'enabled' : 'disabled'}`);
  saveConfigToLocalStorage(true);
}

/**
 * @param {{debouncedNiFiCheck?: Function}} deps
 */
export function attachAutoSaveListeners(deps = {}) {
  console.log('[STORAGE] Attaching auto-save listeners');
  const saveIfAuto = () => {
    if (!state.isUpdating && state.autoSaveEnabled) saveConfigToLocalStorage(false);
  };
  FIELDS_TO_SAVE.forEach((id) => {
    const el = document.getElementById(id);
    if (el) {
      el.addEventListener('input', saveIfAuto);
      el.addEventListener('change', saveIfAuto);
    }
  });

  const nifiUrlInput = document.getElementById('nifiApiUrl');
  if (nifiUrlInput && typeof deps.debouncedNiFiCheck === 'function') {
    nifiUrlInput.addEventListener('input', deps.debouncedNiFiCheck);
  }

  const flowSource = document.getElementById('flowImportSource');
  if (flowSource) flowSource.addEventListener('change', saveIfAuto);
}

/** @param {{toggleImportSource?: Function}} deps */
export function loadInitialPersistedConfig(deps = {}) {
  console.log('[STORAGE] Initial load of persisted config');
  const saved = localStorage.getItem('nifiPersistedConfig');
  if (!saved) {
    const autoSaveCb = document.getElementById('autoSaveToggle');
    if (autoSaveCb) autoSaveCb.checked = true;
    state.autoSaveEnabled = true;
  } else {
    state.isUpdating = true;
    try {
      applyPersistedFields(JSON.parse(saved), deps);
      console.log('[STORAGE] Initial load successful');
    } catch (e) {
      console.error('[STORAGE] Initial load parse error:', e);
    } finally {
      state.isUpdating = false;
    }
  }

  import('../idol/idolCredentials.js').then(({ loadIdolDynamicNifiCredentials }) => loadIdolDynamicNifiCredentials());

  fetch('/config-idol/env/nifi-flows-dir')
    .then((res) => res.json())
    .then((data) => {
      const span = document.getElementById('target-dir-display');
      if (span) span.textContent = data.dir;
      console.log(`[IDOL] Target directory set to: ${data.dir}`);
    })
    .catch((err) => console.warn('[IDOL] Failed to fetch IDOL_NIFI_FLOWS_DIR:', err));
}

export function updateTargetDirDisplay() {
  console.log('[updateTargetDirDisplay] Function called');
  fetch('/config-idol/env/pre-setup-dir')
    .then((res) => {
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return res.json();
    })
    .then((data) => {
      const span = document.getElementById('target-dir-display');
      if (span) span.textContent = data.dir;
    })
    .catch((err) => console.error('[updateTargetDirDisplay] Fetch failed:', err));
}
