import { API_BASE } from '../config/constants.js';

/**
 * Validate a flow file as a real NiFi 2 flow by checking for expected
 * top-level keys. Fails open (returns true) on network/parse errors so
 * the UI doesn't hide files just because the validation call failed.
 * @param {string} urlOrPath
 * @param {boolean} [isRemote]
 * @returns {Promise<boolean>}
 */
export async function isValidNifi2Flow(urlOrPath, isRemote = false) {
  try {
    let json;

    if (isRemote) {
      const res = await fetch(`${API_BASE}/github/fetch-flow-content?url=${encodeURIComponent(urlOrPath)}`);
      if (!res.ok) {
        console.warn(`[VALIDATE] Fetch failed for ${urlOrPath}: HTTP ${res.status}`);
        return true;
      }
      json = await res.json();
    } else {
      const res = await fetch(`${API_BASE}/flows/host/content?path=${encodeURIComponent(urlOrPath)}`);
      if (!res.ok) return true;
      const data = await res.json();
      json = data.content;
    }

    if (json && typeof json === 'object') {
      const hasFlowContents = 'flowContents' in json;
      const hasFlowEncodingVersion = 'flowEncodingVersion' in json;
      if (hasFlowContents || hasFlowEncodingVersion) return true;
      if (json.snapshotMetadata || json.externalControllerServices) return true;
    }

    console.warn(`[VALIDATE] ${urlOrPath} failed NiFi 2 structure check:`, json ? Object.keys(json) : 'null');
    return false;
  } catch (e) {
    console.warn(`[VALIDATE] Error validating ${urlOrPath}:`, e.message);
    return true;
  }
}
