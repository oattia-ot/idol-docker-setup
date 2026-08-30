/**
 * Centralized, immutable application constants.
 */

/** Base URL for all backend API calls. Always hits the same host the page was loaded from*/
export const API_BASE = '/config-nifi/api';

/** Form field ids persisted to localStorage. */
export const FIELDS_TO_SAVE = [
  'nifiApiUrl', 'nifiUsername', 'nifiPassword',
  'githubApiUrl', 'githubOwner', 'githubRepoName', 'githubToken', 'githubBranch', 'githubFlowDir',
  'hostFolderPath', 'repositoryFilePath',
  'filterState', 'filterName', 'filterType', 'filterLocation'
];

export const LOAD_THROTTLE_MS = 1000;
export const NIFI_RETRY_SECS = 15;
