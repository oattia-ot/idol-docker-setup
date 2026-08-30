import { showToast } from './notifications.js';

/**
 * Copy text to clipboard with a graceful fallback for older browsers.
 * @param {string} text
 * @param {string} [successMessage]
 */
export function copyToClipboard(text, successMessage = '✅ Copied to clipboard!') {
  if (!text) {
    showToast('Nothing to copy', 'var(--warning)');
    return;
  }

  navigator.clipboard.writeText(text).then(
    () => showToast(successMessage, 'var(--success)'),
    () => {
      const ta = document.createElement('textarea');
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      showToast(successMessage, 'var(--success)');
    }
  );
}
