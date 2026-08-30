import { getEl, escapeHtml } from './domUtils.js';

/**
 * Show a transient toast notification.
 * @param {string} msg
 * @param {string|null} [bg] CSS color/var override
 */
export function showToast(msg, bg = null) {
  console.log(`[UI] showToast: ${msg} ${bg ? `(bg:${bg})` : ''}`);
  const t = getEl('toast');
  const tm = getEl('toastMsg');
  if (!t || !tm) return;
  tm.textContent = msg;
  if (bg) t.style.background = bg;
  t.classList.add('show');
  setTimeout(() => {
    t.classList.remove('show');
    if (bg) t.style.background = '';
  }, 2400);
}

/**
 * Show a dismissible fixed alert banner.
 * @param {string} msg
 * @param {'info'|'success'|'error'|'warning'} [type]
 */
export function showAlert(msg, type = 'info') {
  console.warn(`[UI] showAlert (${type}): ${msg}`);
  let container = document.getElementById('fixedAlertContainer');
  if (!container) {
    container = document.createElement('div');
    container.id = 'fixedAlertContainer';
    container.className = 'fixed-alert-container';
    document.body.appendChild(container);
  }
  const alertDiv = document.createElement('div');
  alertDiv.className = `fixed-alert-item alert-${type}`;
  const icon = type === 'success' ? '✅' : type === 'error' ? '❌' : 'ℹ️';
  alertDiv.innerHTML = `<span style="font-size: 16px;">${icon}</span><span>${escapeHtml(msg)}</span>`;
  container.appendChild(alertDiv);
  setTimeout(() => {
    alertDiv.style.opacity = '0';
    setTimeout(() => {
      if (alertDiv.parentNode) alertDiv.remove();
      if (container.children.length === 0) container.remove();
    }, 200);
  }, 2800);
}
