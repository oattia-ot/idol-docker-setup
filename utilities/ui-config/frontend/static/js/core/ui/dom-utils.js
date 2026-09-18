/**
 * core/ui/dom-utils.js
 * Pure, framework-agnostic DOM helpers shared by every feature module.
 * Extracted from duplicated copies found in nifi-config.js and
 * idol-setup-manager.js (getEl/getValue/setValue/setHtml/escapeHtml).
 */

export function getEl(id) {
  return document.getElementById(id);
}

export function getValue(id, fallback = '') {
  const el = getEl(id);
  return el ? el.value : fallback;
}

export function setValue(id, value) {
  const el = getEl(id);
  if (el) el.value = value;
}

export function setHtml(id, html) {
  const el = getEl(id);
  if (el) el.innerHTML = html;
}

export function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/[&<>]/g, (m) => (m === '&' ? '&amp;' : m === '<' ? '&lt;' : '&gt;'));
}

/** Debounce a function by `wait` ms (trailing edge). */
export function debounce(fn, wait = 250) {
  let timer = null;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), wait);
  };
}

/**
 * Copies text to the clipboard and reports success/failure to the caller
 * via the returned Promise, instead of reaching into a global toast call.
 * The feature layer decides how to surface the result.
 */
export async function copyToClipboard(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}

/**
 * Lightweight event delegation helper. Lets a single listener on a
 * container handle every `[data-action]` button inside it, replacing
 * dozens of inline `onclick="..."` attributes with one wiring call.
 *
 * @param {HTMLElement} container
 * @param {Record<string, (el: HTMLElement, ev: Event) => void>} handlers
 *        map of action name -> handler, matched against data-action
 */
export function delegate(container, handlers) {
  if (!container) return;
  container.addEventListener('click', (ev) => {
    const target = ev.target.closest('[data-action]');
    if (!target || !container.contains(target)) return;
    const action = target.dataset.action;
    const handler = handlers[action];
    if (handler) handler(target, ev);
  });
}
