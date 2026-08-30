'use strict';

const ENABLE_LOCALSTORAGE = true;
let nifiGroupOriginalParent = null;
let HOST = 'idol-docker-host';

// ==================== 1. IMMEDIATE CHROME EXTENSION NOISE SUPPRESSION ====================
// Must be at the VERY TOP of the file to catch errors before anything else runs
(function killChromeExtensionSpam() {
  const isSpam = (msg) => {
    if (!msg) return false;
    const s = msg.toString().toLowerCase();
    return s.includes('message channel closed') ||
           s.includes('runtime.lasterror') ||
           s.includes('receiving end does not exist') ||
           s.includes('could not establish connection') ||
           s.includes('asynchronous response');
  };

  // Toggle switch → regenerate all URLs
  window.addEventListener('change', function(e) {
    if (e.target.id === 'hostToggleSwitch') {
      const fqdnInput = document.getElementById('fqdn');
      if (e.target.checked && !fqdnInput?.value.trim()) {
        showToast('Please enter an FQDN first', true);
        e.target.checked = false;
        return;
      }
      updateInfoSectionUrls();
      showToast(`Using ${e.target.checked ? 'FQDN' : 'idol-docker-host'} for links`);
    }

    if (e.target.id === 'ipToggleSwitch') {
      const hostIp = document.getElementById('hostIp')?.value?.trim();
      if (e.target.checked && !hostIp) {
        showToast('Please enter a Host IP first', true);
        e.target.checked = false;
        return;
      }
      updateInfoSectionUrls();
      showToast(`Using ${e.target.checked ? hostIp : 'idol-docker-host'} for links`);
    }
  });

  // FQDN input → regenerate URLs if toggle is active
  window.addEventListener('input', function(e) {
    if (e.target.id === 'fqdn') {
      const toggle = document.getElementById('hostToggleSwitch');
      if (toggle?.checked) updateInfoSectionUrls();
    }
    if (e.target.id === 'hostIp') {
      const toggle = document.getElementById('ipToggleSwitch');
      if (toggle?.checked) updateInfoSectionUrls();
    }
  });

  // Catch promise rejections immediately
  window.addEventListener('unhandledrejection', function(e) {
    if (isSpam(e.reason)) {
      e.preventDefault();
      e.stopImmediatePropagation();
      return false;
    }
  }, true);

  // Catch all window errors
  window.addEventListener('error', function(e) {
    if (isSpam(e.message)) {
      e.preventDefault();
      e.stopImmediatePropagation();
      return false;
    }
  }, true);

  // Override console.error
  const oldError = console.error;
  console.error = function(...args) {
    if (args.some(arg => isSpam(arg))) return;
    oldError.apply(console, args);
  };

  console.log('%c✅ Chrome extension spam fully suppressed (IDOL Setup Manager)', 'color:#10b981; font-weight:600');
})();

/* ====================== 2. CONSTANTS & CONFIGURATION ====================== */
const DYNAMIC_NIFI_FIELDS = [
  'dyn-nifi-link',
  'dyn-nifi-username',
  'dyn-nifi-password'
];

function saveDynamicNifiFields() {
  DYNAMIC_NIFI_FIELDS.forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;

    let value = '';
    if (id === 'dyn-nifi-link') {
      value = (el.tagName === 'A' ? el.href : el.textContent) || el.textContent || '';
    } else {
      value = el.textContent.trim();
    }

    localStorage.setItem(`idol_dyn_${id}`, value);
  });
}

function loadDynamicNifiFields() {
  DYNAMIC_NIFI_FIELDS.forEach(id => {
    const savedValue = localStorage.getItem(`idol_dyn_${id}`);
    if (!savedValue) return;

    const el = document.getElementById(id);
    if (!el) return;

    if (id === 'dyn-nifi-link') {
      const anchor = el.tagName === 'A' ? el : el.querySelector('a');
      if (anchor) {
        anchor.href = savedValue;
        anchor.innerHTML = `${savedValue} <i class="fas fa-external-link-alt" style="font-size:10px;"></i>`;
      }
    } else {
      el.textContent = savedValue;
    }
  });
}

function updateExtraIpSans() {
  // Keeps the "Use IP address" toggle label / Back to Home link in sync as the user types
  updateInfoSectionUrls();
  updateHomeBtnHref();
  highlightExtraIpSansDiff();
}

function highlightExtraIpSansDiff() {
  // Visually flags Extra IP SANs in orange/bold when it has been overridden
  // to something other than the Host IP (its default).
  const hostIp = document.getElementById('hostIp')?.value?.trim() || '';
  const extraIpSansEl = document.getElementById('extraIpSans');
  if (!extraIpSansEl) return;

  const extraIpSansVal = extraIpSansEl.value.trim();

  if (extraIpSansVal !== '' && extraIpSansVal !== hostIp) {
    extraIpSansEl.style.color = '#f59e0b';
    extraIpSansEl.style.fontWeight = '600';
  } else {
    extraIpSansEl.style.color = '';
    extraIpSansEl.style.fontWeight = '';
  }
}

function updateHomeBtnHref() {
  const ipToggle = document.getElementById('ipToggleSwitch');
  const homeBtn  = document.getElementById('homeBtn');

  if (!homeBtn) return;

  const hostIp        = document.getElementById('hostIp')?.value?.trim() || '';
  const extraIpSansVal = document.getElementById('extraIpSans')?.value?.trim() || '';
  const extraIps       = parseExtraIpSans(extraIpSansVal);
  const isDefault      = !extraIpSansVal || extraIpSansVal === hostIp;

  // Extra IP SANs still at its default (== Host IP, untouched) → Back to Home stays on localhost.
  // Only once the user overrides it with a different value does Back to Home follow that value.
  if (ipToggle && ipToggle.checked && !isDefault && extraIps.length > 0) {
    homeBtn.href = `http://${extraIps[0]}:5000`;
  } else {
    homeBtn.href = 'http://localhost:5000';
  }
}

// PORT DEFINITIONS
const UI_PORTS = [
  { id:'nifiPort', statusId:'nifiPortStatus', warnId:'nifiPortWarning', dupeId:'nifiPortDupeWarning', label:'NiFi Secure Port', def:8443, range:false }
];

const DA_PORTS = [
  { id: 'findUiPort',         statusId: 'findUiPortStatus',         warnId: 'findUiPortWarning',         dupeId: 'findUiPortDupeWarning',         label: 'Find UI HTTPS',               range: true, rangeSize: 2, aciId: 'findUiPortBaseIdol',    idxId: 'findUiPortDataAdmin' },
  { id: 'dataAdminHttpsUiPort', statusId: 'dataAdminHttpsUiPortStatus', warnId: 'dataAdminHttpsUiPortWarning', dupeId: 'dataAdminHttpsUiPortDupeWarning', label: 'Data Admin HTTPS UI', range: true, rangeSize: 2, aciId: 'dataAdminHttpsBase', idxId: 'dataAdminInternalUiPort' },
  { id:'communityPort', statusId:'communityPortStatus', warnId:'communityPortWarning', dupeId:'communityPortDupeWarning', label:'DA Community', envKey:'PORT_DATA_ADMIN_COMMUNITY', def:9033, range:true, aciId:'communityAci', idxId:'communityIdx', svcId:'communitySvc' },
  { id:'viewServerPort', statusId:'viewServerPortStatus', warnId:'viewServerPortWarning', dupeId:'viewServerPortDupeWarning', label:'DA View Server', envKey:'PORT_DATA_ADMIN_VIEW', def:9083, range:true, aciId:'viewAci', idxId:'viewIdx', svcId:'viewSvc' },
  { id:'passageContentPort', statusId:'passageContentPortStatus', warnId:'passageContentPortWarning', dupeId:'passageContentPortDupeWarning', label:'Passage Extractor Content', envKey:'PORT_DATA_ADMIN_PASSAGE_CONTENT', def:9103, range:true, aciId:'passageContentAci', idxId:'passageContentIdx', svcId:'passageContentSvc' },
  { id:'answerServerPort', statusId:'answerServerPortStatus', warnId:'answerServerPortWarning', dupeId:'answerServerPortDupeWarning', label:'Answer Server', envKey:'PORT_DATA_ADMIN_ANSWER_SERVER', def:12000, range:true, aciId:'answerServerAci', idxId:'answerServerIdx', svcId:'answerServerSvc' },
  { id:'answerBankAgentPort', statusId:'answerBankAgentPortStatus', warnId:'answerBankAgentPortWarning', dupeId:'answerBankAgentPortDupeWarning', label:'Answer Bank AgentStore', envKey:'PORT_DATA_ADMIN_ANSWER_BANK_AGENTSTORE', def:12200, range:true, aciId:'answerBankAci', idxId:'answerBankIdx', svcId:'answerBankSvc' },
  { id:'passageAgentPort', statusId:'passageAgentPortStatus', warnId:'passageAgentPortWarning', dupeId:'passageAgentPortDupeWarning', label:'Passage Extractor AgentStore', envKey:'PORT_DATA_ADMIN_PASSAGE_AGENTSTORE', def:12310, range:true, aciId:'passageAgentAci', idxId:'passageAgentIdx', svcId:'passageAgentSvc' },
  { id:'qmsPort', statusId:'qmsPortStatus', warnId:'qmsPortWarning', dupeId:'qmsPortDupeWarning', label:'QMS', envKey:'PORT_DATA_ADMIN_QMS', def:16000, range:true, aciId:'qmsAci', idxId:'qmsIdx', svcId:'qmsSvc' },
  { id:'qmsAgentPort', statusId:'qmsAgentPortStatus', warnId:'qmsAgentPortWarning', dupeId:'qmsAgentPortDupeWarning', label:'QMS AgentStore', envKey:'PORT_DATA_ADMIN_QMS_AGENTSTORE', def:20050, range:true, aciId:'qmsAgentAci', idxId:'qmsAgentIdx', svcId:'qmsAgentSvc' },
  { id:'statsServerPort', statusId:'statsServerPortStatus', warnId:'statsServerPortWarning', dupeId:'statsServerPortDupeWarning', label:'Stats Server', envKey:'PORT_DATA_ADMIN_STATS_SERVER', def:19870, range:true, aciId:'statsAci', idxId:'statsIdx', svcId:'statsSvc' }
];

const BI_PORTS = [
  { id:'biContentPort', statusId:'biContentPortStatus', warnId:'biContentPortWarning', dupeId:'biContentPortDupeWarning', label:'BI Content', envKey:'PORT_BASIC_IDOL_CONTENT', def:9100, range:true, aciId:'biContentAci', idxId:'biContentIdx', svcId:'biContentSvc' },
  { id:'biAgentStorePort', statusId:'biAgentStorePortStatus', warnId:'biAgentStorePortWarning', dupeId:'biAgentStorePortDupeWarning', label:'BI AgentStore', envKey:'PORT_BASIC_IDOL_AGENTSTORE', def:9050, range:true, aciId:'biAgentStoreAci', idxId:'biAgentStoreIdx', svcId:'biAgentStoreSvc' },
  { id:'biCategoryPort', statusId:'biCategoryPortStatus', warnId:'biCategoryPortWarning', dupeId:'biCategoryPortDupeWarning', label:'BI Category', envKey:'PORT_BASIC_IDOL_CATEGORY', def:9020, range:true, aciId:'biCategoryAci', idxId:'biCategoryIdx', svcId:'biCategorySvc' },
  { id:'biCatAgentStorePort', statusId:'biCatAgentStorePortStatus', warnId:'biCatAgentStorePortWarning', dupeId:'biCatAgentStorePortDupeWarning', label:'BI Cat. AgentStore', envKey:'PORT_BASIC_IDOL_CATEGORISATION_AGENTSTORE', def:9180, range:true, aciId:'biCatAgentStoreAci', idxId:'biCatAgentStoreIdx', svcId:'biCatAgentStoreSvc' },
  { id:'biCommunityPort', statusId:'biCommunityPortStatus', warnId:'biCommunityPortWarning', dupeId:'biCommunityPortDupeWarning', label:'BI Community', envKey:'PORT_BASIC_IDOL_COMMUNITY', def:9030, range:true, aciId:'biCommunityAci', idxId:'biCommunityIdx', svcId:'biCommunitySvc' },
  { id:'biViewPort', statusId:'biViewPortStatus', warnId:'biViewPortWarning', dupeId:'biViewPortDupeWarning', label:'BI View', envKey:'PORT_BASIC_IDOL_VIEW', def:9080, range:true, aciId:'biViewAci', idxId:'biViewIdx', svcId:'biViewSvc' }
];

const RM_PORTS = [
  { id:'rmMediaServerPort', statusId:'rmMediaServerPortStatus', warnId:'rmMediaServerPortWarning', dupeId:'rmMediaServerPortDupeWarning', label:'Media Server', envKey:'PORT_RICH_MEDIA_MEDIASERVER', def:14000, range:true, rangeSize:4, aciId:'rmMediaServerAci', p1Id:'rmMediaServerSvc', p2Id:'rmMediaServerSrvSSL', p3Id:'rmMediaServerSvcSSL' },
  { id:'rmMediaServerPlaylistPort', statusId:'rmMediaServerPlaylistPortStatus', warnId:'rmMediaServerPlaylistPortWarning', dupeId:'rmMediaServerPlaylistPortDupeWarning', label:'Media Server Playlist', envKey:'PORT_RICH_MEDIA_PLAYLIST', def:24000, range:true, rangeSize:2, aciId:'rmMediaServerPlaylistAci', p1Id:'rmMediaServerPlaylistSvc' },
  { id:'mediaServerHttpUiPort', statusId:'mediaServerHttpUiPortStatus', warnId:'mediaServerHttpUiPortWarning', dupeId:'mediaServerHttpUiPortDupeWarning', label:'Media Server Application UI', envKey:'PORT_RICH_MEDIA_UI_PORTAL', def:8003, range:true, rangeSize:2, aciId:'mediaServerHttpUiAci', p1Id:'mediaServerHttpUiSvc' }
];

const ALL_RANGE_PORTS = [...DA_PORTS, ...BI_PORTS, ...RM_PORTS];

const HTTPD_PORTS = [
  { id:'basicIdolHttpdPort',     statusId:'basicIdolHttpdPortStatus',     warnId:'basicIdolHttpdPortWarning',     dupeId:'basicIdolHttpdPortDupeWarning',     label:'Basic IDOL HTTPD',     def:8330, range:false }
];

const ALL_PORTS = [...UI_PORTS, ...HTTPD_PORTS, ...ALL_RANGE_PORTS];

const ENV_VAR_ORDER = [
  'SOURCE_IDOL_LICENSE_KEY_PATH','SOURCE_IDOL_LICENSE_SERVER_PATH',
  'IS_IDOL_NIFI_GITHUB_INTEGRATION','IS_IDOL_NIFI_PRESERVE','IS_IDOL_NIFI_REGISTRY_PRESERVE','IS_IDOL_PRESERVE','IS_IDOL_VALIDATION_MET','IS_IDOL_LICENSE_ACTIVE',
  'GITHUB_REPO','GITHUB_TOKEN','GITHUB_USER',
  'IDOL_BASE_PATH','IDOL_SHARED_FOLDER_PATH','IDOL_DEPLOYMENT_TYPE','IDOL_DEPLOYMENT_SUBTYPE','IDOL_TOOLKIT_PATH','IDOL_DEPLOYMENT_NETWORK',
  'IDOL_SERVER_VERSION','IDOL_DATA_ADMIN_VERSION','IDOL_RICH_MEDIA_VERSION','IDOL_NIFI_DEPLOY_VERSION',
  'IDOL_HOST_FQDN','IDOL_HOST_STORAGE_PATH','IDOL_NET_GUEST_IP','IDOL_NET_HOST_IP','EXTRA_IP_SANS_ENV','IDOL_DRIVER_TYPE',
  'IDOL_BASIC_INSTALL','IDOL_DATA_ADMIN_INSTALL','IDOL_RICH_MEDIA_INSTALL',
  'IDOL_LICENSESERVER_MODE','IDOL_LICENSESERVER_NAME','IDOL_LICENSESERVER_URL','IDOL_LICENSESERVER_PROTOCOL','IDOL_LICENSESERVER_FQDN','IDOL_LICENSESERVER_PORT',
  'IDOL_LICENSE_KEY_HOSTNAME','IDOL_LICENSE_KEY_MAC','IDOL_LICENSE_KEY_MAIL','IDOL_LICENSE_KEY_TOKEN',
  'IDOL_NIFI_DATA_PATH','IDOL_NIFI_SCRIPTS_PATH','IDOL_NIFI_DEPLOY_TYPE',
  'IDOL_NIFI_REGISTRY_PATH',
  'IS_IDOL_NIFI_CONNECTOR_NAR_IMPORT','IDOL_NIFI_CONNECTOR_NAR_PATH',
  'IDOL_PRESERVE_AGENTSTORE_PATH','IDOL_PRESERVE_ANSWERBANK_AGENTSTORE_PATH',
  'IDOL_PRESERVE_ANSWERSERVER_PATH','IDOL_PRESERVE_CATEGORY_PATH','IDOL_PRESERVE_CATEGORISATION_AGENTSTORE_PATH',
  'IDOL_PRESERVE_COMMUNITY_PATH','IDOL_PRESERVE_CONTENT_PATH','IDOL_PRESERVE_DATAADMIN_COMMUNITY_PATH',
  'IDOL_PRESERVE_DATAADMIN_PATH','IDOL_PRESERVE_DATAADMIN_STATSSERVER_PATH','IDOL_PRESERVE_DATAADMIN_VIEWSERVER_PATH',
  'IDOL_PRESERVE_FIND_PATH','IDOL_PRESERVE_IDOL_COMMON_CFG_FILENAME','IDOL_PRESERVE_IDOL_COMMON_CFG_PATH',
  'IDOL_PRESERVE_LICENSESERVER_CFG_PATH','IDOL_PRESERVE_PASSAGEEXTRACTOR_AGENTSTORE_PATH',
  'IDOL_PRESERVE_PASSAGEEXTRACTOR_CONTENT_PATH','IDOL_PRESERVE_PATH','IDOL_PRESERVE_QMS_AGENTSTORE_PATH','IDOL_PRESERVE_QMS_PATH',
  'IDOL_VIEW_PATH','IDOL_PRESERVE_MEDIASERVER_PATH','IDOL_MEDIASERVER_PRETRAINE_MODELS_FOLDER_NAME','IDOL_MEDIASERVER_NIFI_POLICY_FOLDER_NAME',
  'HF_TOKEN','IDOL_LLM_API_KEY','IDOL_LLM_ENABLE_APIKEY','IDOL_LLM_INTEGRATION','IDOL_LLM_MODEL_NAME','IDOL_LLM_MODEL_URL','IDOL_LLM_MODEL_PATH','IDOL_LLM_USE_GPU','IDOL_LLM_MODEL_SELECTION','IDOL_LLM_WIKI_ENABLED',
  'IDOL_NIFI_UI_PORT','IDOL_FIND_UI_BASIC_IDOL_PORT','IDOL_FIND_UI_DATA_ADMIN_PORT','IDOL_DATA_ADMIN_HTTPS_UI_PORT','IDOL_DATA_ADMIN_HTTP_UI_PORT','IDOL_DATA_ADMIN_INTERNAL_UI_PORT',
  'PORT_BASIC_IDOL_HTTPD_REVERSE',
  'PORT_BASIC_IDOL_AGENTSTORE','PORT_BASIC_IDOL_AGENTSTORE_INDEX','PORT_BASIC_IDOL_AGENTSTORE_SERVICE',
  'PORT_BASIC_IDOL_CATEGORISATION_AGENTSTORE','PORT_BASIC_IDOL_CATEGORISATION_AGENTSTORE_INDEX','PORT_BASIC_IDOL_CATEGORISATION_AGENTSTORE_SERVICE','PORT_BASIC_IDOL_CATEGORISATION_AGENTSTORE_QUERY',
  'PORT_BASIC_IDOL_CATEGORY','PORT_BASIC_IDOL_CATEGORY_INDEX','PORT_BASIC_IDOL_CATEGORY_SERVICE',
  'PORT_BASIC_IDOL_COMMUNITY','PORT_BASIC_IDOL_COMMUNITY_INDEX','PORT_BASIC_IDOL_COMMUNITY_SERVICE',
  'PORT_BASIC_IDOL_CONTENT','PORT_BASIC_IDOL_CONTENT_INDEX','PORT_BASIC_IDOL_CONTENT_SERVICE',
  'PORT_BASIC_IDOL_VIEW','PORT_BASIC_IDOL_VIEW_INDEX','PORT_BASIC_IDOL_VIEW_SERVICE',
  'PORT_DATA_ADMIN_ANSWER_BANK_AGENTSTORE','PORT_DATA_ADMIN_ANSWER_BANK_AGENTSTORE_INDEX','PORT_DATA_ADMIN_ANSWER_BANK_AGENTSTORE_SERVICE',
  'PORT_DATA_ADMIN_ANSWER_SERVER','PORT_DATA_ADMIN_ANSWER_SERVER_INDEX','PORT_DATA_ADMIN_ANSWER_SERVER_SERVICE',
  'PORT_DATA_ADMIN_COMMUNITY','PORT_DATA_ADMIN_COMMUNITY_INDEX','PORT_DATA_ADMIN_COMMUNITY_SERVICE',
  'PORT_DATA_ADMIN_PASSAGE_CONTENT','PORT_DATA_ADMIN_PASSAGE_CONTENT_INDEX','PORT_DATA_ADMIN_PASSAGE_CONTENT_SERVICE',
  'PORT_DATA_ADMIN_PASSAGE_AGENTSTORE','PORT_DATA_ADMIN_PASSAGE_AGENTSTORE_INDEX','PORT_DATA_ADMIN_PASSAGE_AGENTSTORE_SERVICE',
  'PORT_DATA_ADMIN_QMS','PORT_DATA_ADMIN_QMS_INDEX','PORT_DATA_ADMIN_QMS_SERVICE',
  'PORT_DATA_ADMIN_QMS_AGENTSTORE','PORT_DATA_ADMIN_QMS_AGENTSTORE_INDEX','PORT_DATA_ADMIN_QMS_AGENTSTORE_SERVICE',
  'PORT_DATA_ADMIN_STATS_SERVER','PORT_DATA_ADMIN_STATS_SERVER_INDEX','PORT_DATA_ADMIN_STATS_SERVER_SERVICE',
  'PORT_DATA_ADMIN_VIEW','PORT_DATA_ADMIN_VIEW_INDEX','PORT_DATA_ADMIN_VIEW_SERVICE',
  'PORT_RICH_MEDIA_MEDIASERVER','PORT_RICH_MEDIA_MEDIASERVER_SSL','PORT_RICH_MEDIA_MEDIASERVER_SERVICE','PORT_RICH_MEDIA_MEDIASERVER_SERVICE_SSL',
  'PORT_RICH_MEDIA_MEDIASERVER_PLAYLISTSERVER','PORT_RICH_MEDIA_MEDIASERVER_PLAYLISTSERVER_SERVICE','PORT_RICH_MEDIA_MEDIASERVER_HTTP_APPLICATION','PORT_RICH_MEDIA_MEDIASERVER_HTTPS_APPLICATION'
];

const fieldConfig = {
  basic: [
    { id:'fqdn', warningId:'fqdnWarning', validate: v => v.trim() !== '', label:'IDOL Host FQDN' },
    { id:'basePath', warningId:'basePathWarning', validate: v => v.trim().startsWith('/'), label:'Base Path' },
    { id:'llmModelPath', warningId:'llmModelPathWarning', validate: v => v.trim() !== '', label:'Target Folder Path for GGUF Models', conditional: () => {
        const llmOn = document.getElementById('llmIntegrationToggle')?.checked || false;
        const llmWikiOn = document.getElementById('llmWikiEnableToggle')?.checked || false;
        const dataAdminOn = document.getElementById('deployTypeDataAdmin')?.checked || false;
        return llmOn && dataAdminOn;
      }
    }
  ],
  network: [
    { id:'hostIp', warningId:'hostIpWarning', validate: v => isValidIp(v), label:'Host IP' },
    { id:'guestIp', warningId:'guestIpWarning', validate: v => isValidIp(v), label:'Guest IP' },
    { id:'extraIpSans', warningId:'extraIpSansWarning', validate: v => isValidExtraIpSans(v), label:'Extra IP SANs', optional: true }
  ],
  nifi: [
    { id:'githubUsername', warningId:'githubUsernameWarning', validate: v => v.trim() !== '', label:'GitHub Username', conditional: () => radioVal('githubIntegration') === 'TRUE' },
    { id:'githubToken', warningId:'githubTokenWarning', validate: v => v.trim() !== '', label:'GitHub Access Token', conditional: () => radioVal('githubIntegration') === 'TRUE' },
    { id:'githubRepo', warningId:'githubRepoWarning', validate: v => v.trim() !== '', label:'GitHub Repo', conditional: () => radioVal('githubIntegration') === 'TRUE' },
    { id:'nifiDataPath', warningId:'nifiDataPathWarning', validate: v => v.trim() !== '', label:'NiFi Data Path', conditional: () => radioVal('nifiPreserve') === 'TRUE' },
    { id:'registryPath', warningId:'registryPathWarning', validate: v => v.trim() !== '', label:'NiFi Registry Path', conditional: () => radioVal('registryPreserve') === 'TRUE' },
    { id:'connectorNarPath', warningId:'connectorNarPathWarning', validate: v => v.trim() !== '', label:'Connector NAR Folder Path', conditional: () => radioVal('connectorNarImport') === 'TRUE' }
  ],
  license: [
    { id:'licenseHostname', warningId:'licenseHostnameWarning', validate: v => v.trim() !== '', label:'License Hostname' },
    { id:'licenseEmail', warningId:'emailWarning', validate: v => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v), label:'Email Address' },
    { id:'licenseMac', warningId:'macWarning', validate: v => /^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$/.test(v), label:'MAC Address' },
    { id:'dockerLicenseToken', warningId:'tokenWarning', validate: v => v.trim().length >= 10, label:'Docker Access Token' },
    { id:'licenseServerPath', warningId:'licenseServerPathWarning', validate: v => v.trim() !== '', label:'License Server Path',    conditional: () => radioVal('licenseMode') !== 'EXISTING' },
    { id:'licenseKeyPath',    warningId:'licenseKeyPathWarning',    validate: v => v.trim() !== '', label:'License Key File Path', conditional: () => radioVal('licenseMode') !== 'EXISTING' },
    { id:'licenseUrl', warningId:'licenseUrlWarning', validate: v => v.trim() !== '', label:'License Server URL', conditional: () => radioVal('licenseMode') === 'EXISTING' }
  ],
  storage: [
    { id:'preservePath', warningId:'preservePathWarning', validate: v => v.trim() !== '', label:'IDOL Preserve Data Path', conditional: () => radioVal('preserve') === 'TRUE' },
    { id:'storagePath', warningId:'storagePathWarning', validate: v => v.trim() !== '', label:'Host Storage Mapping Path' }
  ]
};

const sectionMeta = {
  information: { title:'Information', icon:'fas fa-th-large' },
  basic: { title:'Basic Configuration', icon:'fas fa-star' },
  network: { title:'Network Settings', icon:'fas fa-network-wired' },
  nifi: { title:'NiFi Configuration', icon:'fas fa-stream' },
  ports: { title:'Ports Configuration', icon:'fas fa-plug' },
  license: { title:'License Server', icon:'fas fa-key' },
  storage: { title:'Storage & Paths', icon:'fas fa-database' },
  summary: { title:'Summary & Export', icon:'fas fa-file-export' }
};

const PATH_SUFFIXES = {
  connectorNarPath: '/shared-folder/nifi-connectors',
  nifiDataPath: '/persistent-data/nifi-data',
  registryPath: '/persistent-data/nifi-registry',
  preservePath: '/persistent-data',
  storagePath: '/hotfolder',
  llmModelPath: '/llm-models' 
};

// ==================== SELECTIVE LOCALSTORAGE – ONLY THESE FIELDS ARE SAVED ====================
const FIELDS_TO_SAVE = [
  'basePath',
  'fqdn',
  'hostIp',
  'guestIp',
  'extraIpSans',
  'githubUsername',
  'githubRepo',  
  'preservePath',
  'storagePath',
  'licenseHostname',
  'licenseEmail',
  'licenseMac',
  'dockerLicenseToken',
  'storagePath',
  'licenseServerPath',
  'licenseKeyPath',
  'licenseUrl',
  'nifiDataPath',
  'registryPath',
  'connectorNarPath',
  'llmModelPath',
  'hfToken',
  'llmAPIKey',
  'pretrainedModelsPath',
  'nifiMediaServerPath',
  'dyn_nifi_link',
  'dyn_nifi_username',
  'dyn_nifi_password',
  'licenseMode', 
  'githubIntegration', 
  'nifiPreserve', 
  'registryPreserve', 
  'connectorNarImport',
  'preserve',
  'llmIntegrationToggle', 
  'llmWikiEnableToggle',
  'gpuEnableToggle',
  'llmApiKeyEnabled'
];

const SECTION_ORDER = ['basic','network','nifi','ports','license','storage','summary'];
const touchedFields = new Set();

let portsCheckRan = false;
let allPortsAreFree = false;
let portsConflictsExist = false;
let bypassPortCheck = false;
let isLicenseActive = false;
let currentModels = [];
let autoSaveEnabled = true;

// DEPLOYMENT TYPE
const getDeploymentType = () => {
  const basic = document.getElementById('deployTypeBasic')?.checked || false;
  const dataAdmin = document.getElementById('deployTypeDataAdmin')?.checked || false;
  const richMedia = document.getElementById('deployTypeRichMedia')?.checked || false;
  const selected = [];
  if (basic) selected.push('basic-idol');
  if (dataAdmin) selected.push('data-admin');
  if (richMedia) selected.push('rich-media');
  return selected;
};

/* ====================== 3. GENERAL HELPERS & UTILITIES ====================== */
const radioVal = name => document.querySelector(`input[name="${name}"]:checked`)?.value ?? '';
const isValidIp = v => /^(\d{1,3}\.){3}\d{1,3}$/.test(v.trim()) && v.trim().split('.').every(n => +n >= 0 && +n <= 255);

// Extra IP SANs: optional, comma-separated list — valid if empty, or every entry is a valid IPv4
const parseExtraIpSans = v => (v || '').split(',').map(s => s.trim()).filter(Boolean);
const isValidExtraIpSans = v => {
  const ips = parseExtraIpSans(v);
  return ips.length === 0 || ips.every(isValidIp);
};

function showToast(msg = 'Done!', isError = false) {
  const t = document.getElementById('toast');
  t.style.background = isError ? 'var(--danger)' : 'var(--success)';
  document.getElementById('toastMsg').textContent = msg;
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 2500);
}

function toggleCard(id) { document.getElementById(id)?.classList.toggle('expanded'); }

function togglePortCard(bodyId, chevronId) {
  const body = document.getElementById(bodyId);
  const chevron = document.getElementById(chevronId);
  if (!body) return;
  const isOpen = body.classList.contains('expanded');
  body.classList.toggle('collapsed', isOpen);
  body.classList.toggle('expanded', !isOpen);
  if (chevron) chevron.classList.toggle('open', !isOpen);
}

function toggleSubfolders() {
  const collapse = document.getElementById('subfolderCollapse');
  const chevron = document.getElementById('subfolderChevron');
  const isOpen = collapse.style.display !== 'none';
  collapse.style.display = isOpen ? 'none' : 'block';
  chevron.style.transform = isOpen ? '' : 'rotate(90deg)';
}

function togglePretrainedModelsPath() {
  const toggle = document.getElementById('pretrainedModelsToggle');
  const pathGroup = document.getElementById('pretrainedModelsPathGroup');

  if (!toggle || !pathGroup) {
    console.warn('⚠️ pretrainedModelsToggle or pretrainedModelsPathGroup not found in DOM');
    return;
  }

  pathGroup.style.display = toggle.checked ? 'block' : 'none';

  if (typeof checkBasicNextButton === 'function') {
    checkBasicNextButton();
  }
}

function updateStoragePathHint(value) {
  const base = value.trim() || '<IDOL_HOST_STORAGE_PATH>/hotfolder';
  ['storagePathHint','storageIngestHint','storageStagingHint'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.textContent = base;
  });
}

/* ====================== 4. PATH DERIVATION & AUTO-FILL LOGIC ====================== */
function updatePreservePathFromBase() {
  const baseEl = document.getElementById('basePath');
  const preserveEl = document.getElementById('preservePath');
  if (!baseEl || !preserveEl) return;

  const base = (baseEl.value || '').trim();
  if (!base) return;

  const suffix = PATH_SUFFIXES.preservePath;

  preserveEl.value = base.endsWith('/') 
    ? base + suffix.substring(1) 
    : base + suffix;

  localStorage.setItem('idol_preservePath', preserveEl.value);

  updateNifiAndRegistryPathsFromBase();
}

function updateNifiAndRegistryPathsFromBase() {
  const preserveEl = document.getElementById('preservePath');
  if (!preserveEl) return;
  
  const preserve = (preserveEl.value || '').trim();
  if (!preserve) return;

  const nifiEl = document.getElementById('nifiDataPath');
  const regEl  = document.getElementById('registryPath');

  if (nifiEl) {
    const suffix = '/nifi-data';
    nifiEl.value = preserve.endsWith('/') 
      ? preserve + suffix.substring(1) 
      : preserve + suffix;
    localStorage.setItem('idol_nifiDataPath', nifiEl.value);
  }

  if (regEl) {
    const suffix = '/nifi-registry';
    regEl.value = preserve.endsWith('/') 
      ? preserve + suffix.substring(1) 
      : preserve + suffix;
    localStorage.setItem('idol_registryPath', regEl.value);
  }
}

function updateConnectorNarPathFromBase() {
  const baseEl = document.getElementById('basePath');
  const narEl  = document.getElementById('connectorNarPath');
  if (!baseEl || !narEl) return;

  const base = (baseEl.value || '').trim();
  if (!base) return;

  const suffix = PATH_SUFFIXES.connectorNarPath;
  narEl.value = base.endsWith('/')
    ? base + suffix.substring(1)
    : base + suffix;

  // keep localStorage in sync (same pattern as the other derived paths)
  localStorage.setItem('idol_connectorNarPath', narEl.value);
}

function updateRichMediaBasePathFromBase() {
  const baseInput = document.getElementById('basePath');
  const sharedFolderInput = document.getElementById('sharedFolderBasePath');
  if (!baseInput || !sharedFolderInput) return;

  let base = baseInput.value.trim();
  if (!base) {
    sharedFolderInput.value = '';
    return;
  }
  base = base.replace(/\/+$/, '');
  sharedFolderInput.value = base + '/shared-folder';
  sharedFolderInput.readOnly = true;
  updateAllPathPreviews();
}

/* ====================== 5. NAVIGATION & SECTION MANAGEMENT ====================== */
function setupIdolShowSection(sectionId) {
  document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  document.getElementById(sectionId)?.classList.add('active');
  document.querySelector(`.nav-item[data-section="${sectionId}"]`)?.classList.add('active');
  const meta = sectionMeta[sectionId] || {};
  document.getElementById('topbarTitle').textContent = meta.title || sectionId;
  document.getElementById('topbarIcon').innerHTML = `<i class="${meta.icon || 'fas fa-circle'}"></i>`;
  setupIdolToggleConditionalFields();
  setupIdolValidateSection(sectionId);
  if (sectionId === 'license') setTimeout(checkLicenseServerStatus, 300);
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

function setupIdolNavigateToSection(sectionId) {
  const current = document.querySelector('.section.active');
  if (current) {
    const ci = SECTION_ORDER.indexOf(current.id);
    const ti = SECTION_ORDER.indexOf(sectionId);
    if (ti > ci) {
      const valid = current.id === 'license' ? setupIdolValidateLicenseSection(true) : setupIdolValidateSection(current.id, true);
      if (!valid) {
        alert('Please fill in all required fields before proceeding.');
        return;
      }
    }
  }
  if (sectionId === 'summary') portsCheckAvailability();
  setupIdolShowSection(sectionId);
}

/* ====================== 6. VALIDATION ====================== */
function setupIdolValidateSection(sectionId, forceShowWarnings = false) {
  if (!sectionId || sectionId === 'information' || sectionId === 'summary') return true;
  if (sectionId === 'ports') return portsValidate();
  if (sectionId === 'license') return setupIdolValidateLicenseSection(forceShowWarnings);

  let isValid = true;
  (fieldConfig[sectionId] || []).forEach(field => {
    const el = document.getElementById(field.id);
    if (!el) return;
    const warn = document.getElementById(field.warningId);
    const shouldValidate = field.conditional ? field.conditional() : true;
    const valid = shouldValidate ? field.validate(el.value) : true;
    const showWarn = shouldValidate && !valid && (touchedFields.has(field.id) || forceShowWarnings);
    if (warn) warn.style.display = showWarn ? 'block' : 'none';
    if (shouldValidate && !valid) isValid = false;
  });

  if (sectionId === 'basic') {
    const basicChecked     = document.getElementById('deployTypeBasic')?.checked     || false;
    const dataAdminChecked = document.getElementById('deployTypeDataAdmin')?.checked  || false;
    const richMediaChecked = document.getElementById('deployTypeRichMedia')?.checked  || false;
    const hasDeploymentType = basicChecked || dataAdminChecked || richMediaChecked;

    const deployWarning = document.getElementById('deployTypeWarning');
    if (deployWarning) deployWarning.style.display = hasDeploymentType ? 'none' : 'block';

    if (!hasDeploymentType) isValid = false;

    const llmOn       = document.getElementById('llmIntegrationToggle')?.checked || false;
    const llmWikiOn   = document.getElementById('llmWikiEnableToggle')?.checked  || false;
    const dataAdminOn = document.getElementById('deployTypeDataAdmin')?.checked   || false;
    const nextBtn     = document.getElementById('basicNextBtn');

    if (llmOn && dataAdminOn) {
      const hasSelectedModel = window._llmSelected && window._llmSelected.size > 0;

      const warn = document.getElementById('llmNoModelWarning');
      if (warn) {
          warn.style.display = (hasSelectedModel || !touchedFields.has('llmIntegrationToggle')) 
              ? 'none' 
              : 'block';
      }

      const hfTokenEl   = document.getElementById('hfToken');
      const hfTokenWarn = document.getElementById('hfTokenWarning');
      const hfMissing   = !hfTokenEl?.value?.trim();
      if (hfTokenWarn) {
        hfTokenWarn.style.display = hfMissing && (touchedFields.has('hfToken') || forceShowWarnings) ? 'block' : 'none';
      }

      if (hfMissing) isValid = false;
    } else {
      const hfTokenWarn = document.getElementById('hfTokenWarning');
      if (hfTokenWarn) hfTokenWarn.style.display = 'none';
    }

    // Require llmAPIKey if user chose "Yes" on the toggle
    const llmApiKeyEnabled = radioVal('llmApiKeyEnabled') === 'TRUE';
    const llmApiKeyValue = document.getElementById('llmAPIKey')?.value?.trim() || '';
    const llmApiKeyWarn = document.getElementById('llmAPIKeyWarning');

    if (llmApiKeyEnabled && !llmApiKeyValue) {
        isValid = false;
        if (llmApiKeyWarn) llmApiKeyWarn.style.display = 'block';
    } else {
        if (llmApiKeyWarn) llmApiKeyWarn.style.display = 'none';
    }

    if (richMediaChecked) {
      const nifiEl = document.getElementById('nifiMediaServerPath');
      const nifiValid = nifiEl && nifiEl.value.trim() !== '' && nifiEl.classList.contains('detection-success');
      const pretrainedToggle = document.getElementById('pretrainedModelsToggle');
      const pretrainedRequired = pretrainedToggle && pretrainedToggle.checked;
      const pretrainedEl = document.getElementById('pretrainedModelsPath');
      const pretrainedValid = !pretrainedRequired || (pretrainedEl && pretrainedEl.value.trim() !== '' && pretrainedEl.classList.contains('detection-success'));

      const nifiWarn = document.getElementById('nifiMediaServerPathWarning');
      const preWarn = document.getElementById('pretrainedModelsPathWarning');

      if (nifiWarn) nifiWarn.style.display = nifiValid ? 'none' : 'block';
      if (preWarn) preWarn.style.display = (pretrainedRequired && !pretrainedValid) ? 'block' : 'none';

      if (!nifiValid || !pretrainedValid) isValid = false;
    }
  }

  const nextBtn = document.getElementById(sectionId + 'NextBtn');
  if (nextBtn) nextBtn.disabled = !isValid;
  return isValid;
}

function setupIdolValidateLicenseSection(forceShowWarnings = false) {
  let isValid = true;

  const isExistingMode = () =>
  document.querySelector('input[name="licenseMode"]:checked')?.value === 'EXISTING';
  const isNewMode = () => !isExistingMode();

  (fieldConfig.license || []).forEach(field => {
    const el = document.getElementById(field.id);
    if (!el) return;
    const warn = document.getElementById(field.warningId);
    const shouldValidate = field.conditional ? field.conditional() : true;
    const valid = shouldValidate ? field.validate(el.value) : true;
    const showWarn = shouldValidate && !valid && (touchedFields.has(field.id) || forceShowWarnings);
    if (warn) warn.style.display = showWarn ? 'block' : 'none';
    if (shouldValidate && !valid) isValid = false;
  });
  const btn = document.getElementById('licenseNextBtn');
  if (btn) btn.disabled = !isValid;
  return isValid;
}

function setupIdolValidateConfig(showErrors = false) {
  let isValid = true;
  const errors = [];
  SECTION_ORDER.filter(s => s !== 'summary').forEach(sid => {
    const ok = sid === 'license' ? setupIdolValidateLicenseSection() : setupIdolValidateSection(sid);
    if (!ok) {
      isValid = false;
      if (sid === 'ports') {
        if (portsConflictsExist) errors.push('Ports — resolve all range conflicts before proceeding');
        else if (!portsCheckRan) errors.push('Ports — run the availability check to enable Next button');
        else if (!allPortsAreFree) errors.push('Ports — some ports are in use, change affected ports and re-check');
      } else {
        (fieldConfig[sid] || []).forEach(f => {
          const el = document.getElementById(f.id);
          if (!el) return;
          const active = f.conditional ? f.conditional() : true;
          if (active && !f.validate(el.value)) errors.push(`${f.label} (${sid})`);
        });
      }
    }
  });
  if (showErrors) {
    const vp = document.getElementById('validationWarning');
    const ve = document.getElementById('validationErrors');
    if (vp && ve) {
      ve.innerHTML = errors.map(e => `<li>${e}</li>`).join('');
      vp.style.display = errors.length ? 'block' : 'none';
    }
  }
  return isValid;
}

function checkBasicNextButton() {
  setupIdolValidateSection('basic');
}

/* ====================== 7. CONDITIONAL UI & FEATURE TOGGLING ====================== */
function setupIdolToggleConditionalFields() {
  const licMode = radioVal('licenseMode') || 'NEW';
  const ghInt = radioVal('githubIntegration') || 'FALSE';
  const nifiPres = radioVal('nifiPreserve') || 'TRUE';
  const regPres = radioVal('registryPreserve') || 'TRUE';
  const preserve = radioVal('preserve') || 'TRUE';
  const basicChecked = document.getElementById('deployTypeBasic')?.checked || false;
  const dataAdminChecked = document.getElementById('deployTypeDataAdmin')?.checked || false;
  const richMediaChecked = document.getElementById('deployTypeRichMedia')?.checked || false;
  document.getElementById('dataAdminFeatureRow').style.display = dataAdminChecked ? 'flex' : 'none';
  document.getElementById('richMediaFeatureRow').style.display = richMediaChecked ? 'flex' : 'none';
  document.getElementById('llmIntegrationRow').style.display = dataAdminChecked ? 'flex' : 'none';
  const show = (id, visible) => { const el = document.getElementById(id); if (el) el.style.display = visible ? 'block' : 'none'; };
  show('licenseExistingGroup', licMode === 'EXISTING');
  show('githubIntegrationGroup', ghInt === 'TRUE');
  show('nifiDataPathGroup', nifiPres === 'TRUE');
  show('registryPathGroup', regPres === 'TRUE');
  show('preservePathGroup', preserve === 'TRUE');
  show('connectorNarPathGroup', radioVal('connectorNarImport') === 'TRUE');
  
  if (radioVal('connectorNarImport') === 'TRUE') {
    updateConnectorNarPathFromBase();
  }
  const daVersionSelector = document.querySelector('#dataAdminFeatureRow .professional-version-selector');
  if (daVersionSelector) daVersionSelector.style.display = dataAdminChecked ? 'flex' : 'none';
  if (ghInt === 'TRUE') {
    const nd = document.getElementById('nifiDeployment');
    if (nd) nd.value = 'nifi-ver2-full';
  }
  const storSub = document.getElementById('storageSubfolders');
  const subList = document.getElementById('subfolderList');
  if (preserve === 'TRUE' && storSub && subList) {
    const pp = document.getElementById('preservePath')?.value || '<PRESERVE_PATH>';
    subList.innerHTML = ['content','find','community','agentstore','category','categorisation_agentstore','view','passageextractor_content','passageextractor_agentstore','dataadmin','dataadmin_community','dataadmin_viewserver','dataadmin_statsserver','qms','qms_agentstore','answerserver','answerbank_agentstore','licenseserver','content/cfg'].map(d => `<li style="font-family:var(--font-mono);font-size:11px;">${pp}/${d}</li>`).join('');
    storSub.style.display = 'block';
  } else if (storSub) storSub.style.display = 'none';

  setupGitHubToggle();
  setupConnectorNarToggle();
  setupLlmApiKeyToggle();
  if (document.querySelector('.section.active')?.id === 'basic') setupIdolValidateSection('basic');

  setupIdolReorderNifiPreservePath();

  togglePretrainedModelsPath();
}

function llmToggleGroup(group) {
  const body    = document.getElementById('llmBody'    + group);
  const chevron = document.getElementById('llmChevron' + group);
  const isOpen  = !body.classList.contains('collapsed');

  body.classList.toggle('collapsed', isOpen);
  chevron.classList.toggle('open', !isOpen);
}

function llmInitGroups() {
  const supportedChevron = document.getElementById('llmChevronSupported');
  if (supportedChevron) supportedChevron.classList.add('open');
}

function setupIdolReorderNifiPreservePath() {
  const preserveGroup = document.getElementById('preservePathGroup');
  const nifiGroup     = document.getElementById('nifiDataPathGroup');
  const nifiYesRadio  = document.getElementById('nifi-preserve-yes');

  if (!preserveGroup || !nifiGroup) return;

  if (!nifiGroupOriginalParent) {
    nifiGroupOriginalParent = nifiGroup.parentNode;
  }

  const nifiPres = radioVal('nifiPreserve') || 'TRUE';
  const preserve = radioVal('preserve') || 'TRUE';

  const shouldPlaceAfterPreserve = (nifiPres === 'TRUE' && preserve === 'TRUE');

  if (shouldPlaceAfterPreserve) {
    if (nifiGroup.previousElementSibling !== preserveGroup) {
      preserveGroup.parentNode.insertBefore(nifiGroup, preserveGroup.nextElementSibling);
      nifiGroup.style.marginTop = '12px';
      nifiGroup.style.marginBottom = '8px';
    }
  } else {
    if (nifiGroupOriginalParent && nifiGroup.parentNode !== nifiGroupOriginalParent) {
      nifiGroupOriginalParent.appendChild(nifiGroup);
      nifiGroup.style.marginTop = '';
      nifiGroup.style.marginBottom = '';
    }
  }
}

function setupGitHubToggle() {
  const yesRadio = document.getElementById('github-yes');
  const noRadio = document.getElementById('github-no');
  const group = document.getElementById('githubIntegrationGroup');
  if (!yesRadio || !noRadio || !group) return;
  function toggleGitHubFields() { group.style.display = yesRadio.checked ? 'block' : 'none'; }
  yesRadio.addEventListener('change', toggleGitHubFields);
  noRadio.addEventListener('change', toggleGitHubFields);
  toggleGitHubFields();
}

function setupConnectorNarToggle() {
  const yesRadio = document.getElementById('connectorNar-yes');
  const noRadio  = document.getElementById('connectorNar-no');
  const group    = document.getElementById('connectorNarPathGroup');
  if (!yesRadio || !noRadio || !group) return;
  function toggleNarFields() { group.style.display = yesRadio.checked ? 'block' : 'none'; }
  yesRadio.addEventListener('change', toggleNarFields);
  noRadio.addEventListener('change', toggleNarFields);
  toggleNarFields();
}

function setupLlmApiKeyToggle() {
  const yesRadio = document.getElementById('llm-apikey-yes');
  const noRadio = document.getElementById('llm-apikey-no');
  const group = document.getElementById('llmApiKeyGroup');
  if (!yesRadio || !noRadio || !group) return;

  // Ensure "No" is the default if nothing is selected
  if (!yesRadio.checked && !noRadio.checked) {
    noRadio.checked = true;
  }

  function toggleLlmApiKeyFields() { 
    group.style.display = yesRadio.checked ? 'block' : 'none'; 
  }

  if (yesRadio.dataset.listenerAttached !== 'true') {
    yesRadio.addEventListener('change', toggleLlmApiKeyFields);
    noRadio.addEventListener('change', toggleLlmApiKeyFields);
    yesRadio.dataset.listenerAttached = 'true';
    noRadio.dataset.listenerAttached = 'true';
  }

  toggleLlmApiKeyFields();
}

function updateLlmWikiVisibility() {
  const dataAdminCheckbox = document.getElementById('deployTypeDataAdmin');
  const llmWikiRow = document.getElementById('llmWikiRow');
  if (!dataAdminCheckbox || !llmWikiRow) return;

  const shouldShow = dataAdminCheckbox.checked;
  llmWikiRow.style.display = shouldShow ? 'flex' : 'none';

  if (!shouldShow) {
    const wikiToggle = document.getElementById('llmWikiEnableToggle');
    if (wikiToggle) wikiToggle.checked = false;
  }
}

function initLlmWikiConditional() {
  const dataAdminCb = document.getElementById('deployTypeDataAdmin');
  if (dataAdminCb) {
    dataAdminCb.addEventListener('change', updateLlmWikiVisibility);
    updateLlmWikiVisibility();
  }
}

function toggleLlmAPIKeyVisibility() {
  const input = document.getElementById('llmAPIKey');
  const btn   = document.getElementById('llmAPIKeyToggleBtn');  
  if (!input || !btn) return;

  const icon = btn.querySelector('i');
  if (!icon) return;

  const isMasked = input.classList.contains('masked-input');

  if (isMasked) {
    input.classList.remove('masked-input');
    icon.className = 'fas fa-eye-slash';
  } else {
    input.classList.add('masked-input');
    icon.className = 'fas fa-eye';
  }
}

function toggleHfTokenVisibility() {
  const input = document.getElementById('hfToken');
  const btn   = document.getElementById('hfTokenToggleBtn');
  if (!input || !btn) return;

  const icon = btn.querySelector('i');
  if (!icon) return;

  const isMasked = input.classList.contains('masked-input');

  if (isMasked) {
    input.classList.remove('masked-input');
    icon.className = 'fas fa-eye-slash';
  } else {
    input.classList.add('masked-input');
    icon.className = 'fas fa-eye';
  }
}

function attachTokenToggles() {
  const llmBtn = document.getElementById('llmAPIKeyToggleBtn');
  if (llmBtn && !llmBtn.dataset.listenerAttached) {
    llmBtn.onclick = null;
    llmBtn.addEventListener('click', toggleLlmAPIKeyVisibility);
    llmBtn.dataset.listenerAttached = 'true';
  }

  const hfBtn = document.getElementById('hfTokenToggleBtn');
  if (hfBtn && !hfBtn.dataset.listenerAttached) {
    hfBtn.onclick = null;
    hfBtn.addEventListener('click', toggleHfTokenVisibility);
    hfBtn.dataset.listenerAttached = 'true';
  }
}

function initTokenToggles() {
  attachTokenToggles();
}

window.toggleLlmAPIKeyVisibility = toggleLlmAPIKeyVisibility;
window.toggleHfTokenVisibility   = toggleHfTokenVisibility;

function updateModelVisibility() {
  console.log('%c[LLM Visibility] updateModelVisibility() called', 'color:#0ea5e9; font-weight:600');

  const toggle = document.getElementById('llmIntegrationToggle');
  const dataAdminCheckbox = document.getElementById('deployTypeDataAdmin');
  const modelRow = document.getElementById('llmModelSelectionRow');
  const gpuRow = document.getElementById('gpuEnableRow');

  if (!toggle || !dataAdminCheckbox) {
    console.warn('[LLM Visibility] Required elements not found');
    return;
  }

  const llmEnabled = toggle.checked;
  const dataAdminEnabled = dataAdminCheckbox.checked;
  const shouldShow = llmEnabled && dataAdminEnabled;

  console.log(`[LLM Visibility] LLM: ${llmEnabled} | Data Admin: ${dataAdminEnabled} | Show: ${shouldShow}`);

  // ====================== MODEL ROW ======================
  if (modelRow) {
    modelRow.style.display = shouldShow ? 'block' : 'none';

    if (shouldShow) {
      setupLlmApiKeyToggle();

      // === IMPORTANT: Force inner grids to be visible ===
      setTimeout(() => {
        const supportedGrid = document.getElementById('llmGridSupported');
        const customGrid = document.getElementById('llmGridCustom');

        if (supportedGrid) {
          supportedGrid.style.display = 'grid';
          supportedGrid.style.visibility = 'visible';
        }
        if (customGrid) {
          customGrid.style.display = 'grid';
          customGrid.style.visibility = 'visible';
        }

        // Re-populate if needed (safe to call multiple times)
        if (typeof llmLoadDefaultModels === 'function') {
          llmLoadDefaultModels();
        }

        console.log('%c[LLM Visibility] Grids forced visible', 'color:#10b981');
      }, 80);
    }
  }

  // GPU row
  if (gpuRow) {
    gpuRow.style.display = shouldShow ? 'flex' : 'none';
    if (shouldShow) setTimeout(detectGPUAndUpdateToggle, 400);
  }

  if (!shouldShow) {
    const modelSelect = document.getElementById('llmModelSelect');
    if (modelSelect) modelSelect.value = '';
  }

  setupIdolValidateSection('basic');
  initTokenToggles();
}

/* ====================== 8. FORM PERSISTENCE (LOCALSTORAGE) ====================== */
function setupIdolSaveFormData(force = false) {
  if (!ENABLE_LOCALSTORAGE) return;
  if (!force && !autoSaveEnabled) return;
  const saveSet = new Set(FIELDS_TO_SAVE);
  const portIds = new Set(ALL_PORTS.map(p => p.id));

  document.querySelectorAll('input[type="text"], input[type="email"], input[type="password"], input[type="number"], select').forEach(el => {
    if (!el.id) return;
    if (portIds.has(el.id)) return;
    if (saveSet.has(el.id)) {
      localStorage.setItem(`idol_${el.id}`, el.value);
    }
  });

  document.querySelectorAll('input[type="radio"]').forEach(el => {
    if (el.name && saveSet.has(el.name) && el.checked) {
      localStorage.setItem(`idol_radio_${el.name}`, el.value);
    }
  });

  document.querySelectorAll('input[type="checkbox"]').forEach(el => {
    if (el.id && saveSet.has(el.id)) {
      localStorage.setItem(`idol_chk_${el.id}`, el.checked);
    }
  });

  const modelSelect = document.getElementById('llmModelSelect');
  if (modelSelect && modelSelect.value && saveSet.has('llmModelSelect')) {
    localStorage.setItem('idol_llm_selected_model_url', modelSelect.value);
  }

  saveDynamicNifiFields();
}

function saveConfigToLocalStorage() {
  if (!ENABLE_LOCALSTORAGE) {
    showToast('localStorage is disabled', true);
    return;
  }
  setupIdolSaveFormData(true);
  showToast('Configuration saved to browser storage');
  console.log('%c✅ Config manually saved to localStorage', 'color:#10b981;font-weight:600');
}

function loadConfigFromLocalStorage() {
  if (!ENABLE_LOCALSTORAGE) {
    showToast('localStorage is disabled', true);
    return;
  }
  setupIdolLoadFormData();
  setupIdolToggleConditionalFields?.();
  updateNifiAndRegistryPathsFromBase?.();
  updatePreservePathFromBase?.();
  updateRichMediaBasePathFromBase?.();
  updateModelVisibility?.();
  ['basic','network','nifi','storage'].forEach(s => setupIdolValidateSection?.(s));
  setupIdolValidateLicenseSection?.();
  portsValidate?.();
  showToast('Configuration loaded from browser storage');
  console.log('%c✅ Config manually loaded from localStorage', 'color:#10b981;font-weight:600');
}

function clearLocalStorageConfig() {
  const keysToRemove = Object.keys(localStorage).filter(k => k.startsWith('idol_'));
  keysToRemove.forEach(k => localStorage.removeItem(k));
  showToast(`Cleared ${keysToRemove.length} saved config value${keysToRemove.length !== 1 ? 's' : ''} from browser storage`);
  console.log(`%c✅ Cleared ${keysToRemove.length} localStorage keys`, 'color:#f59e0b;font-weight:600');
}

function toggleAutoSave(checkbox) {
  autoSaveEnabled = checkbox ? checkbox.checked : !autoSaveEnabled;
  const state = autoSaveEnabled ? 'enabled' : 'disabled';
  showToast(`Auto-save ${state}`);
  console.log(`%c✅ Auto-save ${state}`, 'color:#6366f1;font-weight:600');
}

let serverBasePathApplied = false;
async function loadServerDefaults() {
  const basePathInput = document.getElementById('basePath');
  if (!basePathInput) return false;
  try {
    const response = await fetch('/config-idol/defaults', { method: 'GET', cache: 'no-cache', headers: { 'Pragma': 'no-cache', 'Cache-Control': 'no-cache' } });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    const serverValue = data.base_path || '/opt/idol-deployment';
    basePathInput.value = serverValue;
    serverBasePathApplied = true;
    localStorage.removeItem('idol_basePath');
    console.log(`✅ Server basePath set to: ${serverValue}`);
    return true;
  } catch (err) {
    console.error('Failed to load server defaults:', err);
    serverBasePathApplied = false;
    return false;
  }
}

function setupIdolLoadFormData() {
  if (!ENABLE_LOCALSTORAGE) return;

  document.querySelectorAll('input[type="text"],input[type="email"],input[type="number"],select').forEach(el => {
    if (serverBasePathApplied && el.id === 'basePath') return;
    const v = localStorage.getItem(`idol_${el.id}`);
    if (v !== null && el.type !== 'radio') el.value = v;
  });

  document.querySelectorAll('input[type="password"]').forEach(el => {
    if (el.id === 'hfToken' || el.id === 'llmAPIKey') return;
    const v = localStorage.getItem(`idol_${el.id}`);
    if (v !== null) el.value = v;
  });

  document.querySelectorAll('input[type="radio"]').forEach(el => {
    const v = localStorage.getItem(`idol_radio_${el.name}`);
    if (v === el.value) el.checked = true;
  });

  document.querySelectorAll('input[type="checkbox"]').forEach(el => {
    const v = localStorage.getItem(`idol_chk_${el.id}`);
    if (v !== null) el.checked = v === 'true';
  });

  loadDynamicNifiFields();

  const richMediaToggle = document.getElementById('richMediaToggle');
  if (richMediaToggle) {
    richMediaToggle.checked = false;
    localStorage.removeItem('idol_chk_richMediaToggle');
  }

  ALL_PORTS.forEach(({ id, def }) => {
    const el = document.getElementById(id);
    if (el && !el.value) el.value = String(def);
  });

  const AUTO_FILL_FIELDS = [
    'nifiDataPath',
    'registryPath',
    'connectorNarPath',
    'storagePath',
    'llmModelPath',
    'preservePath',
    'hfToken',
    'llmAPIKey'
  ];

  AUTO_FILL_FIELDS.forEach(id => {
    const saved = localStorage.getItem(`idol_${id}`);
    const el    = document.getElementById(id);
    if (saved !== null && el) {
      el.value = saved;
      el.dataset.userEdited = '1';
    }
  });

  updateNifiAndRegistryPathsFromBase();
  updatePreservePathFromBase();
  updateConnectorNarPathFromBase();

  const llmPathEl = document.getElementById('llmModelPath');
  if (llmPathEl && !llmPathEl.value) {
    const base = document.getElementById('basePath')?.value?.trim() || '/opt/idol-deployment';
    llmPathEl.value = `${base}${PATH_SUFFIXES.llmModelPath}`;
  }

  const fqdn = document.getElementById('fqdn');
  const licenseHost = document.getElementById('licenseHostname');
  if (fqdn?.value && licenseHost && !licenseHost.value.trim()) {
    licenseHost.value = fqdn.value.trim();
  }

  updateModelVisibility();

  const bypassToggle = document.getElementById('bypassPortCheckToggle');
  if (bypassToggle) bypassToggle.checked = false;
}

/* ====================== 9. PORTS MANAGEMENT ====================== */
function resetPortsToDefaults() {
  const defaults = {
    mediaServerHttpUiPort: "8003",
    basicIdolHttpdPort: "8330",
    findUiPortBaseIdol: "8440",
    findUiPortDataAdmin: "8441",
    nifiPort: "8443",
    dataAdminHttpsUiPort: "8444",
    dataAdminInternalUiPort: "8445",
    biContentPort: "9100",
    biAgentStorePort: "9050",
    biCategoryPort: "9020",
    biCatAgentStorePort: "9180",
    biCommunityPort: "9030",
    biViewPort: "9080",
    communityPort: "9033",
    viewServerPort: "9083",
    passageContentPort: "9103",
    answerServerPort: "12000",
    answerBankAgentPort: "12200",
    passageAgentPort: "12310",
    qmsPort: "16000",
    qmsAgentPort: "20050",
    statsServerPort: "19870",
    rmMediaServerPort: "14000",
    rmMediaServerPlaylistPort: "24000"
  };

  Object.keys(defaults).forEach(id => {
    const input = document.getElementById(id);
    if (input) input.value = defaults[id];
  });

  if (typeof portsOnInput === "function") portsOnInput();

  if (typeof showToast === "function") {
    showToast("All ports have been reset to their default values");
  } else {
    console.log("%c✅ All ports reset to defaults", "color:#10b981;font-weight:600");
  }
}

function portsIsValidRange(v, rangeSize = 1) {
  const max = 65536 - rangeSize;
  return v !== '' && !isNaN(v) && +v > 0 && +v <= max;
}

function portsUpdateRangePills(p, base) {
  if (!p.range || !p.aciId) return;
  const ok = base !== undefined && base !== '' && portsIsValidRange(String(base), p.rangeSize || 3);
  const b = ok ? +base : '?';
  const pillIds = [p.aciId, p.idxId, p.svcId, p.p1Id, p.p2Id, p.p3Id].filter(Boolean);
  pillIds.forEach((pid, i) => {
    const el = document.getElementById(pid);
    if (el) el.textContent = ok ? b + i : '?';
  });
}

function portsSetStatus(statusId, state) {
  const el = document.getElementById(statusId);
  if (!el) return;
  if (!state) { el.style.display = 'none'; return; }
  const cfg = {
    checking: { bg:'rgba(59,130,246,.15)', border:'rgba(59,130,246,.4)', color:'var(--primary-light)', icon:'fas fa-spinner fa-spin', text:'Checking…' },
    free: { bg:'rgba(16,185,129,.15)', border:'rgba(16,185,129,.4)', color:'var(--success)', icon:'fas fa-check-circle', text:'Free' },
    inuse: { bg:'rgba(245,158,11,.15)', border:'rgba(245,158,11,.5)', color:'var(--warning)', icon:'fas fa-exclamation-triangle', text:'In Use' },
    error: { bg:'rgba(245,158,11,.12)', border:'rgba(245,158,11,.4)', color:'var(--warning)', icon:'fas fa-question-circle', text:'Unknown' }
  };
  const c = cfg[state] || cfg.error;
  el.style.cssText = `display:flex;align-items:center;gap:5px;flex-shrink:0;font-size:11.5px;font-weight:600;padding:6px 10px;border-radius:20px;white-space:nowrap;background:${c.bg};border:1px solid ${c.border};color:${c.color};`;
  el.innerHTML = `<i class="${c.icon}"></i>${c.text}`;
}

function portsOnInput() {
  bypassPortCheck = false;
  document.getElementById('bypassPortCheckToggle').checked = false;
  if (portsCheckRan) {
    portsCheckRan = false;
    allPortsAreFree = false;
    ALL_PORTS.forEach(p => portsSetStatus(p.statusId, null));
    const res = document.getElementById('portsAvailabilityResult');
    if (res) res.style.display = 'none';
    const hint = document.getElementById('portsCheckHint');
    if (hint) {
      hint.style.color = 'var(--warning)';
      hint.innerHTML = '<i class="fas fa-exclamation-circle"></i> Port changed — re-run check to enable Next button';
    }
  }
  ALL_RANGE_PORTS.forEach(p => {
    const el = document.getElementById(p.id);
    portsUpdateRangePills(p, el?.value);
  });
  updateInfoSectionUrls();
  portsValidate();
}

function portsValidate() {
  const entries = ALL_PORTS.map(p => {
    const el = document.getElementById(p.id);
    if (!el) return { ...p, raw: '', ok: true, num: null, ports: [], missing: true };
    const raw = el.value ?? '';
    const ok = portsIsValidRange(raw, p.rangeSize || (p.range ? 3 : 1));
    const num = ok ? +raw : null;
    const size = p.range ? (p.rangeSize || 3) : 1;
    const ports = ok ? Array.from({length: size}, (_, i) => num + i) : [];
    return { ...p, raw, ok, num, ports };
  });

  const freq = {};
  entries.forEach(e => {
    e.ports.forEach(n => {
      if (!freq[n]) freq[n] = [];
      freq[n].push(e.id);
    });
  });
  entries.forEach(e => { e.dupe = e.ok && e.ports.some(n => freq[n] && freq[n].length > 1); });

  portsConflictsExist = entries.some(e => e.dupe);

  // Auto-expand collapsed cards that contain conflicted ports
  const PORT_CARD_MAP = {
    biPortBody:  new Set(BI_PORTS.map(p => p.id)),
    daPortBody:  new Set(DA_PORTS.map(p => p.id)),
    rmPortBody:  new Set(RM_PORTS.map(p => p.id))
  };
  const conflictedIds = new Set(entries.filter(e => e.dupe).map(e => e.id));
  Object.entries(PORT_CARD_MAP).forEach(([bodyId, portIds]) => {
    const hasConflict = [...portIds].some(id => conflictedIds.has(id));
    if (!hasConflict) return;
    const body = document.getElementById(bodyId);
    if (body && !body.classList.contains('expanded')) {
      const chevronId = bodyId.replace('Body', 'Chevron');
      togglePortCard(bodyId, chevronId);
    }
  });

  entries.forEach(e => {
    const warnEl = document.getElementById(e.warnId);
    const dupeEl = document.getElementById(e.dupeId);
    if (warnEl) warnEl.style.display = (!e.ok && touchedFields.has(e.id)) ? 'block' : 'none';
    if (dupeEl) dupeEl.style.display = e.dupe ? 'block' : 'none';
  });

  const dupeAlert = document.getElementById('portsDupeAlert');
  if (dupeAlert) dupeAlert.classList.toggle('hidden', !portsConflictsExist);

  const canProceed = entries.every(e => e.ok) && !portsConflictsExist && (bypassPortCheck || (portsCheckRan && allPortsAreFree));

  const portsNextBtn = document.getElementById('portsNextBtn');
  if (portsNextBtn) portsNextBtn.disabled = !canProceed;

  const hint = document.getElementById('portsCheckHint');
  if (hint) {
    if (!entries.every(e => e.ok)) {
      hint.innerHTML = '<i class="fas fa-times-circle"></i> Fix invalid port values first';
      hint.style.color = 'var(--danger)';
    } else if (portsConflictsExist) {
      hint.innerHTML = '<i class="fas fa-times-circle"></i> Resolve port conflicts first';
      hint.style.color = 'var(--danger)';
    } else if (bypassPortCheck) {
      hint.innerHTML = '<i class="fas fa-check-circle"></i> Bypass enabled';
      hint.style.color = 'var(--success)';
    } else if (!portsCheckRan) {
      hint.innerHTML = '<i class="fas fa-exclamation-circle"></i> Run check to enable Next button';
      hint.style.color = 'var(--warning)';
    } else if (!allPortsAreFree) {
      hint.innerHTML = '<i class="fas fa-times-circle"></i> Some ports are in use';
      hint.style.color = 'var(--danger)';
    } else {
      hint.innerHTML = '<i class="fas fa-check-circle"></i> All ports free — Next enabled';
      hint.style.color = 'var(--success)';
    }
  }

  return canProceed;
}

function portsGetServiceMap() {
  const map = {};

  UI_PORTS.forEach(p => {
    const el = document.getElementById(p.id);
    const v = el?.value ? +el.value : null;
    if (v && v > 0) map[v] = p.label;
  });

  HTTPD_PORTS.forEach(p => {
    const el = document.getElementById(p.id);
    const v = el?.value ? +el.value : null;
    if (v && v > 0) map[v] = p.label;
  });

  const RANGE_LABELS = ['ACI', 'Index', 'Service', '+3', '+4'];
  ALL_RANGE_PORTS.forEach(p => {
    const el = document.getElementById(p.id);
    const base = el?.value ? +el.value : null;
    if (!base || base <= 0) return;
    const size = p.rangeSize || 3;
    for (let i = 0; i < size; i++) {
      map[base + i] = `${p.label} (${RANGE_LABELS[i]})`;
    }
  });

  return map;
}

function portsToggleBypass() {
  bypassPortCheck = document.getElementById('bypassPortCheckToggle').checked;
  const checkBtn = document.getElementById('checkPortsBtn');
  if (checkBtn) {
    checkBtn.disabled = bypassPortCheck;
    if (bypassPortCheck) {
      checkBtn.classList.add('btn-secondary');
      checkBtn.style.opacity = '0.5';
    } else {
      checkBtn.classList.remove('btn-secondary');
      checkBtn.style.opacity = '';
    }
  }
  portsValidate();
}

async function portsCheckAvailability() {
  if (portsConflictsExist) {
    showToast('Resolve port conflicts before checking availability', true);
    return;
  }

  const btn = document.getElementById('checkPortsBtn');
  const resultArea = document.getElementById('portsAvailabilityResult');

  btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Checking…';

  ALL_PORTS.forEach(p => portsSetStatus(p.statusId, 'checking'));

  if (resultArea) resultArea.style.display = 'none';

  const serviceMap = portsGetServiceMap();
  const portNumbers = [...new Set(Object.keys(serviceMap).map(Number).filter(n => n > 0))];

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 12000);

  try {
    const response = await fetch('/config-idol/check-ports', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ports: portNumbers }),
      signal: controller.signal
    });

    clearTimeout(timeoutId);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    const data = await response.json();
    const results = data.results || {};

    ALL_PORTS.forEach(p => {
      const el = document.getElementById(p.id);
      if (!el) return;
      const v = parseInt(el.value, 10);
      if (!v || isNaN(v)) return;

      let status = 'error';
      if (p.range) {
        const size = p.rangeSize || 3;
        const states = Array.from({ length: size }, (_, i) => results[String(v + i)]);
        if (states.some(s => s === false)) status = 'inuse';
        else if (states.every(s => s === true)) status = 'free';
      } else {
        const s = results[String(v)];
        status = s === true ? 'free' : s === false ? 'inuse' : 'error';
      }
      portsSetStatus(p.statusId, status);
    });

    portsCheckRan = true;
    allPortsAreFree = Object.values(results).every(val => val === true);

    let html = `<div class="alert alert-info"><i class="alert-icon fas fa-info-circle"></i><div>Checked <strong>${data.checked_count ?? portNumbers.length}</strong> ports.</div></div>`;

    const inUse = Object.entries(results).filter(([_, free]) => free === false);
    if (inUse.length > 0) {
      html += `<div class="alert alert-danger"><i class="alert-icon fas fa-times-circle"></i><div><strong>${inUse.length} port(s) in use:</strong><ul>`;
      inUse.forEach(([port]) => {
        const label = serviceMap[port] || `Port ${port}`;
        html += `<li><code>:${port}</code> — <strong>${label}</strong></li>`;
      });
      html += `</ul></div></div>`;
    } else if (allPortsAreFree) {
      html += `<div class="alert alert-success"><i class="alert-icon fas fa-check-circle"></i><div><strong>All ports are FREE!</strong> You can proceed.</div></div>`;
    }

    if (resultArea) {
      resultArea.innerHTML = html;
      resultArea.style.display = 'block';
    }

    portsValidate();

  } catch (err) {
    clearTimeout(timeoutId);
    ALL_PORTS.forEach(p => portsSetStatus(p.statusId, 'error'));
    if (resultArea) {
      resultArea.innerHTML = `<div class="alert alert-danger"><i class="alert-icon fas fa-times-circle"></i><div>Port check failed: ${err.message}</div></div>`;
      resultArea.style.display = 'block';
    }

  } finally {
    btn.innerHTML = '<i class="fas fa-satellite-dish"></i> Check All Ports';
    portsValidate();
  }
}

/* ====================== 10. LICENSE & GPU STATUS ====================== */
function getCurrentLicenseServerUrl() {
  const mode = radioVal('licenseMode') || 'NEW';
  
  if (mode === 'EXISTING') {
    const urlInput = document.getElementById('licenseUrl');
    const url = urlInput?.value.trim();
    return url || '(URL not set)';
  } else {
    return 'https://licenseserver:20000/a=getlicenseinfo';
  }
}

async function checkLicenseServerStatus() {
  const badge = document.getElementById('licenseStatusBadge');
  if (!badge) return;

  const urlToCheck = getCurrentLicenseServerUrl();

  // Show the URL being used
  badge.innerHTML = `
    <i class="fas fa-spinner fa-spin"></i> 
    Checking...<br>
    <small style="font-size:10px;opacity:0.7;">${urlToCheck}</small>
  `;
  badge.style.background = 'rgba(148,163,184,.1)';
  badge.style.color = 'var(--text-muted)';
  badge.style.border = '1px solid var(--border)';

  try {
    const response = await fetch('/config-idol/check-license', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: urlToCheck })
    });

    const data = await response.json();

    if (data.success && data.active) {
      isLicenseActive = true;
      badge.innerHTML = `
        <i class="fas fa-check-circle"></i> Active<br>
        <small style="font-size:10px;opacity:0.75;">${urlToCheck}</small>
      `;
      badge.style.background = 'var(--success-glow)';
      badge.style.color = 'var(--success)';
      badge.style.border = '1px solid rgba(16,185,129,.3)';
    } else {
      isLicenseActive = false;
      badge.innerHTML = `
        <i class="fas fa-question-circle"></i> ${data.message || 'Unknown'}<br>
        <small style="font-size:10px;opacity:0.75;">${urlToCheck}</small>
      `;
      badge.style.background = 'var(--warning-glow)';
      badge.style.color = 'var(--warning)';
      badge.style.border = '1px solid rgba(245,158,11,.3)';
    }
  } catch (err) {
    isLicenseActive = false;
    badge.innerHTML = `
      <i class="fas fa-times-circle"></i> Inactive<br>
      <small style="font-size:10px;opacity:0.75;">${urlToCheck}</small>
    `;
    badge.style.background = 'var(--danger-glow)';
    badge.style.color = 'var(--danger)';
    badge.style.border = '1px solid rgba(239,68,68,.3)';
  }
}

// ====================== IMPROVED GPU DETECTION (handles missing endpoint) ======================
async function detectGPUAndUpdateToggle() {
  const gpuRow      = document.getElementById('gpuEnableRow');
  const gpuToggle   = document.getElementById('gpuEnableToggle');
  const statusText  = document.getElementById('gpuStatusText');

  if (!gpuRow || !gpuToggle || !statusText) return;

  console.log('%c🔍 [GPU Detection] Starting GPU detection...', 'color:#0ea5e9; font-weight:600');

  try {
    console.log('📡 [GPU Detection] Fetching /config-idol/detect-gpu');

    const response = await fetch('/config-idol/detect-gpu', { 
      cache: 'no-cache',
      headers: { 'Pragma': 'no-cache' }
    });

    console.log(`📡 [GPU Detection] Response status: ${response.status}`);

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const data = await response.json();
    console.log('%c📦 [GPU Detection] Received data:', 'color:#10b981', data);

    const gpuFound = data.success && data.gpu_detected;

    gpuToggle.checked = gpuFound;
    gpuToggle.disabled = !gpuFound;

    if (gpuFound) {
      statusText.innerHTML = `
        <strong style="color:#10b981">✓ GPU(s) Detected</strong><br>
        <span style="font-size:11.5px; line-height:1.35; display:block; margin-top:4px; font-family:var(--font-mono); color:#0ea5e9;">
          ${data.raw_output ? data.raw_output.replace(/\n/g, '<br>') : 'GPU ready'}
        </span>
      `;
      gpuRow.style.opacity = '1';
      gpuRow.style.pointerEvents = 'auto';
      console.log('✅ [GPU Detection] GPU detected and UI updated');
    } else {
      statusText.innerHTML = `
        <span style="color:#ef4444">No GPU hardware detected</span><br>
        <small style="font-size:11px; color:#f59e0b;">LLM will run on CPU only</small>
      `;
      gpuRow.style.opacity = '0.65';
      gpuRow.style.pointerEvents = 'none';
      console.log('⚠️ [GPU Detection] No GPU found');
    }

  } catch (err) {
    console.error('❌ [GPU Detection] Failed:', err);
    gpuToggle.checked = false;
    gpuToggle.disabled = true;
    statusText.innerHTML = `
      <span style="color:#f59e0b">GPU detection failed or not available</span><br>
      <small style="font-size:11px;">LLM will run on CPU only</small>
    `;
    gpuRow.style.opacity = '0.75';
    gpuRow.style.pointerEvents = 'none';
  }
}

/* ====================== 11. LLM MODEL SYSTEM ====================== */
// Global cache for answer server dropdown and other functions
let llmSupportedModels = [];

function populateModelDropdown(models, selectedUrl) {
  const select = document.getElementById('llmModelSelect');
  if (!select) return;

  select.innerHTML = '<option value="">-- Select a model --</option>';

  models.forEach(model => {
    const opt = document.createElement('option');
    opt.value = model.url || model.downloaded_model_url;
    opt.textContent = model.name;
    opt.dataset.description = model.description || '';
    opt.dataset.responseType = model.main_response_type || '';
    select.appendChild(opt);
  });

  if (selectedUrl) {
    select.value = selectedUrl;
    const event = new Event('change', { bubbles: true });
    select.dispatchEvent(event);
  }
}

function updateModelInfo() {
  const select = document.getElementById('llmModelSelect');
  const descEl = document.getElementById('llmModelDescription');
  const typeEl = document.getElementById('llmModelResponseType');

  if (!select || !descEl || !typeEl) return;

  const option = select.options[select.selectedIndex];
  if (!option || !option.value) {
    descEl.textContent = '';
    typeEl.textContent = '';
    typeEl.style.display = 'none';
    return;
  }

  descEl.textContent = option.dataset.description || 'No description available.';
  const responseType = option.dataset.responseType || '—';
  typeEl.textContent = `Response Type: ${responseType}`;
  typeEl.style.display = 'inline-block';
}

function loadModelsFromJson(jsonData) {
  console.log('%c[DEBUG] loadModelsFromJson received:', 'color:#0ea5e9', jsonData);

  if (!jsonData) {
    document.getElementById('modelLoadStatus').innerHTML = '<span style="color: var(--danger);">No JSON data received.</span>';
    return false;
  }

  let rawModels = [];
  if (Array.isArray(jsonData)) {
    rawModels = jsonData;
  } else if (typeof jsonData === 'object') {
    if (Array.isArray(jsonData.supported)) rawModels = rawModels.concat(jsonData.supported);
    if (Array.isArray(jsonData.custom_required)) rawModels = rawModels.concat(jsonData.custom_required);
  }

  const validModels = rawModels.filter(m => m && m.name && (m.url || m.downloaded_model_url));

  if (validModels.length === 0) {
    document.getElementById('modelLoadStatus').innerHTML = '<span style="color: var(--danger);">No valid model entries found.</span>';
    return false;
  }

  let urlToSelect = localStorage.getItem('idol_llm_selected_model_url');
  if (!urlToSelect || !validModels.some(m => (m.url || m.downloaded_model_url) === urlToSelect)) {
    urlToSelect = validModels[0].url || validModels[0].downloaded_model_url;
    localStorage.setItem('idol_llm_selected_model_url', urlToSelect);
  }

  populateModelDropdown(validModels, urlToSelect);

  setTimeout(() => {
    if (typeof updateModelInfo === 'function') updateModelInfo();
    if (typeof setupIdolValidateSection === 'function') setupIdolValidateSection('basic');
  }, 80);

  document.getElementById('modelLoadStatus').innerHTML = 
    `<span style="color: var(--success);">✅ Loaded ${validModels.length} model(s). First supported model auto-selected.</span>`;

  return true;
}

async function fetchDefaultModels() {
  const statusDiv = document.getElementById('modelLoadStatus');
  statusDiv.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Loading default models...';
  try {
    const url = `/load-models/default-models.json?t=${Date.now()}`;
    const response = await fetch(url);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    loadModelsFromJson(data);
  } catch (err) {
    console.warn('Could not load default models:', err);
    statusDiv.innerHTML = '<span style="color: var(--warning);">Failed to load default models. Please upload a custom JSON file.</span>';
  }
}

function handleModelFileUpload(file) {
  const reader = new FileReader();
  reader.onload = (e) => {
    try {
      const json = JSON.parse(e.target.result);
      loadModelsFromJson(json);
    } catch (err) {
      document.getElementById('modelLoadStatus').innerHTML = `<span style="color: var(--danger);">Invalid JSON file: ${err.message}</span>`;
    }
  };
  reader.onerror = () => {
    document.getElementById('modelLoadStatus').innerHTML = '<span style="color: var(--danger);">Error reading file.</span>';
  };
  reader.readAsText(file);

  // After successfully loading models from JSON
  updateModelVisibility();
}

// Multi-model LLM system
let _llmData = { supported: [], custom_required: [] };
let _llmSelected = new Set();
let _llmQuantState = {};
window._llmSelected = _llmSelected;

function llmLoadDefaultModels() {
  const statusDiv = document.getElementById('modelLoadStatus');
  if (statusDiv) statusDiv.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Loading models...';

  fetch('/load-models/default-models.json?t=' + Date.now())
    .then(r => {
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return r.json();
    })
    .then(data => {
      console.log('%c✅ Models JSON loaded successfully', 'color:#10b981', data);
      llmIngestJson(data);
      if (statusDiv) statusDiv.innerHTML = `<span style="color:#10b981">✅ Loaded ${_llmData.supported.length} models</span>`;
    })
    .catch(err => {
      console.error('❌ Failed to load default-models.json:', err);
      if (statusDiv) {
        statusDiv.innerHTML = `<span style="color:#ef4444">⚠️ Could not load models.<br>Using demo fallback...</span>`;
      }
      // Demo fallback so the UI never stays empty
      llmIngestJson({
        supported: [
          {
            name: "Llama-3.1-8B-Instruct (Demo)",
            gguf_files: { "Q4_K_M": "https://example.com/demo.gguf" },
            recommended_quant: "Q4_K_M",
            size_gb: 5.8,
            description: "Demo model — replace with real models in /load-models/default-models.json"
          }
        ],
        custom_required: []
      });
    });
}

function llmHandleJsonUpload(input) {
  if (!input.files[0]) return;
  const reader = new FileReader();
  reader.onload = e => {
    try {
      llmIngestJson(JSON.parse(e.target.result));
      document.getElementById('modelLoadStatus').textContent = '✓ Custom JSON loaded.';
    }
    catch { document.getElementById('modelLoadStatus').textContent = '✗ Invalid JSON.'; }
  };
  reader.readAsText(input.files[0]);
}

function llmIngestJson(data) {
  console.log('%c[LLM] Ingesting data:', 'color:#0ea5e9', data);

  if (!data || (!data.supported && !data.custom_required)) {
    console.warn('⚠️ Invalid model data received, using empty fallback');
    data = { supported: [], custom_required: [] };
  }

  _llmData = { 
    supported: data.supported || [], 
    custom_required: data.custom_required || [] 
  };

  _llmSelected = new Set();
  _llmQuantState = {};
  window._llmSelected = _llmSelected;

  // === SAFE ASSIGNMENT (this was causing the ReferenceError) ===
  llmSupportedModels = _llmData.supported.map(m => ({
    id: m.name,
    name: m.name
  })) || [];

  llmRenderPicker();
  llmRenderDownloadSection();
  llmSyncAnswerServerDropdown();

  console.log(`%c✅ Ingested ${_llmData.supported.length} supported + ${_llmData.custom_required.length} custom models`, 'color:#10b981');
  
  if (typeof setupIdolValidateSection === 'function') setupIdolValidateSection('basic');
}

function getSelectedModelNamesArray() {
  const names = [];
  [..._llmSelected].sort((a,b) => a-b).forEach(idx => {
    const m = llmGetModelByIdx(idx);
    if (m && m.name) names.push(m.name);
  });
  return names;
}

function getSelectedModelUrlsArray() {
  const urls = [];
  [..._llmSelected].sort((a,b) => a-b).forEach(idx => {
    const m = llmGetModelByIdx(idx);
    if (m && m.gguf_files) {
      const quant = m.recommended_quant || Object.keys(m.gguf_files)[0];
      const url = m.gguf_files[quant];
      if (url) urls.push(url);
    }
  });
  return urls;
}

function llmRenderPicker(filter) {
  const q = (filter || '').toLowerCase();
  const allModels = [
    ..._llmData.supported.map((m, i) => ({ ...m, _idx: i, _group: 'supported' })),
    ..._llmData.custom_required.map((m, i) => ({ ...m, _idx: _llmData.supported.length + i, _group: 'custom' }))
  ];
  const filtered = q ? allModels.filter(m => m.name.toLowerCase().includes(q) || (m.description||'').toLowerCase().includes(q)) : allModels;
 
  document.getElementById('llmPickerCount').textContent = filtered.length + ' model' + (filtered.length !== 1 ? 's' : '') + ' available';
 
  ['supported','custom'].forEach(grp => {
    const grid = document.getElementById('llmGrid' + grp.charAt(0).toUpperCase() + grp.slice(1));
    const groupEl = document.getElementById('llmGroup' + grp.charAt(0).toUpperCase() + grp.slice(1));
    const groupItems = filtered.filter(m => m._group === grp);
    groupEl.style.display = groupItems.length ? '' : 'none';
    grid.innerHTML = '';
    groupItems.forEach(m => grid.appendChild(llmMakeModelCard(m)));
  });
}

function llmMakeModelCard(m) {
  const isSelected = _llmSelected.has(m._idx);
  const card = document.createElement('label');
  card.className = 'llm-model-card' + (isSelected ? ' selected' : '');
  card.setAttribute('for', 'llm_cb_' + m._idx);
  card.setAttribute('data-idx', m._idx);

  const cb = document.createElement('input');
  cb.type = 'checkbox'; cb.id = 'llm_cb_' + m._idx;
  cb.checked = isSelected;
  cb.addEventListener('change', () => llmToggleModel(m._idx, cb.checked, card));

  const nameDiv = document.createElement('div'); nameDiv.className = 'llm-model-card-name'; nameDiv.textContent = m.name;
  const metaDiv = document.createElement('div'); metaDiv.className = 'llm-model-card-meta';
  metaDiv.textContent = (m.recommended_quant ? m.recommended_quant : '') + (m.size_gb ? '  ·  ' + m.size_gb + ' GB' : '');

  card.appendChild(cb);
  card.appendChild(nameDiv);
  card.appendChild(metaDiv);
  return card;
}

function llmToggleModel(idx, checked, cardEl) {
  if (checked) {
    _llmSelected.add(idx);
    cardEl?.classList.add('selected');
    if (!_llmQuantState[idx]) {
      const m = llmGetModelByIdx(idx);
      _llmQuantState[idx] = new Set(m.recommended_quant ? [m.recommended_quant] : []);
    }
  } else {
    _llmSelected.delete(idx);
    cardEl?.classList.remove('selected');
  }
  llmRenderDownloadSection();
  if (typeof setupIdolValidateSection === 'function') setupIdolValidateSection('basic');
}

function llmSelectAllModels() {
  const allModels = [..._llmData.supported, ..._llmData.custom_required];
  allModels.forEach((m, i) => {
    if (!_llmSelected.has(i)) {
      _llmSelected.add(i);
      if (!_llmQuantState[i]) _llmQuantState[i] = new Set(m.recommended_quant ? [m.recommended_quant] : []);
      const cb = document.getElementById('llm_cb_' + i);
      if (cb) { cb.checked = true; cb.closest('.llm-model-card')?.classList.add('selected'); }
    }
  });
  llmRenderDownloadSection();
  if (typeof setupIdolValidateSection === 'function') setupIdolValidateSection('basic');
}

function llmClearAllModels() {
  _llmSelected.clear();
  document.querySelectorAll('.llm-model-card input[type=checkbox]').forEach(cb => {
    cb.checked = false;
    cb.closest('.llm-model-card')?.classList.remove('selected');
  });
  llmRenderDownloadSection();
  if (typeof setupIdolValidateSection === 'function') setupIdolValidateSection('basic');
}

function llmFilterModels(q) { llmRenderPicker(q); }

function llmRenderDownloadSection() {
  const body = document.getElementById('llmDownloadBody');
  const summaryEl = document.getElementById('llmGrandSummary');

  if (!_llmSelected.size) {
    body.innerHTML = '<div class="llm-no-selection"><i class="fas fa-hand-pointer" style="font-size:20px;color:var(--text-muted);display:block;margin-bottom:8px;"></i>Select one or more models above to choose GGUF files</div>';
    summaryEl.style.display = 'none';
    return;
  }

  const table = document.createElement('table');
  table.className = 'llm-download-table';
  table.innerHTML = '<thead><tr><th style="width:30%">Model</th><th>GGUF quants — click to toggle</th><th style="width:34px;"></th></tr></thead>';
  const tbody = document.createElement('tbody');

  [..._llmSelected].sort((a,b) => a-b).forEach(idx => {
    const m = llmGetModelByIdx(idx);
    if (!m) return;
    if (!_llmQuantState[idx]) _llmQuantState[idx] = new Set(m.recommended_quant ? [m.recommended_quant] : []);

    const tr = document.createElement('tr');

    const tdName = document.createElement('td');
    tdName.innerHTML = `<div class="llm-dl-model-name">${m.name}</div><div class="llm-dl-rt">${(m.main_response_type||'').replace(/_/g,' ')}</div>`;
    tr.appendChild(tdName);

    const tdQuants = document.createElement('td');
    const pillWrap = document.createElement('div'); pillWrap.className = 'llm-quant-pills';
    Object.keys(m.gguf_files || {}).forEach(quant => {
      const isVis  = quant.toLowerCase().includes('mmproj') || quant.toLowerCase().includes('vision');
      const isRec  = quant === m.recommended_quant;
      const active = _llmQuantState[idx].has(quant);
      const pill = document.createElement('span');
      pill.className = 'llm-quant-pill' + (isVis ? ' vision' : '') + (active ? ' active' : '');
      pill.title = (m.gguf_files[quant] || '').replace('https://huggingface.co/','hf.co/');
      pill.innerHTML = quant + (isRec ? ' <span style="font-size:9px;opacity:.7;">★</span>' : '');
      pill.addEventListener('click', () => {
        if (_llmQuantState[idx].has(quant)) _llmQuantState[idx].delete(quant);
        else _llmQuantState[idx].add(quant);
        pill.classList.toggle('active', _llmQuantState[idx].has(quant));
        llmUpdateSummary();
      });
      pillWrap.appendChild(pill);
    });
    tdQuants.appendChild(pillWrap);
    tr.appendChild(tdQuants);

    const tdRemove = document.createElement('td');
    tdRemove.style.textAlign = 'center';
    const removeBtn = document.createElement('button');
    removeBtn.className = 'llm-remove-btn';
    removeBtn.title = 'Remove ' + m.name;
    removeBtn.innerHTML = '<i class="fas fa-times-circle"></i>';
    removeBtn.type = 'button';
    removeBtn.addEventListener('click', () => {
      _llmSelected.delete(idx);
      const cb = document.getElementById('llm_cb_' + idx);
      if (cb) { cb.checked = false; cb.closest('.llm-model-card')?.classList.remove('selected'); }
      llmRenderDownloadSection();
    });
    tdRemove.appendChild(removeBtn);
    tr.appendChild(tdRemove);

    tbody.appendChild(tr);
  });

  table.appendChild(tbody);
  body.innerHTML = '';
  body.appendChild(table);
  llmUpdateSummary();
}

function llmUpdateSummary() {
  const summaryEl = document.getElementById('llmGrandSummary');
  let totalFiles = 0; const lines = [];

  [..._llmSelected].sort((a,b) => a-b).forEach(idx => {
    const m = llmGetModelByIdx(idx);
    if (!m || !_llmQuantState[idx]?.size) return;
    const quants = [..._llmQuantState[idx]];
    totalFiles += quants.length;
    lines.push(m.name + ': ' + quants.join(', '));
  });

  if (!totalFiles) { summaryEl.style.display = 'none'; return; }
  summaryEl.style.display = 'flex';
  document.getElementById('llmSummaryModelCount').textContent = _llmSelected.size;
  document.getElementById('llmSummaryFileCount').textContent  = totalFiles;
  document.getElementById('llmSummaryList').innerHTML = lines.map(l => '<div>' + l + '</div>').join('');
}

function llmSetAllQuants(mode) {
  [..._llmSelected].forEach(idx => {
    const m = llmGetModelByIdx(idx);
    if (!m) return;
    if (mode === 'recommended') _llmQuantState[idx] = new Set(m.recommended_quant ? [m.recommended_quant] : []);
    else if (mode === 'all') _llmQuantState[idx] = new Set(Object.keys(m.gguf_files || {}));
    else _llmQuantState[idx] = new Set();
  });
  llmRenderDownloadSection();
}

function llmGetModelByIdx(idx) {
  const all = [..._llmData.supported, ..._llmData.custom_required];
  return all[idx] || null;
}

function llmGetSelectedDownloads() {
  const result = [];
  [..._llmSelected].sort((a,b) => a-b).forEach(idx => {
    const m = llmGetModelByIdx(idx);
    if (!m || !_llmQuantState[idx]?.size) return;
    [..._llmQuantState[idx]].forEach(quant => {
      result.push({
        model : m.name,
        quant,
        url   : (m.gguf_files || {})[quant] || '',
        folder: (document.getElementById('llmModelPath')?.value || '/opt/llm-models').replace(/\/$/, '')
      });
    });
  });
  return result;
}

function llmRenderAnswerServerInfo(modelName) {
  const panel = document.getElementById('llmAnswerServerInfo');
  if (!modelName) { panel.style.display = 'none'; return; }

  const m = _llmData.supported.find(m => m.name === modelName);
  if (!m) { panel.style.display = 'none'; return; }

  const info = m.ollama_info || {};

  document.getElementById('llmInfoModelName').textContent = m.name;
  document.getElementById('llmInfoTag').textContent       = info.tag || '';

  document.getElementById('llmInfoArch').textContent   = info.architecture   || '—';
  document.getElementById('llmInfoParams').textContent  = info.parameter_count || '—';
  document.getElementById('llmInfoCtx').textContent     = info.context_length  ? info.context_length.toLocaleString() : '—';
  document.getElementById('llmInfoEmbed').textContent   = info.embedding_length ? info.embedding_length.toLocaleString() : '—';
  document.getElementById('llmInfoQuant').textContent   = info.quantization    || m.recommended_quant || '—';
  document.getElementById('llmInfoSize').textContent    = m.size_gb            ? m.size_gb + ' GB' : '—';

  const capEl = document.getElementById('llmInfoCapabilities');
  capEl.innerHTML = '';
  (info.capabilities || []).forEach(cap => {
    const pill = document.createElement('span');
    pill.className = 'llm-info-cap-pill';
    pill.textContent = cap;
    capEl.appendChild(pill);
  });

  const defEl = document.getElementById('llmInfoDefaults');
  defEl.innerHTML = '';
  Object.entries(info.default_parameters || {}).forEach(([k, v]) => {
    const pill = document.createElement('span');
    pill.className = 'llm-info-param-pill';
    pill.textContent = `${k}: ${v}`;
    defEl.appendChild(pill);
  });

  document.getElementById('llmInfoDescription').textContent = m.description || '';

  panel.style.display = 'block';
}

function llmSyncAnswerServerDropdown() {
  const select = document.getElementById('defualtllmModelForIDOLAnswerServer');
  const prevValue = select.value;

  select.innerHTML = '<option value="" disabled>— select a model —</option>';
  llmSupportedModels.forEach(m => {
    const opt = document.createElement('option');
    opt.value = m.id;
    opt.textContent = m.name;
    select.appendChild(opt);
  });

  if (prevValue && select.querySelector(`option[value="${CSS.escape(prevValue)}"]`)) {
    select.value = prevValue;
  } else if (llmSupportedModels.length > 0) {
    select.value = llmSupportedModels[0].id;
  }

  llmSelectCardForAnswerServer(select.value);
  llmRenderAnswerServerInfo(select.value);

  select.onchange = () => {
    llmSelectCardForAnswerServer(select.value);
    llmRenderAnswerServerInfo(select.value);
  };
}

function llmSelectCardForAnswerServer(modelName) {
  if (!modelName) return;

  const idx = _llmData.supported.findIndex(m => m.name === modelName);
  if (idx === -1) return;

  if (!_llmSelected.has(idx)) {
    _llmSelected.add(idx);
    if (!_llmQuantState[idx]) {
      const m = _llmData.supported[idx];
      _llmQuantState[idx] = new Set(m.recommended_quant ? [m.recommended_quant] : []);
    }
  }

  const cb = document.getElementById('llm_cb_' + idx);
  if (cb) {
    cb.checked = true;
    cb.closest('.llm-model-card')?.classList.add('selected');
  }

  llmRenderDownloadSection();
  if (typeof setupIdolValidateSection === 'function') setupIdolValidateSection('basic');
}

/* ====================== 12. ENVIRONMENT & SCRIPT GENERATION ====================== */
function getScriptPaths() {
  const bp = (document.getElementById('basePath')?.value ?? '').trim();

  const hostIp         = (document.getElementById('hostIp')?.value ?? '').trim();
  const extraIpSansVal = (document.getElementById('extraIpSans')?.value ?? '').trim();
  const extraIps       = parseExtraIpSans(extraIpSansVal);

  // Only inject EXTRA_IP_SANS_ENV when it differs from the Host IP - To enforce recreation of all ssl certifcations when the user adds extra IPs to the SAN list
  let sslCmd = `${bp}/utilities/generate-ssl-certs/generate-ssl.sh`;
  if (extraIps.length > 0 && extraIpSansVal !== hostIp) {
    sslCmd = `EXTRA_IP_SANS_ENV="${extraIps.join(',')}" ${bp}/utilities/generate-ssl-certs/generate-ssl.sh --auto`;
  }

  const commonSteps = [
    { cmd: `source ${bp}/pre-setup.sh`,                                      comment: 'Source IDOL env vars' },
    { cmd: sslCmd,                                                           comment: 'Generate SSL certificates' },
    { cmd: `source ~/.bashrc`,                                               comment: 'Reload shell environment' },
    { cmd: `${bp}/init-setup.sh`,                                            comment: 'Initialize IDOL environment' },
    { cmd: `cd ${bp}/utilities/config-placeholders && ./placeholders-replacement.sh`, comment: 'IDOL Preparing Setup Files' },
    { cmd: `cd ${bp}/idol-monitoring && ./monitor.sh start dozzle monitor-ui`,       comment: 'Enable Monitoring Stack' }
  ];

  const deployMap = {
    'basic-idol': { folder: 'basic-idol', comment: 'Start Basic IDOL' },
    'data-admin': { folder: 'data-admin', comment: 'Start Data Admin IDOL' },
    'rich-media': { folder: 'rich-media', comment: 'Start Rich Media' }
  };

  const selected = getDeploymentType();
  let steps = [...commonSteps];

  selected.forEach(type => {
    const step = deployMap[type];
    if (step) {
      steps.push({ 
        cmd: `cd ${bp}/idol-containers-toolkit/${step.folder} && ./deploy.sh up -d`, 
        comment: step.comment 
      });
    }
  });

  const parts = [];

  parts.push('# =============================================');
  parts.push('# IDOL DOCKER SETUP - FULL INSTALLATION SCRIPT');
  parts.push('# =============================================');
  parts.push('');

  // Common steps – always followed by License Server, so always chain with &&
  commonSteps.forEach((step) => {
    parts.push(`# ${step.comment}`);
    parts.push(`${step.cmd} &&`);
    parts.push('');
  });

  // =============================================
  // DEPLOY LICENSE SERVER (with cd to its folder)
  // =============================================
  parts.push('# =============================================');
  parts.push('# DEPLOY LICENSE SERVER');
  parts.push('# =============================================');
  parts.push('');

  const licenseCmd = `cd ${bp}/idol-licenseserver && ./deploy-license-server.sh $IDOL_LICENSESERVER_PROTOCOL $SOURCE_IDOL_LICENSE_SERVER_PATH $SOURCE_IDOL_LICENSE_KEY_PATH $IDOL_LICENSE_KEY_MAC`;
  
  parts.push('# Deploy License Server');
  // Chain with && only if there are Idol services after it
  if (selected.length > 0) {
    parts.push(`${licenseCmd} &&`);
  } else {
    parts.push(licenseCmd);
  }
  parts.push('');

  if (selected.length > 0) {
    parts.push('# =============================================');
    parts.push('# DEPLOY SELECTED IDOL SERVICES');
    parts.push('# =============================================');
    parts.push('');

    const deploySteps = steps.slice(commonSteps.length);
    deploySteps.forEach((step, index) => {
      parts.push(`# ${step.comment}`);
      const isLast = index === deploySteps.length - 1;
      parts.push(`${step.cmd}${isLast ? '' : ' &&'}`);
      parts.push('');
    });
  }

  return parts.join('\n');
}

function setupIdolGetEnv() {
  const env = {};
  const basicOn     = document.getElementById('deployTypeBasic')?.checked     || false;
  const dataAdminOn = document.getElementById('deployTypeDataAdmin')?.checked  || false;
  const richMediaOn = document.getElementById('deployTypeRichMedia')?.checked  || false;
  const g = id => document.getElementById(id)?.value?.trim() || '';

  env.IDOL_HOST_FQDN           = g('fqdn');
  env.IDOL_BASE_PATH           = g('basePath');
  env.IDOL_BASIC_INSTALL       = basicOn     ? 'TRUE' : 'FALSE';
  env.IDOL_DATA_ADMIN_INSTALL  = dataAdminOn ? 'TRUE' : 'FALSE';
  env.IDOL_RICH_MEDIA_INSTALL  = richMediaOn ? 'TRUE' : 'FALSE';
  env.IDOL_SHARED_FOLDER_PATH= g('sharedFolderBasePath');
  env.IDOL_DEPLOYMENT_TYPE     = 'idol-demo';
  env.IDOL_DEPLOYMENT_NETWORK  = `${env.IDOL_DEPLOYMENT_TYPE}-network`;
  env.IDOL_DEPLOYMENT_SUBTYPE  = getDeploymentType();

  // New toggle: Whether user wants to provide a custom LLM API Key
  env.IDOL_LLM_ENABLE_APIKEY = radioVal('llmApiKeyEnabled') || 'FALSE';

  env.IDOL_LLM_INTEGRATION = !dataAdminOn
    ? 'FALSE'
    : (document.getElementById('llmIntegrationToggle')?.checked ? 'TRUE' : 'FALSE');

  env.IDOL_LLM_WIKI_ENABLED = document.getElementById('llmWikiEnableToggle')?.checked ? 'TRUE' : 'FALSE';

  if (env.IDOL_LLM_INTEGRATION === 'TRUE') {
    const modelNames             = getSelectedModelNamesArray();
    const modelUrls              = getSelectedModelUrlsArray();
    
    env.IDOL_LLM_MODEL_NAME      = modelNames[0] ?? '';
    env.IDOL_LLM_MODEL_SELECTION = modelNames.join(',');
    env.IDOL_LLM_MODEL_URL       = modelUrls.join(',');
    env.IDOL_LLM_MODEL_PATH      = g('llmModelPath');

    env.HF_TOKEN = g('hfToken');
    env.IDOL_LLM_USE_GPU = document.getElementById('gpuEnableToggle')?.checked ? 'TRUE' : 'FALSE';

    // Only export IDOL_LLM_API_KEY if user chose "Yes"
    if (env.IDOL_LLM_ENABLE_APIKEY === 'TRUE') {
      env.IDOL_LLM_API_KEY = g('llmAPIKey');
    } else {
      env.IDOL_LLM_API_KEY = 'Hyper-Scaler API Key is Not provided (user chose "No")';
    }
  }

  env.IDOL_SERVER_VERSION      = g('basic-idol-version') || '26.1';
  env.IDOL_DATA_ADMIN_VERSION  = dataAdminOn ? (g('data-admin-version') || '24.3') : '';
  env.IDOL_RICH_MEDIA_VERSION  = richMediaOn ? (g('rich-media-version') || '25.2') : '';

  env.IDOL_NET_HOST_IP  = g('hostIp');
  env.IDOL_NET_GUEST_IP = g('guestIp');
  env.EXTRA_IP_SANS_ENV = parseExtraIpSans(g('extraIpSans')).join(',');

  env.IDOL_DATA_ADMIN_HTTP_UI_PORT     = g('mediaServerHttpUiPort')  || '8003';
  env.PORT_BASIC_IDOL_HTTPD_REVERSE    = g('basicIdolHttpdPort')      || '8330';
  env.IDOL_NIFI_UI_PORT                = g('nifiPort')                || '8443';
  env.IDOL_FIND_UI_BASIC_IDOL_PORT     = g('findUiPortBaseIdol')      || '8440';
  env.IDOL_FIND_UI_DATA_ADMIN_PORT     = g('findUiPortDataAdmin')     || '8441';
  env.IDOL_DATA_ADMIN_HTTPS_UI_PORT    = g('dataAdminHttpsUiPort')    || '8444';
  env.IDOL_DATA_ADMIN_INTERNAL_UI_PORT = g('dataAdminInternalUiPort') || '8445';

  const daMap = {
    PORT_DATA_ADMIN_COMMUNITY:             g('communityPort')       || '9033',
    PORT_DATA_ADMIN_VIEW:                  g('viewServerPort')      || '9083',
    PORT_DATA_ADMIN_PASSAGE_CONTENT:       g('passageContentPort')  || '9103',
    PORT_DATA_ADMIN_ANSWER_SERVER:         g('answerServerPort')    || '12000',
    PORT_DATA_ADMIN_ANSWER_BANK_AGENTSTORE:g('answerBankAgentPort') || '12200',
    PORT_DATA_ADMIN_PASSAGE_AGENTSTORE:    g('passageAgentPort')    || '12310',
    PORT_DATA_ADMIN_QMS:                   g('qmsPort')             || '16000',
    PORT_DATA_ADMIN_QMS_AGENTSTORE:        g('qmsAgentPort')        || '20050',
    PORT_DATA_ADMIN_STATS_SERVER:          g('statsServerPort')     || '19870',
  };
  Object.entries(daMap).forEach(([k, v]) => {
    env[k]              = v;
    env[k + '_INDEX']   = String(+v + 1);
    env[k + '_SERVICE'] = String(+v + 2);
  });

  const biMap = {
    PORT_BASIC_IDOL_CONTENT:                    g('biContentPort')      || '9100',
    PORT_BASIC_IDOL_AGENTSTORE:                 g('biAgentStorePort')   || '9050',
    PORT_BASIC_IDOL_CATEGORY:                   g('biCategoryPort')     || '9020',
    PORT_BASIC_IDOL_CATEGORISATION_AGENTSTORE:  g('biCatAgentStorePort')|| '9180',
    PORT_BASIC_IDOL_COMMUNITY:                  g('biCommunityPort')    || '9030',
    PORT_BASIC_IDOL_VIEW:                       g('biViewPort')         || '9080',
  };
  Object.entries(biMap).forEach(([k, v]) => {
    env[k]              = v;
    env[k + '_INDEX']   = String(+v + 1);
    env[k + '_SERVICE'] = String(+v + 2);
  });

  const mediaServerBase = +(g('rmMediaServerPort')         || '14000');
  const playlistBase    = +(g('rmMediaServerPlaylistPort') || '24000');
  const uiPortalBase    = +(g('mediaServerHttpUiPort')    || '8003');

  env.PORT_RICH_MEDIA_MEDIASERVER                          = String(mediaServerBase);
  env.PORT_RICH_MEDIA_MEDIASERVER_SERVICE                  = String(mediaServerBase + 1);
  env.PORT_RICH_MEDIA_MEDIASERVER_SSL                      = String(mediaServerBase + 2);
  env.PORT_RICH_MEDIA_MEDIASERVER_SERVICE_SSL              = String(mediaServerBase + 3);
  env.PORT_RICH_MEDIA_MEDIASERVER_PLAYLISTSERVER           = String(playlistBase);
  env.PORT_RICH_MEDIA_MEDIASERVER_PLAYLISTSERVER_SERVICE   = String(playlistBase + 1);
  env.PORT_RICH_MEDIA_MEDIASERVER_HTTP_APPLICATION         = String(uiPortalBase);
  env.PORT_RICH_MEDIA_MEDIASERVER_HTTPS_APPLICATION        = String(uiPortalBase + 1);

  const catAgentBase = +(g('biCatAgentStorePort') || '9180');
  env.PORT_BASIC_IDOL_CATEGORISATION_AGENTSTORE_QUERY = String(catAgentBase + 3);

  const nd = g('nifiDeployment') || 'nifi-ver2-full';
  env.IDOL_NIFI_DEPLOY_VERSION = nd.includes('ver2') ? 'nifi-ver2' : 'nifi-ver1';
  env.IDOL_NIFI_DEPLOY_TYPE    = nd;

  env.IS_IDOL_NIFI_GITHUB_INTEGRATION = radioVal('githubIntegration') || 'FALSE';
  env.GITHUB_USER  = g('githubUsername');
  env.GITHUB_TOKEN = g('githubToken');
  env.GITHUB_REPO  = g('githubRepo');

  env.IS_IDOL_NIFI_PRESERVE          = radioVal('nifiPreserve')     || 'FALSE';
  env.IS_IDOL_NIFI_REGISTRY_PRESERVE = radioVal('registryPreserve') || 'TRUE';
  env.IDOL_NIFI_REGISTRY_PATH        = g('registryPath');

  env.IS_IDOL_NIFI_CONNECTOR_NAR_IMPORT = radioVal('connectorNarImport') || 'FALSE';

  // Only define IDOL_NIFI_CONNECTOR_NAR_PATH when import is enabled
  if (env.IS_IDOL_NIFI_CONNECTOR_NAR_IMPORT === 'TRUE') {
    env.IDOL_NIFI_CONNECTOR_NAR_PATH = g('connectorNarPath') || '';
  } else {
    // Important: delete it so validation skips it
    delete env.IDOL_NIFI_CONNECTOR_NAR_PATH;
  }

  env.IDOL_LICENSE_KEY_HOSTNAME  = g('licenseHostname');
  env.IDOL_LICENSE_KEY_MAIL      = g('licenseEmail');
  env.IDOL_LICENSE_KEY_MAC       = g('licenseMac');
  env.IDOL_LICENSE_KEY_TOKEN     = g('dockerLicenseToken');
  env.SOURCE_IDOL_LICENSE_SERVER_PATH = g('licenseServerPath');
  env.SOURCE_IDOL_LICENSE_KEY_PATH    = g('licenseKeyPath');
  env.IDOL_LICENSESERVER_NAME   = env.SOURCE_IDOL_LICENSE_SERVER_PATH
    .split('/').find(f => f.startsWith('LicenseServer_')) || '';
  const licenseMode = radioVal('licenseMode') || 'NEW';
  env.IDOL_LICENSESERVER_MODE = licenseMode;

  if (licenseMode === 'EXISTING') {
    env.IDOL_LICENSESERVER_URL = g('licenseUrl');                    // use the user-provided URL
  } else {
    env.IDOL_LICENSESERVER_URL = 'https://licenseserver:20000/a=getlicenseinfo';   // NEW mode → internal license server
  }
  
  // =============================================================================
  // AUTO-PARSE IDOL_LICENSESERVER_URL 
  //   • IDOL_LICENSESERVER_PROTOCOL
  //   • IDOL_LICENSESERVER_FQDN
  //   • IDOL_LICENSESERVER_PORT
  // =============================================================================
  if (env.IDOL_LICENSESERVER_URL) {
      try {
        let urlStr = env.IDOL_LICENSESERVER_URL.trim();

        console.log('🔍 [License Parser] Original URL:', urlStr);

        // Remove everything after the host:port (path, query, fragment)
        // This regex keeps only scheme://host:port
        let cleanUrl = urlStr.replace(/^(https?:\/\/[^\/]+).*$/i, '$1');

        console.log('🧹 [License Parser] Cleaned URL:', cleanUrl);

        const parsed = new URL(cleanUrl);

        env.IDOL_LICENSESERVER_PROTOCOL = parsed.protocol.replace(':', ''); // "https" or "http"
        env.IDOL_LICENSESERVER_FQDN     = parsed.hostname;                   // e.g. eecmidollicense.idoldemos.net

        // Port handling
        if (parsed.port) {
          env.IDOL_LICENSESERVER_PORT = parsed.port;
        } else if (urlStr.includes(':20000')) {
          env.IDOL_LICENSESERVER_PORT = '20000';
        } else {
          env.IDOL_LICENSESERVER_PORT = (parsed.protocol === 'https:') ? '443' : '80';
        }

        console.log(`✅ [License Parser] Successfully parsed → ${env.IDOL_LICENSESERVER_PROTOCOL}://${env.IDOL_LICENSESERVER_FQDN}:${env.IDOL_LICENSESERVER_PORT}`);

      } catch (err) {
        console.error('❌ [License Parser] Failed to parse IDOL_LICENSESERVER_URL:', env.IDOL_LICENSESERVER_URL);
        console.error('Error details:', err);

        // Safe fallback
        env.IDOL_LICENSESERVER_PROTOCOL = 'https';
        env.IDOL_LICENSESERVER_FQDN     = 'licenseserver';
        env.IDOL_LICENSESERVER_PORT     = '20000';
      }
  }

  env.IS_IDOL_PRESERVE  = radioVal('preserve') || 'TRUE';
  env.IDOL_PRESERVE_PATH = g('preservePath');
  const pp = env.IDOL_PRESERVE_PATH;

  const pretrainedModelsPath = g('pretrainedModelsPath') || '/mnt/c/OpenText/hotfolder/pretrainedModels';
  const nifiMediaServerPath  = g('nifiMediaServerPath')  || '/mnt/c/OpenText/hotfolder/nifiMediaServer';
  env.IDOL_MEDIASERVER_PRETRAINE_MODELS_FOLDER_NAME = pretrainedModelsPath;
  env.IDOL_MEDIASERVER_NIFI_POLICY_FOLDER_NAME       = nifiMediaServerPath;

  const subDirs = {
    IDOL_NIFI_DATA_PATH:                             `${pp}/nifi-data`,
    IDOL_NIFI_SCRIPTS_PATH:                          `${pp}/nifi-scripts`,
    IDOL_PRESERVE_FIND_PATH:                         `${pp}/find`,
    IDOL_PRESERVE_CONTENT_PATH:                      `${pp}/content`,
    IDOL_PRESERVE_COMMUNITY_PATH:                    `${pp}/community`,
    IDOL_PRESERVE_AGENTSTORE_PATH:                   `${pp}/agentstore`,
    IDOL_PRESERVE_CATEGORY_PATH:                     `${pp}/category`,
    IDOL_PRESERVE_CATEGORISATION_AGENTSTORE_PATH:    `${pp}/categorisation_agentstore`,
    IDOL_VIEW_PATH:                                  `${pp}/view`,
    IDOL_PRESERVE_PASSAGEEXTRACTOR_CONTENT_PATH:     `${pp}/passageextractor_content`,
    IDOL_PRESERVE_PASSAGEEXTRACTOR_AGENTSTORE_PATH:  `${pp}/passageextractor_agentstore`,
    IDOL_PRESERVE_DATAADMIN_PATH:                    `${pp}/dataadmin`,
    IDOL_PRESERVE_DATAADMIN_COMMUNITY_PATH:          `${pp}/dataadmin_community`,
    IDOL_PRESERVE_DATAADMIN_VIEWSERVER_PATH:         `${pp}/dataadmin_viewserver`,
    IDOL_PRESERVE_DATAADMIN_STATSSERVER_PATH:        `${pp}/dataadmin_statsserver`,
    IDOL_PRESERVE_QMS_PATH:                          `${pp}/qms`,
    IDOL_PRESERVE_QMS_AGENTSTORE_PATH:               `${pp}/qms_agentstore`,
    IDOL_PRESERVE_ANSWERSERVER_PATH:                 `${pp}/answerserver`,
    IDOL_PRESERVE_ANSWERBANK_AGENTSTORE_PATH:        `${pp}/answerbank_agentstore`,
    IDOL_PRESERVE_LICENSESERVER_CFG_PATH:            `${pp}/licenseserver`,
    IDOL_PRESERVE_IDOL_COMMON_CFG_PATH:              `${pp}/content/cfg`,
    IDOL_PRESERVE_IDOL_COMMON_CFG_FILENAME:          'idol.common.cfg',
    IDOL_PRESERVE_MEDIASERVER_PATH:                  `${pp}/mediaserver`,
  };
  Object.assign(env, subDirs);

  env.IDOL_HOST_STORAGE_PATH   = g('storagePath');
  env.IS_IDOL_VALIDATION_MET   = 'TRUE';
  env.IDOL_TOOLKIT_PATH        = 'idol-containers-toolkit';
  env.IDOL_DRIVER_TYPE         = 'local';
  env.IS_IDOL_LICENSE_ACTIVE   = isLicenseActive ? 'TRUE' : 'FALSE';
  return env;
}

function llmGetAnswerServerEnvVars() {
  const select = document.getElementById('defualtllmModelForIDOLAnswerServer');
  const modelName = select?.value;
  if (!modelName) return {};

  const m = _llmData.supported.find(m => m.name === modelName);
  if (!m) return {};

  const info = m.ollama_info || {};
  const def  = info.default_parameters || {};

  return {
    IDOL_ANSWERSERVER_LLM_MODEL_NAME        : m.name                                  || '',
    IDOL_ANSWERSERVER_LLM_OLLAMA_TAG        : info.tag                                || '',
    IDOL_ANSWERSERVER_LLM_DESCRIPTION       : m.description                           || '',
    IDOL_ANSWERSERVER_LLM_HF_REPO           : m.hf_repo                              || '',
    IDOL_ANSWERSERVER_LLM_ARCHITECTURE      : info.architecture                       || '',
    IDOL_ANSWERSERVER_LLM_PARAMETER_COUNT   : info.parameter_count                    || '',
    IDOL_ANSWERSERVER_LLM_CONTEXT_LENGTH    : info.context_length                     || '',
    IDOL_ANSWERSERVER_LLM_EMBEDDING_LENGTH  : info.embedding_length                   || '',
    IDOL_ANSWERSERVER_LLM_QUANTIZATION      : info.quantization  || m.recommended_quant || '',
    IDOL_ANSWERSERVER_LLM_SIZE_GB           : m.size_gb                               || '',
    IDOL_ANSWERSERVER_LLM_CAPABILITIES      : (info.capabilities || []).join(' ')     || '',
    IDOL_ANSWERSERVER_LLM_NUM_CTX           : def.num_ctx                             || '',
    IDOL_ANSWERSERVER_LLM_STOP              : def.stop                                || '',
    IDOL_ANSWERSERVER_LLM_TEMPERATURE       : def.temperature                         || '',
    IDOL_ANSWERSERVER_LLM_TOP_P             : def.top_p                               || '',
    IDOL_ANSWERSERVER_LLM_SYSTEM_PROMPT     : info.system_prompt                      || '',
    IDOL_ANSWERSERVER_LLM_MODEL_PATH        : document.getElementById('llmModelPath')?.value?.replace(/\/$/, '') || '',
  };
}

function summaryResetAllButtons() {
  const buildBtn = document.getElementById('buildScriptBtn');
  const stepBtn = document.getElementById('generateSetupScriptBtn');
  const cmdBtn = document.getElementById('generateCommandBtn');
  const copyBtn = document.getElementById('copyCommandBtn');
  const bashPre = document.getElementById('bashPreSetup');
  const execSec = document.getElementById('executeSection');
  if (buildBtn) {
    buildBtn.classList.remove('btn-warning','btn-success','btn-danger','btn-secondary');
    buildBtn.classList.add('btn-primary');
    buildBtn.innerHTML = '<i class="fas fa-cogs"></i> Build Pre-Setup Script';
  }
  if (stepBtn) {
    stepBtn.classList.remove('btn-warning','btn-success','btn-danger','btn-secondary');
    stepBtn.classList.add('btn-primary');
    stepBtn.classList.add('hidden');
  }
  if (cmdBtn) {
    cmdBtn.classList.remove('btn-warning','btn-success','btn-danger','btn-secondary');
    cmdBtn.classList.add('btn-primary');
    cmdBtn.innerHTML = '<i class="fas fa-arrow-right"></i> Continue to Step 3 - Generate Command';
  }
  if (copyBtn) {
    copyBtn.classList.remove('btn-primary','btn-success','btn-danger','btn-secondary');
    copyBtn.classList.add('btn-warning');
  }
  if (bashPre) bashPre.classList.add('hidden');
  if (execSec) execSec.classList.add('hidden');
}

function setupIdolGeneratePreSetupScript() {
  const bashPreSetup    = document.getElementById('bashPreSetup');
  const buildScriptBtn  = document.getElementById('buildScriptBtn');
  const genBtn          = document.getElementById('generateSetupScriptBtn');
  const scriptContentEl = document.getElementById('scriptContent');
  if (!bashPreSetup || !buildScriptBtn || !scriptContentEl) return;

  if (buildScriptBtn.classList.contains('btn-warning')) {
    summaryResetAllButtons();
    return;
  }

  const env = setupIdolGetEnv();
  let script = '#!/bin/bash\n\n# IDOL Pre-Setup Script\n# Generated: ' + new Date().toLocaleString() + '\n\n';

  ENV_VAR_ORDER.forEach(key => {
    if (key === 'IDOL_LICENSESERVER_PROTOCOL') {
      script += '\n# License server protocol\nexport IDOL_LICENSESERVER_PROTOCOL=https\n';
      return;
    }

    if (key === 'IS_IDOL_NIFI_CONNECTOR_NAR_IMPORT') {
      const importEnabled = env.IS_IDOL_NIFI_CONNECTOR_NAR_IMPORT === 'TRUE';
      script += `export IS_IDOL_NIFI_CONNECTOR_NAR_IMPORT="${importEnabled ? 'TRUE' : 'FALSE'}"\n`;
      
      if (importEnabled && env.IDOL_NIFI_CONNECTOR_NAR_PATH) {
        script += `export IDOL_NIFI_CONNECTOR_NAR_PATH="${env.IDOL_NIFI_CONNECTOR_NAR_PATH}"\n`;
      } else {
        script += `export IDOL_NIFI_CONNECTOR_NAR_PATH=$IDOL_BASE_PATH/persistent-data/nifi-connectors\n`;
      }
      return;
    }

    if (key === 'IDOL_DATA_ADMIN_INSTALL') {
      const daV = env.IDOL_DATA_ADMIN_VERSION || '24.3';
      script += `\nexport IDOL_DATA_ADMIN_INSTALL="${env.IDOL_DATA_ADMIN_INSTALL}"\n`;
      script += `if [ "$IDOL_DATA_ADMIN_INSTALL" = "TRUE" ]; then\n`;
      script += `  export IDOL_DATA_ADMIN_VERSION=${daV}\n`;
      script += `else\n`;
      script += `  export IDOL_DATA_ADMIN_VERSION=$IDOL_SERVER_VERSION\n`;
      script += `fi\n`;
      return;
    }

    if (key === 'IDOL_RICH_MEDIA_INSTALL') {
      const rmV               = env.IDOL_RICH_MEDIA_VERSION          || '25.2';
      const pretrainedModels  = env.IDOL_MEDIASERVER_PRETRAINE_MODELS_FOLDER_NAME || '.';
      const nifiMediaServerPath = env.IDOL_MEDIASERVER_NIFI_POLICY_FOLDER_NAME     || '.';
      script += `\nexport IDOL_RICH_MEDIA_INSTALL="${env.IDOL_RICH_MEDIA_INSTALL}"\n`;
      script += `if [ "$IDOL_RICH_MEDIA_INSTALL" = "TRUE" ]; then\n`;
      script += `  export IDOL_RICH_MEDIA_VERSION=${rmV}\n`;
      script += `  export IDOL_MEDIASERVER_PRETRAINE_MODELS_FOLDER_NAME="${pretrainedModels}"\n`;
      script += `  export IDOL_MEDIASERVER_NIFI_POLICY_FOLDER_NAME="${nifiMediaServerPath}"\n`;
      script += `else\n`;
      script += `  export IDOL_RICH_MEDIA_VERSION=$IDOL_SERVER_VERSION\n`;
      script += `  export IDOL_MEDIASERVER_PRETRAINE_MODELS_FOLDER_NAME="."\n`;
      script += `  export IDOL_MEDIASERVER_NIFI_POLICY_FOLDER_NAME="."\n`;
      script += `fi\n`;
      return;
    }

    // === EXCLUDE VARS THAT SHOULD NOT BE EXPORTED OR VALIDATED ===
    const excludedVars = new Set([
      'IDOL_NIFI_CONNECTOR_NAR_PATH',
    ]);

    if (excludedVars.has(key)) {
      return;
    }

    const value = env[key];
    
    if (value !== undefined && value !== '') {
      const needsQuotes = value.includes(' ') || 
                         key.toLowerCase().includes('path') || 
                         key.toLowerCase().includes('token') || 
                         key.toLowerCase().includes('mail');
                         
      script += `export ${key}=${needsQuotes ? `"${value}"` : value}\n`;
    }
  });

  if (env.IDOL_LLM_INTEGRATION === 'TRUE') {
    const llmVars = llmGetAnswerServerEnvVars();
    if (Object.keys(llmVars).length) {
      script += '\n# ── LLM Answer Server Model ────────────────────────────\n';
      Object.entries(llmVars).forEach(([key, value]) => {
        if (value === '' || value === undefined || value === null) return;
        const v = String(value);
        const needsQuotes = v.includes(' ') || key.toLowerCase().includes('path') || key.toLowerCase().includes('prompt') || key.toLowerCase().includes('description') || key.toLowerCase().includes('stop');
        script += `export ${key}=${needsQuotes ? `"${v.replace(/"/g, '\\"')}"` : v}\n`;
      });
    }
  }

  script += '\necho "Setting up IDOL deployment directories..."\n';

  if (env.IS_IDOL_PRESERVE === 'TRUE' && env.IDOL_PRESERVE_PATH) {
    const dirs = [
      env.IDOL_PRESERVE_FIND_PATH,
      env.IDOL_PRESERVE_CONTENT_PATH,
      env.IDOL_PRESERVE_COMMUNITY_PATH,
      env.IDOL_PRESERVE_AGENTSTORE_PATH,
      env.IDOL_PRESERVE_CATEGORY_PATH,
      env.IDOL_PRESERVE_CATEGORISATION_AGENTSTORE_PATH,
      env.IDOL_VIEW_PATH,
      env.IDOL_PRESERVE_PASSAGEEXTRACTOR_CONTENT_PATH,
      env.IDOL_PRESERVE_PASSAGEEXTRACTOR_AGENTSTORE_PATH,
      env.IDOL_PRESERVE_DATAADMIN_PATH,
      env.IDOL_PRESERVE_DATAADMIN_COMMUNITY_PATH,
      env.IDOL_PRESERVE_DATAADMIN_VIEWSERVER_PATH,
      env.IDOL_PRESERVE_DATAADMIN_STATSSERVER_PATH,
      env.IDOL_PRESERVE_QMS_PATH,
      env.IDOL_PRESERVE_QMS_AGENTSTORE_PATH,
      env.IDOL_PRESERVE_ANSWERSERVER_PATH,
      env.IDOL_PRESERVE_ANSWERBANK_AGENTSTORE_PATH,
      env.IDOL_PRESERVE_IDOL_COMMON_CFG_PATH,
      env.IDOL_PRESERVE_MEDIASERVER_PATH,
    ].filter(Boolean);

    dirs.forEach(d => {
      script += `sudo mkdir -p "${d}" && sudo install -d -m 755 -o $USER -g $USER "${d}"\n`;
    });
  }

  if (env.IS_IDOL_NIFI_PRESERVE === 'TRUE' && env.IDOL_NIFI_DATA_PATH && env.IDOL_NIFI_SCRIPTS_PATH) {
    script += `sudo mkdir -p "${env.IDOL_NIFI_DATA_PATH}" && sudo install -d -m 755 -o $USER -g $USER "${env.IDOL_NIFI_DATA_PATH}"\n`;
    script += `sudo mkdir -p "${env.IDOL_NIFI_SCRIPTS_PATH}" && sudo install -d -m 755 -o $USER -g $USER "${env.IDOL_NIFI_SCRIPTS_PATH}"\n`;
  }

  if (env.IS_IDOL_NIFI_REGISTRY_PRESERVE === 'TRUE' && env.IDOL_NIFI_REGISTRY_PATH) {
    script += `sudo mkdir -p "${env.IDOL_NIFI_REGISTRY_PATH}" && sudo install -d -m 755 -o $USER -g $USER "${env.IDOL_NIFI_REGISTRY_PATH}"\n`;
  }

  if (env.IDOL_HOST_STORAGE_PATH) {
    script += `\n# Host storage mapping directories\n`;
    [
      env.IDOL_HOST_STORAGE_PATH,
      `${env.IDOL_HOST_STORAGE_PATH}/ingest`,
      `${env.IDOL_HOST_STORAGE_PATH}/staging`,
    ].forEach(d => {
      script += `sudo mkdir -p "${d}" && sudo install -d -m 755 -o $USER -g $USER "${d}"\n`;
    });
  }

  if (env.IDOL_LLM_INTEGRATION === 'TRUE' && env.IDOL_LLM_MODEL_PATH) {
    script += `\n# LLM model directory\n`;
    script += `sudo mkdir -p "${env.IDOL_LLM_MODEL_PATH}" && sudo install -d -m 755 -o $USER -g $USER "${env.IDOL_LLM_MODEL_PATH}"\n`;
  }

  script += '\necho "IDOL pre-setup complete!"\n';

  scriptContentEl.textContent = script;
  bashPreSetup.classList.remove('hidden');
  genBtn?.classList.remove('hidden');
  buildScriptBtn.classList.remove('btn-primary', 'btn-success', 'btn-danger', 'btn-secondary');
  buildScriptBtn.classList.add('btn-warning');
  buildScriptBtn.innerHTML = '<i class="fas fa-sync-alt"></i> Regenerated Script';
}

function setupIdolGenerateSetupScript() {
  const execSection = document.getElementById('executeSection');
  const genBtn = document.getElementById('generateSetupScriptBtn');
  const bashPreSetup = document.getElementById('bashPreSetup');
  if (bashPreSetup) {
    if (genBtn && genBtn.classList.contains('btn-primary')) {
      bashPreSetup.classList.add('hidden');
    } else {
      bashPreSetup.classList.remove('hidden');
    }
  }
  if (genBtn) {
    genBtn.classList.remove('btn-primary','btn-success','btn-danger','btn-secondary');
    genBtn.classList.add('btn-warning');
  }
  if (execSection) {
    execSection.classList.remove('hidden');
    execSection.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }
  setupIdolInitializeCommandListeners();
}

async function setupIdolGenerateBashCommand() {
  setupIdolValidateConfig(true);
  setupIdolInitializeCommandListeners();
  await setupIdolSaveScriptToServer();
  const genBtn = document.getElementById('generateCommandBtn');
  const copyBtn = document.getElementById('copyCommandBtn');
  if (genBtn) {
    genBtn.classList.remove('btn-primary','btn-success','btn-danger','btn-secondary');
    genBtn.classList.add('btn-warning');
    genBtn.innerHTML = '<i class="fas fa-check"></i> Saved. Run in Terminal -->';
  }
  if (copyBtn) {
    copyBtn.classList.remove('btn-warning','btn-success','btn-danger','btn-secondary');
    copyBtn.classList.add('btn-primary');
  }
}

function setupIdolCopyPreSetupScript() {
  const el = document.getElementById('scriptContent');
  if (!el) return;
  navigator.clipboard.writeText(el.textContent).then(() => showToast('Script copied!')).catch(() => showToast('Copy failed', true));
}

function setupIdolDownloadPreSetupScript() {
  const el = document.getElementById('scriptContent');
  if (!el) return;
  const blob = new Blob([el.textContent], { type:'text/x-shellscript' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'idol-pre-setup.sh';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(a.href);
  showToast('Script downloaded!');
}

function setupIdolCopyCommand() {
  const el  = document.getElementById('commandOutput');
  const btn = document.getElementById('copyCommandBtn');
  if (!el) return;

  const text = el.textContent?.trim();

  if (!text || text === 'Click "Generate Command" to build the deployment command') {
    showToast('Generate the command first!', true);
    return;
  }

  const doFeedback = (success) => {
    if (success) {
      btn.innerHTML = '<i class="fas fa-check"></i> Copied! Paste it in your terminal';
      btn.style.background = 'var(--success, #22c55e)';
      showToast('Command copied!');
    } else {
      btn.innerHTML = '<i class="fas fa-times"></i> Copy failed — select & copy manually';
      btn.style.background = 'var(--danger, #ef4444)';
      showToast('Copy failed', true);
    }
    setTimeout(() => {
      btn.innerHTML = '<i class="far fa-copy"></i> Final Step - Copy Command to Terminal and Execute it';
      btn.style.background = '';
    }, 3000);
  };

  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text)
      .then(() => doFeedback(true))
      .catch(() => doFeedback(false));
  } else {
    try {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.cssText = 'position:fixed;opacity:0;top:0;left:0;';
      document.body.appendChild(ta);
      ta.focus();
      ta.select();
      const ok = document.execCommand('copy');
      document.body.removeChild(ta);
      doFeedback(ok);
    } catch {
      doFeedback(false);
    }
  }
}

async function setupIdolSaveScriptToServer() {
  const sc = document.getElementById('scriptContent');
  const res = document.getElementById('saveScriptResult');
  if (!sc || !res) return false;
  res.style.display = 'none';
  try {
    const r = await fetch('/config-idol/save-script', {
      method:'POST',
      headers:{ 'Content-Type':'application/json' },
      body: JSON.stringify({ file_path:'/setup-scripts/pre-setup.sh', script_content:sc.textContent })
    });
    const data = await r.json();
    res.innerHTML = (r.ok && data.success)
      ? `<div class="alert alert-success"><i class="alert-icon fas fa-check-circle"></i><div><strong>Saved!</strong> ${data.file_path}</div></div>`
      : `<div class="alert alert-danger"><i class="alert-icon fas fa-times-circle"></i><div>Failed: ${data.error || 'Unknown error'}</div></div>`;
    res.style.display = 'block';
    return r.ok && data.success;
  } catch(e) {
    res.innerHTML = `<div class="alert alert-danger"><i class="alert-icon fas fa-times-circle"></i><div>Network error: ${e.message}</div></div>`;
    res.style.display = 'block';
    return false;
  }
}

function setupIdolInitializeCommandListeners() {
  const out = document.getElementById('commandOutput');
  const customCmd = document.getElementById('commandContent');
  const update = () => {
    const command = getScriptPaths();
    const custom = customCmd?.value?.trim() || '';
    if (out) {
      out.textContent = custom ? `${command} && \\\n${custom}` : command;
    }
  };
  if (customCmd) {
    if (customCmd._handler) customCmd.removeEventListener('input', customCmd._handler);
    customCmd._handler = update;
    customCmd.addEventListener('input', update);
  }
  update();
}

/* ====================== 13. DYNAMIC LINKS & INFO SECTION ====================== */
function updateInfoSectionUrls() {
  // === HOST RESOLUTION (FQDN vs IP vs idol-docker-host) ===
  const isChecked    = document.getElementById('hostToggleSwitch')?.checked || false;
  const isIpChecked  = document.getElementById('ipToggleSwitch')?.checked || false;
  const fqdnInput    = document.getElementById('fqdn');
  const fqdn         = fqdnInput?.value?.trim();
  const hostIp       = document.getElementById('hostIp')?.value?.trim();

  // === Extra IP SANs: defaults to hostIp; if the user overrides it with a
  // different value, that value takes over as the displayed/used IP ===
  const extraIpSansInput = document.getElementById('extraIpSans');
  if (extraIpSansInput && !extraIpSansInput.value.trim() && hostIp) {
    extraIpSansInput.value = hostIp;
  }
  const extraIpSansVal = extraIpSansInput?.value?.trim();
  const extraIps = parseExtraIpSans(extraIpSansVal);
  const effectiveIp = (extraIps.length > 0 && extraIpSansVal !== hostIp) ? extraIps[0] : hostIp;

  if (isChecked && fqdn) {
    HOST = fqdn;
  } else if (isIpChecked && effectiveIp) {
    HOST = effectiveIp;
  } else {
    HOST = 'idol-docker-host';
  }

  // update the label in the checkbox — follows Extra IP SANs when it differs from hostIp
  const ipLabel = document.getElementById('ipToggleLabel');
  if (ipLabel) ipLabel.textContent = effectiveIp || '–';

  console.log('%c[updateInfoSectionUrls] HOST →', 'color:#10b981;font-weight:600', HOST);

  // === PORT HELPER ===
  function port(id, defaultVal) {
    const el = document.getElementById(id);
    const v = parseInt(el ? el.value : '', 10);
    return isNaN(v) ? defaultVal : v;
  }

  // === ALL PORTS USED IN THE PAGE ===
  const p = {
    nifi: port('nifiPort', 8443),
    nifiRegistry: 18080,

    // Basic IDOL
    biCategory: port('biCategoryPort', 9020),
    biCommunity: port('biCommunityPort', 9030),
    biContent: port('biContentPort', 9100),
    biAgentStore: port('biAgentStorePort', 9050),
    biCatAgentStore: port('biCatAgentStorePort', 9180),
    biView: port('biViewPort', 9080),

    // Data Admin Classic
    daCommunity: port('communityPort', 9033),
    daView: port('viewServerPort', 9083),
    daContent: port('passageContentPort', 9103),

    // Answer Server / QMS / Stats
    answerServer: port('answerServerPort', 12000),
    answerBank: port('answerBankAgentPort', 12200),
    passageAgent: port('passageAgentPort', 12310),
    qms: port('qmsPort', 16000),
    qmsAgent: port('qmsAgentPort', 20050),
    stats: port('statsServerPort', 19870),

    // Rich Media
    rmMedia: port('rmMediaServerPort', 14000),
    rmPlaylist: port('rmMediaServerPlaylistPort', 24000),

    // UIs & Proxies
    findBaUi: port('find-ba-Ui', 8440),
    findDaUi: port('find-da-Ui', 8441),
    dataAdminUi: port('dataAdminHttpsUiPort', 8444),
    mediaServerUi: port('mediaServerHttpUiPort', 8003),
    httpdBasic: port('basicIdolHttpdPort', 8330),

    // External
    ollama: 8888,
    llmWiki: 3001,
    ldap: 7777,
    harborDocker: 5443,
    harborMinikube: 30003,
    connector: 11000
  };

  // === HELPERS ===
  function setLink(linkId, url, copyId) {
    try {
      const a = document.getElementById(linkId);
      if (!a) return;
      a.href = url;
      a.textContent = url + ' ';
      const icon = document.createElement('i');
      icon.className = 'fas fa-external-link-alt';
      icon.style.fontSize = '10px';
      a.appendChild(icon);

      const btn = copyId ? document.getElementById(copyId) : a.closest('.row')?.querySelector('.copy-btn');
      if (btn) btn.setAttribute('data-copy', url);
    } catch (err) {
      console.error(`[updateInfoSectionUrls] setLink(${linkId}) failed:`, err);
    }
  }

  function setText(textId, value, copyId) {
    try {
      const el = document.getElementById(textId);
      if (el) el.textContent = value;
      const btn = document.getElementById(copyId);
      if (btn) btn.setAttribute('data-copy', value);
    } catch (err) {
      console.error(`[updateInfoSectionUrls] setText(${textId}) failed:`, err);
    }
  }

  // ====================== MAIN SERVICE LINKS ======================
  // NiFi
  setLink('dyn-nifi-card-link', `https://${HOST}:${p.nifi}/nifi`, 'dyn-nifi-card-copy');
  setLink('dyn-nifi-link', `https://${HOST}:${p.nifi}`, 'dyn-nifi-copy');
  setLink('dyn-nifi-registry-link', `http://${HOST}:${p.nifiRegistry}/nifi-registry`, 'dyn-nifi-registry-copy');
  
  // Basic IDOL
  setLink('dyn-category-link', `https://${HOST}:${p.biCategory}/a=admin`, 'dyn-category-copy');
  setLink('dyn-community-link', `https://${HOST}:${p.biCommunity}/a=admin`, 'dyn-community-copy');
  setLink('dyn-content-link', `https://${HOST}:${p.biContent}/a=admin`, 'dyn-content-copy');
  setLink('dyn-agentstore-link', `https://${HOST}:${p.biAgentStore}/a=admin`, 'dyn-agentstore-copy');
  setLink('dyn-catagentstore-link', `https://${HOST}:${p.biCatAgentStore}/a=admin`, 'dyn-catagentstore-copy');
  setLink('dyn-view-link', `https://${HOST}:${p.biView}/a=admin`, 'dyn-view-copy');

  // Data Admin Classic
  setLink('dyn-da-community-link', `https://${HOST}:${p.daCommunity}/a=admin`, 'dyn-da-community-copy');
  setLink('dyn-da-view-link', `https://${HOST}:${p.daView}/a=admin`, 'dyn-da-view-copy');
  setLink('dyn-da-content-link', `https://${HOST}:${p.daContent}/a=admin`, 'dyn-da-content-copy');

  // REST GetStatus links
  setLink('dyn-rest-comm-status', `https://${HOST}:${p.daCommunity}/action=GetStatus`, 'dyn-rest-comm-status-copy');
  setLink('dyn-rest-cont-status', `https://${HOST}:${p.daContent}/action=GetStatus`, 'dyn-rest-cont-status-copy');
  setLink('dyn-rest-bi-comm-status', `https://${HOST}:${p.biCommunity}/action=GetStatus`, 'dyn-rest-bi-comm-status-copy');
  setLink('dyn-rest-comm-status-hk', `https://${HOST}:${p.daCommunity}/action=GetStatus`, 'dyn-rest-comm-status-hk-copy');
  setLink('dyn-rest-cont-status-hk', `https://${HOST}:${p.daContent}/action=GetStatus`, 'dyn-rest-cont-status-hk-copy');
  setLink('dyn-rest-agent-status', `https://${HOST}:${p.biAgentStore}/action=GetStatus`, 'dyn-rest-agent-status-copy');

  // Answer Server / QMS / Stats
  setLink('dyn-answerserver-link', `https://${HOST}:${p.answerServer}/a=admin`, 'dyn-answerserver-copy');
  setLink('dyn-answerbank-link', `https://${HOST}:${p.answerBank}/a=admin`, 'dyn-answerbank-copy');
  setLink('dyn-passageagent-link', `https://${HOST}:${p.passageAgent}/a=admin`, 'dyn-passageagent-copy');
  setLink('dyn-qms-link', `https://${HOST}:${p.qms}/a=admin`, 'dyn-qms-copy');
  setLink('dyn-qmsagent-link', `https://${HOST}:${p.qmsAgent}/a=admin`, 'dyn-qmsagent-copy');
  setLink('dyn-stats-link', `https://${HOST}:${p.stats}/a=admin`, 'dyn-stats-copy');

  // Rich Media
  setLink('dyn-rm-media-admin-link', `https://${HOST}:${p.rmMedia}/a=admin`, 'dyn-rm-media-admin-copy');
  setLink('dyn-rm-playlist-admin-link', `https://${HOST}:${p.rmPlaylist}/a=admin`, 'dyn-rm-playlist-admin-copy');
  setLink('dyn-rm-playlist-link', `https://${HOST}:${p.rmPlaylist}`, 'dyn-rm-playlist-copy');
  setLink('dyn-rm-media-app-link', `http://${HOST}:${p.mediaServerUi}`, 'dyn-rm-media-app-copy');
  setLink('dyn-rm-mediaserver-gui-link', `https://${HOST}:${p.rmMedia}/a=gui`, 'dyn-rm-mediaserver-gui-copy');

  // IDOL UIs & Proxies
  setLink('dyn-find-ba-link', `https://${HOST}:${p.findBaUi}`, 'dyn-find-ba-copy');
  setLink('dyn-find-da-link', `https://${HOST}:${p.findDaUi}`, 'dyn-find-da-copy');
  setLink('dyn-dataadmin-link', `https://${HOST}:${p.dataAdminUi}`, 'dyn-dataadmin-copy');
  setLink('dyn-httpd-basic-link', `https://${HOST}:${p.httpdBasic}`, 'dyn-httpd-basic-copy');
  setLink('dyn-httpd-dataadmin-link', `https://${HOST}:${p.httpdDataAdmin}`, 'dyn-httpd-dataadmin-copy');
  setLink('dyn-httpd-richmedia-link', `https://${HOST}:${p.httpdRichMedia}`, 'dyn-httpd-richmedia-copy');

  // External Tools
  setLink('dyn-ollama-link', `http://${HOST}:${p.ollama}`, 'dyn-ollama-copy');
  setLink('dyn-llmwiki-link', `https://${HOST}:${p.llmWiki}`, 'dyn-llmwiki-copy');
  setLink('dyn-ldap-link', `http://${HOST}:${p.ldap}`, 'dyn-ldap-copy');
  setLink('dyn-harbor-docker-link', `https://${HOST}:${p.harborDocker}`, 'dyn-harbor-docker-copy');
  setLink('dyn-harbor-minikube-link', `https://${HOST}:${p.harborMinikube}`, 'dyn-harbor-minikube-copy');

  // Connector
  setLink('dyn-connector-version-link', `https://${HOST}:${p.connector}/action=GetVersion`, 'dyn-connector-version-copy');
  setLink('dyn-connector-status-link', `https://${HOST}:${p.connector}/action=GetStatus`, 'dyn-connector-status-copy');

  // ====================== GRL LINKS (THE FIX) ======================
  const grlMap = {
    'category-bi':       { proto: 'https', portKey: 'biCategory',      path: '/a=grl' },
    'community-bi':      { proto: 'https', portKey: 'biCommunity',     path: '/a=grl' },
    'content-bi':        { proto: 'https', portKey: 'biContent',       path: '/a=grl' },
    'agentstore-bi':     { proto: 'https', portKey: 'biAgentStore',    path: '/a=grl' },
    'catagentstore-bi':  { proto: 'https', portKey: 'biCatAgentStore', path: '/a=grl' },
    'view-bi':           { proto: 'https', portKey: 'biView',          path: '/a=grl' },

    'community-da':      { proto: 'https', portKey: 'daCommunity',     path: '/a=grl' },
    'viewserver-da':     { proto: 'https', portKey: 'daView',          path: '/a=grl' },
    'passagecontent-da': { proto: 'https', portKey: 'daContent',       path: '/a=grl' },

    'answerserver':      { proto: 'https', portKey: 'answerServer',    path: '/a=grl' },
    'answerbank':        { proto: 'https', portKey: 'answerBank',      path: '/a=grl' },
    'passageagent':      { proto: 'https', portKey: 'passageAgent',    path: '/a=grl' },
    'qms':               { proto: 'https', portKey: 'qms',             path: '/a=grl' },
    'qmsagent':          { proto: 'https', portKey: 'qmsAgent',        path: '/a=grl' },
    'stats':             { proto: 'https', portKey: 'stats',           path: '/a=grl' },

    'media-rm':          { proto: 'https', portKey: 'rmMedia',         path: '/a=grl' },
    'playlist-rm':       { proto: 'https', portKey: 'rmPlaylist',      path: '/a=grl' }
  };

  Object.entries(grlMap).forEach(([key, cfg]) => {
    const portNum = p[cfg.portKey];
    if (!portNum) return;

    const url = `${cfg.proto}://${HOST}:${portNum}${cfg.path}`;

    document.querySelectorAll(`[data-grl="${key}"]`).forEach(el => {
      if (el.tagName === 'A') {
        el.href = url;
        el.textContent = url + ' ';
        const icon = document.createElement('i');
        icon.className = 'fas fa-external-link-alt';
        icon.style.fontSize = '10px';
        el.appendChild(icon);
      }
      // Also update copy buttons
      if (el.classList.contains('copy-btn') || el.hasAttribute('data-copy')) {
        el.setAttribute('data-copy', url);
      }
    });
  });

  // Curl command examples in Housekeeping section
  setText('dyn-rest-comm-admin-text', `curl http://idol-community:${p.daCommunity}/a=admin`, 'dyn-rest-comm-admin-copy');
  setText('dyn-rest-cont-admin-text', `curl http://idol-content:${p.daContent}/a=admin`, 'dyn-rest-cont-admin-copy');
  setText('dyn-rest-agent-admin-text', `curl http://idol-agentstore:${p.biAgentStore}/a=admin`, 'dyn-rest-agent-admin-copy');

  highlightExtraIpSansDiff();

  console.log('%c✅ updateInfoSectionUrls() — all links & GRLs updated', 'color:#10b981;font-weight:600');
}

function initInformationUrls() {
  const fqdnInput = document.getElementById('fqdn');
  if (fqdnInput) {
    fqdnInput.addEventListener('input', () => updateInfoSectionUrls());
  }
  updateInfoSectionUrls();
}

/* ====================== 14. IMPORT / EXPORT CONFIG ====================== */
function exportAllFieldsToJson() {
  try {
    const config = {
      exportVersion: '1.0',
      exportDate: new Date().toISOString(),
      formFields: {},
      deploymentTypes: {},
      llmModelSelections: [],
      llmSelectedQuants: {},
      githubIntegration: {},
      licenseMode: null,
      nifiPreserve: null,
      registryPreserve: null,
      connectorNarImport: null,
      idolPreserve: null,
      bypassPortCheck: false
    };

    const fieldIds = [
      'fqdn', 'basePath', 'basic-idol-version',
      'hostIp', 'guestIp', 'extraIpSans',
      'nifiDeployment', 'githubUsername', 'githubToken', 'githubRepo',
      'nifiDataPath', 'registryPath', 'connectorNarPath',
      'licenseHostname', 'licenseEmail', 'licenseMac', 'dockerLicenseToken',
      'licenseServerPath', 'licenseKeyPath', 'licenseUrl',
      'preservePath', 'storagePath',
      'llmModelPath', 'nifiMediaServerPath', 'pretrainedModelsPath', 'hfToken', 'llmAPIKey',
      'nifiPort', 'findUiPortBaseIdol', 'findUiPortDataAdmin', 'dataAdminHttpsUiPort', 'mediaServerHttpUiPort',
      'dataAdminInternalUiPort', 'basicIdolHttpdPort', 'dataAdminHttpdPort',
      'richMediaHttpdPort',
      'biContentPort', 'biAgentStorePort', 'biCategoryPort',
      'biCatAgentStorePort', 'biCommunityPort', 'biViewPort',
      'communityPort', 'viewServerPort', 'passageContentPort',
      'answerServerPort', 'answerBankAgentPort', 'passageAgentPort',
      'qmsPort', 'qmsAgentPort', 'statsServerPort',
      'rmMediaServerPort', 'rmMediaServerPlaylistPort'
    ];

    fieldIds.forEach(id => {
      const element = document.getElementById(id);
      if (element) config.formFields[id] = element.value;
    });

    config.deploymentTypes = {
      basicIdol: document.getElementById('deployTypeBasic')?.checked || false,
      dataAdmin: document.getElementById('deployTypeDataAdmin')?.checked || false,
      richMedia: document.getElementById('deployTypeRichMedia')?.checked || false
    };

    const dataAdminVersion = document.getElementById('data-admin-version');
    if (dataAdminVersion) config.formFields['data-admin-version'] = dataAdminVersion.value;
    const richMediaVersion = document.getElementById('rich-media-version');
    if (richMediaVersion) config.formFields['rich-media-version'] = richMediaVersion.value;

    const toggleIds = [
      'llmIntegrationToggle',
      'llmWikiEnableToggle',
      'gpuEnableToggle',
      'pretrainedModelsToggle',
      'hostToggleSwitch'
    ];
    toggleIds.forEach(id => {
      const element = document.getElementById(id);
      if (element) config.formFields[id] = element.checked;
    });

    // NEW: Capture the EFFECTIVE host name value controlled by #hostToggleSwitch
    // (this is what all dynamic links in the INFORMATION section actually use)
    const hostToggle = document.getElementById('hostToggleSwitch');
    const fqdnField = document.getElementById('fqdn');
    let effectiveHost = 'idol-docker-host';
    
    if (hostToggle?.checked && fqdnField?.value?.trim()) {
      effectiveHost = fqdnField.value.trim();
    }
    
    config.formFields.effectiveHost = effectiveHost;

    const githubRadio = document.querySelector('input[name="githubIntegration"]:checked');
    if (githubRadio) config.githubIntegration.enabled = githubRadio.value === 'TRUE';
    const nifiPreserveRadio = document.querySelector('input[name="nifiPreserve"]:checked');
    if (nifiPreserveRadio) config.nifiPreserve = nifiPreserveRadio.value === 'TRUE';
    const registryPreserveRadio = document.querySelector('input[name="registryPreserve"]:checked');
    if (registryPreserveRadio) config.registryPreserve = registryPreserveRadio.value === 'TRUE';
    const connectorNarRadio = document.querySelector('input[name="connectorNarImport"]:checked');
    if (connectorNarRadio) config.connectorNarImport = connectorNarRadio.value === 'TRUE';
    const idolPreserveRadio = document.querySelector('input[name="preserve"]:checked');
    if (idolPreserveRadio) config.idolPreserve = idolPreserveRadio.value === 'TRUE';
    const licenseModeRadio = document.querySelector('input[name="licenseMode"]:checked');
    if (licenseModeRadio) config.licenseMode = licenseModeRadio.value;
    const bypassToggle = document.getElementById('bypassPortCheckToggle');
    if (bypassToggle) config.bypassPortCheck = bypassToggle.checked;

    config.llmSelectedQuants = collectLlmSelectionsFromDom();
    config.llmModelSelections = collectSelectedModelsList();

    const llmModelPathWarning = document.getElementById('llmModelPathWarning');
    if (llmModelPathWarning) config.llmModelPathValid = llmModelPathWarning.style.display !== 'block';

    const jsonStr = JSON.stringify(config, null, 2);
    const blob = new Blob([jsonStr], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `idol-config-${new Date().toISOString().slice(0,19).replace(/:/g, '-')}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    
    showToast('Configuration exported successfully!');
  } catch (error) {
    console.error('Export failed:', error);
    showToast('Export failed: ' + error.message, true);
  }
}

function collectLlmSelectionsFromDom() {
  const selections = {};
  const modelCards = document.querySelectorAll('.llm-model-card, [data-model-id]');
  modelCards.forEach(card => {
    const modelId = card.getAttribute('data-model-id') || 
                    card.querySelector('.model-name')?.getAttribute('data-id') ||
                    card.id?.replace('model-', '');
    if (modelId) {
      const selectedQuants = [];
      const quantCheckboxes = card.querySelectorAll('input[type="checkbox"][data-quant]');
      quantCheckboxes.forEach(cb => {
        if (cb.checked) selectedQuants.push(cb.value || cb.getAttribute('data-quant'));
      });
      if (selectedQuants.length > 0) selections[modelId] = selectedQuants;
    }
  });
  return selections;
}

function collectSelectedModelsList() {
  const selectedModels = [];
  const checkboxes = document.querySelectorAll('#llmGridSupported input[type="checkbox"].model-select, #llmGridCustom input[type="checkbox"].model-select');
  checkboxes.forEach(cb => {
    if (cb.checked && cb.value) selectedModels.push(cb.value);
  });
  return selectedModels;
}

function importAllFieldsFromJson(file) {
  const reader = new FileReader();
  reader.onload = function(e) {
    try {
      const config = JSON.parse(e.target.result);
      
      if (!config.formFields) throw new Error('Invalid configuration file: missing formFields');
      
      for (const [id, value] of Object.entries(config.formFields)) {
        const element = document.getElementById(id);
        if (element) {
          if (element.type === 'checkbox') {
            element.checked = value === true || value === 'true';
            element.dispatchEvent(new Event('change', { bubbles: true }));
            element.dispatchEvent(new Event('input', { bubbles: true }));
          } else {
            element.value = value;
            element.dispatchEvent(new Event('input', { bubbles: true }));
            element.dispatchEvent(new Event('change', { bubbles: true }));
          }
        }
      }
      
      if (config.deploymentTypes) {
        const basicCheckbox = document.getElementById('deployTypeBasic');
        const dataAdminCheckbox = document.getElementById('deployTypeDataAdmin');
        const richMediaCheckbox = document.getElementById('deployTypeRichMedia');
        
        if (basicCheckbox) basicCheckbox.checked = config.deploymentTypes.basicIdol || false;
        if (dataAdminCheckbox) dataAdminCheckbox.checked = config.deploymentTypes.dataAdmin || false;
        if (richMediaCheckbox) richMediaCheckbox.checked = config.deploymentTypes.richMedia || false;
      }
      
      if (config.formFields['data-admin-version']) {
        const daVersion = document.getElementById('data-admin-version');
        if (daVersion) daVersion.value = config.formFields['data-admin-version'];
      }
      if (config.formFields['rich-media-version']) {
        const rmVersion = document.getElementById('rich-media-version');
        if (rmVersion) rmVersion.value = config.formFields['rich-media-version'];
      }
      
      // Updated toggle list — now includes hostToggleSwitch
      const toggleIds = [
        'llmIntegrationToggle',
        'llmWikiEnableToggle',
        'gpuEnableToggle',
        'pretrainedModelsToggle',
        'hostToggleSwitch'
      ];
      toggleIds.forEach(id => {
        const element = document.getElementById(id);
        if (element && typeof config.formFields[id] !== 'undefined') {
          element.checked = config.formFields[id] === true || config.formFields[id] === 'true';
          element.dispatchEvent(new Event('change', { bubbles: true }));
        }
      });
      
      // NEW: Restore effectiveHost logic (ensures the exact hostname used in dynamic links matches export)
      if (config.formFields && typeof config.formFields.effectiveHost !== 'undefined') {
        const hostToggle = document.getElementById('hostToggleSwitch');
        const fqdnField = document.getElementById('fqdn');
        
        if (hostToggle && fqdnField) {
          const exportedHost = String(config.formFields.effectiveHost).trim();
          
          if (exportedHost === 'idol-docker-host') {
            hostToggle.checked = false;
          } else {
            hostToggle.checked = true;
            // Enforce the exact FQDN that was used at export time
            fqdnField.value = exportedHost;
          }
          
          // Trigger events so updateDynamicLinks() and any dependent logic see the correct host
          hostToggle.dispatchEvent(new Event('change', { bubbles: true }));
          fqdnField.dispatchEvent(new Event('input', { bubbles: true }));
          fqdnField.dispatchEvent(new Event('change', { bubbles: true }));
        }
      }
      
      if (typeof config.githubIntegration?.enabled !== 'undefined') {
        const githubYes = document.getElementById('github-yes');
        const githubNo = document.getElementById('github-no');
        if (config.githubIntegration.enabled) githubYes?.click(); else githubNo?.click();
      }
      if (typeof config.nifiPreserve !== 'undefined') {
        const preserveYes = document.getElementById('nifi-preserve-yes');
        const preserveNo = document.getElementById('nifi-preserve-no');
        if (config.nifiPreserve) preserveYes?.click(); else preserveNo?.click();
      }
      if (typeof config.registryPreserve !== 'undefined') {
        const regYes = document.getElementById('registry-preserve-yes');
        const regNo = document.getElementById('registry-preserve-no');
        if (config.registryPreserve) regYes?.click(); else regNo?.click();
      }
      if (typeof config.connectorNarImport !== 'undefined') {
        const narYes = document.getElementById('connectorNar-yes');
        const narNo = document.getElementById('connectorNar-no');
        if (config.connectorNarImport) narYes?.click(); else narNo?.click();
      }
      if (typeof config.idolPreserve !== 'undefined') {
        const idolYes = document.getElementById('preserve-yes');
        const idolNo = document.getElementById('preserve-no');
        if (config.idolPreserve) idolYes?.click(); else idolNo?.click();
      }
      if (config.licenseMode) {
        const modeNew = document.getElementById('license-new');
        const modeExisting = document.getElementById('license-existing');
        if (config.licenseMode === 'NEW') modeNew?.click(); else if (config.licenseMode === 'EXISTING') modeExisting?.click();
      }
      const bypassToggle = document.getElementById('bypassPortCheckToggle');
      if (bypassToggle && typeof config.bypassPortCheck !== 'undefined') {
        bypassToggle.checked = config.bypassPortCheck;
        if (typeof portsToggleBypass === 'function') portsToggleBypass();
      }
      
      const pretrainedToggle = document.getElementById('pretrainedModelsToggle');
      if (pretrainedToggle && pretrainedToggle.checked) {
        const pathGroup = document.getElementById('pretrainedModelsPathGroup');
        if (pathGroup) pathGroup.style.display = 'block';
      }
      
      if (config.llmSelectedQuants && Object.keys(config.llmSelectedQuants).length > 0) {
        restoreLlmSelections(config.llmSelectedQuants);
      }
      
      updateAllDependentUi();
      
      if (typeof portsOnInput === 'function') portsOnInput();
      
      if (typeof updateDynamicLinks === 'function') updateDynamicLinks();
      if (typeof populateDerivedPaths === 'function') populateDerivedPaths();
      if (typeof updateStoragePathHint === 'function') {
        const storagePath = document.getElementById('storagePath');
        if (storagePath) updateStoragePathHint(storagePath.value);
      }
      
      if (typeof validateAllSections === 'function') validateAllSections();
      
      showToast('Configuration imported successfully!');
      
    } catch (error) {
      console.error('Import failed:', error);
      showToast('Import failed: ' + error.message, true);
    }
  };
  reader.onerror = function() {
    showToast('Error reading file', 'error');
  };
  reader.readAsText(file);
}

function restoreLlmSelections(selectionsMap) {
  setTimeout(() => {
    for (const [modelId, quants] of Object.entries(selectionsMap)) {
      const modelContainer = document.querySelector(`[data-model-id="${modelId}"]`) ||
                            document.getElementById(`model-${modelId}`) ||
                            document.querySelector(`.llm-model-card:has(.model-name[data-id="${modelId}"])`);
      
      if (modelContainer) {
        const modelCheckbox = modelContainer.querySelector('input[type="checkbox"].model-select, input[type="checkbox"].select-model');
        if (modelCheckbox && !modelCheckbox.checked) {
          modelCheckbox.checked = true;
          modelCheckbox.dispatchEvent(new Event('change', { bubbles: true }));
        }
        
        for (const quant of quants) {
          const quantCb = modelContainer.querySelector(`input[type="checkbox"][data-quant="${quant}"], input[type="checkbox"][value="${quant}"]`);
          if (quantCb && !quantCb.checked) {
            quantCb.checked = true;
            quantCb.dispatchEvent(new Event('change', { bubbles: true }));
          }
        }
      }
    }
    
    if (typeof llmUpdateSummary === 'function') llmUpdateSummary();
    else if (typeof refreshLlmSummary === 'function') refreshLlmSummary();
    else if (typeof llmRefreshSelectedList === 'function') llmRefreshSelectedList();
  }, 100);
}

function updateAllDependentUi() {
  const githubRadio = document.querySelector('input[name="githubIntegration"]:checked');
  const githubGroup = document.getElementById('githubIntegrationGroup');
  if (githubGroup && githubRadio) githubGroup.style.display = githubRadio.value === 'TRUE' ? 'block' : 'none';
  
  const licenseModeRadio = document.querySelector('input[name="licenseMode"]:checked');
  const existingGroup = document.getElementById('licenseExistingGroup');
  if (existingGroup && licenseModeRadio) existingGroup.style.display = licenseModeRadio.value === 'EXISTING' ? 'block' : 'none';
  
  const nifiPreserveYes = document.getElementById('nifi-preserve-yes');
  const nifiPathGroup = document.getElementById('nifiDataPathGroup');
  if (nifiPathGroup && nifiPreserveYes) nifiPathGroup.style.display = nifiPreserveYes.checked ? 'block' : 'none';
  
  const registryPreserveYes = document.getElementById('registry-preserve-yes');
  const registryPathGroup = document.getElementById('registryPathGroup');
  if (registryPathGroup && registryPreserveYes) registryPathGroup.style.display = registryPreserveYes.checked ? 'block' : 'none';

  const connectorNarYes = document.getElementById('connectorNar-yes');
  const connectorNarPathGroup = document.getElementById('connectorNarPathGroup');
  if (connectorNarPathGroup && connectorNarYes) connectorNarPathGroup.style.display = connectorNarYes.checked ? 'block' : 'none';
  
  const idolPreserveYes = document.getElementById('preserve-yes');
  const idolPathGroup = document.getElementById('preservePathGroup');
  if (idolPathGroup && idolPreserveYes) idolPathGroup.style.display = idolPreserveYes.checked ? 'block' : 'none';
  
  const llmToggle = document.getElementById('llmIntegrationToggle');
  const llmSelectionRow = document.getElementById('llmModelSelectionRow');
  if (llmSelectionRow && llmToggle) llmSelectionRow.style.display = llmToggle.checked ? 'block' : 'none';
  
  const dataAdminChecked = document.getElementById('deployTypeDataAdmin')?.checked;
  const daRow = document.getElementById('dataAdminFeatureRow');
  if (daRow) daRow.style.display = dataAdminChecked ? 'block' : 'none';
  
  const richMediaChecked = document.getElementById('deployTypeRichMedia')?.checked;
  const rmRow = document.getElementById('richMediaFeatureRow');
  if (rmRow) rmRow.style.display = richMediaChecked ? 'block' : 'none';
  
  if (typeof updatePortRangeDisplays === 'function') updatePortRangeDisplays();
}

function triggerImportFilePicker() {
  const fileInput = document.getElementById('importFileInput');
  if (fileInput) fileInput.click();
}

function setupImportExportHandlers() {
  const exportBtn = document.getElementById('globalExportBtn');
  const importBtn = document.getElementById('globalImportBtn');
  const fileInput = document.getElementById('importFileInput');
  
  if (exportBtn) exportBtn.addEventListener('click', exportAllFieldsToJson);
  if (importBtn) importBtn.addEventListener('click', triggerImportFilePicker);
  
  if (fileInput) {
    fileInput.addEventListener('change', function(e) {
      if (this.files && this.files[0]) {
        importAllFieldsFromJson(this.files[0]);
        this.value = '';
      }
    });
  }
}

/* ====================== 15. RICH MEDIA AUTO-DETECTION ====================== */
function togglePretrainedModels() {
  const toggle = document.getElementById('pretrainedModelsToggle');
  const group = document.getElementById('pretrainedModelsPathGroup');
  if (group) group.style.display = toggle.checked ? 'block' : 'none';
  setupIdolValidateSection('basic');
}

function updateAllPathPreviews() {
  const baseInput = document.getElementById('sharedFolderBasePath').value.trim();
  const base   = baseInput || '~/idol-docker-setup/shared-folder';
  const prefix = base.endsWith('/') ? base : base + '/';
  document.getElementById('nifiMediaServerBasePrefix').textContent    = prefix + 'richmedia-packages';
  document.getElementById('pretrainedModelsBasePrefix').textContent   = prefix + 'richmedia-packages';
}

function onBasePathChange() {
  updateRichMediaBasePathFromBase();
  updateAllPathPreviews();
  setupIdolValidateSection('basic'); 
}

async function performAutoDetect(button, basePath, regexTerm, targetInputId, warningId) {
  const originalHTML = button.innerHTML;
  const targetInput = document.getElementById(targetInputId);
  const warningEl = document.getElementById(warningId);
  
  if (!targetInput) {
    console.error(`Target input "${targetInputId}" not found`);
    button.disabled = false;
    button.innerHTML = originalHTML;
    return;
  }

  targetInput.classList.remove('detection-success', 'detection-failure');
  
  button.disabled = true;
  button.innerHTML = `<i class="fas fa-spinner fa-spin"></i> Detecting...`;
  if (warningEl) warningEl.style.display = 'none';

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 15000);

  try {
    const response = await fetch('/api/detect-folder', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ basePath: basePath, contains: regexTerm }),
      signal: controller.signal
    });
    clearTimeout(timeoutId);

    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    const data = await response.json();

    if (data.success && data.folder) {
      targetInput.value = data.folder;
      targetInput.classList.add('detection-success');
      if (warningEl) warningEl.style.display = 'none';
      if (typeof checkBasicNextButton === 'function') checkBasicNextButton();
      showToast(`✅ Detected: ${data.folder}`);
    } else {
      const reason = data.message || data.error || `No folder containing "${regexTerm}" found`;
      if (warningEl) {
        warningEl.innerHTML = `${reason} in <code>${basePath}</code>.<br>Make sure the folder exists and the backend has read permission.`;
        warningEl.style.display = 'block';
      }
      targetInput.classList.add('detection-failure');
      showToast(`Detection failed: ${reason}`, true);
    }
  } catch (err) {
    clearTimeout(timeoutId);
    console.error('[AutoDetect] Error:', err);
    let errorMsg = err.message;
    if (err.name === 'AbortError') errorMsg = 'Request timed out after 15 seconds. The server may be slow or unreachable.';
    if (warningEl) {
      warningEl.innerHTML = `❌ ${errorMsg}<br>Check server and network.`;
      warningEl.style.display = 'block';
    }
    targetInput.classList.add('detection-failure');
    showToast(`Detection failed — ${errorMsg}`, true);
  } finally {
    button.disabled = false;
    button.innerHTML = originalHTML;
    if (typeof setupIdolValidateSection === 'function') setupIdolValidateSection('basic');
  }
}

function autoDetectNiFiMediaServer(btn) {
  const basePath = '/rich-media-software';
  performAutoDetect(btn, basePath, 'NiFiPolicy', 'nifiMediaServerPath', 'nifiMediaServerPathWarning');
}

function autoDetectPretrainedModels(btn) {
  const basePath = '/rich-media-software';
  performAutoDetect(btn, basePath, 'MediaServerPretrainedModels', 'pretrainedModelsPath', 'pretrainedModelsPathWarning');
}

async function runAutoDetectionOnLoad() {
  const nifiInput = document.getElementById('nifiMediaServerPath');
  const pretrainedInput = document.getElementById('pretrainedModelsPath');
  
  if (!nifiInput || !pretrainedInput) return;

  const basePath = '/rich-media-software';
  
  async function detect(fieldId, regexTerm, warningId) {
    const targetInput = document.getElementById(fieldId);
    const warningEl = document.getElementById(warningId);
    if (!targetInput) return;

    targetInput.classList.remove('detection-success', 'detection-failure');
    if (warningEl) warningEl.style.display = 'none';

    try {
      const response = await fetch('/api/detect-folder', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ basePath, contains: regexTerm })
      });
      const data = await response.json();

      if (data.success && data.folder) {
        targetInput.value = data.folder;
        targetInput.classList.add('detection-success');
        if (warningEl) warningEl.style.display = 'none';
        console.log(`✅ Auto-detected ${regexTerm}: ${data.folder}`);
      } else {
        const reason = data.message || data.error || `No folder containing "${regexTerm}" found`;
        if (warningEl) {
          warningEl.innerHTML = `❌ ${reason} in <code>${basePath}</code>.`;
          warningEl.style.display = 'block';
        }
        targetInput.classList.add('detection-failure');
        console.warn(`⚠️ Auto-detection failed for ${regexTerm}: ${reason}`);
      }
    } catch (err) {
      console.error(`Auto-detection error for ${regexTerm}:`, err);
      if (warningEl) {
        warningEl.innerHTML = `❌ Request failed: ${err.message}`;
        warningEl.style.display = 'block';
      }
      targetInput.classList.add('detection-failure');
    }
  }

  if (typeof setupIdolValidateSection === 'function') setupIdolValidateSection('basic');

  await detect('nifiMediaServerPath', 'NiFiPolicy', 'nifiMediaServerPathWarning');
  await detect('pretrainedModelsPath', 'MediaServerPretrainedModels', 'pretrainedModelsPathWarning');
  
  if (typeof checkBasicNextButton === 'function') checkBasicNextButton();
}

async function loadDefaultRichMediaPath() {
  try {
    const response = await fetch('/api/rich-media/default');
    if (!response.ok) throw new Error('Failed to fetch default path');
    const data = await response.json();
    window.defaultDetectionBasePath = data.defaultPath || '/rich-media-software';
    console.log(`[Init] Detection base path set to: ${window.defaultDetectionBasePath}`);
  } catch (error) {
    console.error('[Init] Could not load default rich media path:', error);
    window.defaultDetectionBasePath = '/rich-media-software';
  }
}

/* ====================== 16. CARD & QUICK ACCESS HELPERS ====================== */
function toggle(head) {
  const card = head.closest('.card');
  if (!card) return;
  
  const body = card.querySelector('.card-body');
  const chevron = head.querySelector('.chevron');
  if (!body || !chevron) return;

  const isOpen = body.style.display !== 'none' && body.style.display !== '';

  body.style.display = isOpen 
    ? 'none' 
    : (body.dataset.display || 'block');

  chevron.classList.toggle('open', !isOpen);
}

function toggleAll(btn) {
  const bodies = document.querySelectorAll('#grid .card-body');
  const chevrons = document.querySelectorAll('#grid .chevron');
  
  const anyHidden = Array.from(bodies).some(b => 
    b.style.display === 'none' || b.style.display === ''
  );

  bodies.forEach(body => {
    body.style.display = anyHidden 
      ? (body.dataset.display || 'block') 
      : 'none';
  });

  chevrons.forEach(ch => ch.classList.toggle('open', anyHidden));

  btn.innerHTML = anyHidden
    ? '<i class="fas fa-compress-alt"></i> Collapse all'
    : '<i class="fas fa-expand-alt"></i> Expand all';
}

// Robust clipboard copy for the "Run in Ubuntu WSL" command snippets.
// navigator.clipboard requires a secure context (HTTPS or localhost) — this app
// is commonly opened over plain http://<ip>:5000 or http://idol-docker-host:5000,
// so we fall back to a hidden-textarea + execCommand('copy') when needed, and we
// always .catch() so a rejected promise doesn't fail silently.
function copyWslCommand(text) {
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text)
      .then(() => showToast('Command copied!'))
      .catch(() => copyWslCommandFallback(text));
  } else {
    copyWslCommandFallback(text);
  }
}

function copyWslCommandFallback(text) {
  try {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.cssText = 'position:fixed;opacity:0;top:0;left:0;';
    document.body.appendChild(ta);
    ta.focus();
    ta.select();
    const ok = document.execCommand('copy');
    document.body.removeChild(ta);
    showToast(ok ? 'Command copied!' : 'Copy failed — select & copy manually', !ok);
  } catch (e) {
    showToast('Copy failed — select & copy manually', true);
  }
}

function cp(text, btn) {
  const finish = (ok) => {
    if (btn) {
      if (ok) btn.classList.add('copied');
      setTimeout(() => btn.classList.remove('copied'), 1400);
    }
    showToast(ok ? 'Password copied!' : 'Copy failed — select & copy manually', !ok);
  };

  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text)
      .then(() => finish(true))
      .catch(() => copyViaExecCommand(text, finish));
  } else {
    copyViaExecCommand(text, finish);
  }
}

function copyViaExecCommand(text, finish) {
  try {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.cssText = 'position:fixed;opacity:0;top:0;left:0;';
    document.body.appendChild(ta);
    ta.focus();
    ta.select();
    const ok = document.execCommand('copy');
    document.body.removeChild(ta);
    finish(ok);
  } catch (_) {
    finish(false);
  }
}

function initQuickAccessCards() {
  const grid = document.getElementById('grid');
  if (!grid) return;

  grid.querySelectorAll('.card-body').forEach(body => {
    const card = body.closest('.card');
    
    if (card && card.style.gridColumn === '1 / -1') {
      body.dataset.display = 'grid';
      body.style.display = 'none';
    } 
    else {
      if (!body.dataset.display) body.dataset.display = 'block';
    }
  });

  console.log('✅ Quick Access cards initialized — Housekeeping starts collapsed');
}

function collapseAllCards() {
  document.querySelectorAll('.service-card-body').forEach(body => {
    body.style.display = 'none';
  });
  document.querySelectorAll('.service-card .chevron-btn i').forEach(icon => {
    icon.classList.remove('fa-chevron-down');
    icon.classList.add('fa-chevron-right');
  });
}

function initToggleAllServices() {
  const btn = document.getElementById('toggleAllServices');
  if (!btn) return;
  let expanded = false;
  btn.addEventListener('click', () => {
    expanded = !expanded;
    document.querySelectorAll('.service-card-body').forEach(body => {
      body.style.display = expanded ? 'block' : 'none';
    });
    document.querySelectorAll('.service-card .chevron-btn i').forEach(icon => {
      icon.classList.remove('fa-chevron-down', 'fa-chevron-right');
      icon.classList.add(expanded ? 'fa-chevron-down' : 'fa-chevron-right');
    });
    const span = btn.querySelector('.btn-text');
    if (span) span.textContent = expanded ? 'Collapse All' : 'Expand All';
  });
}

/* ====================== 17. PASSWORD MASKING & MISC ====================== */
const SENSITIVE_FIELD_IDS = ['dockerLicenseToken', 'githubToken', 'hfToken', 'llmAPIKey'];

function convertToMaskedTextField(id) {
  const el = document.getElementById(id);
  if (!el) return;
  el.type = 'text';
  el.classList.add('masked-input');
  el.setAttribute('autocomplete', 'off');
  el.setAttribute('spellcheck', 'false');
}

SENSITIVE_FIELD_IDS.forEach(convertToMaskedTextField);

const maskStyle = document.createElement('style');
maskStyle.textContent = `
  .masked-input { -webkit-text-security: disc; letter-spacing: 0.1em; }
  .masked-input.revealed { -webkit-text-security: none; letter-spacing: normal; }
`;
document.head.appendChild(maskStyle);

document.getElementById('showLicenseToken')?.addEventListener('change', e => {
  document.getElementById('dockerLicenseToken')?.classList.toggle('revealed', e.target.checked);
});

document.getElementById('showGithubToken')?.addEventListener('change', e => {
  document.getElementById('githubToken')?.classList.toggle('revealed', e.target.checked);
});

/* ====================== 18. MAIN INITIALIZATION ====================== */
document.addEventListener('DOMContentLoaded', async () => {
  // ====================== INITIAL CLEANUP ======================
  ['idol_githubUsername', 'idol_githubToken', 'idol_githubRepo'].forEach(k => { 
    try { localStorage.removeItem(k); } catch(e){} 
  });

  document.getElementById('currentDate').textContent = new Date().toISOString().split('T')[0];

  // ====================== INFORMATION SECTION COPY BUTTONS ======================
  // Populate data-copy values FIRST, before any awaited network calls below.
  // If a later step throws (a server request fails/hangs on a non-localhost
  // deployment, a missing element, etc.), the whole async DOMContentLoaded
  // callback stops — but because this runs early, the Information section's
  // copy buttons are already wired up and unaffected by that failure.
  // (updateInfoSectionUrls() is still called again later via
  // initInformationUrls() once the FQDN/host inputs exist.)
  try {
    updateInfoSectionUrls();
  } catch (err) {
    console.error('[Init] Early updateInfoSectionUrls() failed:', err);
  }

  // ====================== NAVIGATION & GLOBAL LISTENERS ======================
  document.querySelectorAll('.nav-item[data-section]').forEach(item => 
    item.addEventListener('click', () => setupIdolNavigateToSection(item.dataset.section))
  );

  document.getElementById('toggleAllServices')?.addEventListener('click', () => {
    const cards = document.querySelectorAll('.service-card');
    const anyExpanded = [...cards].some(c => c.classList.contains('expanded'));
    cards.forEach(c => c.classList.toggle('expanded', !anyExpanded));
    const txt = document.querySelector('#toggleAllServices .btn-text');
    const ico = document.querySelector('#toggleAllServices i');
    if (txt) txt.textContent = anyExpanded ? 'Collapse All' : 'Expand All';
    if (ico) ico.className = anyExpanded ? 'fas fa-expand-alt' : 'fas fa-compress-alt';
  });

  // Global copy button handler — works on localhost AND plain http://IP:5000
  document.addEventListener('click', e => {
    const btn = e.target.closest('[data-copy]');
    if (!btn) return;
    const text = btn.dataset.copy;
    if (!text) {
      console.warn('[copy-btn] Clicked but data-copy is empty — updateInfoSectionUrls() may not have run yet.', btn);
      showToast('Nothing to copy yet — try refreshing the page', true);
      return;
    }

    e.preventDefault();

    const finish = (ok) => {
      btn.classList.toggle('copied', ok);
      setTimeout(() => btn.classList.remove('copied'), 1400);
      showToast(ok ? 'Copied!' : 'Copy failed — select & copy manually', !ok);
    };

    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text)
        .then(() => finish(true))
        .catch(() => copyViaExecCommand(text, finish));
    } else {
      copyViaExecCommand(text, finish);
    }
  });

  document.getElementById('deployTypeRichMedia').addEventListener('change', checkBasicNextButton);

  // ====================== MASKED INPUT STYLING ======================
  const maskStyle2 = document.createElement('style');
  maskStyle2.textContent = `
    .masked-input { -webkit-text-security: disc; letter-spacing: 0.1em; }
    .masked-input.revealed { -webkit-text-security: none; letter-spacing: normal; }
  `;
  document.head.appendChild(maskStyle2);

  ['dockerLicenseToken', 'githubToken'].forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.type = 'text';
    el.classList.add('masked-input');
    el.setAttribute('autocomplete', 'off');
    el.setAttribute('spellcheck', 'false');
  });

  document.getElementById('showLicenseToken')?.addEventListener('change', e => {
    document.getElementById('dockerLicenseToken')?.classList.toggle('revealed', e.target.checked);
  });
  document.getElementById('showGithubToken')?.addEventListener('change', e => {
    document.getElementById('githubToken')?.classList.toggle('revealed', e.target.checked);
  });

  // ====================== PORTS & BASIC SETUP ======================
  const checkPortsBtn = document.getElementById('checkPortsBtn');
  if (checkPortsBtn) checkPortsBtn.classList.add('btn-primary');

  ALL_PORTS.forEach(({ id }) => {
    const el = document.getElementById(id);
    if (el) el.setAttribute('autocomplete', 'off');
  });

  // ====================== FORM INPUT LISTENERS ======================
  document.querySelectorAll('input[type="text"],input[type="email"],input[type="number"],input[type="password"]').forEach(el => {
    el.addEventListener('input', () => {
      touchedFields.add(el.id);

      if (el.id === 'basePath') {
        updateStoragePathHint(el.value);
        updatePreservePathFromBase();
        updateConnectorNarPathFromBase();
      }
      else if (['storagePath','llmModelPath','hfToken','llmAPIKey'].includes(el.id)) {
        el.dataset.userEdited = '1';
      }

      if (el.id === 'fqdn') {
        const licenseHost = document.getElementById('licenseHostname');
        if (licenseHost && !licenseHost.dataset.userEdited) {
          licenseHost.value = el.value.trim();
        }
      }

      const active = document.querySelector('.section.active');
      if (active) setupIdolValidateSection(active.id);

      setupIdolSaveFormData();
    });

    el.addEventListener('focus', () => touchedFields.add(el.id));
  });

  document.querySelectorAll('select').forEach(el => {
    el.addEventListener('change', () => {
      const active = document.querySelector('.section.active');
      if (active) setupIdolValidateSection(active.id);
      setupIdolSaveFormData();
    });
  });

  document.querySelectorAll('input[type="radio"]').forEach(el => {
    el.addEventListener('change', () => {
      setupIdolToggleConditionalFields();
      setTimeout(setupIdolReorderNifiPreservePath, 300);
      const active = document.querySelector('.section.active');
      if (active) setupIdolValidateSection(active.id);
      setupIdolSaveFormData();
    });
  });

  // Specific preserve radio handlers
  document.getElementById('nifi-preserve-yes')?.addEventListener('change', () => {
    updateNifiAndRegistryPathsFromBase();
    setupIdolValidateSection('nifi');
  });
  document.getElementById('nifi-preserve-no')?.addEventListener('change', () => {
    setupIdolValidateSection('nifi');
  });

  document.getElementById('nifi-preserve-yes')?.addEventListener('change', setupIdolReorderNifiPreservePath);
  document.getElementById('nifi-preserve-no')?.addEventListener('change', setupIdolReorderNifiPreservePath);

  // Deployment type changes
  document.querySelectorAll('input[name="deploymentType"]').forEach(el => {
    el.addEventListener('change', () => {
      setupIdolToggleConditionalFields();
      setTimeout(setupIdolReorderNifiPreservePath, 300);
      updateModelVisibility();
      checkBasicNextButton();
      updateLlmWikiVisibility();
    });
  });

  // ====================== LICENSE LISTENERS (CLEANED) ======================
  document.getElementById('license-existing')?.addEventListener('change', setupIdolToggleConditionalFields);
  document.getElementById('license-new')?.addEventListener('change', setupIdolToggleConditionalFields);

  document.querySelectorAll('input[name="licenseMode"]').forEach(radio => {
    if (radio._licenseListenerAdded) return;
    radio.addEventListener('change', () => {
      setTimeout(checkLicenseServerStatus, 150);
    });
    radio._licenseListenerAdded = true;
  });

  const licenseUrlInput = document.getElementById('licenseUrl');
  if (licenseUrlInput) {
    let debounceTimer = null;
    licenseUrlInput.addEventListener('input', () => {
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(checkLicenseServerStatus, 450);
    });
    licenseUrlInput.addEventListener('change', checkLicenseServerStatus);
  }

  // ====================== OTHER FEATURE LISTENERS ======================
  document.getElementById('dataAdminToggle')?.addEventListener('change', () => {
    setupIdolToggleConditionalFields();
    setTimeout(setupIdolReorderNifiPreservePath, 300);
    setupIdolSaveFormData();
  });

  document.getElementById('storagePath').addEventListener('input', function() {
    this.dataset.userEdited = '1';
    setupIdolSaveFormData();
  });

  const nifiInput = document.getElementById('nifiMediaServerPath');
  const pretrainedInput = document.getElementById('pretrainedModelsPath');
  if (nifiInput) {
    nifiInput.addEventListener('input', function() {
      this.classList.remove('detection-success', 'detection-failure');
      checkBasicNextButton();
    });
  }
  if (pretrainedInput) {
    pretrainedInput.addEventListener('input', function() {
      this.classList.remove('detection-success', 'detection-failure');
      checkBasicNextButton();
    });
  }

  document.getElementById('pretrainedModelsToggle')?.addEventListener('change', togglePretrainedModelsPath);

  // Tooltip
  const tooltipEl = document.getElementById('tooltipPopup');
  document.addEventListener('mouseover', e => {
    const icon = e.target.closest('.info-icon');
    if (!icon) return;
    const desc = icon.dataset.desc || icon.closest('[data-desc]')?.dataset.desc;
    if (!desc) return;
    tooltipEl.textContent = desc;
    tooltipEl.style.display = 'block';
    const r = icon.getBoundingClientRect();
    tooltipEl.style.left = Math.min(r.left - 120 + r.width / 2, window.innerWidth - 290) + 'px';
    tooltipEl.style.top = (r.bottom + window.scrollY + 8) + 'px';
  });
  document.addEventListener('mouseout', e => {
    if (e.target.closest('.info-icon')) tooltipEl.style.display = 'none';
  });

  // ====================== LLM VISIBILITY LISTENERS (CLEAN & CORRECT) ======================
  const llmToggle = document.getElementById('llmIntegrationToggle');
  const llmWikiToggle = document.getElementById('llmWikiEnableToggle');
  const dataAdminToggle = document.getElementById('deployTypeDataAdmin');

  if (llmToggle) {
    llmToggle.addEventListener('change', () => {
      updateModelVisibility();
      setupIdolValidateSection('basic', true);
    });
  }

  if (llmWikiToggle) {
    llmWikiToggle.addEventListener('change', updateModelVisibility);
  }

  if (dataAdminToggle) {
    dataAdminToggle.addEventListener('change', () => {
      setupIdolToggleConditionalFields();
      updateModelVisibility();
      setupIdolValidateSection('basic', true);
      updateLlmWikiVisibility();
    });
  }

  // ====================== FINAL INITIALIZATION ======================
  await loadServerDefaults();
  setupIdolLoadFormData();
  updateNifiAndRegistryPathsFromBase();
  updatePreservePathFromBase();
  updateModelVisibility();                    // ← Important: call after loading config
  setupIdolToggleConditionalFields(); 
  togglePretrainedModelsPath();

  initTokenToggles();
  initLlmWikiConditional();

  const fqdnInput = document.getElementById('fqdn');
  const licenseHost = document.getElementById('licenseHostname');
  if (fqdnInput && licenseHost && !licenseHost.dataset.userEdited) {
    licenseHost.value = fqdnInput.value.trim();
  }

  ALL_RANGE_PORTS.forEach(p => {
    const el = document.getElementById(p.id);
    portsUpdateRangePills(p, el?.value);
  });

  ['basic','network','nifi','storage'].forEach(s => setupIdolValidateSection(s));
  setupIdolValidateLicenseSection();
  portsValidate();
  updateInfoSectionUrls();
  setupIdolShowSection('information');

  // Expose functions to window
  Object.assign(window, {
    toggleCard, togglePortCard, toggleSubfolders, showToast,
    portsOnInput, portsCheckAvailability, updateInfoSectionUrls,
    setupIdolNavigateToSection, setupIdolGeneratePreSetupScript,
    setupIdolGenerateSetupScript, setupIdolGenerateBashCommand,
    setupIdolCopyPreSetupScript, setupIdolDownloadPreSetupScript,
    setupIdolCopyCommand, updateStoragePathHint,
    togglePretrainedModelsPath,
    saveConfigToLocalStorage, loadConfigFromLocalStorage,
    clearLocalStorageConfig, toggleAutoSave,
    toggleLlmAPIKeyVisibility, toggleHfTokenVisibility,
    updateLlmWikiVisibility, updateModelVisibility
  });

  document.querySelectorAll('input[name="deploymentType"]').forEach(el => 
    el.addEventListener('change', updateInfoSectionUrls)
  );

  console.log('✅ IDOL Deployment Setup Manager is ready');

  // Chrome extension noise suppression
  (function suppressExtensionNoise() {
    const isExtensionError = (msg) => {
      if (!msg) return false;
      const str = msg.toString().toLowerCase();
      return str.includes('message channel closed') ||
             str.includes('runtime.lasterror') ||
             str.includes('receiving end does not exist') ||
             str.includes('could not establish connection') ||
             str.includes('asynchronous response');
    };
    window.addEventListener('unhandledrejection', (event) => {
      if (isExtensionError(event.reason)) {
        event.preventDefault();
        event.stopImmediatePropagation();
        return false;
      }
    });
    const originalConsoleError = console.error;
    console.error = function(...args) {
      if (args.some(arg => isExtensionError(arg))) return;
      originalConsoleError.apply(console, args);
    };
    window.addEventListener('error', (event) => {
      if (isExtensionError(event.message)) {
        event.preventDefault();
        event.stopImmediatePropagation();
        return false;
      }
    });
    console.log('✅ Chrome extension noise fully suppressed (IDOL Setup Manager)');
  })();

  // LLM model loading
  const loadDefaultBtn = document.getElementById('loadDefaultModelsBtn');
  if (loadDefaultBtn) loadDefaultBtn.addEventListener('click', fetchDefaultModels);

  const fileUpload = document.getElementById('modelJsonUpload');
  if (fileUpload) {
    fileUpload.addEventListener('change', (e) => {
      if (e.target.files && e.target.files[0]) handleModelFileUpload(e.target.files[0]);
      e.target.value = '';
    });
  }

  const modelSelect = document.getElementById('llmModelSelect');
  if (modelSelect) modelSelect.addEventListener('change', updateModelInfo);

  fetchDefaultModels();
  llmLoadDefaultModels();
  checkBasicNextButton();
  updateRichMediaBasePathFromBase();

  await loadDefaultRichMediaPath();

  const sharedFolderBasePathInput = document.getElementById('sharedFolderBasePath');
  const nifiMediaServerInput = document.getElementById('nifiMediaServerPath');
  const pretrainedModelsInput = document.getElementById('pretrainedModelsPath');

  if (sharedFolderBasePathInput) sharedFolderBasePathInput.classList.add('professional-select');
  if (nifiMediaServerInput) nifiMediaServerInput.classList.add('professional-select');
  if (pretrainedModelsInput) pretrainedModelsInput.classList.add('professional-select');

  setTimeout(() => runAutoDetectionOnLoad(), 100);

  initInformationUrls();
  collapseAllCards();
  initToggleAllServices();

  // ====================== CHEVRON BUTTONS ======================
  document.querySelectorAll('.chevron-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const head = btn.closest('.service-card-head');
      if (head?.parentElement) toggleCard(head.parentElement.id);
    });
  });

  // Host toggle switch in Quick Access
  const quickAccessHeader = document.querySelector('#information .card-header, #grid .card-header');
  if (quickAccessHeader) {
    const switchWrapper = document.createElement('div');
    switchWrapper.style.cssText = 'margin-left: auto; display: flex; align-items: center; gap: 8px; font-size: 13px;';
    switchWrapper.innerHTML = `
      <label style="display: flex; align-items: center; gap: 6px; cursor: pointer;">
        <input type="checkbox" id="hostToggleSwitch">
        <span>Use FQDN instead of <code>idol-docker-host</code></span>
      </label>
    `;
    quickAccessHeader.appendChild(switchWrapper);

    const hostToggle = document.getElementById('hostToggleSwitch');
    const fqdnInputEl = document.getElementById('fqdn');

    if (hostToggle) {
      hostToggle.addEventListener('change', () => {
        if (hostToggle.checked && !fqdnInputEl?.value.trim()) {
          showToast('Please enter an FQDN first', true);
          hostToggle.checked = false;
          return;
        }
        updateInfoSectionUrls();
        showToast(`Using ${hostToggle.checked ? 'FQDN' : 'idol-docker-host'} for links`);
      });
    }

    fqdnInputEl?.addEventListener('input', updateInfoSectionUrls);
  }

  initQuickAccessCards();
  setupImportExportHandlers();
  updateHomeBtnHref();

  // Final safety call for LLM visibility
  setTimeout(() => {
    updateModelVisibility();
  }, 400);

  console.log('✅ IDOL Deployment Setup Manager – fully initialized with LLM fixes');
});