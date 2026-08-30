import { setValue } from '../core/domUtils.js';
import { showToast } from '../core/notifications.js';

/** Load dynamic NiFi credentials previously stored by the IDOL integration. */
export function loadIdolDynamicNifiCredentials() {
  console.log('[IDOL] Loading dynamic NiFi credentials from localStorage');
  const rawApiUrl = localStorage.getItem('idol_dyn_dyn-nifi-link');
  const username = localStorage.getItem('idol_dyn_dyn-nifi-username');
  const password = localStorage.getItem('idol_dyn_dyn-nifi-password');

  if (rawApiUrl) {
    let cleanUrl = rawApiUrl.trim();
    console.debug(`[IDOL] Raw API URL: ${rawApiUrl}`);
    if (cleanUrl.endsWith('/nifi')) {
      cleanUrl = cleanUrl.slice(0, -5) + '/nifi-api';
      console.debug(`[IDOL] Fixed URL (removed /nifi): ${cleanUrl}`);
    } else if (cleanUrl.endsWith('/nifi/')) {
      cleanUrl = cleanUrl.slice(0, -6) + '/nifi-api';
      console.debug(`[IDOL] Fixed URL (removed /nifi/): ${cleanUrl}`);
    } else if (!cleanUrl.endsWith('/nifi-api')) {
      if (cleanUrl.endsWith('/')) cleanUrl = cleanUrl.slice(0, -1);
      cleanUrl += '/nifi-api';
      console.debug(`[IDOL] Appended /nifi-api: ${cleanUrl}`);
    }
    setValue('nifiApiUrl', cleanUrl);
  }

  if (username) { setValue('nifiUsername', username); console.log('[IDOL] Username loaded'); }
  if (password) { setValue('nifiPassword', password); console.log('[IDOL] Password loaded (hidden)'); }

  if (rawApiUrl || username || password) {
    showToast('✅ IDOL dynamic NiFi credentials loaded automatically', 'var(--success)');
  }
}
