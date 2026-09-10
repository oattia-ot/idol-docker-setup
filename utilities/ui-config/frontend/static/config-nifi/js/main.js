/**
 * main.js — application entry point.
 * Loaded via: <script type="module" src="/static/js/main.js"></script>
 */
import { injectContextListStyles } from './styles/injectStyles.js';

import { copyToClipboard } from './core/clipboard.js';
import { state } from './core/state.js';

import { loadIdolDynamicNifiCredentials } from './idol/idolCredentials.js';

import {
  testNiFiConnection, testGitHubConnection,
  exportConfigToFile, importConfigFromFile, resetConfig,
  loadConfig,
} from './settings/configManager.js';
import {
  saveConfigToLocalStorage, loadConfigFromLocalStorage, clearLocalStorageConfig,
  toggleAutoSave, attachAutoSaveListeners, loadInitialPersistedConfig,
} from './settings/localStoragePersistence.js';

import {
  listParamContexts, deleteParamContext, debouncedFilterParamContexts, clearAllParameterContexts,
} from './paramContexts/paramContextsList.js';
import { viewParamContext, hideInlineParamDetail } from './paramContexts/paramContextsView.js';
import {
  showUpdateParamContext, addInlineParameter, removeInlineParameter,
  syncFromInlineJSON, formatInlineJSON, validateInlineJSON, saveInlineParameterContext,
} from './paramContexts/paramContextsEditor.js';
import { showCreateParamContext, createParamContext } from './paramContexts/paramContextsCreate.js';

import {
  loadControllerServices, clearControllerServiceFilters, exportControllerServices,
  debouncedLoadServices,
} from './controllerServices/controllerServicesList.js';
import {
  enableControllerService, disableControllerService, deleteControllerService,
  bulkEnableServices, bulkDisableServices, bulkDisableServicesInternal,
} from './controllerServices/controllerServicesActions.js';
import {
  editControllerService, viewControllerService, saveInlineControllerService, validateControllerServiceProperties,
} from './controllerServices/controllerServicesEditor.js';

import {
  loadHostFolderFlows, importFlowFromHost, importSelectedHostFlows,
  toggleHostFlowSelection, resetAllSelections,
} from './flows/hostFlows.js';
import {
  loadGitHubBuckets, loadRepositoryFlows, importFlowFromRepository,
  displayImportedGithubRegistryFlows, debouncedFilterGitHubFlows,
} from './flows/githubFlows.js';
import { listRegistries, listBuckets, listFlows, uploadToRepository } from './flows/registries.js';

import { triggerFileUpload, initUploadDropZone } from './upload/fileUpload.js';
import { checkNiFiApiStatus, debouncedNiFiCheck } from './nifiStatus/nifiApiStatus.js';
import { showSection, toggleImportSource, updateHomeBtnHref } from './ui/navigation.js';
import { getEl, closeModal, getValue } from './core/domUtils.js';

// ---------------------------------------------------------------------------
// Inline `onclick="..."` handlers in the existing HTML reference these names
// on `window`. Centralizing the exposure here keeps every module itself free
// of global-namespace pollution.
// ---------------------------------------------------------------------------
function exposeGlobals() {
  Object.assign(window, {
    copyToClipboard,

    testNiFiConnection,
    testGitHubConnection,
    exportConfigToFile,
    importConfigFromFile,
    resetConfig,

    saveConfigToLocalStorage: () => saveConfigToLocalStorage(true),
    loadConfigFromLocalStorage: () => loadConfigFromLocalStorage({ toggleImportSource, loadControllerServices }),
    clearLocalStorageConfig: () => clearLocalStorageConfig({ toggleImportSource }),
    toggleAutoSave,
    loadIdolDynamicNifiCredentials,

    listParamContexts,
    clearAllParameterContexts,
    viewParamContext: (id) => viewParamContext(id, showUpdateParamContext, () => hideInlineParamDetail(listParamContexts)),
    showUpdateParamContext,
    deleteParamContext,
    showCreateParamContext,
    createParamContext,
    hideInlineParamDetail: () => hideInlineParamDetail(listParamContexts),
    addInlineParameter,
    removeInlineParameter,
    syncFromInlineJSON,
    formatInlineJSON,
    validateInlineJSON,
    saveInlineParameterContext,
    debouncedFilterParamContexts,

    loadControllerServices,
    clearControllerServiceFilters,
    exportControllerServices,
    bulkEnableServices,
    bulkDisableServices,
    bulkDisableServicesInternal,
    enableControllerService,
    disableControllerService,
    deleteControllerService,
    editControllerService,
    viewControllerService,
    saveInlineControllerService,
    validateControllerServiceProperties,
    debouncedLoadServices,

    loadHostFolderFlows,
    importFlowFromHost,
    importSelectedHostFlows,
    toggleHostFlowSelection,
    resetAllSelections,

    loadGitHubBuckets,
    loadRepositoryFlows,
    importFlowFromRepository,
    displayImportedGithubRegistryFlows,
    debouncedFilterGitHubFlows,

    listRegistries,
    listBuckets,
    listFlows,
    uploadToRepository,
    triggerFileUpload,

    toggleImportSource,
    showSection,
    closeModal,

    checkNiFiApiStatus,
    debouncedNiFiCheck,
  });
}

function initInterface() {
  console.log('[UI] Initializing interface');
  document.querySelectorAll('.nav-item').forEach((item) => {
    item.addEventListener('click', () => showSection(item.dataset.section));
  });

  loadConfig();
  loadInitialPersistedConfig({ toggleImportSource });
  attachAutoSaveListeners({ debouncedNiFiCheck });

  document.querySelectorAll('.info-message').forEach((el) => { el.style.display = 'none'; });
  const d = getEl('currentDate');
  if (d) d.textContent = new Date().toISOString().split('T')[0];
  toggleImportSource();

  console.log('[STARTUP] Scheduling optimized auto-load...');
  requestAnimationFrame(() => {
    console.log('[STARTUP] Running auto-load for all sections');
    listParamContexts();
    loadControllerServices();
    listRegistries();
    loadHostFolderFlows();
    displayImportedGithubRegistryFlows();
  });

  if (getValue('flowImportSource') === 'repository') {
    setTimeout(loadGitHubBuckets, 800);
  }

  console.log('[UI] Initialization complete');
}

function ensureInit() {
  initInterface();
  console.log('[NIFI UI] ✅ initInterface executed – all clicks restored');

  setTimeout(() => {
    const url = document.getElementById('nifiApiUrl')?.value?.trim();
    if (url) {
      console.log('[STARTUP] nifiApiUrl found after init – running initial reachability check');
      checkNiFiApiStatus();
    } else {
      // No URL yet — leave the "no reachability check" path handled inside checkNiFiApiStatus
      const badge = document.getElementById('nifiApiStatusBadge');
      if (badge) checkNiFiApiStatus();
    }
  }, 600);
}

function bootstrap() {
  injectContextListStyles();
  exposeGlobals();
  initUploadDropZone();

  console.log('%c[NiFi Config] Page loaded - initializing...', 'color:#0ea5e9');

  ensureInit();
  updateHomeBtnHref();
  loadConfig();

  setTimeout(() => {
    console.log('%c[NiFi Config] Auto-loading Parameter Contexts...', 'color:#22c55e');
    listParamContexts();
  }, 700);

  loadControllerServices();
  testNiFiConnection();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', bootstrap, { once: true });
} else {
  bootstrap();
}

console.log('[NIFI UI] ✅ Full modular script ready – Edit button only for INVALID services + Validate button in inline editor');
