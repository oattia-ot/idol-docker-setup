/**
 * Inline, in-page replacements for native browser dialogs.
 *
 * Why this exists:
 *  - `window.confirm()` / `window.alert()` block the JS thread, look jarring,
 *    and can't be styled — they break the app's visual language.
 *  - `confirmDialog()` shows an in-page modal (same `.modal` styling already
 *    used elsewhere in this app) and resolves a Promise<boolean> once the
 *    user picks Yes/Cancel.
 *  - `showProgress()` shows a full-screen blocking overlay while an async
 *    action runs, so the user can't click anything else mid-operation. It
 *    returns a small handle to update the status text and to close it when
 *    the work is done.
 *
 * Both rely on markup that lives in the page template:
 *   #confirmActionModal / #confirmActionTitle / #confirmActionMessage /
 *   #confirmActionYesBtn / #confirmActionNoBtn
 *   #blockingProgressOverlay / #progressMessage / #progressSteps
 */
import { escapeHtml } from './domUtils.js';

/**
 * Show an inline confirmation modal in place of `window.confirm()`.
 * @param {string} message Plain-text message (escaped automatically; '\n' becomes a line break).
 * @param {Object} [opts]
 * @param {string} [opts.title]
 * @param {string} [opts.confirmText]
 * @param {string} [opts.cancelText]
 * @param {boolean} [opts.danger] Style the confirm button as destructive (red) and use a warning icon.
 * @returns {Promise<boolean>} resolves true if confirmed, false if cancelled/escaped.
 */
export function confirmDialog(message, opts = {}) {
  const {
    title = 'Confirm Action',
    confirmText = 'Yes, continue',
    cancelText = 'Cancel',
    danger = false,
  } = opts;

  return new Promise((resolve) => {
    const modal = document.getElementById('confirmActionModal');
    const titleEl = document.getElementById('confirmActionTitle');
    const msgEl = document.getElementById('confirmActionMessage');
    const yesBtn = document.getElementById('confirmActionYesBtn');
    const noBtn = document.getElementById('confirmActionNoBtn');

    if (!modal || !titleEl || !msgEl || !yesBtn || !noBtn) {
      console.error('[Dialog] confirmActionModal markup missing from page — failing safe (cancel).');
      resolve(false);
      return;
    }

    console.log(`[Dialog] confirmDialog: "${message}"`);

    titleEl.innerHTML = `<i class="fas fa-${danger ? 'triangle-exclamation' : 'circle-question'}"></i> ${escapeHtml(title)}`;
    msgEl.innerHTML = escapeHtml(message).replace(/\n/g, '<br>');
    yesBtn.innerHTML = `<i class="fas fa-check"></i> ${escapeHtml(confirmText)}`;
    yesBtn.className = `btn ${danger ? 'btn-danger' : 'btn-success'}`;
    noBtn.innerHTML = `<i class="fas fa-times"></i> ${escapeHtml(cancelText)}`;

    let settled = false;
    const cleanup = (result) => {
      if (settled) return;
      settled = true;
      modal.style.display = 'none';
      yesBtn.removeEventListener('click', onYes);
      noBtn.removeEventListener('click', onNo);
      document.removeEventListener('keydown', onKey);
      resolve(result);
    };
    const onYes = () => cleanup(true);
    const onNo = () => cleanup(false);
    const onKey = (e) => { if (e.key === 'Escape') cleanup(false); };

    yesBtn.addEventListener('click', onYes);
    noBtn.addEventListener('click', onNo);
    document.addEventListener('keydown', onKey);

    modal.style.display = 'flex';
    yesBtn.focus();
  });
}

/**
 * Show a full-screen blocking overlay in place of using `window.alert()` /
 * timed toasts to narrate a multi-step async operation. While shown, the
 * overlay sits above the rest of the UI and intercepts all clicks, so the
 * user can't start another action until the current one finishes.
 *
 * @param {string} message Initial status line shown under the spinner.
 * @returns {{update: (text: string) => void, close: () => void}}
 */
export function showProgress(message) {
  const overlay = document.getElementById('blockingProgressOverlay');
  const msgEl = document.getElementById('progressMessage');
  const stepsEl = document.getElementById('progressSteps');

  if (!overlay || !msgEl) {
    console.error('[Dialog] blockingProgressOverlay markup missing from page.');
    return { update() {}, close() {} };
  }

  console.log(`[Dialog] showProgress: "${message}"`);
  msgEl.textContent = message;
  if (stepsEl) stepsEl.innerHTML = '';
  overlay.classList.add('show');

  let closed = false;
  return {
    /** Update the headline status and append a step line to the log. */
    update(text) {
      if (closed) return;
      msgEl.textContent = text;
      if (stepsEl) {
        const line = document.createElement('div');
        line.textContent = `• ${text}`;
        stepsEl.appendChild(line);
        stepsEl.scrollTop = stepsEl.scrollHeight;
      }
    },
    /** Hide the overlay and restore normal interaction. */
    close() {
      if (closed) return;
      closed = true;
      overlay.classList.remove('show');
    },
  };
}
