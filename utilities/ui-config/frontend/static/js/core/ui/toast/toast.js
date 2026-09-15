/**
 * core/ui/toast/toast.js
 * Single toast/notification implementation reused by every page.
 * Previously duplicated three times (main.js, monitor-config.js,
 * nifi-config.js) with slightly different type names and timeouts.
 *
 * Usage:
 *   import { createToaster } from '../core/ui/toast/toast.js';
 *   const toast = createToaster('toastWrap');
 *   toast('Saved!', 'success');
 */

const TYPE_ALIASES = {
  ok: 'success',
  inf: 'info',
  err: 'error',
};

let uid = 0;

/**
 * @param {string} containerId - id of the element toasts are appended to
 * @param {{ duration?: number }} [options]
 * @returns {(msg: string, type?: 'success'|'error'|'info') => void}
 */
export function createToaster(containerId, options = {}) {
  const duration = options.duration ?? 3000;

  return function toast(msg, type = 'info') {
    const container = document.getElementById(containerId);
    if (!container) return;

    const normalizedType = TYPE_ALIASES[type] || type;
    const el = document.createElement('div');
    el.className = `toast ${normalizedType}`;
    el.id = `toast-${++uid}`;
    el.innerHTML = `<span class="toast-prompt">$</span> ${msg}`;
    container.appendChild(el);

    setTimeout(() => {
      el.style.opacity = '0';
      el.style.transition = 'opacity 0.3s';
      setTimeout(() => el.remove(), 300);
    }, duration);
  };
}
