/**
 * Shared mutable application state.
 * Centralizing this avoids scattered `let` globals while keeping the
 * simple "shared object" model the original script relied on.
 */
export const state = {
  // Host flow selection
  selectedHostFlows: new Set(),
  currentHostScanRoot: '/nifi-flows',
  importResults: new Map(),

  // Controller services
  serviceOperationStatus: {},
  allControllerServices: [],
  controllerServicesLoaded: false,
  controllerServicesDataLoaded: false,
  isReloading: false,
  lastLoadTime: 0,

  // Parameter context inline editor
  currentEditContextId: null,
  currentEditRevision: null,
  currentEditParameters: [],
  newParamCounter: 1,
  editFormAbortController: null,
  allParamContexts: [],
  paramContextFilter: '',
  paramContextsLoaded: false,

  // Controller service inline editor
  currentEditCSId: null,
  currentEditCSRevision: null,
  currentEditCSProperties: {},
  editCSAbortController: null,

  // Config import/export
  importedConfig: null,

  // GitHub filter debounce
  githubFilterTimeout: null,
  paramFilterTimeout: null,
  controllerDebounce: null,

  // LocalStorage persistence
  autoSaveEnabled: true,
  isUpdating: false,

  // NiFi reachability polling
  nifiRetryTimer: null,
  nifiCheckTimer: null,
};
