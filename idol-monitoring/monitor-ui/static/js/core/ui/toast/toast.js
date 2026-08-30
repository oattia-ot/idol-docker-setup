/**
 * Simple toast notification system
 */

let container = null;

function ensureContainer() {
  if (container) return container;
  container = document.getElementById('toast-container');
  if (!container) {
    container = document.createElement('div');
    container.id = 'toast-container';
    document.body.appendChild(container);
  }
  return container;
}

/**
 * Show a toast message
 * @param {string} message
 * @param {'success'|'error'|'info'} [type='info']
 * @param {number} [duration=3200]
 */
export function showToast(message, type = 'info', duration = 3200) {
  const c = ensureContainer();
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;

  c.appendChild(toast);

  // Auto dismiss
  setTimeout(() => {
    toast.style.transition = 'all 0.2s ease';
    toast.style.opacity = '0';
    setTimeout(() => toast.remove(), 200);
  }, duration);

  // Click to dismiss
  toast.addEventListener('click', () => toast.remove());
}
