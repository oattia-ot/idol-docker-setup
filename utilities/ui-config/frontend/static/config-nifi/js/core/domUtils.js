/**
 * Low-level DOM helper functions used throughout the app.
 */

/** @param {string} id @returns {HTMLElement|null} */
export function getEl(id) {
  console.debug(`[UI] getElementById('${id}')`);
  return document.getElementById(id);
}

/**
 * @param {string} id
 * @param {string} [def]
 * @returns {string}
 */
export function getValue(id, def = '') {
  const e = getEl(id);
  const val = e ? e.value : def;
  console.debug(`[UI] getValue('${id}') => ${val !== undefined ? (id.includes('password') ? '***' : val) : def}`);
  return val;
}

/**
 * @param {string} id
 * @param {string|undefined} v
 */
export function setValue(id, v) {
  const e = getEl(id);
  if (e && v !== undefined) {
    e.value = v;
    console.debug(`[UI] setValue('${id}', ${id.includes('password') ? '***' : v})`);
  }
}

/**
 * @param {string} id
 * @param {string} html
 */
export function setHtml(id, html) {
  const e = getEl(id);
  if (e) {
    e.innerHTML = html;
    console.debug(`[UI] setHtml('${id}') updated`);
  }
}

/** @param {string} id */
export function showLoading(id) {
  console.log(`[UI] showLoading('${id}')`);
  setHtml(id, '<div style="padding:30px;text-align:center"><i class="fas fa-spinner fa-spin"></i><br>Loading...</div>');
}

/**
 * Minimal HTML escaping for untrusted strings rendered into innerHTML.
 * @param {string} str
 * @returns {string}
 */
export function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/[&<>]/g, (m) => (m === '&' ? '&amp;' : m === '<' ? '&lt;' : '&gt;'));
}

/** @param {string} id */
export function openModal(id) {
  console.log(`[UI] openModal('${id}')`);
  const m = getEl(id);
  if (m) m.style.display = 'flex';
}

/** @param {string} id */
export function closeModal(id) {
  console.log(`[UI] closeModal('${id}')`);
  const m = getEl(id);
  if (m) m.style.display = 'none';
}
